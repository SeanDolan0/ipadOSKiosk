#import "NetworkMonitor.h"
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#import <arpa/inet.h>

@interface NetworkMonitor ()
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, strong) NSTimer *haHealthTimer;
@end

@implementation NetworkMonitor

- (void)start {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8123);
    addr.sin_addr.s_addr = inet_addr("192.168.50.150");

    _reachability = SCNetworkReachabilityCreateWithAddress(NULL,
        (const struct sockaddr *)&addr);

    SCNetworkReachabilityContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
    SCNetworkReachabilitySetCallback(_reachability, reachabilityCallback, &ctx);
    SCNetworkReachabilitySetDispatchQueue(_reachability,
        dispatch_get_main_queue());

    _haHealthTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                     target:self
                                                   selector:@selector(checkHAHealth)
                                                   userInfo:nil
                                                    repeats:YES];
    [self checkHAHealth];
}

- (void)stop {
    if (_reachability) {
        SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
        SCNetworkReachabilitySetDispatchQueue(_reachability, NULL);
        CFRelease(_reachability);
        _reachability = NULL;
    }
    [_haHealthTimer invalidate];
}

static void reachabilityCallback(SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void *info) {
    NetworkMonitor *monitor = (__bridge NetworkMonitor *)info;
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        monitor.isConnected = reachable;
        if (monitor.onStateChange) {
            monitor.onStateChange(reachable);
        }
    });
}

- (void)checkHAHealth {
    NSURL *url = [NSURL URLWithString:@"http://192.168.50.150:8123/"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"HEAD";
    request.timeoutInterval = 5.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            BOOL haReachable = (error == nil);
            if (haReachable != self.isConnected) {
                self.isConnected = haReachable;
                if (self.onStateChange) {
                    self.onStateChange(haReachable);
                }
            }
        }];
    [task resume];
}

@end
