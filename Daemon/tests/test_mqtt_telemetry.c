#include "../MQTTTelemetry.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>

static void test_entity_counts(void) {
    int total = mqttEntityCount();
    assert(total == 26);

    int sensors = mqttSensorCount();
    assert(sensors == 13);

    printf("  [PASS] test_entity_counts (total=%d, sensors=%d)\n", total, sensors);
}

static void test_discovery_topics(void) {
    const char *prefix = "kiosk";
    char topic[256];

    // Check specific known entity discovery topics
    assert(mqttDiscoveryTopic(prefix, 0, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/sensor/kiosk_battery_level/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 13, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/switch/kiosk_screen/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 14, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/switch/kiosk_screensaver/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 15, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/switch/kiosk_dnd/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 16, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/number/kiosk_brightness/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 17, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/number/kiosk_volume/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 18, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_reload/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 19, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_wake/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 20, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_beep/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 21, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_clear_cache/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 22, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_reboot/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 23, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/button/kiosk_relaunch/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 24, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/text/kiosk_tts/config") == 0);

    assert(mqttDiscoveryTopic(prefix, 25, topic, sizeof(topic)) == 0);
    assert(strcmp(topic, "homeassistant/text/kiosk_url/config") == 0);

    // Verify all 26 entities format properly
    for (int i = 0; i < mqttEntityCount(); i++) {
        assert(mqttDiscoveryTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "homeassistant/", 14) == 0);
        assert(strstr(topic, "/config") != NULL);
        assert(strstr(topic, "kiosk_") != NULL);
    }

    printf("  [PASS] test_discovery_topics (all 26 topics verified)\n");
}

static void test_command_and_state_topics(void) {
    const char *prefix = "kiosk";
    char topic[256];

    // 13 sensors: state topic should succeed, command topic should fail (-1)
    for (int i = 0; i < 13; i++) {
        assert(mqttStateTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/sensor/", 13) == 0);
        assert(strstr(topic, "/state") != NULL);
        assert(mqttCommandTopic(prefix, i, topic, sizeof(topic)) == -1);
    }

    // 3 switches: both state topic and command topic should succeed
    for (int i = 13; i <= 15; i++) {
        assert(mqttStateTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/state/", 12) == 0);
        assert(mqttCommandTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/set/", 10) == 0);
    }

    // 2 numbers: command topic succeeds
    for (int i = 16; i <= 17; i++) {
        assert(mqttCommandTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/set/", 10) == 0);
    }

    // 6 buttons: command topic succeeds, state topic fails (-1)
    for (int i = 18; i <= 23; i++) {
        assert(mqttCommandTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/set/", 10) == 0);
        assert(mqttStateTopic(prefix, i, topic, sizeof(topic)) == -1);
    }

    // 2 text: command topic succeeds, state topic fails (-1)
    for (int i = 24; i <= 25; i++) {
        assert(mqttCommandTopic(prefix, i, topic, sizeof(topic)) == 0);
        assert(strncmp(topic, "kiosk/set/", 10) == 0);
        assert(mqttStateTopic(prefix, i, topic, sizeof(topic)) == -1);
    }

    printf("  [PASS] test_command_and_state_topics\n");
}

static void test_discovery_json_generation(void) {
    const char *prefix = "test_kiosk";
    char json[1024];

    for (int i = 0; i < mqttEntityCount(); i++) {
        int rc = mqttDiscoveryJSON(prefix, i, json, sizeof(json));
        assert(rc == 0);
        assert(json[0] == '{');
        assert(json[strlen(json) - 1] == '}');

        // Common required fields across all entities
        assert(strstr(json, "\"name\":") != NULL);
        assert(strstr(json, "\"unique_id\":") != NULL);
        assert(strstr(json, "\"availability_topic\":\"test_kiosk/status\"") != NULL);
        assert(strstr(json, "\"device\":{") != NULL);
        assert(strstr(json, "\"identifiers\":[\"hasmartboard_kiosk\"]") != NULL);
        assert(strstr(json, "\"model\":\"iPad Mini 2\"") != NULL);

        const char *comp = mqttEntityComponent(i);
        if (strcmp(comp, "sensor") == 0) {
            assert(strstr(json, "\"state_topic\":\"test_kiosk/sensor/") != NULL);
        } else if (strcmp(comp, "switch") == 0) {
            assert(strstr(json, "\"command_topic\":\"test_kiosk/set/") != NULL);
            assert(strstr(json, "\"state_topic\":\"test_kiosk/state/") != NULL);
            assert(strstr(json, "\"payload_on\":\"ON\"") != NULL);
            assert(strstr(json, "\"payload_off\":\"OFF\"") != NULL);
        } else if (strcmp(comp, "number") == 0) {
            assert(strstr(json, "\"command_topic\":\"test_kiosk/set/") != NULL);
            assert(strstr(json, "\"min\":0") != NULL);
            assert(strstr(json, "\"max\":100") != NULL);
            assert(strstr(json, "\"step\":1") != NULL);
            assert(strstr(json, "\"unit_of_measurement\":\"%\"") != NULL);
        } else if (strcmp(comp, "button") == 0) {
            assert(strstr(json, "\"command_topic\":\"test_kiosk/set/") != NULL);
        } else if (strcmp(comp, "text") == 0) {
            assert(strstr(json, "\"command_topic\":\"test_kiosk/set/") != NULL);
            assert(strstr(json, "\"mode\":\"text\"") != NULL);
        }
    }

    printf("  [PASS] test_discovery_json_generation (all 26 discovery JSONs verified)\n");
}

static void test_state_payloads(void) {
    TelemetrySnapshot snap;
    memset(&snap, 0, sizeof(snap));

    snap.batteryLevel = 85;
    snap.batteryCurrentMA = -450;
    snap.batteryTempDeciC = 295; // 29.5°C
    snap.batteryHealthPct = 98;
    snap.batteryCycles = 312;
    snap.wifiRSSI = -65;
    strncpy(snap.wifiSSID, "HomeWiFi-5G", sizeof(snap.wifiSSID));
    snap.wifiLinkSpeed = 150;
    snap.storageFreeBytes = 12LL * 1024 * 1024 * 1024; // 12288 MB
    snap.memoryFreeBytes = 512LL * 1024 * 1024;        // 512 MB
    snap.uptimeSeconds = 86400;
    snap.netRxBytes = 10485760LL;
    snap.netTxBytes = 2097152LL;

    char payload[128];

    // ENT_BATTERY_LEVEL (0)
    assert(mqttStatePayload(&snap, 0, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "85") == 0);

    // ENT_BATTERY_CURRENT (1)
    assert(mqttStatePayload(&snap, 1, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "-450") == 0);

    // ENT_BATTERY_TEMP (2)
    assert(mqttStatePayload(&snap, 2, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "29.5") == 0);

    // ENT_BATTERY_HEALTH (3)
    assert(mqttStatePayload(&snap, 3, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "98") == 0);

    // ENT_BATTERY_CYCLES (4)
    assert(mqttStatePayload(&snap, 4, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "312") == 0);

    // ENT_WIFI_RSSI (5)
    assert(mqttStatePayload(&snap, 5, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "-65") == 0);

    // ENT_WIFI_SSID (6)
    assert(mqttStatePayload(&snap, 6, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "HomeWiFi-5G") == 0);

    // ENT_WIFI_LINK_SPEED (7)
    assert(mqttStatePayload(&snap, 7, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "150") == 0);

    // ENT_STORAGE_FREE (8)
    assert(mqttStatePayload(&snap, 8, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "12288") == 0);

    // ENT_MEMORY_FREE (9)
    assert(mqttStatePayload(&snap, 9, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "512") == 0);

    // ENT_UPTIME (10)
    assert(mqttStatePayload(&snap, 10, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "86400") == 0);

    // ENT_NETWORK_RX_BYTES (11)
    assert(mqttStatePayload(&snap, 11, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "10485760") == 0);

    // ENT_NETWORK_TX_BYTES (12)
    assert(mqttStatePayload(&snap, 12, payload, sizeof(payload)) == 0);
    assert(strcmp(payload, "2097152") == 0);

    // Non-sensor entities should return -1
    for (int i = 13; i < mqttEntityCount(); i++) {
        assert(mqttStatePayload(&snap, i, payload, sizeof(payload)) == -1);
    }

    printf("  [PASS] test_state_payloads\n");
}

static void test_bounds_and_error_handling(void) {
    char buf[512];
    const char *prefix = "kiosk";
    TelemetrySnapshot snap;
    memset(&snap, 0, sizeof(snap));

    // Invalid index
    assert(mqttEntityComponent(-1) == NULL);
    assert(mqttEntityComponent(26) == NULL);
    assert(mqttEntityName(-1) == NULL);
    assert(mqttEntityName(26) == NULL);
    assert(mqttDiscoveryTopic(prefix, -1, buf, sizeof(buf)) == -1);
    assert(mqttDiscoveryTopic(prefix, 26, buf, sizeof(buf)) == -1);
    assert(mqttStateTopic(prefix, -1, buf, sizeof(buf)) == -1);
    assert(mqttStateTopic(prefix, 26, buf, sizeof(buf)) == -1);
    assert(mqttCommandTopic(prefix, -1, buf, sizeof(buf)) == -1);
    assert(mqttCommandTopic(prefix, 26, buf, sizeof(buf)) == -1);
    assert(mqttDiscoveryJSON(prefix, -1, buf, sizeof(buf)) == -1);
    assert(mqttDiscoveryJSON(prefix, 26, buf, sizeof(buf)) == -1);
    assert(mqttStatePayload(&snap, -1, buf, sizeof(buf)) == -1);
    assert(mqttStatePayload(&snap, 26, buf, sizeof(buf)) == -1);

    // NULL pointers
    assert(mqttDiscoveryTopic(prefix, 0, NULL, sizeof(buf)) == -1);
    assert(mqttStateTopic(prefix, 0, NULL, sizeof(buf)) == -1);
    assert(mqttStateTopic(NULL, 0, buf, sizeof(buf)) == -1);
    assert(mqttCommandTopic(prefix, 13, NULL, sizeof(buf)) == -1);
    assert(mqttCommandTopic(NULL, 13, buf, sizeof(buf)) == -1);
    assert(mqttDiscoveryJSON(prefix, 0, NULL, sizeof(buf)) == -1);
    assert(mqttDiscoveryJSON(NULL, 0, buf, sizeof(buf)) == -1);
    assert(mqttStatePayload(NULL, 0, buf, sizeof(buf)) == -1);
    assert(mqttStatePayload(&snap, 0, NULL, sizeof(buf)) == -1);

    // Buffer capacity too small
    assert(mqttDiscoveryTopic(prefix, 0, buf, 5) == -1);
    assert(mqttStateTopic(prefix, 0, buf, 5) == -1);
    assert(mqttCommandTopic(prefix, 13, buf, 5) == -1);
    assert(mqttDiscoveryJSON(prefix, 0, buf, 20) == -1);
    assert(mqttStatePayload(&snap, 0, buf, 1) == -1);

    printf("  [PASS] test_bounds_and_error_handling\n");
}

int main(void) {
    printf("Running MQTTTelemetry test suite...\n");
    test_entity_counts();
    test_discovery_topics();
    test_command_and_state_topics();
    test_discovery_json_generation();
    test_state_payloads();
    test_bounds_and_error_handling();

    printf("All MQTTTelemetry tests passed successfully (26 entities verified)!\n");
    return 0;
}
