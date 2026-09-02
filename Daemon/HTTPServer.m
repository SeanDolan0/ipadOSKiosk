#import "HTTPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdio.h>
#include <poll.h>

static int g_serverFD = -1;
static volatile int g_running = 0;
static pthread_t g_serverThread;
static HTTPServerConfig g_config;

#pragma mark - JSON Helper

int extractJSONString(const char *json, const char *key, char *out, size_t cap) {
    if (!json || !key || !out || cap == 0) return -1;
    out[0] = '\0';

    char searchKey[128];
    snprintf(searchKey, sizeof(searchKey), "\"%s\"", key);
    size_t searchKeyLen = strlen(searchKey);

    const char *p = json;
    while ((p = strstr(p, searchKey)) != NULL) {
        const char *after = p + searchKeyLen;
        while (*after == ' ' || *after == '\t' || *after == '\r' || *after == '\n') after++;
        if (*after == ':') {
            after++; // skip ':'
            while (*after == ' ' || *after == '\t' || *after == '\r' || *after == '\n') after++;

            if (*after == '"') {
                after++; // skip opening quote
                size_t idx = 0;
                while (*after && *after != '"' && idx < cap - 1) {
                    if (*after == '\\' && *(after + 1) != '\0') {
                        after++; // skip escape backslash
                    }
                    out[idx++] = *after++;
                }
                out[idx] = '\0';
                return 0;
            } else {
                // Numeric / boolean / raw token
                size_t idx = 0;
                while (*after && *after != ',' && *after != '}' && *after != ']' &&
                       *after != ' ' && *after != '\t' && *after != '\r' && *after != '\n' &&
                       idx < cap - 1) {
                    out[idx++] = *after++;
                }
                out[idx] = '\0';
                return idx > 0 ? 0 : -1;
            }
        }
        p += searchKeyLen;
    }
    return -1;
}

