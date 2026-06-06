#import "iTermTabParkingController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermGCDTimer.h"
#import "iTermPreferences.h"
#import "NSStringITerm.h"
#import "PTYSession.h"

static const NSTimeInterval kParkingCheckInterval = 15.0;
// Grace period after sending the exit sequence before force-killing survivors.
static const NSTimeInterval kClaudeGracePeriodSeconds = 3.0;

@implementation iTermTabParkingController {
    iTermGCDTimer *_timer;
}

+ (instancetype)sharedInstance {
    static iTermTabParkingController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)start {
    if (_timer) return;
    _timer = [[iTermGCDTimer alloc] initWithInterval:kParkingCheckInterval
                                               queue:dispatch_get_main_queue()
                                              target:self
                                            selector:@selector(checkIdleSessions:)];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

#pragma mark - Idle check

- (void)checkIdleSessions:(iTermGCDTimer *)timer {
    if (![iTermPreferences boolForKey:kPreferenceKeyTabParkingEnabled]) return;

    NSInteger timeoutMinutes = [iTermPreferences integerForKey:kPreferenceKeyTabParkingTimeout];
    NSDate *threshold = [NSDate dateWithTimeIntervalSinceNow:-(timeoutMinutes * 60.0)];

    for (PTYSession *session in [[iTermController sharedInstance] allSessions]) {
        [self considerParkingSession:session idleThreshold:threshold];
    }
}

- (void)considerParkingSession:(PTYSession *)session idleThreshold:(NSDate *)threshold {
    if (session.exited || session.isParked) return;
    if (session.isTmuxClient || session.isBrowserSession) return;
    if (session.focused) return;
    if ([session.lastForegroundDate compare:threshold] == NSOrderedDescending) return;

    // Park only when the terminal has also had no output for at least as long.
    if (session.lastOutputTimeInterval > [threshold timeIntervalSinceReferenceDate]) return;

    // If Claude is the foreground job, send the graceful-exit sequence first.
    NSSet<NSString *> *claudeNames = [self claudeProcessNames];
    BOOL hasClaudeForeground = [session foregroundJobPidIfMatchingGracefulExitNames:claudeNames] > 0;

    if (hasClaudeForeground) {
        [self parkClaudeSession:session];
    } else {
        [session park];
    }
}

#pragma mark - Claude graceful park

- (NSSet<NSString *> *)claudeProcessNames {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSString *raw in [[iTermAdvancedSettingsModel claudeGracefulExitProcessNames]
                            componentsSeparatedByString:@","]) {
        NSString *trimmed = [[raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        if (trimmed.length > 0) [names addObject:trimmed];
    }
    return names;
}

- (void)parkClaudeSession:(PTYSession *)session {
    DLog(@"Tab parking: sending graceful-exit sequence to Claude session %@", session);

    // Mark parked now so the idle timer doesn't pick it up again and so that
    // the eventual brokenPipe routes through the parked (not dead) code path.
    session.isParked = YES;

    NSData *sequence = [NSString dataForHexCodes:
                        [iTermAdvancedSettingsModel claudeGracefulExitSequenceHex]];
    if (sequence.length == 0) {
        [session forceKillRemainingProcesses];
        return;
    }

    // Replicate the same split-and-delay logic as the app-quit path:
    // first byte (Ctrl-S, stash prompt) sent immediately; remainder (double Ctrl-C)
    // sent after claudeGracefulExitInitialDelayMS so Claude has time to stash.
    NSData *firstByte = [sequence subdataWithRange:NSMakeRange(0, 1)];
    NSData *remainder = sequence.length > 1
        ? [sequence subdataWithRange:NSMakeRange(1, sequence.length - 1)]
        : nil;
    int delayMS = MAX(0, [iTermAdvancedSettingsModel claudeGracefulExitInitialDelayMS]);

    [session writeDataForParking:firstByte];

    __weak PTYSession *weakSession = session;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMS * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        PTYSession *s = weakSession;
        if (!s) return;
        if (remainder) [s writeDataForParking:remainder];

        // Give Claude the grace period to exit on its own, then kill everything
        // that survived — including processes in separate process groups (golsp,
        // MCP servers, node itself if it called setsid()).
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kClaudeGracePeriodSeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PTYSession *ss = weakSession;
            if (ss && !ss.exited) {
                [ss forceKillRemainingProcesses];
            }
        });
    });
}

@end
