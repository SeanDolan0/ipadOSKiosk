#include "../MQTTClient.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>

static void test_build_subscribe_basic(void) {
    uint8_t buf[256];
    int len = mqttBuildSubscribe(buf, sizeof(buf), 1, "kiosk/set/#");
    assert(len > 0);
    assert(buf[0] == 0x82); // SUBSCRIBE QoS 1 fixed header

    // Decode remaining length
    // remLen for packetId(2) + topicLen(2) + strlen("kiosk/set/#")(11) + qos(1) = 16 (0x10)
    assert(buf[1] == 16);
    // Packet ID 1 (0x0001)
    assert(buf[2] == 0x00);
    assert(buf[3] == 0x01);
    // Topic length: 11 (0x000B)
    assert(buf[4] == 0x00);
    assert(buf[5] == 11);
    // Topic string
    assert(memcmp(buf + 6, "kiosk/set/#", 11) == 0);
    // Requested QoS: 0
    assert(buf[17] == 0x00);
    assert(len == 18);
    printf("  [PASS] test_build_subscribe_basic\n");
}

static void test_build_subscribe_packet_id(void) {
    uint8_t buf[256];
    int len = mqttBuildSubscribe(buf, sizeof(buf), 0x1234, "home/livingroom/temp");
    assert(len > 0);
    assert(buf[0] == 0x82);
    // Packet ID 0x1234
    assert(buf[2] == 0x12);
    assert(buf[3] == 0x34);
    printf("  [PASS] test_build_subscribe_packet_id\n");
}

static void test_build_subscribe_buffer_too_small(void) {
    uint8_t buf[10];
    int len = mqttBuildSubscribe(buf, sizeof(buf), 1, "kiosk/set/#");
    assert(len == -1);

    int len_null = mqttBuildSubscribe(NULL, sizeof(buf), 1, "kiosk/set/#");
    assert(len_null == -1);

    int len_notopic = mqttBuildSubscribe(buf, sizeof(buf), 1, NULL);
    assert(len_notopic == -1);
    printf("  [PASS] test_build_subscribe_buffer_too_small\n");
}

static void test_parse_publish_basic(void) {
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[256];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/set/brightness", "0.75", 0);
    assert(pubLen > 0);

    char topic[128] = {0};
    char payload[128] = {0};
    int rc = mqttParsePublish(pubPkt, (size_t)pubLen, topic, sizeof(topic), payload, sizeof(payload));
    assert(rc == 0);
    assert(strcmp(topic, "kiosk/set/brightness") == 0);
    assert(strcmp(payload, "0.75") == 0);
    printf("  [PASS] test_parse_publish_basic\n");
}

static void test_parse_publish_empty_payload(void) {
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[256];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/command/reload", "", 0);
    assert(pubLen > 0);

    char topic[128] = {0};
    char payload[128] = {0};
    int rc = mqttParsePublish(pubPkt, (size_t)pubLen, topic, sizeof(topic), payload, sizeof(payload));
    assert(rc == 0);
    assert(strcmp(topic, "kiosk/command/reload") == 0);
    assert(strcmp(payload, "") == 0);
    printf("  [PASS] test_parse_publish_empty_payload\n");
}

static void test_parse_publish_retained(void) {
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[256];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/state/status", "online", 1);
    assert(pubLen > 0);
    assert((pubPkt[0] & 0x01) == 0x01); // retain flag

    char topic[128] = {0};
    char payload[128] = {0};
    int rc = mqttParsePublish(pubPkt, (size_t)pubLen, topic, sizeof(topic), payload, sizeof(payload));
    assert(rc == 0);
    assert(strcmp(topic, "kiosk/state/status") == 0);
    assert(strcmp(payload, "online") == 0);
    printf("  [PASS] test_parse_publish_retained\n");
}

static void test_parse_publish_multibyte_length(void) {
    // Test with payload > 127 bytes to trigger multibyte remaining length encoding
    char longPayload[200];
    memset(longPayload, 'A', sizeof(longPayload) - 1);
    longPayload[sizeof(longPayload) - 1] = '\0';

    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[512];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/set/tts", longPayload, 0);
    assert(pubLen > 0);

    char topic[128] = {0};
    char payload[256] = {0};
    int rc = mqttParsePublish(pubPkt, (size_t)pubLen, topic, sizeof(topic), payload, sizeof(payload));
    assert(rc == 0);
    assert(strcmp(topic, "kiosk/set/tts") == 0);
    assert(strcmp(payload, longPayload) == 0);
    printf("  [PASS] test_parse_publish_multibyte_length\n");
}

static void test_parse_publish_invalid_packets(void) {
    char topic[128] = {0};
    char payload[128] = {0};

    // NULL pointers
    assert(mqttParsePublish(NULL, 10, topic, sizeof(topic), payload, sizeof(payload)) == -1);
    assert(mqttParsePublish((const uint8_t *)"\x30\x00", 2, NULL, sizeof(topic), payload, sizeof(payload)) == -1);
    assert(mqttParsePublish((const uint8_t *)"\x30\x00", 2, topic, sizeof(topic), NULL, sizeof(payload)) == -1);

    // Length too small
    assert(mqttParsePublish((const uint8_t *)"\x30\x00", 2, topic, sizeof(topic), payload, sizeof(payload)) == -1);

    // Non-PUBLISH packet type (e.g. CONNECT = 0x10, CONNACK = 0x20)
    uint8_t connack[4] = {0x20, 0x02, 0x00, 0x00};
    assert(mqttParsePublish(connack, sizeof(connack), topic, sizeof(topic), payload, sizeof(payload)) == -1);

    // Truncated packet
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[256];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/set/brightness", "0.75", 0);
    assert(pubLen > 0);
    // Pass shorter length than packet indicates
    assert(mqttParsePublish(pubPkt, (size_t)(pubLen - 5), topic, sizeof(topic), payload, sizeof(payload)) == -1);

    // Topic buffer too small
    char tinyTopic[4] = {0};
    assert(mqttParsePublish(pubPkt, (size_t)pubLen, tinyTopic, sizeof(tinyTopic), payload, sizeof(payload)) == -1);

    printf("  [PASS] test_parse_publish_invalid_packets\n");
}

int main(void) {
    printf("Running MQTTClient test suite...\n");
    test_build_subscribe_basic();
    test_build_subscribe_packet_id();
    test_build_subscribe_buffer_too_small();
    test_parse_publish_basic();
    test_parse_publish_empty_payload();
    test_parse_publish_retained();
    test_parse_publish_multibyte_length();
    test_parse_publish_invalid_packets();

    printf("MQTT SUBSCRIBE and PUBLISH parse tests passed!\n");
    return 0;
}
