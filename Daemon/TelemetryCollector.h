#ifndef TelemetryCollector_h
#define TelemetryCollector_h
#if defined(__OBJC__) || defined(__APPLE__)
#import <Foundation/Foundation.h>
#endif

// ponytail: flat C struct, no NSObject overhead in hot path
typedef struct {
    // Battery
    int batteryLevel;           // 0-100 %
    int batteryCurrentMA;       // milliamps (negative = discharging)
    int batteryCycles;          // charge cycles
    int batteryTempDeciC;       // temperature in 0.1°C (e.g., 312 = 31.2°C)
    int batteryVoltageMV;       // millivolts
    int batteryHealthPct;       // max capacity / design capacity * 100

    // WiFi
    int wifiRSSI;               // dBm (e.g., -52)
    char wifiSSID[64];          // network name
    char wifiBSSID[24];         // MAC address string
    int wifiChannel;            // channel number
    int wifiLinkSpeed;          // Mbps
    int wifiNoise;              // dBm noise floor

    // Storage
    long long storageFreeBytes;
    long long storageTotalBytes;

    // Memory
    long long memoryFreeBytes;
    long long memoryActiveBytes;

    // Network
    long long netRxBytes;
    long long netTxBytes;

    // System
    int uptimeSeconds;
} TelemetrySnapshot;

// Collects all system telemetry. Call once per 30s cycle.
// Returns 0 on success, -1 on partial failure (some fields zeroed).
int TelemetryCollect(TelemetrySnapshot *snapshot);

// Returns a human-readable JSON string (caller must free).
char *TelemetrySnapshotToJSON(const TelemetrySnapshot *snapshot);

#endif
