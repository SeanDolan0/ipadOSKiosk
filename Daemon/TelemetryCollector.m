#import "TelemetryCollector.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <syslog.h>
#include <dlfcn.h>

// IOKit PowerSources declarations (headers not in iOS SDK, symbols in IOKit.tbd)
extern CFTypeRef IOPSCopyPowerSourcesInfo(void);
extern CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob);
extern CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef source);

#pragma mark - Battery (IOKit IOPowerSources)

static int collectBattery(TelemetrySnapshot *s) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return -1;
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    if (!sources) { CFRelease(info); return -1; }
    if (CFArrayGetCount(sources) == 0) { CFRelease(sources); CFRelease(info); return -1; }
    CFDictionaryRef desc = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, 0));
    if (!desc || CFGetTypeID(desc) != CFDictionaryGetTypeID()) {
        CFRelease(sources); CFRelease(info); return -1;
    }
    // Use runtime-created CFString keys to avoid CFSTR linker issues
    CFStringRef capKey = CFStringCreateWithCString(NULL, "Current Capacity", kCFStringEncodingMacRoman);
    CFStringRef maxKey = CFStringCreateWithCString(NULL, "Max Capacity", kCFStringEncodingMacRoman);
    CFStringRef cycKey = CFStringCreateWithCString(NULL, "Cycle Count", kCFStringEncodingMacRoman);
    CFStringRef ampKey = CFStringCreateWithCString(NULL, "Amperage", kCFStringEncodingMacRoman);
    CFStringRef tempKey = CFStringCreateWithCString(NULL, "Temperature", kCFStringEncodingMacRoman);
    CFStringRef voltKey = CFStringCreateWithCString(NULL, "Voltage", kCFStringEncodingMacRoman);
    CFNumberRef val;
    val = (CFNumberRef)CFDictionaryGetValue(desc, capKey);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &s->batteryLevel);
    val = (CFNumberRef)CFDictionaryGetValue(desc, maxKey);
    int maxCap = 0;
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &maxCap);
    if (maxCap > 0 && s->batteryLevel > 0)
        s->batteryHealthPct = (int)((float)maxCap / 100.0f * 100.0f);
    val = (CFNumberRef)CFDictionaryGetValue(desc, cycKey);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &s->batteryCycles);
    val = (CFNumberRef)CFDictionaryGetValue(desc, ampKey);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &s->batteryCurrentMA);
    val = (CFNumberRef)CFDictionaryGetValue(desc, tempKey);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &s->batteryTempDeciC);
    val = (CFNumberRef)CFDictionaryGetValue(desc, voltKey);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID())
        CFNumberGetValue(val, kCFNumberIntType, &s->batteryVoltageMV);
    CFRelease(capKey);
    CFRelease(maxKey);
    CFRelease(cycKey);
    CFRelease(ampKey);
    CFRelease(tempKey);
    CFRelease(voltKey);
    CFRelease(sources);
    CFRelease(info);
    return 0;
}

#pragma mark - WiFi (private MobileWiFi API, resolved at runtime)

// MobileWiFi's current-network symbols vary by iOS build (and can be absent),
// so everything is dlsym'd and any missing symbol degrades to empty wifi
// metrics instead of aborting. On iOS 12 the property route is
// WiFiManagerClientCopyDevices → WiFiDeviceClientCopyProperty.
static int collectWiFi(TelemetrySnapshot *s) {
    void *(*createFn)(void *) = dlsym(RTLD_DEFAULT, "WiFiManagerClientCreate");
    CFArrayRef (*devicesFn)(void *) = dlsym(RTLD_DEFAULT, "WiFiManagerClientCopyDevices");
    CFTypeRef (*propFn)(void *, CFStringRef) = dlsym(RTLD_DEFAULT, "WiFiDeviceClientCopyProperty");
    if (!createFn || !devicesFn || !propFn) return -1;

    void *manager = createFn(NULL);
    if (!manager) return -1;
    CFArrayRef devices = devicesFn(manager);
    if (!devices || CFArrayGetCount(devices) == 0) {
        if (devices) CFRelease(devices);
        return -1;
    }
    void *device = (void *)CFArrayGetValueAtIndex(devices, 0);

    CFStringRef ssidKey = CFStringCreateWithCString(NULL, "SSID", kCFStringEncodingUTF8);
    CFStringRef bssidKey = CFStringCreateWithCString(NULL, "BSSID", kCFStringEncodingUTF8);
    CFStringRef rssiKey = CFStringCreateWithCString(NULL, "RSSI", kCFStringEncodingUTF8);
    CFStringRef chanKey = CFStringCreateWithCString(NULL, "CHANNEL", kCFStringEncodingUTF8);
    CFStringRef speedKey = CFStringCreateWithCString(NULL, "LINK_SPEED", kCFStringEncodingUTF8);
    CFStringRef noiseKey = CFStringCreateWithCString(NULL, "NOISE", kCFStringEncodingUTF8);

    CFTypeRef v = propFn(device, ssidKey);
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        const char *ssid = CFStringGetCStringPtr(v, kCFStringEncodingUTF8);
        if (ssid) { strncpy(s->wifiSSID, ssid, sizeof(s->wifiSSID) - 1); s->wifiSSID[sizeof(s->wifiSSID) - 1] = '\0'; }
    }
    v = propFn(device, bssidKey);
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        const char *bssid = CFStringGetCStringPtr(v, kCFStringEncodingUTF8);
        if (bssid) { strncpy(s->wifiBSSID, bssid, sizeof(s->wifiBSSID) - 1); s->wifiBSSID[sizeof(s->wifiBSSID) - 1] = '\0'; }
    }
    v = propFn(device, rssiKey);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &s->wifiRSSI);
    v = propFn(device, chanKey);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &s->wifiChannel);
    v = propFn(device, speedKey);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) {
        int speed = 0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &speed);
        s->wifiLinkSpeed = speed;
    }
    v = propFn(device, noiseKey);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &s->wifiNoise);

    CFRelease(ssidKey); CFRelease(bssidKey); CFRelease(rssiKey);
    CFRelease(chanKey); CFRelease(speedKey); CFRelease(noiseKey);
    CFRelease(devices);
    return 0;
}

