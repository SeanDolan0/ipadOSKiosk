#include "../HTTPServer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define TEST_PORT 18080

// Mock recorder
static char g_lastAction[128] = {0};
static char g_lastValue[512] = {0};
static int g_commandCount = 0;
static int g_wakeCount = 0;

static void mockCommandHandler(const char *action, const char *value, void *context) {
    (void)context;
    strncpy(g_lastAction, action ? action : "", sizeof(g_lastAction) - 1);
    strncpy(g_lastValue, value ? value : "", sizeof(g_lastValue) - 1);
    g_commandCount++;
}

static void mockWakeHandler(void *context) {
    (void)context;
    g_wakeCount++;
}

// Mock TelemetrySnapshotToJSON implementation for test harness
char *TelemetrySnapshotToJSON(const TelemetrySnapshot *snapshot) {
    (void)snapshot;
    char *json = malloc(512);
    if (!json) return NULL;
    snprintf(json, 512, "{\"battery\":{\"level\":100},\"wifi\":{\"rssi\":-50},\"uptime\":3600}");
    return json;
}

static int sendHTTPRequest(int port, const char *request, char *responseOut, size_t responseCap) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    size_t reqLen = strlen(request);
    ssize_t written = write(fd, request, reqLen);
    if (written < (ssize_t)reqLen) {
        close(fd);
        return -1;
    }

    size_t total = 0;
    while (total < responseCap - 1) {
        ssize_t n = read(fd, responseOut + total, responseCap - 1 - total);
        if (n <= 0) break;
        total += (size_t)n;
    }
    responseOut[total] = '\0';
    close(fd);
    return (int)total;
}

static int sendGET(int port, const char *path, char *respOut, size_t respCap) {
    char req[512];
    snprintf(req, sizeof(req),
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n",
        path);
    return sendHTTPRequest(port, req, respOut, respCap);
}

