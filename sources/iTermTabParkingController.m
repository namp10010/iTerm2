#import "iTermTabParkingController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermGCDTimer.h"
#import "iTermPreferences.h"
#import "NSStringITerm.h"
#import "PTYSession.h"

static const NSTimeInterval kParkingCheckInterval = 15.0;
// How long to wait after sending the graceful-exit sequence before reading the
// screen for the session ID and force-killing any surviving processes.
static const NSTimeInterval kHibernationCaptureDelay = 2.5;

@implementation iTermTabParkingController {
    iTermGCDTimer *_timer;
}

+ (instancetype)sharedInstance {
    static iTermTabParkingController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)start {
    if (_timer) {
        return;
    }
    _timer = [[iTermGCDTimer alloc] initWithInterval:kParkingCheckInterval
                                               queue:dispatch_get_main_queue()
                                              target:self
                                            selector:@selector(checkIdleSessions:)];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

- (void)checkIdleSessions:(iTermGCDTimer *)timer {
    if (![iTermPreferences boolForKey:kPreferenceKeyTabParkingEnabled]) {
        return;
    }
    NSInteger timeoutMinutes = [iTermPreferences integerForKey:kPreferenceKeyTabParkingTimeout];
    NSTimeInterval timeoutSeconds = timeoutMinutes * 60.0;
    NSDate *threshold = [NSDate dateWithTimeIntervalSinceNow:-timeoutSeconds];

    for (PTYSession *session in [[iTermController sharedInstance] allSessions]) {
        [self considerParkingSession:session idleThreshold:threshold];
    }
}

- (void)considerParkingSession:(PTYSession *)session idleThreshold:(NSDate *)threshold {
    if (session.exited || session.isParked) {
        return;
    }
    if (session.isTmuxClient) {
        return;
    }
    if (session.isBrowserSession) {
        return;
    }
    if (session.focused) {
        return;
    }
    if ([session.lastForegroundDate compare:threshold] == NSOrderedDescending) {
        return;
    }
    // The terminal must also have had no output for at least as long.
    // Using output rather than hasNontrivialJob so that idle Claude Code
    // sessions (node process always running, but no terminal output) get parked.
    NSTimeInterval thresholdInterval = [threshold timeIntervalSinceReferenceDate];
    if (session.lastOutputTimeInterval > thresholdInterval) {
        return;
    }

    // Check if Claude Code is the foreground job; if so, hibernate gracefully.
    NSSet<NSString *> *claudeNames = [self claudeProcessNames];
    pid_t claudePid = [session foregroundJobPidIfMatchingGracefulExitNames:claudeNames];
    if (claudePid > 0) {
        [self hibernateClaudeSession:session];
    } else {
        [session park];
    }
}

#pragma mark - Claude hibernation

- (NSSet<NSString *> *)claudeProcessNames {
    // Re-use the same configured name list as the graceful-quit feature.
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSString *raw in [[iTermAdvancedSettingsModel claudeGracefulExitProcessNames]
                            componentsSeparatedByString:@","]) {
        NSString *trimmed = [[raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        if (trimmed.length > 0) {
            [names addObject:trimmed];
        }
    }
    return names;
}

- (void)hibernateClaudeSession:(PTYSession *)session {
    DLog(@"Hibernating Claude session %@", session);

    // Mark parked immediately to prevent the idle timer from picking it up again
    // and to route the upcoming brokenPipe through the parked path.
    session.isParked = YES;

    // Send the graceful-exit sequence (default: Ctrl-S, Ctrl-C, Ctrl-C).
    // Ctrl-S stashes the prompt; first Ctrl-C makes Claude print its session ID;
    // second Ctrl-C causes it to exit cleanly.
    NSData *sequence = [NSString dataForHexCodes:
                        [iTermAdvancedSettingsModel claudeGracefulExitSequenceHex]];
    if (sequence.length == 0) {
        // No sequence configured — fall back to immediate kill.
        [session park];
        return;
    }

    NSData *firstByte = [sequence subdataWithRange:NSMakeRange(0, 1)];
    NSData *remainder = sequence.length > 1
        ? [sequence subdataWithRange:NSMakeRange(1, sequence.length - 1)]
        : nil;
    int delayMS = MAX(0, [iTermAdvancedSettingsModel claudeGracefulExitInitialDelayMS]);

    [session sendGracefulExitSequenceData:firstByte];

    __weak PTYSession *weakSession = session;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMS * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        PTYSession *s = weakSession;
        if (!s) return;
        if (remainder) {
            [s sendGracefulExitSequenceData:remainder];
        }

        // Wait for Claude to write its session ID to the terminal, then capture it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kHibernationCaptureDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PTYSession *strongSession = weakSession;
            if (!strongSession) return;

            NSString *resumeCommand = [self extractResumeCommandFromSession:strongSession];
            if (resumeCommand) {
                DLog(@"Captured Claude resume command: %@", resumeCommand);
                strongSession.parkedClaudeResumeCommand = resumeCommand;
            }

            // Force-kill anything still running (node, golsp, MCP servers).
            if (!strongSession.exited) {
                [strongSession forceKillRemainingProcesses];
            }
        });
    });
}

// Reads the last portion of the terminal's scrollback and looks for the
// "claude --resume <id>" pattern that Claude Code prints on graceful exit.
- (NSString *)extractResumeCommandFromSession:(PTYSession *)session {
    NSString *screenText = [session.screen compactLineDumpWithHistory];
    if (!screenText) {
        return nil;
    }

    // Claude Code prints something like:
    //   > claude --resume abc123xyz
    // Match the resume ID (alphanumeric + hyphens/underscores, at least 8 chars).
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"claude\\s+--resume\\s+([A-Za-z0-9_-]{8,})"
                             options:NSRegularExpressionCaseInsensitive
                               error:&error];
    if (!regex) {
        return nil;
    }

    // Search the last 4000 characters to avoid scanning a huge scrollback.
    NSString *searchText = screenText.length > 4000
        ? [screenText substringFromIndex:screenText.length - 4000]
        : screenText;

    NSTextCheckingResult *match = [regex
        firstMatchInString:searchText
                   options:0
                     range:NSMakeRange(0, searchText.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }

    NSString *sessionId = [searchText substringWithRange:[match rangeAtIndex:1]];
    return [NSString stringWithFormat:@"claude --resume %@", sessionId];
}

@end
