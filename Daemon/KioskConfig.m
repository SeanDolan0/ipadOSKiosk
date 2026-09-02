#import "KioskConfig.h"
#import <Foundation/Foundation.h>
#include <string.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

void KioskConfigLoadMQTT(KioskMQTTConfig *out) {
    memset(out, 0, sizeof(*out));
    out->enabled = 0;
    out->port = 1883;
    out->interval = 30;
    snprintf(out->host, sizeof(out->host), "%s", "192.168.50.150");
    snprintf(out->clientId, sizeof(out->clientId), "%s", "hasmartboard-ipad");
    snprintf(out->prefix, sizeof(out->prefix), "%s", "kiosk");

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSDictionary *mqtt = prefs[@"mqtt"];
    if (![mqtt isKindOfClass:[NSDictionary class]]) return;

    if ([mqtt objectForKey:@"enabled"])
        out->enabled = [mqtt[@"enabled"] boolValue];
    else
        out->enabled = 1; // block present without explicit flag => on

    if ([mqtt objectForKey:@"host"]) {
        NSString *v = mqtt[@"host"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->host))
            snprintf(out->host, sizeof(out->host), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"port"])
        out->port = [mqtt[@"port"] intValue];
    if ([mqtt objectForKey:@"user"]) {
        NSString *v = mqtt[@"user"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->username))
            snprintf(out->username, sizeof(out->username), "%s", v.UTF8String);
    } else if ([mqtt objectForKey:@"username"]) {
        NSString *v = mqtt[@"username"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->username))
            snprintf(out->username, sizeof(out->username), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"pass"]) {
        NSString *v = mqtt[@"pass"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->password))
            snprintf(out->password, sizeof(out->password), "%s", v.UTF8String);
    } else if ([mqtt objectForKey:@"password"]) {
        NSString *v = mqtt[@"password"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->password))
            snprintf(out->password, sizeof(out->password), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"prefix"]) {
        NSString *v = mqtt[@"prefix"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->prefix))
            snprintf(out->prefix, sizeof(out->prefix), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"clientId"]) {
        NSString *v = mqtt[@"clientId"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->clientId))
            snprintf(out->clientId, sizeof(out->clientId), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"interval"])
        out->interval = [mqtt[@"interval"] intValue];
}