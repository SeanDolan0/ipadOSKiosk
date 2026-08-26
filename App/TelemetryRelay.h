#import <Foundation/Foundation.h>

@interface TelemetryRelay : NSObject

- (instancetype)initWithBaseURL:(NSString *)baseURL token:(NSString *)token;
- (void)relayTelemetry:(NSDictionary *)telemetry;

@end
