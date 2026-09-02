#import <UIKit/UIKit.h>

@protocol ScreensaverViewDelegate <NSObject>
- (void)screensaverDidReceiveTouch;
- (void)screensaverDidRequestSettings;
@end

@interface ScreensaverView : UIView

@property (nonatomic, weak) id<ScreensaverViewDelegate> delegate;

- (void)configureWithMode:(NSString *)mode
                photoURLs:(NSArray<NSString *> *)photoURLs
            dimBrightness:(float)dimBrightness;

- (void)fadeIn;
- (void)fadeOut;

@end
