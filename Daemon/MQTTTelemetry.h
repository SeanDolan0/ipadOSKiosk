#ifndef MQTTTelemetry_h
#define MQTTTelemetry_h

#include "TelemetryCollector.h"
#include <stddef.h>

// Maps TelemetrySnapshot to HA MQTT discovery + state topics/payloads.
// 13 entities, matching the README sensor table and the entity list in the
// MQTT design spec.

int mqttEntityCount(void);

// homeassistant/sensor/kiosk_<id>/config  (uses the *discovery* object id)
int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap);

// <prefix>/sensor/<id>/state
int mqttStateTopic(const char *prefix, int index, char *out, size_t cap);

// Discovery config JSON (device_class omitted when empty; availability topic set).
// 0 on success, -1 on bad index / buffer too small.
int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap);

// String form of the value for one entity (0 on success, -1 on bad index).
int mqttStatePayload(const TelemetrySnapshot *snap, int index, char *out, size_t cap);

#endif
