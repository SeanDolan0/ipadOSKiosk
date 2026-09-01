#include "MQTTTelemetry.h"
#include <stdio.h>
#include <string.h>

typedef enum {
    ENT_BATTERY_LEVEL = 0,
    ENT_BATTERY_CURRENT,
    ENT_BATTERY_TEMP,
    ENT_BATTERY_HEALTH,
    ENT_BATTERY_CYCLES,
    ENT_WIFI_RSSI,
    ENT_WIFI_SSID,
    ENT_WIFI_LINK_SPEED,
    ENT_STORAGE_FREE,
    ENT_MEMORY_FREE,
    ENT_UPTIME,
    ENT_NETWORK_RX_BYTES,
    ENT_NETWORK_TX_BYTES,
    ENT_COUNT
} KioskEntityIndex;

typedef struct {
    const char *entity;       // short id appended to sensor topic
    const char *friendly;     // HA friendly name
    const char *unit;         // unit_of_measurement ("" = omit)
    const char *deviceClass;  // device_class ("" = omit)
} KioskEntity;

static const KioskEntity kEntities[ENT_COUNT] = {
    [ENT_BATTERY_LEVEL]      = {"battery_level",       "Kiosk Battery Level",     "%",  "battery"},
    [ENT_BATTERY_CURRENT]    = {"battery_current",     "Kiosk Battery Current",   "mA", ""},
    [ENT_BATTERY_TEMP]       = {"battery_temp",        "Kiosk Battery Temp",      "°C", "temperature"},
    [ENT_BATTERY_HEALTH]     = {"battery_health",      "Kiosk Battery Health",    "%",  "battery"},
    [ENT_BATTERY_CYCLES]     = {"battery_cycles",      "Kiosk Battery Cycles",    "count", ""},
    [ENT_WIFI_RSSI]          = {"wifi_rssi",           "Kiosk WiFi RSSI",         "dBm","signal_strength"},
    [ENT_WIFI_SSID]          = {"wifi_ssid",           "Kiosk WiFi SSID",         "",   ""},
    [ENT_WIFI_LINK_SPEED]    = {"wifi_link_speed",     "Kiosk WiFi Link Speed",   "Mbps",""},
    [ENT_STORAGE_FREE]       = {"storage_free",        "Kiosk Storage Free",      "MB", "data_size"},
    [ENT_MEMORY_FREE]        = {"memory_free",         "Kiosk Memory Free",       "MB", "data_size"},
    [ENT_UPTIME]             = {"uptime",              "Kiosk Uptime",            "s",  "duration"},
    [ENT_NETWORK_RX_BYTES]   = {"network_rx_bytes",    "Kiosk Network RX",        "bytes", "data_size"},
    [ENT_NETWORK_TX_BYTES]   = {"network_tx_bytes",    "Kiosk Network TX",        "bytes", "data_size"},
};

int mqttEntityCount(void) {
    return ENT_COUNT;
}

int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    int n = snprintf(out, cap, "homeassistant/sensor/kiosk_%s/config", kEntities[index].entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStateTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    int n = snprintf(out, cap, "%s/sensor/%s/state", prefix, kEntities[index].entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    const KioskEntity *e = &kEntities[index];
    char stateTopic[256];
    if (mqttStateTopic(prefix, index, stateTopic, sizeof(stateTopic)) != 0) return -1;
    char uniqueId[128];
    snprintf(uniqueId, sizeof(uniqueId), "kiosk_%s", e->entity);
    int n;
    if (e->deviceClass[0]) {
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
            "\"unit_of_measurement\":\"%s\",\"device_class\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, stateTopic, e->unit, e->deviceClass, prefix);
    } else {
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
            "\"unit_of_measurement\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, stateTopic, e->unit, prefix);
    }
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStatePayload(const TelemetrySnapshot *s, int index, char *out, size_t cap) {
    if (!s) return -1;
    int n = -1;
    switch (index) {
        case ENT_BATTERY_LEVEL:    n = snprintf(out, cap, "%d", s->batteryLevel); break;
        case ENT_BATTERY_CURRENT:  n = snprintf(out, cap, "%d", s->batteryCurrentMA); break;
        case ENT_BATTERY_TEMP:     n = snprintf(out, cap, "%.1f", s->batteryTempDeciC / 10.0); break;
        case ENT_BATTERY_HEALTH:   n = snprintf(out, cap, "%d", s->batteryHealthPct); break;
        case ENT_BATTERY_CYCLES:   n = snprintf(out, cap, "%d", s->batteryCycles); break;
        case ENT_WIFI_RSSI:        n = snprintf(out, cap, "%d", s->wifiRSSI); break;
        case ENT_WIFI_SSID:        n = snprintf(out, cap, "%s", s->wifiSSID[0] ? s->wifiSSID : ""); break;
        case ENT_WIFI_LINK_SPEED:  n = snprintf(out, cap, "%d", s->wifiLinkSpeed); break;
        case ENT_STORAGE_FREE:     n = snprintf(out, cap, "%lld", s->storageFreeBytes / (1024 * 1024)); break;
        case ENT_MEMORY_FREE:      n = snprintf(out, cap, "%lld", s->memoryFreeBytes / (1024 * 1024)); break;
        case ENT_UPTIME:           n = snprintf(out, cap, "%d", s->uptimeSeconds); break;
        case ENT_NETWORK_RX_BYTES: n = snprintf(out, cap, "%lld", s->netRxBytes); break;
        case ENT_NETWORK_TX_BYTES: n = snprintf(out, cap, "%lld", s->netTxBytes); break;
        default: return -1;
    }
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}
