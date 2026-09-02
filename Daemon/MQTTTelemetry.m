#include "MQTTTelemetry.h"
#include <stdio.h>
#include <string.h>

#define SENSOR_COUNT 13

typedef enum {
    // 13 Telemetry Sensors
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

    // 3 Switches
    ENT_SW_SCREEN,
    ENT_SW_SCREENSAVER,
    ENT_SW_DND,

    // 2 Numbers
    ENT_NUM_BRIGHTNESS,
    ENT_NUM_VOLUME,

    // 6 Buttons
    ENT_BTN_RELOAD,
    ENT_BTN_WAKE,
    ENT_BTN_BEEP,
    ENT_BTN_CLEAR_CACHE,
    ENT_BTN_REBOOT,
    ENT_BTN_RELAUNCH,

    // 2 Text Entities
    ENT_TXT_TTS,
    ENT_TXT_URL,

    ENT_COUNT
} KioskEntityIndex;

typedef struct {
    const char *component;    // "sensor", "switch", "number", "button", "text"
    const char *entity;       // short ID (e.g. "battery_level", "screen", "brightness", "reload", "tts")
    const char *friendly;     // HA friendly name (e.g. "Kiosk Screen")
    const char *unit;         // unit_of_measurement ("" = omit)
    const char *deviceClass;  // device_class ("" = omit)
    int hasCommandTopic;      // 1 if <prefix>/set/<entity> exists
    int hasStateTopic;        // 1 if state topic exists
} KioskEntity;

static const KioskEntity kEntities[ENT_COUNT] = {
    // 13 Sensors
    [ENT_BATTERY_LEVEL]    = {"sensor", "battery_level",    "Kiosk Battery Level",   "%",     "battery",         0, 1},
    [ENT_BATTERY_CURRENT]  = {"sensor", "battery_current",  "Kiosk Battery Current", "mA",    "",                0, 1},
    [ENT_BATTERY_TEMP]     = {"sensor", "battery_temp",     "Kiosk Battery Temp",    "°C",    "temperature",     0, 1},
    [ENT_BATTERY_HEALTH]   = {"sensor", "battery_health",   "Kiosk Battery Health",  "%",     "",                0, 1},
    [ENT_BATTERY_CYCLES]   = {"sensor", "battery_cycles",   "Kiosk Battery Cycles",  "count", "",                0, 1},
    [ENT_WIFI_RSSI]        = {"sensor", "wifi_rssi",        "Kiosk WiFi RSSI",       "dBm",   "signal_strength", 0, 1},
    [ENT_WIFI_SSID]        = {"sensor", "wifi_ssid",        "Kiosk WiFi SSID",       "",      "",                0, 1},
    [ENT_WIFI_LINK_SPEED]  = {"sensor", "wifi_link_speed",  "Kiosk WiFi Link Speed", "Mbps",  "",                0, 1},
    [ENT_STORAGE_FREE]     = {"sensor", "storage_free",     "Kiosk Storage Free",    "MB",    "data_size",       0, 1},
    [ENT_MEMORY_FREE]      = {"sensor", "memory_free",      "Kiosk Memory Free",     "MB",    "data_size",       0, 1},
    [ENT_UPTIME]           = {"sensor", "uptime",           "Kiosk Uptime",          "s",     "duration",        0, 1},
    [ENT_NETWORK_RX_BYTES] = {"sensor", "network_rx_bytes", "Kiosk Network RX",      "bytes", "data_size",       0, 1},
    [ENT_NETWORK_TX_BYTES] = {"sensor", "network_tx_bytes", "Kiosk Network TX",      "bytes", "data_size",       0, 1},

    // 3 Switches
    [ENT_SW_SCREEN]        = {"switch", "screen",           "Kiosk Screen",          "",      "",                1, 1},
    [ENT_SW_SCREENSAVER]   = {"switch", "screensaver",      "Kiosk Screensaver",     "",      "",                1, 1},
    [ENT_SW_DND]           = {"switch", "dnd",              "Kiosk Do Not Disturb",  "",      "",                1, 1},

    // 2 Numbers
    [ENT_NUM_BRIGHTNESS]   = {"number", "brightness",       "Kiosk Brightness",      "%",     "",                1, 0},
    [ENT_NUM_VOLUME]       = {"number", "volume",           "Kiosk Volume",          "%",     "",                1, 0},

    // 6 Buttons
    [ENT_BTN_RELOAD]       = {"button", "reload",           "Kiosk Reload",          "",      "",                1, 0},
    [ENT_BTN_WAKE]         = {"button", "wake",             "Kiosk Wake",            "",      "",                1, 0},
    [ENT_BTN_BEEP]         = {"button", "beep",             "Kiosk Beep",            "",      "",                1, 0},
    [ENT_BTN_CLEAR_CACHE]  = {"button", "clear_cache",      "Kiosk Clear Cache",     "",      "",                1, 0},
    [ENT_BTN_REBOOT]       = {"button", "reboot",           "Kiosk Reboot",          "",      "",                1, 0},
    [ENT_BTN_RELAUNCH]     = {"button", "relaunch",         "Kiosk Relaunch",        "",      "",                1, 0},

    // 2 Text Entities
    [ENT_TXT_TTS]          = {"text",   "tts",              "Kiosk TTS",             "",      "",                1, 0},
    [ENT_TXT_URL]          = {"text",   "url",              "Kiosk URL",             "",      "",                1, 0},
};

