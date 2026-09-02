#import "DeviceControl.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/syslog.h>
#include <dlfcn.h>

// RB_AUTOBOOT not in iOS SDK headers, defined in BSD <sys/reboot.h>
#ifndef RB_AUTOBOOT
#define RB_AUTOBOOT 0x0405
#endif

// BackBoardServices — brightness control
extern void BBSetBrightness(float value);

#pragma mark - Brightness

static void setBrightness(const char *value) {
    if (!value) return;
    float level = (float)atof(value);
    if (level > 1.0f) {
        level = level / 100.0f;
    }
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;
    BBSetBrightness(level);
    syslog(LOG_NOTICE, "kioskd: brightness set to %.2f", level);
}

#pragma mark - Volume

static void setVolume(const char *value) {
    if (!value) return;
    float level = (float)atof(value);
    if (level > 1.0f) {
        level = level / 100.0f;
    }
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
    // MobileWiFi is a private API whose symbols vary by iOS build; resolve at
    // runtime so a missing symbol fails the command instead of crashing kioskd.
    void *(*createFn)(void *) = dlsym(RTLD_DEFAULT, "WiFiManagerClientCreate");
    void (*setPowerFn)(void *, int) = dlsym(RTLD_DEFAULT, "WiFiManagerClientSetPower");
    if (!createFn || !setPowerFn) {
        syslog(LOG_WARNING, "kioskd: WiFi control unavailable");
        return;
    }
    void *manager = createFn(NULL);
    if (manager) {
        setPowerFn(manager, power);
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

static void restartDaemon(void) {
    syslog(LOG_NOTICE, "kioskd: restart requested");
    exit(0);
}

#pragma mark - UI & Media Actions (Forwarded via IPC in Task 5)

static void setScreen(const char *value) {
    syslog(LOG_NOTICE, "kioskd: setScreen %s", value ? value : "");
}

static void setScreensaver(const char *value) {
    syslog(LOG_NOTICE, "kioskd: setScreensaver %s", value ? value : "");
}

static void reloadApp(void) {
    syslog(LOG_NOTICE, "kioskd: reload requested");
}

static void wakeDevice(void) {
    syslog(LOG_NOTICE, "kioskd: wake requested");
}

static void beepDevice(void) {
    syslog(LOG_NOTICE, "kioskd: beep requested");
}

static void clearCache(void) {
    syslog(LOG_NOTICE, "kioskd: clearCache requested");
}

static void speakTTS(const char *value) {
    syslog(LOG_NOTICE, "kioskd: tts '%s'", value ? value : "");
}

static void loadURL(const char *value) {
    syslog(LOG_NOTICE, "kioskd: loadURL '%s'", value ? value : "");
}

#pragma mark - Public API

void DeviceControlExecute(const char *action, const char *value, void *context) {
    (void)context;

    if (!action) return;

    if (strcmp(action, "setBrightness") == 0) setBrightness(value);
    else if (strcmp(action, "setVolume") == 0) setVolume(value);
    else if (strcmp(action, "muteVolume") == 0) muteVolume(value);
    else if (strcmp(action, "toggleWiFi") == 0) toggleWiFi(value);
    else if (strcmp(action, "toggleBluetooth") == 0) toggleBluetooth(value);
    else if (strcmp(action, "setDND") == 0) setDND(value);
    else if (strcmp(action, "lockOrientation") == 0) lockOrientation(value);
    else if (strcmp(action, "reboot") == 0) rebootDevice();
    else if (strcmp(action, "relaunchApp") == 0) relaunchApp();
    else if (strcmp(action, "restartDaemon") == 0) restartDaemon();
    else if (strcmp(action, "setScreen") == 0) setScreen(value);
    else if (strcmp(action, "setScreensaver") == 0) setScreensaver(value);
    else if (strcmp(action, "reload") == 0) reloadApp();
    else if (strcmp(action, "wake") == 0) wakeDevice();
    else if (strcmp(action, "beep") == 0) beepDevice();
    else if (strcmp(action, "clearCache") == 0) clearCache();
    else if (strcmp(action, "tts") == 0) speakTTS(value);
    else if (strcmp(action, "loadURL") == 0) loadURL(value);
    else {
        syslog(LOG_WARNING, "kioskd: unknown command '%s'", action);
    }
}
