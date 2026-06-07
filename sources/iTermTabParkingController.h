#import <Foundation/Foundation.h>

// Monitors all sessions and parks idle ones to save memory.
// A session is park-eligible when it has not been focused for longer than the
// configured timeout AND has no nontrivial foreground job running.
// Parked sessions can be revived by clicking their tab.
@interface iTermTabParkingController : NSObject

+ (instancetype)sharedInstance;

// Start the periodic idle-check timer. Call once at app launch.
- (void)start;

// Stop the timer (useful for testing or when the feature is disabled at runtime).
- (void)stop;

@end
