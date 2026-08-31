#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <syslog.h>
#include <pthread.h>
#include "HTTPServer.h"
#include "TelemetryCollector.h"
#include "DeviceControl.h"

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

    int rc = HTTPServerStart(&httpConfig);
    if (rc != 0) {
        syslog(LOG_ERR, "kioskd: HTTP server failed rc=%d", rc);
        return 1;
    }
    syslog(LOG_NOTICE, "kioskd: HTTP on port %d", HTTP_PORT);

    pthread_t tid;
    pthread_create(&tid, NULL, telemetryLoop, &snapshot);

    while (g_running) sleep(1);

    syslog(LOG_NOTICE, "kioskd: shutting down");
    HTTPServerStop();
    pthread_join(tid, NULL);
    closelog();
    return 0;
}
