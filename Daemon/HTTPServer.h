#ifndef HTTPServer_h
#define HTTPServer_h
#include <stddef.h>
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

// JSON string and value extractor helper
int extractJSONString(const char *json, const char *key, char *out, size_t cap);

#endif

