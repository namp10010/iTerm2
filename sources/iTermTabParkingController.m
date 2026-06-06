#import "iTermTabParkingController.h"

#import "iTermController.h"
#import "iTermGCDTimer.h"
#import "iTermPreferences.h"
#import "PTYSession.h"

static const NSTimeInterval kParkingCheckInterval = 15.0;

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
    // The tab must have been out of focus for longer than the threshold.
    if ([session.lastForegroundDate compare:threshold] == NSOrderedDescending) {
        return;
    }
    // The terminal must also have had no output for at least as long.
    // This keeps actively-responding Claude sessions alive while idle ones get parked.
    // Using terminal output rather than hasNontrivialJob so that long-running background
    // processes (e.g. node/Claude Code waiting for input) don't block parking.
    NSTimeInterval thresholdInterval = [threshold timeIntervalSinceReferenceDate];
    if (session.lastOutputTimeInterval > thresholdInterval) {
        return;
    }
    [session park];
}

@end
