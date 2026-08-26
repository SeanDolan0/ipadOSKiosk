#import "TelemetryCollector.h"
#include <string.h>
#include <stdlib.h>
int TelemetryCollect(TelemetrySnapshot *snapshot) {
    memset(snapshot, 0, sizeof(TelemetrySnapshot));
    return 0;
}
char *TelemetrySnapshotToJSON(const TelemetrySnapshot *snapshot) {
    char *json = malloc(256);
    snprintf(json, 256, "{\"uptime\":%d}", snapshot->uptimeSeconds);
    return json;
}
