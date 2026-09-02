#ifndef MQTTClient_h
#define MQTTClient_h

#include <stddef.h>
#include <stdint.h>

// Minimal MQTT 3.1.1 client (QoS 0, publish-only) on BSD sockets. Mirrors
// HTTPServer.m: no Foundation, no third-party libs. Not thread-safe — all
// calls from the single MQTT thread.

typedef struct {
    int  sockfd;          // -1 when disconnected
    char host[128];
    int  port;
    char username[64];
    char password[64];
    char clientId[64];
    int  keepalive;       // seconds; 0 disables pings
    char willTopic[128];  // LWT topic ("" = none); will payload fixed "offline"
} MQTTClient;

// Wire helpers (pure C, sized output buffers; capacity is the array size):

// Encodes an MQTT variable-length integer (max 4 bytes). Returns bytes written.
int mqttEncodeRemainingLength(uint8_t *out, int value);

// Encodes a UTF-8 string: 2-byte big-endian length prefix + bytes. Returns bytes written.
int mqttEncodeString(uint8_t *out, const char *s);

// Builds a CONNECT packet (with LWT if willTopic non-empty, username/password if set,
// clean session, keepalive). Returns total packet length or -1 if it doesn't fit.
int mqttBuildConnect(uint8_t *out, size_t cap, const MQTTClient *c);

// Builds a SUBSCRIBE (QoS 0 requested) packet. Returns total packet length or -1 if it doesn't fit.
int mqttBuildSubscribe(uint8_t *out, size_t cap, uint16_t packetId, const char *topicFilter);

// Builds a PUBLISH (QoS 0) packet. retain = 1 sets the retain flag. Returns length or -1.
int mqttBuildPublish(uint8_t *out, size_t cap, const MQTTClient *c,
                     const char *topic, const char *payload, int retain);

// Parses a CONNACK (must be >= 4 bytes). Stores return code (0 = accepted).
// Returns 0 on parse success (even if returnCode != 0).
int mqttParseConnack(const uint8_t *pkt, size_t len, int *returnCode);

// Parses a PUBLISH packet (QoS 0). Extracts topic and payload as null-terminated strings.
// Returns 0 on parse success, or -1 on parse failure.
int mqttParsePublish(const uint8_t *pkt, size_t len, char *topicOut, size_t topicCap,
                     char *payloadOut, size_t payloadCap);

// Transport: TCP connect + MQTT CONNECT handshake. Returns 0 on success,
// nonzero otherwise. On success c->sockfd is a connected socket.
int mqttConnect(MQTTClient *c);

// Publishes topic/payload (QoS 0). Returns 0 on success. On failure the
// caller should treat the connection as dead and reconnect.
int mqttPublish(MQTTClient *c, const char *topic, const char *payload, int retain);

// Sends PINGREQ and waits (5s) for PINGRESP. 0 on success.
int mqttPing(MQTTClient *c);

// Closes the socket and sets sockfd = -1.
void mqttClose(MQTTClient *c);

#endif