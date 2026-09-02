#ifndef MQTTTelemetry_h
#define MQTTTelemetry_h

#include "TelemetryCollector.h"
#include <stddef.h>

// Home Assistant MQTT Entity Model (26 total entities):
// - 13 Telemetry Sensors (component: "sensor")
// - 3 Switches (component: "switch": screen, screensaver, dnd)
// - 2 Numbers (component: "number": brightness, volume)
// - 6 Buttons (component: "button": reload, wake, beep, clear_cache, reboot, relaunch)
// - 2 Text (component: "text": tts, url)

// Total number of HA entities (26)
int mqttEntityCount(void);

// Number of telemetry sensors (13)
int mqttSensorCount(void);

// Entity component type ("sensor", "switch", "number", "button", "text")
const char *mqttEntityComponent(int index);

// Entity short ID (e.g. "battery_level", "screen", "brightness", "reload", "tts")
const char *mqttEntityName(int index);

// HA Discovery config topic:
// homeassistant/<component>/kiosk_<id>/config
// 0 on success, -1 on bad index / invalid buffer / overflow.
int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap);

// State topic:
//   <prefix>/sensor/<id>/state for sensors
//   <prefix>/state/<id> for switches
// 0 on success, -1 on bad index / entity without state topic / overflow.
int mqttStateTopic(const char *prefix, int index, char *out, size_t cap);

// Command topic:
//   <prefix>/set/<id> for interactive entities (switches, numbers, buttons, text)
// 0 on success, -1 on bad index / entity without command topic / overflow.
int mqttCommandTopic(const char *prefix, int index, char *out, size_t cap);

// Discovery config JSON (valid HA MQTT Discovery configuration).
// 0 on success, -1 on bad index / invalid buffer / overflow.
int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap);

// String form of the value for one sensor entity (0 on success, -1 on bad index or non-sensor).
int mqttStatePayload(const TelemetrySnapshot *snap, int index, char *out, size_t cap);

#endif
