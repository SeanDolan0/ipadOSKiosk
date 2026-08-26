#import "HTTPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdio.h>

static int g_serverFD = -1;
static volatile int g_running = 0;
static pthread_t g_serverThread;
static HTTPServerConfig g_config;

#pragma mark - HTTP Response Helpers

static void sendResponse(int clientFD, int statusCode, const char *statusText,
                         const char *contentType, const char *body) {
    char header[512];
    int bodyLen = body ? (int)strlen(body) : 0;
    snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %d\r\n"
        "Connection: close\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "\r\n",
        statusCode, statusText, contentType, bodyLen);

    write(clientFD, header, strlen(header));
    if (body && bodyLen > 0) {
        write(clientFD, body, bodyLen);
    }
}

static void sendJSON(int clientFD, int statusCode, const char *body) {
    sendResponse(clientFD, statusCode, "OK", "application/json", body);
}

static void send404(int clientFD) {
    sendResponse(clientFD, 404, "Not Found", "text/plain", "Not Found");
}

static void send405(int clientFD) {
    sendResponse(clientFD, 405, "Method Not Allowed", "text/plain", "Method Not Allowed");
}

static void send400(int clientFD) {
    sendResponse(clientFD, 400, "Bad Request", "text/plain", "Bad Request");
}

#pragma mark - Request Parsing

static int readRequest(int clientFD, char *buffer, int bufferSize) {
    int total = 0;
    int n;
    while (total < bufferSize - 1) {
        n = (int)read(clientFD, buffer + total, bufferSize - 1 - total);
        if (n <= 0) break;
        total += n;
        buffer[total] = '\0';
        if (strstr(buffer, "\r\n\r\n")) break;
    }
    return total;
}

static int getContentLength(const char *headers) {
    const char *cl = strstr(headers, "Content-Length:");
    if (!cl) cl = strstr(headers, "content-length:");
    if (!cl) return -1;
    return atoi(cl + 15);
}

static void readBody(int clientFD, char *buffer, int headerEnd, int totalRead, int contentLength) {
    int bodyRead = totalRead - headerEnd;
    while (bodyRead < contentLength) {
        int n = (int)read(clientFD, buffer + totalRead, contentLength - bodyRead);
        if (n <= 0) break;
        totalRead += n;
        bodyRead += n;
    }
    buffer[totalRead] = '\0';
}

#pragma mark - Route Handlers

static void handleGETTelemetry(int clientFD) {
    char *json = TelemetrySnapshotToJSON(g_config.snapshot);
    if (json) {
        sendJSON(clientFD, 200, json);
        free(json);
    } else {
        sendJSON(clientFD, 500, "{\"error\":\"telemetry unavailable\"}");
    }
}

static void handleGETHealth(int clientFD) {
    char body[128];
    snprintf(body, sizeof(body),
        "{\"status\":\"ok\",\"pid\":%d,\"uptime\":%d}",
        getpid(), g_config.snapshot->uptimeSeconds);
    sendJSON(clientFD, 200, body);
}

static void handlePOSTCommand(int clientFD, const char *body) {
    const char *actionStart = strstr(body, "\"action\"");
    if (!actionStart) { send400(clientFD); return; }

    actionStart = strchr(actionStart, ':');
    if (!actionStart) { send400(clientFD); return; }
    actionStart++;
    while (*actionStart == ' ') actionStart++;
    if (*actionStart == '"') actionStart++;

    char action[64] = {0};
    int i = 0;
    while (*actionStart && *actionStart != '"' && i < 63) {
        action[i++] = *actionStart++;
    }

    const char *valueStart = strstr(body, "\"value\"");
    char value[64] = {0};
    if (valueStart) {
        valueStart = strchr(valueStart, ':');
        if (valueStart) {
            valueStart++;
            while (*valueStart == ' ') valueStart++;
            if (*valueStart == '"') valueStart++;
            i = 0;
            while (*valueStart && *valueStart != '"' && i < 63) {
                value[i++] = *valueStart++;
            }
        }
    }

    if (g_config.commandHandler) {
        g_config.commandHandler(action, value, g_config.callbackContext);
    }

    sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
}

static void handlePOSTWake(int clientFD) {
    if (g_config.wakeHandler) {
        g_config.wakeHandler(g_config.callbackContext);
    }
    sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
}

#pragma mark - Request Router

static void handleClient(int clientFD) {
    char buffer[4096];
    int totalRead = readRequest(clientFD, buffer, sizeof(buffer));
    if (totalRead <= 0) { close(clientFD); return; }

    char method[8] = {0};
    char path[256] = {0};
    sscanf(buffer, "%7s %255s", method, path);

    char *headerEnd = strstr(buffer, "\r\n\r\n");
    int headerEndOffset = headerEnd ? (int)(headerEnd - buffer) + 4 : totalRead;

    if (strcmp(method, "GET") == 0) {
        if (strcmp(path, "/telemetry") == 0) {
            handleGETTelemetry(clientFD);
        } else if (strcmp(path, "/health") == 0) {
            handleGETHealth(clientFD);
        } else {
            send404(clientFD);
        }
    }
    else if (strcmp(method, "POST") == 0) {
        int contentLength = getContentLength(buffer);
        if (contentLength > 0) {
            readBody(clientFD, buffer, headerEndOffset, totalRead, contentLength);
        }
        const char *body = headerEndOffset < totalRead ? buffer + headerEndOffset : "";

        if (strcmp(path, "/command") == 0) {
            handlePOSTCommand(clientFD, body);
        } else if (strcmp(path, "/wake") == 0) {
            handlePOSTWake(clientFD);
        } else {
            send404(clientFD);
        }
    }
    else {
        send405(clientFD);
    }

    close(clientFD);
}

#pragma mark - Server Thread

static void *serverThread(void *arg) {
    (void)arg;
    while (g_running) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientFD = accept(g_serverFD, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientFD < 0) continue;
        handleClient(clientFD);
    }
    return NULL;
}

#pragma mark - Public API

int HTTPServerStart(const HTTPServerConfig *config) {
    g_config = *config;

    g_serverFD = socket(AF_INET, SOCK_STREAM, 0);
    if (g_serverFD < 0) return -1;

    int reuse = 1;
    setsockopt(g_serverFD, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(config->port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (bind(g_serverFD, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(g_serverFD);
        return -1;
    }

    if (listen(g_serverFD, 5) < 0) {
        close(g_serverFD);
        return -1;
    }

    g_running = 1;
    if (pthread_create(&g_serverThread, NULL, serverThread, NULL) != 0) {
        close(g_serverFD);
        return -1;
    }

    return 0;
}

void HTTPServerStop(void) {
    g_running = 0;
    close(g_serverFD);
    pthread_join(g_serverThread, NULL);
}
