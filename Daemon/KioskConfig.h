#ifndef KioskConfig_h
#define KioskConfig_h

// Plist-derived MQTT config for kioskd. Mirror of the `mqtt` block in
// /var/mobile/Library/Preferences/com.hasmartboard.plist (see config.plist.example).
typedef struct {
    int  enabled;         // 0 = MQTT off (no thread started)
    char host[128];       // broker host, default 192.168.50.150
    int  port;            // broker port, default 1883
    char username[64];    // MQTT user (ex: "kiosk")
    char password[64];    // MQTT password — NEVER log
    char prefix[64];      // topic base, default "kiosk"
    char clientId[64];    // default "hasmartboard-ipad"
    int  interval;        // state publish cadence seconds, default 30
} KioskMQTTConfig;

// Reads the mqtt block from the device plist. If absent, leaves defaults with
// enabled=0. Safe to call at startup only (not thread-safe).
void KioskConfigLoadMQTT(KioskMQTTConfig *out);

#endif