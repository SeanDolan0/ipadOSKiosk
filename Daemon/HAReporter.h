#ifndef HAReporter_h
#define HAReporter_h
#include "TelemetryCollector.h"
typedef struct {
    char haURL[256];
    char haToken[256];
} HAReporterConfig;
int HAReporterInit(const HAReporterConfig *config);
int HAReporterPush(const TelemetrySnapshot *snapshot);
#endif
