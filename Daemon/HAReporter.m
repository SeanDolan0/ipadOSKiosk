#import "HAReporter.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

static HAReporterConfig g_config;

#pragma mark - HTTP POST to HA

static int postToHA(const char *path, const char *body) {
    const char *hostStart = strstr(g_config.haURL, "://");
    if (!hostStart) return -1;
    hostStart += 3;

    char host[128] = {0};
    int port = 80;
    const char *portSep = strchr(hostStart, ':');
    const char *pathStart = strchr(hostStart, '/');

    if (portSep) {
        strncpy(host, hostStart, portSep - hostStart);
        port = atoi(portSep + 1);
    } else if (pathStart) {
        strncpy(host, hostStart, pathStart - hostStart);
    } else {
        strncpy(host, hostStart, sizeof(host) - 1);
    }

    struct hostent *he = gethostbyname(host);
    if (!he) return -1;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);

    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return -1;
    }

    int bodyLen = (int)strlen(body);
    char header[1024];
    snprintf(header, sizeof(header),
        "POST %s HTTP/1.1\r\n"
        "Host: %s:%d\r\n"
        "Authorization: Bearer %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %d\r\n"
        "Connection: close\r\n"
        "\r\n",
        path, host, port, g_config.haToken, bodyLen);

    write(sock, header, strlen(header));
    write(sock, body, bodyLen);

    char response[256] = {0};
    read(sock, response, sizeof(response) - 1);
    close(sock);

    return strstr(response, "200") ? 0 : -1;
}

#pragma mark - Sensor State Push

static void pushSensor(const char *entityId, const char *state,
                       const char *unit, const char *friendlyName) {
    char body[512];
    snprintf(body, sizeof(body),
        "{\"state\":\"%s\","
        "\"attributes\":{"
        "\"unit_of_measurement\":\"%s\","
        "\"friendly_name\":\"%s\""
        "}}",
        state, unit, friendlyName);

    char path[256];
    snprintf(path, sizeof(path), "/api/states/%s", entityId);

    if (postToHA(path, body) != 0) {
        syslog(LOG_WARNING, "kioskd: failed to push %s", entityId);
    }
}

#pragma mark - Public API

int HAReporterInit(const HAReporterConfig *config) {
    g_config = *config;
    return 0;
}

int HAReporterPush(const TelemetrySnapshot *s) {
    char buf[32];

    snprintf(buf, sizeof(buf), "%d", s->batteryLevel);
    pushSensor("sensor.kiosk_battery_level", buf, "%", "Kiosk Battery Level");

    snprintf(buf, sizeof(buf), "%d", s->batteryCurrentMA);
    pushSensor("sensor.kiosk_battery_current", buf, "mA", "Kiosk Battery Current");

    float tempC = s->batteryTempDeciC / 10.0f;
    snprintf(buf, sizeof(buf), "%.1f", tempC);
    pushSensor("sensor.kiosk_battery_temp", buf, "°C", "Kiosk Battery Temp");

    snprintf(buf, sizeof(buf), "%d", s->batteryHealthPct);
    pushSensor("sensor.kiosk_battery_health", buf, "%", "Kiosk Battery Health");

    snprintf(buf, sizeof(buf), "%d", s->batteryCycles);
    pushSensor("sensor.kiosk_battery_cycles", buf, "", "Kiosk Battery Cycles");

    snprintf(buf, sizeof(buf), "%d", s->wifiRSSI);
    pushSensor("sensor.kiosk_wifi_rssi", buf, "dBm", "Kiosk WiFi RSSI");

    pushSensor("sensor.kiosk_wifi_ssid", s->wifiSSID, "", "Kiosk WiFi SSID");

    snprintf(buf, sizeof(buf), "%d", s->wifiLinkSpeed);
    pushSensor("sensor.kiosk_wifi_link_speed", buf, "Mbps", "Kiosk WiFi Link Speed");

    snprintf(buf, sizeof(buf), "%lld", s->storageFreeBytes / (1024 * 1024));
    pushSensor("sensor.kiosk_storage_free", buf, "MB", "Kiosk Storage Free");

    snprintf(buf, sizeof(buf), "%lld", s->memoryFreeBytes / (1024 * 1024));
    pushSensor("sensor.kiosk_memory_free", buf, "MB", "Kiosk Memory Free");

    snprintf(buf, sizeof(buf), "%d", s->uptimeSeconds);
    pushSensor("sensor.kiosk_uptime", buf, "s", "Kiosk Uptime");

    snprintf(buf, sizeof(buf), "%lld", s->netRxBytes);
    pushSensor("sensor.kiosk_network_rx_bytes", buf, "B", "Kiosk Network RX");

    snprintf(buf, sizeof(buf), "%lld", s->netTxBytes);
    pushSensor("sensor.kiosk_network_tx_bytes", buf, "B", "Kiosk Network TX");

    return 0;
}
