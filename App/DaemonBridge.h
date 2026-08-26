#import <Foundation/Foundation.h>

typedef void (^TelemetryCompletion)(NSDictionary *telemetry);
typedef void (^WakeCompletion)(BOOL shouldWake);

@interface DaemonBridge : NSObject

- (void)fetchTelemetryWithCompletion:(TelemetryCompletion)completion;
- (void)checkWakeWithCompletion:(WakeCompletion)completion;

@end