static int sendPOST(int port, const char *path, const char *body, char *respOut, size_t respCap) {
    char req[2048];
    int bodyLen = body ? (int)strlen(body) : 0;
    snprintf(req, sizeof(req),
        "POST %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %d\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        path, bodyLen, body ? body : "");
    return sendHTTPRequest(port, req, respOut, respCap);
}

#pragma mark - Unit Tests: extractJSONString

static void test_json_extractor(void) {
    char out[256];

    // 1. Quoted string value
    assert(extractJSONString("{\"text\":\"Hello world\"}", "text", out, sizeof(out)) == 0);
    assert(strcmp(out, "Hello world") == 0);

    // 2. Numeric values (float, integer)
    assert(extractJSONString("{\"value\":0.8}", "value", out, sizeof(out)) == 0);
    assert(strcmp(out, "0.8") == 0);

    assert(extractJSONString("{\"value\":100}", "value", out, sizeof(out)) == 0);
    assert(strcmp(out, "100") == 0);

    assert(extractJSONString("{\"value\":-45}", "value", out, sizeof(out)) == 0);
    assert(strcmp(out, "-45") == 0);

    // 3. Multiple keys and whitespace formatting
    const char *multi = "{\n  \"action\" : \"setBrightness\" ,\n  \"value\" : 0.75\n}";
    assert(extractJSONString(multi, "action", out, sizeof(out)) == 0);
    assert(strcmp(out, "setBrightness") == 0);
    assert(extractJSONString(multi, "value", out, sizeof(out)) == 0);
    assert(strcmp(out, "0.75") == 0);

    // 4. URL string with special characters
    const char *urlJson = "{\"url\":\"http://192.168.50.150:8123/lovelace/0?kiosk=1\"}";
    assert(extractJSONString(urlJson, "url", out, sizeof(out)) == 0);
    assert(strcmp(out, "http://192.168.50.150:8123/lovelace/0?kiosk=1") == 0);

    // 5. Escaped quotes within string
    const char *escaped = "{\"text\":\"Hello \\\"Alice\\\" and \\\"Bob\\\"\"}";
    assert(extractJSONString(escaped, "text", out, sizeof(out)) == 0);
    assert(strcmp(out, "Hello \"Alice\" and \"Bob\"") == 0);

    // 6. Missing key
    assert(extractJSONString("{\"text\":\"Hello\"}", "missing", out, sizeof(out)) == -1);

    // 7. NULL and bounds handling
    assert(extractJSONString(NULL, "text", out, sizeof(out)) == -1);
    assert(extractJSONString("{\"text\":\"Hello\"}", NULL, out, sizeof(out)) == -1);
    assert(extractJSONString("{\"text\":\"Hello\"}", "text", NULL, sizeof(out)) == -1);
    assert(extractJSONString("{\"text\":\"Hello\"}", "text", out, 0) == -1);

    // 8. Buffer truncation safety
    char tiny[4];
    assert(extractJSONString("{\"text\":\"Hello\"}", "text", tiny, sizeof(tiny)) == 0);
    assert(strcmp(tiny, "Hel") == 0);

    printf("  [PASS] test_json_extractor\n");
}

#pragma mark - Integration Tests: REST API Routes

static void test_http_server_endpoints(void) {
    TelemetrySnapshot snap;
    memset(&snap, 0, sizeof(snap));
    snap.uptimeSeconds = 3600;

    HTTPServerConfig config;
    memset(&config, 0, sizeof(config));
    config.port = TEST_PORT;
    config.snapshot = &snap;
    config.commandHandler = mockCommandHandler;
    config.wakeHandler = mockWakeHandler;

    int rc = HTTPServerStart(&config);
    assert(rc == 0);
    usleep(50000); // 50ms wait for server thread to bind and listen

    char resp[2048];

    // 1. GET /api/status -> 200 OK + JSON
    rc = sendGET(TEST_PORT, "/api/status", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(strstr(resp, "Content-Type: application/json") != NULL);
    assert(strstr(resp, "\"battery\"") != NULL);
    printf("  [PASS] GET /api/status\n");

    // 2. GET /telemetry (legacy alias) -> 200 OK
    rc = sendGET(TEST_PORT, "/telemetry", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    printf("  [PASS] GET /telemetry\n");

    // 3. GET /api/health -> 200 OK + pid + uptime
    rc = sendGET(TEST_PORT, "/api/health", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(strstr(resp, "\"status\":\"ok\"") != NULL);
    assert(strstr(resp, "\"uptime\":3600") != NULL);
    printf("  [PASS] GET /api/health\n");

    // 4. GET /health (legacy alias) -> 200 OK
    rc = sendGET(TEST_PORT, "/health", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    printf("  [PASS] GET /health\n");

    // 5. POST /api/tts with {"text":"Hello"}
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/tts", "{\"text\":\"Hello\"}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "tts") == 0);
    assert(strcmp(g_lastValue, "Hello") == 0);
    printf("  [PASS] POST /api/tts\n");

    // 6. POST /api/brightness with {"value":0.8}
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/brightness", "{\"value\":0.8}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setBrightness") == 0);
    assert(strcmp(g_lastValue, "0.8") == 0);
    printf("  [PASS] POST /api/brightness\n");

    // 7. POST /api/brightness with raw string body "0.5"
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/brightness", "0.5", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setBrightness") == 0);
    assert(strcmp(g_lastValue, "0.5") == 0);
    printf("  [PASS] POST /api/brightness (raw body fallback)\n");

    // 8. POST /api/volume with {"value":0.65}
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/volume", "{\"value\":0.65}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setVolume") == 0);
    assert(strcmp(g_lastValue, "0.65") == 0);
    printf("  [PASS] POST /api/volume\n");

    // 9. POST /api/audio/beep
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/audio/beep", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "beep") == 0);
    printf("  [PASS] POST /api/audio/beep\n");

    // 10. POST /api/beep (alias)
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/beep", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "beep") == 0);
    printf("  [PASS] POST /api/beep\n");

    // 11. POST /api/reload
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/reload", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "reload") == 0);
    printf("  [PASS] POST /api/reload\n");

    // 12. POST /api/url with {"url":"http://192.168.1.100:8123"}
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/url", "{\"url\":\"http://192.168.1.100:8123\"}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "loadURL") == 0);
    assert(strcmp(g_lastValue, "http://192.168.1.100:8123") == 0);
    printf("  [PASS] POST /api/url\n");

    // 13. POST /api/screensaver/on
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/screensaver/on", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setScreensaver") == 0);
    assert(strcmp(g_lastValue, "ON") == 0);
    printf("  [PASS] POST /api/screensaver/on\n");

    // 14. POST /api/screensaver/off
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/screensaver/off", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setScreensaver") == 0);
    assert(strcmp(g_lastValue, "OFF") == 0);
    printf("  [PASS] POST /api/screensaver/off\n");

    // 15. POST /api/screen/on
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/screen/on", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setScreen") == 0);
    assert(strcmp(g_lastValue, "ON") == 0);
    printf("  [PASS] POST /api/screen/on\n");

    // 16. POST /api/screen/off
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/screen/off", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setScreen") == 0);
    assert(strcmp(g_lastValue, "OFF") == 0);
    printf("  [PASS] POST /api/screen/off\n");

    // 17. POST /api/clearCache
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/clearCache", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "clearCache") == 0);
    printf("  [PASS] POST /api/clearCache\n");

    // 18. POST /api/reboot
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/reboot", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "reboot") == 0);
    printf("  [PASS] POST /api/reboot\n");

    // 19. POST /api/restart-ui
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/api/restart-ui", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "relaunchApp") == 0);
    printf("  [PASS] POST /api/restart-ui\n");

    // 20. POST /wake and POST /api/wake
    g_wakeCount = 0;
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/wake", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_wakeCount == 1);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "wake") == 0);

    rc = sendPOST(TEST_PORT, "/api/wake", "", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_wakeCount == 2);
    assert(g_commandCount == 2);
    printf("  [PASS] POST /wake & /api/wake\n");

    // 21. POST /command (legacy)
    g_commandCount = 0;
    rc = sendPOST(TEST_PORT, "/command", "{\"action\":\"setBrightness\",\"value\":\"0.85\"}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 200 OK") != NULL);
    assert(g_commandCount == 1);
    assert(strcmp(g_lastAction, "setBrightness") == 0);
    assert(strcmp(g_lastValue, "0.85") == 0);
    printf("  [PASS] POST /command (legacy)\n");

    // 22. POST /command without action -> 400 Bad Request
    rc = sendPOST(TEST_PORT, "/command", "{\"value\":0.5}", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 400 Bad Request") != NULL);
    printf("  [PASS] POST /command (400 on missing action)\n");

    // 23. GET /unknown-path -> 404 Not Found
    rc = sendGET(TEST_PORT, "/unknown-path", resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 404 Not Found") != NULL);
    printf("  [PASS] GET /unknown-path (404 Not Found)\n");

    // 24. DELETE /api/status -> 405 Method Not Allowed
    char delReq[512];
    snprintf(delReq, sizeof(delReq), "DELETE /api/status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
    rc = sendHTTPRequest(TEST_PORT, delReq, resp, sizeof(resp));
    assert(rc > 0);
    assert(strstr(resp, "HTTP/1.1 405 Method Not Allowed") != NULL);
    printf("  [PASS] DELETE /api/status (405 Method Not Allowed)\n");

    HTTPServerStop();
    printf("  [PASS] HTTPServerStop\n");
}

#pragma mark - Concurrency Tests

typedef struct {
    int port;
    int clientIndex;
    int success;
} ConcurrentClientArg;

static void *concurrentClientWorker(void *arg) {
    ConcurrentClientArg *carg = (ConcurrentClientArg *)arg;
    char resp[1024] = {0};
    int rc = -1;

    if (carg->clientIndex % 3 == 0) {
        rc = sendGET(carg->port, "/api/status", resp, sizeof(resp));
        if (rc > 0 && strstr(resp, "200 OK") && strstr(resp, "\"battery\"")) {
            carg->success = 1;
        }
    } else if (carg->clientIndex % 3 == 1) {
        rc = sendGET(carg->port, "/api/health", resp, sizeof(resp));
        if (rc > 0 && strstr(resp, "200 OK") && strstr(resp, "\"status\":\"ok\"")) {
            carg->success = 1;
        }
    } else {
        char body[128];
        snprintf(body, sizeof(body), "{\"text\":\"Client %d\"}", carg->clientIndex);
        rc = sendPOST(carg->port, "/api/tts", body, resp, sizeof(resp));
        if (rc > 0 && strstr(resp, "200 OK") && strstr(resp, "\"status\":\"ok\"")) {
            carg->success = 1;
        }
    }
    return NULL;
}

static void test_concurrent_clients(void) {
    TelemetrySnapshot snap;
    memset(&snap, 0, sizeof(snap));
    snap.uptimeSeconds = 1200;

    HTTPServerConfig config;
    memset(&config, 0, sizeof(config));
    config.port = TEST_PORT;
    config.snapshot = &snap;
    config.commandHandler = mockCommandHandler;
    config.wakeHandler = mockWakeHandler;

    int rc = HTTPServerStart(&config);
    assert(rc == 0);
    usleep(50000);

    // 1. Test 12 simultaneous client threads
    #define NUM_CONCURRENT 12
    pthread_t threads[NUM_CONCURRENT];
    ConcurrentClientArg args[NUM_CONCURRENT];

    for (int i = 0; i < NUM_CONCURRENT; i++) {
        args[i].port = TEST_PORT;
        args[i].clientIndex = i;
        args[i].success = 0;
        int pt_rc = pthread_create(&threads[i], NULL, concurrentClientWorker, &args[i]);
        assert(pt_rc == 0);
    }

    for (int i = 0; i < NUM_CONCURRENT; i++) {
        pthread_join(threads[i], NULL);
        assert(args[i].success == 1);
    }
    printf("  [PASS] 12 concurrent requests completed successfully\n");

    // 2. Slow client non-blocking test:
    // Open slow connection fd, don't send data immediately.
    int slowFD = socket(AF_INET, SOCK_STREAM, 0);
    assert(slowFD >= 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)TEST_PORT);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    assert(connect(slowFD, (struct sockaddr *)&addr, sizeof(addr)) == 0);

    // Fast client connects while slow client holds socket open without writing
    char fastResp[1024] = {0};
    int fastRC = sendGET(TEST_PORT, "/api/health", fastResp, sizeof(fastResp));
    assert(fastRC > 0);
    assert(strstr(fastResp, "200 OK") != NULL);
    printf("  [PASS] Fast client served while slow client is connected\n");

    // Slow client sends request after delay
    const char *slowReq = "GET /api/status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    assert(write(slowFD, slowReq, strlen(slowReq)) == (ssize_t)strlen(slowReq));
    char slowResp[1024] = {0};
    size_t total = 0;
    while (total < sizeof(slowResp) - 1) {
        ssize_t n = read(slowFD, slowResp + total, sizeof(slowResp) - 1 - total);
        if (n <= 0) break;
        total += (size_t)n;
    }
    slowResp[total] = '\0';
    close(slowFD);
    assert(strstr(slowResp, "200 OK") != NULL);
    printf("  [PASS] Slow client completed after delay\n");

    HTTPServerStop();
    printf("  [PASS] test_concurrent_clients\n");
}

int main(void) {
    printf("Running HTTPServer test suite...\n");
    test_json_extractor();
    test_http_server_endpoints();
    test_concurrent_clients();
    printf("All HTTPServer tests passed successfully!\n");
    return 0;
}
