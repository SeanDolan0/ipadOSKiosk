#include "MQTTClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>

int mqttEncodeRemainingLength(uint8_t *out, int value) {
    int n = 0;
    do {
        uint8_t digit = (uint8_t)(value % 128);
        value /= 128;
        if (value > 0) digit |= 0x80;
        out[n++] = digit;
    } while (value > 0);
    return n;
}

int mqttEncodeString(uint8_t *out, const char *s) {
    size_t len = strlen(s);
    out[0] = (uint8_t)((len >> 8) & 0xFF);
    out[1] = (uint8_t)(len & 0xFF);
    memcpy(out + 2, s, len);
    return (int)len + 2;
}

int mqttBuildConnect(uint8_t *out, size_t cap, const MQTTClient *c) {
    uint8_t vh[64];
    size_t vn = 0;
    vn += mqttEncodeString(vh + vn, "MQTT");
    vh[vn++] = 0x04;                          // protocol level 3.1.1
    uint8_t flags = 0x02;                     // clean session
    int hasUser = c->username[0] != '\0';
    int hasPass = c->password[0] != '\0';
    int hasWill = c->willTopic[0] != '\0';
    if (hasUser) flags |= 0x80;
    if (hasPass) flags |= 0x40;
    if (hasWill) flags |= 0x04 | 0x20;        // will flag + will retain
    vh[vn++] = flags;
    vh[vn++] = (uint8_t)((c->keepalive >> 8) & 0xFF);
    vh[vn++] = (uint8_t)(c->keepalive & 0xFF);

    uint8_t payload[512];
    size_t pn = 0;
    pn += mqttEncodeString(payload + pn, c->clientId);
    if (hasWill) {
        pn += mqttEncodeString(payload + pn, c->willTopic);
        pn += mqttEncodeString(payload + pn, "offline");
    }
    if (hasUser) pn += mqttEncodeString(payload + pn, c->username);
    if (hasPass) {
        size_t pl = strlen(c->password);
        if (pl > 0xFFFF) return -1;
        payload[pn++] = (uint8_t)((pl >> 8) & 0xFF);
        payload[pn++] = (uint8_t)(pl & 0xFF);
        memcpy(payload + pn, c->password, pl);
        pn += pl;
    }

    size_t rem = vn + pn;
    uint8_t rl[4];
    int rln = mqttEncodeRemainingLength(rl, (int)rem);
    size_t total = 1 + (size_t)rln + vn + pn;
    if (total > cap) return -1;
    out[0] = 0x10;                           // CONNECT
    memcpy(out + 1, rl, (size_t)rln);
    if (vn) memcpy(out + 1 + rln, vh, vn);
    if (pn) memcpy(out + 1 + rln + vn, payload, pn);
    return (int)total;
}

int mqttBuildPublish(uint8_t *out, size_t cap, const MQTTClient *c,
                     const char *topic, const char *payload, int retain) {
    (void)c;
    uint8_t vh[300];
    size_t vn = mqttEncodeString(vh, topic);
    size_t plen = strlen(payload);
    size_t rem = vn + plen;
    uint8_t rl[4];
    int rln = mqttEncodeRemainingLength(rl, (int)rem);
    size_t total = 1 + (size_t)rln + vn + plen;
    if (total > cap) return -1;
    out[0] = (uint8_t)(0x30 | (retain ? 0x01 : 0x00));  // PUBLISH QoS 0 [+retain]
    memcpy(out + 1, rl, (size_t)rln);
    if (vn) memcpy(out + 1 + rln, vh, vn);
    if (plen) memcpy(out + 1 + rln + vn, payload, plen);
    return (int)total;
}

int mqttParseConnack(const uint8_t *pkt, size_t len, int *returnCode) {
    if (len < 4) return -1;
    if (pkt[0] != 0x20) return -1;           // CONNACK
    *returnCode = pkt[3];
    return 0;
}

static int sendAll(int fd, const uint8_t *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = send(fd, buf + off, len - off, 0);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

int mqttConnect(MQTTClient *c) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", c->port);
    if (getaddrinfo(c->host, portStr, &hints, &res) != 0) return -1;

    int fd = -1;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) return -2;

    uint8_t pkt[512];
    int len = mqttBuildConnect(pkt, sizeof(pkt), c);
    if (len < 0) { close(fd); return -3; }
    if (sendAll(fd, pkt, (size_t)len) != 0) { close(fd); return -4; }

    uint8_t ack[4];
    ssize_t got = recv(fd, ack, sizeof(ack), 0);
    if (got != 4) { close(fd); return -5; }
    int rc = -1;
    if (mqttParseConnack(ack, 4, &rc) != 0 || rc != 0) { close(fd); return -6; }

    c->sockfd = fd;
    return 0;
}

int mqttPublish(MQTTClient *c, const char *topic, const char *payload, int retain) {
    uint8_t pkt[1024];
    int len = mqttBuildPublish(pkt, sizeof(pkt), c, topic, payload, retain);
    if (len < 0) return -1;
    return sendAll(c->sockfd, pkt, (size_t)len);
}

int mqttPing(MQTTClient *c) {
    static const uint8_t pingreq[2] = {0xC0, 0x00};
    if (sendAll(c->sockfd, pingreq, 2) != 0) return -1;
    struct pollfd pf;
    pf.fd = c->sockfd;
    pf.events = POLLIN;
    if (poll(&pf, 1, 5000) != 1) return -1;
    uint8_t resp[2];
    ssize_t n = recv(c->sockfd, resp, 2, 0);
    if (n != 2 || resp[0] != 0xD0) return -1;
    return 0;
}

void mqttClose(MQTTClient *c) {
    if (c->sockfd >= 0) close(c->sockfd);
    c->sockfd = -1;
}