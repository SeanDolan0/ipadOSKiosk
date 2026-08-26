#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <syslog.h>
#include <pthread.h>
#include "TelemetryCollector.h"
#include "HTTPServer.h"
#include "HAReporter.h"
#include "DeviceControl.h"

// ponytail: config compiled-in. For token rotation, recompile and redeploy.
#define HA_URL   "http://192.168.50.150:8123"
#define HA_TOKEN "YOUR_LONG_LIVED_ACCESS_TOKEN_HERE"
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
        syslog(LOG_NOTICE, "kioskd: collecting telemetry");
        TelemetryCollect(snapshot);
        HAReporterPush(snapshot);

        for (int i = 0; i < TELEMETRY_INTERVAL && g_running; i++) {
            sleep(1);
        }
    }
    return NULL;
}

static void onCommand(const char *action, const char *value, void *context) {
    (void)context;
    syslog(LOG_NOTICE, "kioskd: command received: %s = %s", action, value);
    DeviceControlExecute(action, value, NULL);
}

static void onWake(void *context) {
    (void)context;
    syslog(LOG_NOTICE, "kioskd: wake signal received");
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    openlog("kioskd", LOG_PID | LOG_NDELAY, LOG_DAEMON);
    syslog(LOG_NOTICE, "kioskd: starting (pid %d)", getpid());

    signal(SIGTERM, signalHandler);
    signal(SIGINT, signalHandler);

    static TelemetrySnapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));

    HAReporterConfig haConfig;
    memset(&haConfig, 0, sizeof(haConfig));
    strncpy(haConfig.haURL, HA_URL, sizeof(haConfig.haURL) - 1);
    strncpy(haConfig.haToken, HA_TOKEN, sizeof(haConfig.haToken) - 1);
    HAReporterInit(&haConfig);

    HTTPServerConfig httpConfig;
    memset(&httpConfig, 0, sizeof(httpConfig));
    httpConfig.port = HTTP_PORT;
    httpConfig.snapshot = &snapshot;
    httpConfig.commandHandler = onCommand;
    httpConfig.wakeHandler = onWake;
    httpConfig.callbackContext = NULL;

    if (HTTPServerStart(&httpConfig) != 0) {
        syslog(LOG_ERR, "kioskd: failed to start HTTP server on port %d", HTTP_PORT);
        return 1;
    }
    syslog(LOG_NOTICE, "kioskd: HTTP server listening on 127.0.0.1:%d", HTTP_PORT);

    pthread_t telemetryThread;
    pthread_create(&telemetryThread, NULL, telemetryLoop, &snapshot);

    while (g_running) {
        sleep(1);
    }

    syslog(LOG_NOTICE, "kioskd: shutting down");
    HTTPServerStop();
    pthread_join(telemetryThread, NULL);
    closelog();

    return 0;
}
