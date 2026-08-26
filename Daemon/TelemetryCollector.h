#ifndef TelemetryCollector_h
#define TelemetryCollector_h
#import <Foundation/Foundation.h>
typedef struct {
    int batteryLevel;
    int batteryCurrentMA;
    int batteryCycles;
    int batteryTempDeciC;
    int batteryVoltageMV;
    int batteryHealthPct;
    int wifiRSSI;
    char wifiSSID[64];
    char wifiBSSID[24];
    int wifiChannel;
    int wifiLinkSpeed;
    int wifiNoise;
    long long storageFreeBytes;
    long long storageTotalBytes;
    long long memoryFreeBytes;
    long long memoryActiveBytes;
    long long netRxBytes;
    long long netTxBytes;
    int uptimeSeconds;
} TelemetrySnapshot;
int TelemetryCollect(TelemetrySnapshot *snapshot);
char *TelemetrySnapshotToJSON(const TelemetrySnapshot *snapshot);
#endif