int mqttEntityCount(void) {
    return ENT_COUNT;
}

int mqttSensorCount(void) {
    return SENSOR_COUNT;
}

const char *mqttEntityComponent(int index) {
    if (index < 0 || index >= ENT_COUNT) return NULL;
    return kEntities[index].component;
}

const char *mqttEntityName(int index) {
    if (index < 0 || index >= ENT_COUNT) return NULL;
    return kEntities[index].entity;
}

int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap) {
    (void)prefix;
    if (index < 0 || index >= ENT_COUNT || !out || cap == 0) return -1;
    const KioskEntity *e = &kEntities[index];
    int n = snprintf(out, cap, "homeassistant/%s/kiosk_%s/config", e->component, e->entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStateTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT || !out || cap == 0 || !prefix) return -1;
    const KioskEntity *e = &kEntities[index];
    if (!e->hasStateTopic) return -1;
    int n;
    if (strcmp(e->component, "sensor") == 0) {
        n = snprintf(out, cap, "%s/sensor/%s/state", prefix, e->entity);
    } else {
        n = snprintf(out, cap, "%s/state/%s", prefix, e->entity);
    }
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttCommandTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT || !out || cap == 0 || !prefix) return -1;
    const KioskEntity *e = &kEntities[index];
    if (!e->hasCommandTopic) return -1;
    int n = snprintf(out, cap, "%s/set/%s", prefix, e->entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT || !out || cap == 0 || !prefix) return -1;
    const KioskEntity *e = &kEntities[index];
    char uniqueId[128];
    snprintf(uniqueId, sizeof(uniqueId), "kiosk_%s", e->entity);

    int n = -1;

    if (strcmp(e->component, "sensor") == 0) {
        char stateTopic[256];
        if (mqttStateTopic(prefix, index, stateTopic, sizeof(stateTopic)) != 0) return -1;
        if (e->deviceClass[0] && e->unit[0]) {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
                "\"unit_of_measurement\":\"%s\",\"device_class\":\"%s\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, stateTopic, e->unit, e->deviceClass, prefix);
        } else if (e->unit[0]) {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
                "\"unit_of_measurement\":\"%s\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, stateTopic, e->unit, prefix);
        } else if (e->deviceClass[0]) {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
                "\"device_class\":\"%s\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, stateTopic, e->deviceClass, prefix);
        } else {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, stateTopic, prefix);
        }
    } else if (strcmp(e->component, "switch") == 0) {
        char cmdTopic[256], stateTopic[256];
        if (mqttCommandTopic(prefix, index, cmdTopic, sizeof(cmdTopic)) != 0) return -1;
        if (e->hasStateTopic && mqttStateTopic(prefix, index, stateTopic, sizeof(stateTopic)) == 0) {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"command_topic\":\"%s\",\"state_topic\":\"%s\","
                "\"payload_on\":\"ON\",\"payload_off\":\"OFF\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, cmdTopic, stateTopic, prefix);
        } else {
            n = snprintf(out, cap,
                "{\"name\":\"%s\",\"unique_id\":\"%s\",\"command_topic\":\"%s\","
                "\"payload_on\":\"ON\",\"payload_off\":\"OFF\","
                "\"availability_topic\":\"%s/status\","
                "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
                e->friendly, uniqueId, cmdTopic, prefix);
        }
    } else if (strcmp(e->component, "number") == 0) {
        char cmdTopic[256];
        if (mqttCommandTopic(prefix, index, cmdTopic, sizeof(cmdTopic)) != 0) return -1;
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"command_topic\":\"%s\","
            "\"min\":0,\"max\":100,\"step\":1,\"unit_of_measurement\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, cmdTopic, e->unit[0] ? e->unit : "%", prefix);
    } else if (strcmp(e->component, "button") == 0) {
        char cmdTopic[256];
        if (mqttCommandTopic(prefix, index, cmdTopic, sizeof(cmdTopic)) != 0) return -1;
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"command_topic\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, cmdTopic, prefix);
    } else if (strcmp(e->component, "text") == 0) {
        char cmdTopic[256];
        if (mqttCommandTopic(prefix, index, cmdTopic, sizeof(cmdTopic)) != 0) return -1;
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"command_topic\":\"%s\",\"mode\":\"text\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, cmdTopic, prefix);
    }

    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStatePayload(const TelemetrySnapshot *s, int index, char *out, size_t cap) {
    if (!s || !out || cap == 0) return -1;
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
    return (n >= 0 && (size_t)n < cap) ? 0 : -1;
}

