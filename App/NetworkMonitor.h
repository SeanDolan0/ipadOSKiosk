#import <Foundation/Foundation.h>

typedef void (^NetworkStateBlock)(BOOL connected);

@interface NetworkMonitor : NSObject

@property (nonatomic, copy) NetworkStateBlock onStateChange;
@property (nonatomic, assign, readonly) BOOL isConnected;

- (void)start;
- (void)stop;

@end
