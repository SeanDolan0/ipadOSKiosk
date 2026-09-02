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
#include <notify.h>
#include <sys/stat.h>

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

#pragma mark - App IPC Dispatch

#define SPOOL_DIR @"/var/mobile/Library/hasmartboard-cmds"
static uint64_t s_cmdSeq = 0;

static void ensureSpoolDirectory(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:SPOOL_DIR]) {
        NSDictionary *attrs = @{NSFilePosixPermissions: @(0777)};
        [fm createDirectoryAtPath:SPOOL_DIR withIntermediateDirectories:YES attributes:attrs error:nil];
        chmod([SPOOL_DIR UTF8String], 0777);
    }
}

static void dispatchAppCommand(const char *action, const char *value) {
    if (!action) return;
    @autoreleasepool {
        ensureSpoolDirectory();

        NSString *actionStr = [NSString stringWithUTF8String:action];
        NSString *valueStr = value ? [NSString stringWithUTF8String:value] : @"";
        NSDictionary *payload = @{
            @"action": actionStr,
            @"payload": valueStr
        };
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
        if (!error && jsonData) {
            uint64_t ts = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
            uint64_t seq = ++s_cmdSeq;
            NSString *filename = [NSString stringWithFormat:@"cmd-%llu-%llu.json",
                                  (unsigned long long)ts, (unsigned long long)seq];
            NSString *cmdPath = [SPOOL_DIR stringByAppendingPathComponent:filename];

            if ([jsonData writeToFile:cmdPath atomically:YES]) {
                chmod([cmdPath UTF8String], 0666);
                notify_post("com.hasmartboard.command");
                syslog(LOG_NOTICE, "kioskd: queued app IPC command '%s' in %s", action, [filename UTF8String]);
            } else {
                syslog(LOG_ERR, "kioskd: failed to write IPC command file %s", [cmdPath UTF8String]);
            }
        } else {
            syslog(LOG_ERR, "kioskd: failed to serialize IPC command '%s'", action);
        }
    }
}

#pragma mark - UI & Media Actions (Forwarded via IPC)

static void setScreen(const char *value) {
    if (value && strcmp(value, "OFF") == 0) {
        BBSetBrightness(0.0f);
    } else if (value && strcmp(value, "ON") == 0) {
        BBSetBrightness(0.8f);
    }
    dispatchAppCommand("setScreen", value);
}

static void setScreensaver(const char *value) {
    dispatchAppCommand("setScreensaver", value);
}

static void reloadApp(void) {
    dispatchAppCommand("reload", NULL);
}

static void wakeDevice(void) {
    dispatchAppCommand("wake", NULL);
}

static void beepDevice(void) {
    dispatchAppCommand("beep", NULL);
}

static void clearCache(void) {
    dispatchAppCommand("clearCache", NULL);
}

static void speakTTS(const char *value) {
    dispatchAppCommand("tts", value);
}

static void loadURL(const char *value) {
    dispatchAppCommand("loadURL", value);
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
