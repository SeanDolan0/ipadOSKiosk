#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class ScreensaverView;
@class NetworkMonitor;
@class DaemonBridge;
@class TelemetryRelay;

@interface KioskViewController : UIViewController <WKNavigationDelegate,
    WKScriptMessageHandler, ScreensaverViewDelegate>
@end
