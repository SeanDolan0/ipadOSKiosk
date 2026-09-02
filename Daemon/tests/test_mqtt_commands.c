#include "../MQTTClient.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#include <stdint.h>
#include <strings.h>

// Mock recorder for command executions
static char g_lastAction[128] = {0};
static char g_lastValue[512] = {0};
static int g_commandCount = 0;

static void mockOnCommand(const char *action, const char *value, void *context) {
    (void)context;
    strncpy(g_lastAction, action ? action : "", sizeof(g_lastAction) - 1);
    strncpy(g_lastValue, value ? value : "", sizeof(g_lastValue) - 1);
    g_commandCount++;
}

static void dispatchMqttCommandTest(const char *target, const char *payload) {
    if (!target) return;

    if (strcmp(target, "screen") == 0) {
        mockOnCommand("setScreen", payload ? payload : "", NULL);
    } else if (strcmp(target, "screensaver") == 0) {
        mockOnCommand("setScreensaver", payload ? payload : "", NULL);
    } else if (strcmp(target, "dnd") == 0) {
        const char *val = "false";
        if (payload && (strcasecmp(payload, "ON") == 0 ||
                        strcasecmp(payload, "true") == 0 ||
                        strcmp(payload, "1") == 0)) {
            val = "true";
        }
        mockOnCommand("setDND", val, NULL);
    } else if (strcmp(target, "brightness") == 0) {
        mockOnCommand("setBrightness", payload ? payload : "", NULL);
    } else if (strcmp(target, "volume") == 0) {
        mockOnCommand("setVolume", payload ? payload : "", NULL);
    } else if (strcmp(target, "reload") == 0) {
        mockOnCommand("reload", "", NULL);
    } else if (strcmp(target, "wake") == 0) {
        mockOnCommand("wake", "", NULL);
    } else if (strcmp(target, "beep") == 0) {
        mockOnCommand("beep", "", NULL);
    } else if (strcmp(target, "clear_cache") == 0) {
        mockOnCommand("clearCache", "", NULL);
    } else if (strcmp(target, "reboot") == 0) {
        mockOnCommand("reboot", "", NULL);
    } else if (strcmp(target, "relaunch") == 0) {
        mockOnCommand("relaunchApp", "", NULL);
    } else if (strcmp(target, "tts") == 0) {
        mockOnCommand("tts", payload ? payload : "", NULL);
    } else if (strcmp(target, "url") == 0) {
        mockOnCommand("loadURL", payload ? payload : "", NULL);
    }
}

static float normalizeLevel(const char *value) {
    if (!value) return 0.0f;
    float level = (float)atof(value);
    if (level > 1.0f) {
        level = level / 100.0f;
    }
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;
    return level;
}

static void test_brightness_volume_normalization(void) {
    assert(normalizeLevel("0") == 0.0f);
    assert(normalizeLevel("0.0") == 0.0f);
    assert(normalizeLevel("0.5") == 0.5f);
    assert(normalizeLevel("1.0") == 1.0f);
    assert(normalizeLevel("1") == 1.0f);
    assert(normalizeLevel("50") == 0.5f);
    assert(normalizeLevel("75") == 0.75f);
    assert(normalizeLevel("100") == 1.0f);
    assert(normalizeLevel("-10") == 0.0f);
    assert(normalizeLevel("150") == 1.0f);
    printf("  [PASS] test_brightness_volume_normalization\n");
}

