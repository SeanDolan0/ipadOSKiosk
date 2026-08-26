#import "DaemonBridge.h"

#define DAEMON_BASE_URL @"http://127.0.0.1:9090"

@implementation DaemonBridge

- (void)fetchTelemetryWithCompletion:(TelemetryCompletion)completion {
    NSURL *url = [NSURL URLWithString:[DAEMON_BASE_URL stringByAppendingString:@"/telemetry"]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:5.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                NSLog(@"DaemonBridge: telemetry fetch failed: %@", error.localizedDescription);
                completion(nil);
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                options:0
                                                                  error:nil];
            completion(json);
        }];
    [task resume];
}

- (void)checkWakeWithCompletion:(WakeCompletion)completion {
    NSURL *url = [NSURL URLWithString:[DAEMON_BASE_URL stringByAppendingString:@"/health"]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:2.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            completion(NO);
        }];
    [task resume];
}

@end
