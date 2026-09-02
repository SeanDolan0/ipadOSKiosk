#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <syslog.h>
#include <pthread.h>
#include <time.h>
#include <poll.h>
#include <sys/socket.h>
#include <strings.h>
#include "HTTPServer.h"
#include "TelemetryCollector.h"
#include "DeviceControl.h"
#include "KioskConfig.h"
#include "MQTTClient.h"
#include "MQTTTelemetry.h"

#define HTTP_PORT 8080
#define TELEMETRY_INTERVAL 30

static volatile int g_running = 1;

static void signalHandler(int sig) {
    (void)sig;
    g_running = 0;
}

static void *telemetryLoop(void *arg) {
    TelemetrySnapshot *snapshot = (TelemetrySnapshot *)arg;
    while (g_running) {
        TelemetryCollect(snapshot);
        for (int i = 0; i < TELEMETRY_INTERVAL && g_running; i++) {
            sleep(1);
        }
    }
    return NULL;
}

typedef struct {
    KioskMQTTConfig *cfg;
    TelemetrySnapshot *snapshot;
} MQTTLoopArgs;

static void onCommand(const char *action, const char *value, void *context) {
    DeviceControlExecute(action, value, context);
}

static void onWake(void *context) {
    (void)context;
}

static void dispatchMqttCommand(const char *target, const char *payload) {
    if (!target) return;

    if (strcmp(target, "screen") == 0) {
        onCommand("setScreen", payload ? payload : "", NULL);
    } else if (strcmp(target, "screensaver") == 0) {
        onCommand("setScreensaver", payload ? payload : "", NULL);
    } else if (strcmp(target, "dnd") == 0) {
        const char *val = "false";
        if (payload && (strcasecmp(payload, "ON") == 0 ||
                        strcasecmp(payload, "true") == 0 ||
                        strcmp(payload, "1") == 0)) {
            val = "true";
        }
        onCommand("setDND", val, NULL);
    } else if (strcmp(target, "brightness") == 0) {
        onCommand("setBrightness", payload ? payload : "", NULL);
    } else if (strcmp(target, "volume") == 0) {
        onCommand("setVolume", payload ? payload : "", NULL);
    } else if (strcmp(target, "reload") == 0) {
        onCommand("reload", "", NULL);
    } else if (strcmp(target, "wake") == 0) {
        onCommand("wake", "", NULL);
    } else if (strcmp(target, "beep") == 0) {
        onCommand("beep", "", NULL);
    } else if (strcmp(target, "clear_cache") == 0) {
        onCommand("clearCache", "", NULL);
    } else if (strcmp(target, "reboot") == 0) {
        onCommand("reboot", "", NULL);
    } else if (strcmp(target, "relaunch") == 0) {
        onCommand("relaunchApp", "", NULL);
    } else if (strcmp(target, "tts") == 0) {
        onCommand("tts", payload ? payload : "", NULL);
    } else if (strcmp(target, "url") == 0) {
        onCommand("loadURL", payload ? payload : "", NULL);
    } else {
        syslog(LOG_WARNING, "kioskd: MQTT unknown command target '%s'", target);
    }
}

