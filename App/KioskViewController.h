#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "ScreensaverView.h"
#import "SettingsViewController.h"

@class NetworkMonitor;
@class DaemonBridge;
@class TelemetryRelay;

@interface KioskViewController : UIViewController <WKNavigationDelegate,
    WKScriptMessageHandler, ScreensaverViewDelegate, SettingsViewControllerDelegate>

- (void)openSettings;
- (void)reloadDashboard;
- (void)handleDarwinCommand;

@end
