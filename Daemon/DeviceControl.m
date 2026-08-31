#import "DeviceControl.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/syslog.h>

// RB_AUTOBOOT not in iOS SDK headers, defined in BSD <sys/reboot.h>
#ifndef RB_AUTOBOOT
#define RB_AUTOBOOT 0x0405
#endif

// BackBoardServices — brightness control
extern void BBSetBrightness(float value);

// MobileWiFi — WiFi toggle
extern void *WiFiManagerClientCreate(void *allocator);
extern void WiFiManagerClientSetPower(void *manager, int power);

#pragma mark - Brightness

static void setBrightness(const char *value) {
    float level = atof(value);
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;
    BBSetBrightness(level);
    syslog(LOG_NOTICE, "kioskd: brightness set to %.2f", level);
}

#pragma mark - Volume

static void setVolume(const char *value) {
    float level = atof(value);
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;

    // ponytail: objc runtime lookup — no compile-time dep on private headers
    Class cls = objc_getClass("AVSystemController");
    if (cls) {
        id controller = [(id)cls performSelector:@selector(sharedInstance)];
        if (controller) {
            [controller performSelector:@selector(setSystemVolume:)
                            withObject:@(level)];
            syslog(LOG_NOTICE, "kioskd: volume set to %.2f", level);
        }
    }
}

static void muteVolume(const char *value) {
    BOOL mute = (strcmp(value, "true") == 0);
    Class cls = objc_getClass("AVSystemController");
    if (cls) {
        id controller = [(id)cls performSelector:@selector(sharedInstance)];
        if (controller) {
            [controller performSelector:@selector(muteSystemVolume:)
                            withObject:@(mute)];
            syslog(LOG_NOTICE, "kioskd: mute %s", mute ? "on" : "off");
        }
    }
}

#pragma mark - WiFi

static void toggleWiFi(const char *value) {
    int power = (strcmp(value, "true") == 0) ? 1 : 0;
    void *manager = WiFiManagerClientCreate(NULL);
    if (manager) {
        WiFiManagerClientSetPower(manager, power);
        CFRelease(manager);
        syslog(LOG_NOTICE, "kioskd: WiFi %s", power ? "on" : "off");
    }
}

#pragma mark - Bluetooth

static void toggleBluetooth(const char *value) {
    BOOL enabled = (strcmp(value, "true") == 0);
    Class cls = objc_getClass("BluetoothManager");
    if (cls) {
        id manager = [(id)cls performSelector:@selector(sharedManager)];
        if (manager) {
            [manager performSelector:@selector(setEnabled:)
                          withObject:@(enabled)];
            syslog(LOG_NOTICE, "kioskd: Bluetooth %s", enabled ? "on" : "off");
        }
    }
}

#pragma mark - DND

static void setDND(const char *value) {
    BOOL enabled = (strcmp(value, "true") == 0);
    NSString *path = @"/var/mobile/Library/Preferences/com.apple.donotdisturb.plist";
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!prefs) prefs = [NSMutableDictionary dictionary];

    prefs[@"enabled"] = @(enabled);
    prefs[@"scheduleEnabled"] = @NO;
    [prefs writeToFile:path atomically:YES];
    syslog(LOG_NOTICE, "kioskd: DND %s", enabled ? "on" : "off");
}

#pragma mark - Orientation

static void lockOrientation(const char *value) {
    BOOL lock = (strcmp(value, "true") == 0);
    Class cls = objc_getClass("SBOrientationLockManager");
    if (cls) {
        id manager = [(id)cls performSelector:@selector(sharedInstance)];
        if (manager) {
            if (lock) {
                [manager performSelector:@selector(lock)];
            } else {
                [manager performSelector:@selector(unlock)];
            }
            syslog(LOG_NOTICE, "kioskd: orientation %s", lock ? "locked" : "unlocked");
        }
    }
}

#pragma mark - Reboot

static void rebootDevice(void) {
    syslog(LOG_NOTICE, "kioskd: rebooting device");
    sync();
    reboot(RB_AUTOBOOT);
}

#pragma mark - Relaunch App

static void relaunchApp(void) {
    FILE *p = popen("pidof HASmartboard", "r");
    if (p) {
        char pidStr[16] = {0};
        if (fgets(pidStr, sizeof(pidStr), p)) {
            int pid = atoi(pidStr);
            if (pid > 0) {
                kill(pid, SIGKILL);
                syslog(LOG_NOTICE, "kioskd: relaunched app (killed pid %d)", pid);
            }
        }
        pclose(p);
    }
}

#pragma mark - Public API

void DeviceControlExecute(const char *action, const char *value, void *context) {
    (void)context;

    if (strcmp(action, "setBrightness") == 0) setBrightness(value);
    else if (strcmp(action, "setVolume") == 0) setVolume(value);
    else if (strcmp(action, "muteVolume") == 0) muteVolume(value);
    else if (strcmp(action, "toggleWiFi") == 0) toggleWiFi(value);
    else if (strcmp(action, "toggleBluetooth") == 0) toggleBluetooth(value);
    else if (strcmp(action, "setDND") == 0) setDND(value);
    else if (strcmp(action, "lockOrientation") == 0) lockOrientation(value);
    else if (strcmp(action, "reboot") == 0) rebootDevice();
    else if (strcmp(action, "relaunchApp") == 0) relaunchApp();
    else {
        syslog(LOG_WARNING, "kioskd: unknown command '%s'", action);
    }
}
