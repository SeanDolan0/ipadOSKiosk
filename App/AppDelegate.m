#import "AppDelegate.h"
#import "KioskViewController.h"
#include <IOKit/pwr_mgt/IOPMLib.h>

@implementation AppDelegate {
    IOPMAssertionID _sleepAssertion;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[KioskViewController alloc] init];
    [self.window makeKeyAndVisible];

    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("HASmartboard Kiosk"),
        &_sleepAssertion
    );

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("HASmartboard Kiosk Background"),
        &_sleepAssertion
    );
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end
