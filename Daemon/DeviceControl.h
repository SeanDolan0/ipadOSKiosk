#ifndef DeviceControl_h
#define DeviceControl_h

// Dispatches hardware and system commands on behalf of HTTP server and MQTT client.
void DeviceControlExecute(const char *action, const char *value, void *context);

#endif