static void *mqttLoop(void *arg) {
    MQTTLoopArgs *args = (MQTTLoopArgs *)arg;
    KioskMQTTConfig *cfg = args->cfg;
    TelemetrySnapshot *snapshot = args->snapshot;

    MQTTClient client;
    memset(&client, 0, sizeof(client));
    client.sockfd = -1;
    snprintf(client.host, sizeof(client.host), "%s", cfg->host);
    client.port = cfg->port;
    snprintf(client.username, sizeof(client.username), "%s", cfg->username);
    snprintf(client.password, sizeof(client.password), "%s", cfg->password);
    snprintf(client.clientId, sizeof(client.clientId), "%s", cfg->clientId);
    client.keepalive = 60;
    snprintf(client.willTopic, sizeof(client.willTopic), "%s/status", cfg->prefix);

    char statusTopic[256];
    snprintf(statusTopic, sizeof(statusTopic), "%s/status", cfg->prefix);

    int backoff = 1;
    while (g_running) {
        if (mqttConnect(&client) != 0) {
            syslog(LOG_WARNING, "kioskd: MQTT connect to %s:%d failed, retry in %ds",
                   client.host, client.port, backoff);
            for (int i = 0; i < backoff && g_running; i++) sleep(1);
            if (backoff < 30) backoff *= 2;
            continue;
        }
        backoff = 1;
        syslog(LOG_NOTICE, "kioskd: MQTT connected to %s:%d", client.host, client.port);

        for (int i = 0; i < mqttEntityCount(); i++) {
            char topic[256], payload[1024];
            if (mqttDiscoveryTopic(cfg->prefix, i, topic, sizeof(topic)) != 0) continue;
            if (mqttDiscoveryJSON(cfg->prefix, i, payload, sizeof(payload)) != 0) continue;
            mqttPublish(&client, topic, payload, 1);   // retained discovery
        }
        mqttPublish(&client, statusTopic, "online", 1); // retained birth

        char subTopic[256];
        snprintf(subTopic, sizeof(subTopic), "%s/set/#", cfg->prefix);
        uint8_t subPkt[256];
        int subLen = mqttBuildSubscribe(subPkt, sizeof(subPkt), 1, subTopic);
        if (subLen <= 0 || send(client.sockfd, subPkt, (size_t)subLen, 0) <= 0) {
            syslog(LOG_WARNING, "kioskd: failed to send subscribe packet");
            mqttClose(&client);
            continue;
        }
        syslog(LOG_NOTICE, "kioskd: subscribed to %s", subTopic);

        time_t lastState = 0;
        time_t lastSend = time(NULL);
        while (g_running) {
            struct pollfd pfd;
            pfd.fd = client.sockfd;
            pfd.events = POLLIN;
            pfd.revents = 0;

            int pret = poll(&pfd, 1, 1000);
            if (pret < 0) {
                if (!g_running) break;
                syslog(LOG_WARNING, "kioskd: MQTT poll error, disconnecting");
                break;
            }

            if (pret > 0 && (pfd.revents & POLLIN)) {
                uint8_t buf[2048];
                ssize_t n = recv(client.sockfd, buf, sizeof(buf) - 1, 0);
                if (n <= 0) {
                    syslog(LOG_WARNING, "kioskd: MQTT connection lost during recv");
                    break;
                }

                size_t off = 0;
                while (off < (size_t)n) {
                    const uint8_t *pkt = buf + off;
                    size_t remaining = (size_t)n - off;
                    if (remaining < 2) break;

                    uint8_t pktType = pkt[0] & 0xF0;
                    if (pktType == 0x30) { // PUBLISH
                        char topic[256] = {0};
                        char payload[1024] = {0};
                        if (mqttParsePublish(pkt, remaining, topic, sizeof(topic), payload, sizeof(payload)) == 0) {
                            char setPrefix[256];
                            snprintf(setPrefix, sizeof(setPrefix), "%s/set/", cfg->prefix);
                            size_t setPrefixLen = strlen(setPrefix);
                            if (strncmp(topic, setPrefix, setPrefixLen) == 0) {
                                const char *target = topic + setPrefixLen;
                                dispatchMqttCommand(target, payload);
                            } else {
                                syslog(LOG_WARNING, "kioskd: MQTT received publish with unexpected topic: %s", topic);
                            }
                        }

                        // Advance past this PUBLISH packet
                        size_t idx = 1;
                        uint32_t remLen = 0;
                        uint32_t mult = 1;
                        int done = 0;
                        while (idx < remaining && idx < 5) {
                            uint8_t digit = pkt[idx++];
                            remLen += (uint32_t)(digit & 0x7F) * mult;
                            mult *= 128;
                            if ((digit & 0x80) == 0) {
                                done = 1;
                                break;
                            }
                        }
                        if (done && idx + remLen <= remaining) {
                            off += idx + remLen;
                        } else {
                            break;
                        }
                    } else if (pktType == 0x90) { // SUBACK
                        size_t idx = 1;
                        uint32_t remLen = 0;
                        uint32_t mult = 1;
                        int done = 0;
                        while (idx < remaining && idx < 5) {
                            uint8_t digit = pkt[idx++];
                            remLen += (uint32_t)(digit & 0x7F) * mult;
                            mult *= 128;
                            if ((digit & 0x80) == 0) {
                                done = 1;
                                break;
                            }
                        }
                        if (done && idx + remLen <= remaining) {
                            off += idx + remLen;
                        } else {
                            break;
                        }
                    } else if (pktType == 0xD0) { // PINGRESP
                        off += 2;
                    } else {
                        break;
                    }
                }
            } else if (pret > 0 && (pfd.revents & (POLLERR | POLLHUP | POLLNVAL))) {
                syslog(LOG_WARNING, "kioskd: MQTT socket error event: 0x%x", pfd.revents);
                break;
            }

            time_t now = time(NULL);
            if (now - lastState >= cfg->interval) {
                int ok = 1;
                for (int i = 0; i < mqttSensorCount(); i++) {
                    char topic[256], value[128];
                    if (mqttStateTopic(cfg->prefix, i, topic, sizeof(topic)) != 0) { ok = 0; break; }
                    if (mqttStatePayload(snapshot, i, value, sizeof(value)) != 0) { ok = 0; break; }
                    if (mqttPublish(&client, topic, value, 0) != 0) { ok = 0; break; }
                }
                if (!ok) break;                 // link broken
                lastState = now;
                lastSend = now;
            } else if (client.keepalive > 0 && now - lastSend >= client.keepalive) {
                if (mqttPing(&client) != 0) break;
                lastSend = now;
            }
        }
        syslog(LOG_WARNING, "kioskd: MQTT link lost, reconnecting");
        mqttClose(&client);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    openlog("kioskd", LOG_PID | LOG_NDELAY, LOG_DAEMON);
    syslog(LOG_NOTICE, "kioskd: starting pid=%d", getpid());

    signal(SIGTERM, signalHandler);
    signal(SIGINT, signalHandler);
    signal(SIGHUP, SIG_IGN);

    static TelemetrySnapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));

    HTTPServerConfig httpConfig;
    memset(&httpConfig, 0, sizeof(httpConfig));
    httpConfig.port = HTTP_PORT;
    httpConfig.snapshot = &snapshot;
    httpConfig.commandHandler = onCommand;
    httpConfig.wakeHandler = onWake;
    httpConfig.callbackContext = NULL;

    KioskMQTTConfig mqttCfg;
    KioskConfigLoadMQTT(&mqttCfg);
    if (mqttCfg.enabled) {
        syslog(LOG_NOTICE, "kioskd: MQTT enabled host=%s port=%d prefix=%s interval=%d",
               mqttCfg.host, mqttCfg.port, mqttCfg.prefix, mqttCfg.interval);
    } else {
        syslog(LOG_NOTICE, "kioskd: MQTT disabled (no mqtt block or enabled=false)");
    }

    int rc = HTTPServerStart(&httpConfig);
    if (rc != 0) {
        syslog(LOG_ERR, "kioskd: HTTP server failed rc=%d", rc);
        return 1;
    }
    syslog(LOG_NOTICE, "kioskd: HTTP on port %d", HTTP_PORT);

    pthread_t tid;
    pthread_create(&tid, NULL, telemetryLoop, &snapshot);

    pthread_t mqttTid = 0;
    static MQTTLoopArgs mqttArgs;
    if (mqttCfg.enabled) {
        mqttArgs.cfg = &mqttCfg;
        mqttArgs.snapshot = &snapshot;
        pthread_create(&mqttTid, NULL, mqttLoop, &mqttArgs);
    }

    while (g_running) sleep(1);

    syslog(LOG_NOTICE, "kioskd: shutting down");
    HTTPServerStop();
    pthread_join(tid, NULL);
    if (mqttCfg.enabled) {
        pthread_join(mqttTid, NULL);
    }
    closelog();
    return 0;
}

