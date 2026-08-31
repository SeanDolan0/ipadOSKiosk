#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "ScreensaverView.h"

@class NetworkMonitor;
@class DaemonBridge;
@class TelemetryRelay;

@interface KioskViewController : UIViewController <WKNavigationDelegate,
    WKScriptMessageHandler, ScreensaverViewDelegate>
@end
