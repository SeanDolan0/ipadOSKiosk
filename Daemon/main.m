#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <syslog.h>
#include <pthread.h>
#include <time.h>
#include "HTTPServer.h"
#include "TelemetryCollector.h"
#include "DeviceControl.h"
#include "KioskConfig.h"
#include "MQTTClient.h"
#include "MQTTTelemetry.h"

#define HTTP_PORT 9090
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

        time_t lastState = 0;
        time_t lastSend = time(NULL);
        while (g_running) {
            time_t now = time(NULL);
            if (now - lastState >= cfg->interval) {
                int ok = 1;
                for (int i = 0; i < mqttEntityCount(); i++) {
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
            sleep(1);
        }
        syslog(LOG_WARNING, "kioskd: MQTT link lost, reconnecting");
        mqttClose(&client);
    }
    return NULL;
}

static void onCommand(const char *action, const char *value, void *context) {
    DeviceControlExecute(action, value, context);
}

static void onWake(void *context) {
    (void)context;
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