static void getBodyValueOrRaw(const char *body, const char *key, char *out, size_t cap) {
    if (!body || !out || cap == 0) return;
    out[0] = '\0';

    if (extractJSONString(body, key, out, cap) == 0) {
        return;
    }

    // Fallback: trimmed body string if body is not a JSON object
    const char *p = body;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (*p == '{') {
        out[0] = '\0';
        return;
    }

    size_t len = strlen(p);
    while (len > 0 && (p[len - 1] == ' ' || p[len - 1] == '\t' || p[len - 1] == '\r' || p[len - 1] == '\n')) {
        len--;
    }
    if (len > 0 && len < cap) {
        memcpy(out, p, len);
        out[len] = '\0';
    }
}

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

    ssize_t w1 = write(clientFD, header, strlen(header));
    (void)w1;
    if (body && bodyLen > 0) {
        ssize_t w2 = write(clientFD, body, (size_t)bodyLen);
        (void)w2;
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
        n = (int)read(clientFD, buffer + total, (size_t)(bufferSize - 1 - total));
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

static void readBody(int clientFD, char *buffer, int bufferSize, int headerEnd, int *pTotalRead, int contentLength) {
    int totalRead = *pTotalRead;
    int bodyRead = totalRead - headerEnd;
    while (bodyRead < contentLength && totalRead < bufferSize - 1) {
        int toRead = contentLength - bodyRead;
        if (totalRead + toRead >= bufferSize) {
            toRead = bufferSize - 1 - totalRead;
        }
        int n = (int)read(clientFD, buffer + totalRead, (size_t)toRead);
        if (n <= 0) break;
        totalRead += n;
        bodyRead += n;
    }
    buffer[totalRead] = '\0';
    *pTotalRead = totalRead;
}

#pragma mark - Route Handlers

static void handleGETTelemetry(int clientFD) {
    if (g_config.snapshot) {
        char *json = TelemetrySnapshotToJSON(g_config.snapshot);
        if (json) {
            sendJSON(clientFD, 200, json);
            free(json);
            return;
        }
    }
    sendJSON(clientFD, 500, "{\"error\":\"telemetry unavailable\"}");
}

static void handleGETHealth(int clientFD) {
    char body[128];
    int uptime = g_config.snapshot ? g_config.snapshot->uptimeSeconds : 0;
    snprintf(body, sizeof(body),
        "{\"status\":\"ok\",\"pid\":%d,\"uptime\":%d}",
        (int)getpid(), uptime);
    sendJSON(clientFD, 200, body);
}

static void handlePOSTCommand(int clientFD, const char *body) {
    char action[64] = {0};
    char value[512] = {0};

    if (extractJSONString(body, "action", action, sizeof(action)) != 0) {
        send400(clientFD);
        return;
    }
    extractJSONString(body, "value", value, sizeof(value));

    if (g_config.commandHandler) {
        g_config.commandHandler(action, value, g_config.callbackContext);
    }

    sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
}

static void handlePOSTWake(int clientFD) {
    if (g_config.wakeHandler) {
        g_config.wakeHandler(g_config.callbackContext);
    }
    if (g_config.commandHandler) {
        g_config.commandHandler("wake", "", g_config.callbackContext);
    }
    sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
}

#pragma mark - Request Router

static void handleClient(int clientFD) {
    char buffer[4096];
    int totalRead = readRequest(clientFD, buffer, (int)sizeof(buffer));
    if (totalRead <= 0) { close(clientFD); return; }

    char method[8] = {0};
    char path[256] = {0};
    if (sscanf(buffer, "%7s %255s", method, path) < 2) {
        send400(clientFD);
        close(clientFD);
        return;
    }

    // Strip query parameters if present
    char *query = strchr(path, '?');
    if (query) *query = '\0';

    char *headerEnd = strstr(buffer, "\r\n\r\n");
    int headerEndOffset = headerEnd ? (int)(headerEnd - buffer) + 4 : totalRead;

    if (strcmp(method, "GET") == 0) {
        if (strcmp(path, "/api/status") == 0 || strcmp(path, "/telemetry") == 0) {
            handleGETTelemetry(clientFD);
        } else if (strcmp(path, "/api/health") == 0 || strcmp(path, "/health") == 0) {
            handleGETHealth(clientFD);
        } else {
            send404(clientFD);
        }
    }
    else if (strcmp(method, "POST") == 0) {
        int contentLength = getContentLength(buffer);
        if (contentLength > 0 && contentLength < (int)sizeof(buffer) - headerEndOffset) {
            readBody(clientFD, buffer, (int)sizeof(buffer), headerEndOffset, &totalRead, contentLength);
        }
        const char *body = headerEndOffset < totalRead ? buffer + headerEndOffset : "";

        if (strcmp(path, "/command") == 0) {
            handlePOSTCommand(clientFD, body);
        } else if (strcmp(path, "/wake") == 0 || strcmp(path, "/api/wake") == 0) {
            handlePOSTWake(clientFD);
        } else if (strcmp(path, "/api/brightness") == 0) {
            char val[128] = {0};
            getBodyValueOrRaw(body, "value", val, sizeof(val));
            if (g_config.commandHandler) {
                g_config.commandHandler("setBrightness", val, g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/volume") == 0) {
            char val[128] = {0};
            getBodyValueOrRaw(body, "value", val, sizeof(val));
            if (g_config.commandHandler) {
                g_config.commandHandler("setVolume", val, g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/tts") == 0) {
            char text[1024] = {0};
            getBodyValueOrRaw(body, "text", text, sizeof(text));
            if (g_config.commandHandler) {
                g_config.commandHandler("tts", text, g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/audio/beep") == 0 || strcmp(path, "/api/beep") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("beep", "", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/reload") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("reload", "", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/url") == 0) {
            char url[1024] = {0};
            getBodyValueOrRaw(body, "url", url, sizeof(url));
            if (g_config.commandHandler) {
                g_config.commandHandler("loadURL", url, g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/screensaver/on") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("setScreensaver", "ON", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/screensaver/off") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("setScreensaver", "OFF", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/screen/on") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("setScreen", "ON", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/screen/off") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("setScreen", "OFF", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/clearCache") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("clearCache", "", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/reboot") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("reboot", "", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
        } else if (strcmp(path, "/api/restart-ui") == 0) {
            if (g_config.commandHandler) {
                g_config.commandHandler("relaunchApp", "", g_config.callbackContext);
            }
            sendJSON(clientFD, 200, "{\"status\":\"ok\"}");
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
        struct pollfd pfd;
        pfd.fd = g_serverFD;
        pfd.events = POLLIN;
        pfd.revents = 0;

        int pret = poll(&pfd, 1, 100);
        if (pret <= 0 || !g_running) continue;

        if (pfd.revents & POLLIN) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientFD = accept(g_serverFD, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientFD < 0) continue;

            struct timeval tv;
            tv.tv_sec = 1;
            tv.tv_usec = 0;
            setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));

            handleClient(clientFD);
        }
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
    addr.sin_port = htons((uint16_t)config->port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(g_serverFD, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(g_serverFD);
        g_serverFD = -1;
        return -1;
    }

    if (listen(g_serverFD, 5) < 0) {
        close(g_serverFD);
        g_serverFD = -1;
        return -1;
    }

    g_running = 1;
    if (pthread_create(&g_serverThread, NULL, serverThread, NULL) != 0) {
        close(g_serverFD);
        g_serverFD = -1;
        return -1;
    }

    return 0;
}

void HTTPServerStop(void) {
    if (!g_running) return;
    g_running = 0;
    pthread_join(g_serverThread, NULL);
    if (g_serverFD >= 0) {
        close(g_serverFD);
        g_serverFD = -1;
    }
}