#pragma mark - Storage

static int collectStorage(TelemetrySnapshot *s) {
    struct statvfs buf;
    if (statvfs("/", &buf) != 0) return -1;
    s->storageFreeBytes = (long long)buf.f_bavail * buf.f_frsize;
    s->storageTotalBytes = (long long)buf.f_blocks * buf.f_frsize;
    return 0;
}

#pragma mark - Memory

static int collectMemory(TelemetrySnapshot *s) {
    vm_size_t pageSize = 0;
    host_page_size(mach_host_self(), &pageSize);
    vm_statistics64_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&stats, &count) != KERN_SUCCESS)
        return -1;
    s->memoryFreeBytes = (long long)stats.free_count * pageSize;
    s->memoryActiveBytes = (long long)stats.active_count * pageSize;
    return 0;
}

#pragma mark - Network Interface Stats

static int collectNetwork(TelemetrySnapshot *s) {
    struct ifaddrs *interfaces;
    if (getifaddrs(&interfaces) != 0) return -1;
    for (struct ifaddrs *iface = interfaces; iface; iface = iface->ifa_next) {
        if (iface->ifa_name && strcmp(iface->ifa_name, "en0") == 0 && iface->ifa_data) {
            struct if_data *data = (struct if_data *)iface->ifa_data;
            s->netRxBytes = data->ifi_ibytes;
            s->netTxBytes = data->ifi_obytes;
            break;
        }
    }
    freeifaddrs(interfaces);
    return 0;
}

#pragma mark - Uptime

static int collectUptime(TelemetrySnapshot *s) {
    struct timeval boottime;
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    size_t len = sizeof(boottime);
    if (sysctl(mib, 2, &boottime, &len, NULL, 0) != 0) return -1;
    time_t now = time(NULL);
    s->uptimeSeconds = (int)(now - boottime.tv_sec);
    return 0;
}

#pragma mark - Public API

int TelemetryCollect(TelemetrySnapshot *snapshot) {
    memset(snapshot, 0, sizeof(TelemetrySnapshot));
    int failures = 0;
    failures += collectBattery(snapshot) < 0 ? 1 : 0;
    failures += collectWiFi(snapshot) < 0 ? 1 : 0;
    failures += collectStorage(snapshot) < 0 ? 1 : 0;
    failures += collectMemory(snapshot) < 0 ? 1 : 0;
    failures += collectNetwork(snapshot) < 0 ? 1 : 0;
    failures += collectUptime(snapshot) < 0 ? 1 : 0;
    return failures > 0 ? -1 : 0;
}

char *TelemetrySnapshotToJSON(const TelemetrySnapshot *s) {
    char *json = malloc(2048);
    if (!json) return NULL;
    snprintf(json, 2048,
        "{"
        "\"battery\":{\"level\":%d,\"current\":%d,\"temp\":%d,"
        "\"cycles\":%d,\"voltage\":%d,\"health\":%d},"
        "\"wifi\":{\"rssi\":%d,\"ssid\":\"%s\",\"bssid\":\"%s\","
        "\"channel\":%d,\"linkSpeed\":%d,\"noise\":%d},"
        "\"storage\":{\"free\":%lld,\"total\":%lld},"
        "\"memory\":{\"free\":%lld,\"active\":%lld},"
        "\"network\":{\"rxBytes\":%lld,\"txBytes\":%lld},"
        "\"uptime\":%d,"
        "\"timestamp\":%lld"
        "}",
        s->batteryLevel, s->batteryCurrentMA, s->batteryTempDeciC,
        s->batteryCycles, s->batteryVoltageMV, s->batteryHealthPct,
        s->wifiRSSI, s->wifiSSID, s->wifiBSSID,
        s->wifiChannel, s->wifiLinkSpeed, s->wifiNoise,
        s->storageFreeBytes, s->storageTotalBytes,
        s->memoryFreeBytes, s->memoryActiveBytes,
        s->netRxBytes, s->netTxBytes,
        s->uptimeSeconds,
        (long long)time(NULL)
    );
    return json;
}
