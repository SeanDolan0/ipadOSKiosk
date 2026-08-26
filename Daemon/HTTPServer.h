#ifndef HTTPServer_h
#define HTTPServer_h
#include "TelemetryCollector.h"
typedef void (*CommandHandler)(const char *action, const char *value, void *context);
typedef void (*WakeHandler)(void *context);
typedef struct {
    int port;
    TelemetrySnapshot *snapshot;
    CommandHandler commandHandler;
    WakeHandler wakeHandler;
    void *callbackContext;
} HTTPServerConfig;
int HTTPServerStart(const HTTPServerConfig *config);
void HTTPServerStop(void);
#endif
