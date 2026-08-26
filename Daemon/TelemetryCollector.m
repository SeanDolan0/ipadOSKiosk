#import "TelemetryCollector.h"
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

// MobileWiFi extern declarations (private framework, no headers in SDK)
extern void *WiFiManagerClientCreate(void *allocator);
extern void *WiFiManagerClientCopyCurrentNetwork(void *manager);
extern int32_t WiFiNetworkGetRSSI(void *network);
extern const char *WiFiNetworkGetSSID(void *network);
extern const char *WiFiNetworkGetBSSID(void *network);
extern uint32_t WiFiNetworkGetChannel(void *network);
extern uint64_t WiFiNetworkGetLinkSpeed(void *network);
extern int32_t WiFiNetworkGetNoise(void *network);

#pragma mark - Battery (IOKit IOPowerSources)

static int collectBattery(TelemetrySnapshot *s) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return -1;

    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    if (!sources || CFArrayGetCount(sources) == 0) {
        if (sources) CFRelease(sources);
        CFRelease(info);
        return -1;
    }

    CFDictionaryRef desc = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, 0));
    if (!desc) {
        CFRelease(sources);
        CFRelease(info);
        return -1;
    }

    CFNumberRef val;

    val = CFDictionaryGetValue(desc, CFSTR(kIOPSCurrentCapacityKey));
    if (val) CFNumberGetValue(val, kCFNumberIntType, &s->batteryLevel);

    val = CFDictionaryGetValue(desc, CFSTR(kIOPSMaxCapacityKey));
    int maxCap = 0;
    if (val) CFNumberGetValue(val, kCFNumberIntType, &maxCap);
    if (maxCap > 0 && s->batteryLevel > 0) {
        s->batteryHealthPct = (int)((float)maxCap / 100.0f * 100.0f);
    }

    val = CFDictionaryGetValue(desc, CFSTR(kIOPSCycleCountKey));
    if (val) CFNumberGetValue(val, kCFNumberIntType, &s->batteryCycles);

    // Temperature from IORegistry charger node (0.1°C units)
    io_registry_entry_t charger = IORegistryEntryFromPath(
        kIOMasterPortDefault,
        "IOService:/AppleARMPE/charger"
    );
    if (charger) {
        CFMutableDictionaryRef props = NULL;
        IORegistryEntryCreateCFProperties(charger, &props, kCFAllocatorDefault, 0);
        if (props) {
            CFDictionaryRef batteryInfo = CFDictionaryGetValue(props, CFSTR("IOBatteryInfo"));
            if (batteryInfo) {
                CFNumberRef temp = CFDictionaryGetValue(batteryInfo, CFSTR("Temperature"));
                if (temp) CFNumberGetValue(temp, kCFNumberIntType, &s->batteryTempDeciC);

                CFNumberRef volt = CFDictionaryGetValue(batteryInfo, CFSTR("Voltage"));
                if (volt) CFNumberGetValue(volt, kCFNumberIntType, &s->batteryVoltageMV);
            }
            CFRelease(props);
        }
        IOObjectRelease(charger);
    }

    CFRelease(sources);
    CFRelease(info);
    return 0;
}

#pragma mark - WiFi (MobileWiFi.framework)

static int collectWiFi(TelemetrySnapshot *s) {
    void *manager = WiFiManagerClientCreate(kCFAllocatorDefault);
    if (!manager) return -1;

    void *network = WiFiManagerClientCopyCurrentNetwork(manager);
    if (!network) {
        CFRelease(manager);
        return -1;
    }

    s->wifiRSSI = WiFiNetworkGetRSSI(network);

    const char *ssid = WiFiNetworkGetSSID(network);
    if (ssid) {
        strncpy(s->wifiSSID, ssid, sizeof(s->wifiSSID) - 1);
        s->wifiSSID[sizeof(s->wifiSSID) - 1] = '\0';
    }

    const char *bssid = WiFiNetworkGetBSSID(network);
    if (bssid) {
        strncpy(s->wifiBSSID, bssid, sizeof(s->wifiBSSID) - 1);
        s->wifiBSSID[sizeof(s->wifiBSSID) - 1] = '\0';
    }

    s->wifiChannel = (int)WiFiNetworkGetChannel(network);
    s->wifiLinkSpeed = (int)WiFiNetworkGetLinkSpeed(network);
    s->wifiNoise = WiFiNetworkGetNoise(network);

    CFRelease(network);
    CFRelease(manager);
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
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&stats, &count) != KERN_SUCCESS) {
        return -1;
    }

    s->memoryFreeBytes = (long long)stats.free_count * pageSize;
    s->memoryActiveBytes = (long long)stats.active_count * pageSize;
    return 0;
}

#pragma mark - Network Interface Stats

static int collectNetwork(TelemetrySnapshot *s) {
    struct ifaddrs *interfaces;
    if (getifaddrs(&interfaces) != 0) return -1;

    for (struct ifaddrs *iface = interfaces; iface; iface = iface->ifa_next) {
        if (iface->ifa_name && strcmp(iface->ifa_name, "en0") == 0 &&
            iface->ifa_data) {
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