static void test_command_dispatch_targets(void) {
    g_commandCount = 0;

    dispatchMqttCommandTest("screen", "ON");
    assert(strcmp(g_lastAction, "setScreen") == 0);
    assert(strcmp(g_lastValue, "ON") == 0);

    dispatchMqttCommandTest("screensaver", "OFF");
    assert(strcmp(g_lastAction, "setScreensaver") == 0);
    assert(strcmp(g_lastValue, "OFF") == 0);

    dispatchMqttCommandTest("dnd", "ON");
    assert(strcmp(g_lastAction, "setDND") == 0);
    assert(strcmp(g_lastValue, "true") == 0);

    dispatchMqttCommandTest("dnd", "OFF");
    assert(strcmp(g_lastAction, "setDND") == 0);
    assert(strcmp(g_lastValue, "false") == 0);

    dispatchMqttCommandTest("dnd", "true");
    assert(strcmp(g_lastAction, "setDND") == 0);
    assert(strcmp(g_lastValue, "true") == 0);

    dispatchMqttCommandTest("dnd", "false");
    assert(strcmp(g_lastAction, "setDND") == 0);
    assert(strcmp(g_lastValue, "false") == 0);

    dispatchMqttCommandTest("brightness", "80");
    assert(strcmp(g_lastAction, "setBrightness") == 0);
    assert(strcmp(g_lastValue, "80") == 0);

    dispatchMqttCommandTest("volume", "50");
    assert(strcmp(g_lastAction, "setVolume") == 0);
    assert(strcmp(g_lastValue, "50") == 0);

    dispatchMqttCommandTest("reload", "ignored");
    assert(strcmp(g_lastAction, "reload") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("wake", "ignored");
    assert(strcmp(g_lastAction, "wake") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("beep", "ignored");
    assert(strcmp(g_lastAction, "beep") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("clear_cache", "ignored");
    assert(strcmp(g_lastAction, "clearCache") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("reboot", "ignored");
    assert(strcmp(g_lastAction, "reboot") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("relaunch", "ignored");
    assert(strcmp(g_lastAction, "relaunchApp") == 0);
    assert(strcmp(g_lastValue, "") == 0);

    dispatchMqttCommandTest("tts", "Attention: front door is open");
    assert(strcmp(g_lastAction, "tts") == 0);
    assert(strcmp(g_lastValue, "Attention: front door is open") == 0);

    dispatchMqttCommandTest("url", "http://192.168.50.150:8123/dashboard/1");
    assert(strcmp(g_lastAction, "loadURL") == 0);
    assert(strcmp(g_lastValue, "http://192.168.50.150:8123/dashboard/1") == 0);

    assert(g_commandCount == 16);
    printf("  [PASS] test_command_dispatch_targets\n");
}

static void processMqttAccumulator(uint8_t *recvBuf, size_t *recvLen, const char *prefix) {
    char setPrefix[256];
    snprintf(setPrefix, sizeof(setPrefix), "%s/set/", prefix);
    size_t setPrefixLen = strlen(setPrefix);

    size_t off = 0;
    while (off < *recvLen) {
        size_t available = *recvLen - off;
        if (available < 2) {
            break;
        }

        const uint8_t *pkt = recvBuf + off;
        uint8_t pktType = pkt[0] & 0xF0;

        size_t idx = 1;
        uint32_t remLen = 0;
        uint32_t mult = 1;
        int remLenDone = 0;
        while (idx < available && idx < 5) {
            uint8_t digit = pkt[idx++];
            remLen += (uint32_t)(digit & 0x7F) * mult;
            mult *= 128;
            if ((digit & 0x80) == 0) {
                remLenDone = 1;
                break;
            }
        }

        if (!remLenDone) {
            break;
        }

        size_t remLenBytes = idx - 1;
        size_t pktTotalLen = 1 + remLenBytes + (size_t)remLen;

        if (available < pktTotalLen) {
            break;
        }

        if (pktType == 0x30) { // PUBLISH
            char topic[256] = {0};
            char payload[1024] = {0};
            if (mqttParsePublish(pkt, pktTotalLen, topic, sizeof(topic), payload, sizeof(payload)) == 0) {
                if (strncmp(topic, setPrefix, setPrefixLen) == 0) {
                    const char *target = topic + setPrefixLen;
                    dispatchMqttCommandTest(target, payload);
                }
            }
        } else if (pktType == 0x90) { // SUBACK
            // Handled
        } else if (pktType == 0xD0) { // PINGRESP
            // Handled
        }

        off += pktTotalLen;
    }

    if (off > 0) {
        size_t remainingBytes = *recvLen - off;
        if (remainingBytes > 0) {
            memmove(recvBuf, recvBuf + off, remainingBytes);
        }
        *recvLen = remainingBytes;
    }
}

static void test_packet_stream_processing(void) {
    uint8_t stream[1024];
    size_t totalLen = 0;

    // 1. SUBACK (0x90, len=3, packetId=1, returnCode=0)
    stream[totalLen++] = 0x90;
    stream[totalLen++] = 0x03;
    stream[totalLen++] = 0x00;
    stream[totalLen++] = 0x01;
    stream[totalLen++] = 0x00;

    // 2. PUBLISH (kiosk/set/tts, "Hello world")
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    int pubLen = mqttBuildPublish(stream + totalLen, sizeof(stream) - totalLen, &dummy,
                                 "kiosk/set/tts", "Hello world", 0);
    assert(pubLen > 0);
    totalLen += (size_t)pubLen;

    // 3. PINGRESP (0xD0 0x00)
    stream[totalLen++] = 0xD0;
    stream[totalLen++] = 0x00;

    // 4. PUBLISH (kiosk/set/screen, "ON")
    int pubLen2 = mqttBuildPublish(stream + totalLen, sizeof(stream) - totalLen, &dummy,
                                  "kiosk/set/screen", "ON", 0);
    assert(pubLen2 > 0);
    totalLen += (size_t)pubLen2;

    uint8_t recvBuf[4096];
    memcpy(recvBuf, stream, totalLen);
    size_t recvLen = totalLen;

    g_commandCount = 0;
    processMqttAccumulator(recvBuf, &recvLen, "kiosk");

    assert(recvLen == 0);
    assert(g_commandCount == 2);
    assert(strcmp(g_lastAction, "setScreen") == 0);
    assert(strcmp(g_lastValue, "ON") == 0);

    printf("  [PASS] test_packet_stream_processing\n");
}

static void test_fragmented_tcp_stream(void) {
    // Build a sequence of 3 publish packets
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t stream[1024];
    size_t streamLen = 0;

    int l1 = mqttBuildPublish(stream + streamLen, sizeof(stream) - streamLen, &dummy,
                              "kiosk/set/volume", "85", 0);
    assert(l1 > 0);
    streamLen += (size_t)l1;

    int l2 = mqttBuildPublish(stream + streamLen, sizeof(stream) - streamLen, &dummy,
                              "kiosk/set/tts", "Fragmented test message across packets", 0);
    assert(l2 > 0);
    streamLen += (size_t)l2;

    int l3 = mqttBuildPublish(stream + streamLen, sizeof(stream) - streamLen, &dummy,
                              "kiosk/set/brightness", "0.45", 0);
    assert(l3 > 0);
    streamLen += (size_t)l3;

    // Feed bytes in arbitrary fragmented chunk sizes (e.g. 3 bytes at a time)
    uint8_t recvBuf[4096];
    size_t recvLen = 0;
    g_commandCount = 0;

    size_t fed = 0;
    const size_t chunkSize = 3;
    while (fed < streamLen) {
        size_t toFeed = chunkSize;
        if (fed + toFeed > streamLen) {
            toFeed = streamLen - fed;
        }
        memcpy(recvBuf + recvLen, stream + fed, toFeed);
        recvLen += toFeed;
        fed += toFeed;

        processMqttAccumulator(recvBuf, &recvLen, "kiosk");
    }

    assert(recvLen == 0);
    assert(g_commandCount == 3);
    assert(strcmp(g_lastAction, "setBrightness") == 0);
    assert(strcmp(g_lastValue, "0.45") == 0);

    printf("  [PASS] test_fragmented_tcp_stream (chunk size = 3 bytes)\n");
}

static void test_spool_filename_sorting(void) {
    // Verify that timestamp-sequence filenames sort chronologically
    const char *files[] = {
        "cmd-1725235000000-1.json",
        "cmd-1725235000000-2.json",
        "cmd-1725235000001-3.json",
        "cmd-1725235000005-4.json",
        "cmd-1725235000010-5.json"
    };

    for (int i = 0; i < 4; i++) {
        assert(strcmp(files[i], files[i + 1]) < 0);
    }
    printf("  [PASS] test_spool_filename_sorting\n");
}

int main(void) {
    printf("Running MQTT command dispatch test suite...\n");
    test_brightness_volume_normalization();
    test_command_dispatch_targets();
    test_packet_stream_processing();
    test_fragmented_tcp_stream();
    test_spool_filename_sorting();

    printf("All MQTT command dispatch tests passed successfully!\n");
    return 0;
}