#import "TelemetryRelay.h"

@interface TelemetryRelay ()
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *token;
@end

@implementation TelemetryRelay

- (instancetype)initWithBaseURL:(NSString *)baseURL token:(NSString *)token {
    self = [super init];
    if (self) {
        _baseURL = [baseURL copy];
        _token = [token copy];
    }
    return self;
}

- (void)relayTelemetry:(NSDictionary *)telemetry {
    NSDictionary *battery = telemetry[@"battery"];
    NSDictionary *wifi = telemetry[@"wifi"];
    NSDictionary *storage = telemetry[@"storage"];
    NSDictionary *memory = telemetry[@"memory"];
    NSDictionary *network = telemetry[@"network"];

    [self pushState:@"sensor.kiosk_battery_level"
              state:[battery[@"level"] stringValue]
               unit:@"%"
        friendlyName:@"Kiosk Battery Level"];

    [self pushState:@"sensor.kiosk_battery_current"
              state:[battery[@"current"] stringValue]
               unit:@"mA"
        friendlyName:@"Kiosk Battery Current"];

    float tempC = [battery[@"temp"] floatValue] / 10.0f;
    [self pushState:@"sensor.kiosk_battery_temp"
              state:[NSString stringWithFormat:@"%.1f", tempC]
               unit:@"°C"
        friendlyName:@"Kiosk Battery Temp"];

    [self pushState:@"sensor.kiosk_battery_health"
              state:[battery[@"health"] stringValue]
               unit:@"%"
        friendlyName:@"Kiosk Battery Health"];

    [self pushState:@"sensor.kiosk_battery_cycles"
              state:[battery[@"cycles"] stringValue]
               unit:@""
        friendlyName:@"Kiosk Battery Cycles"];

    [self pushState:@"sensor.kiosk_wifi_rssi"
              state:[wifi[@"rssi"] stringValue]
               unit:@"dBm"
        friendlyName:@"Kiosk WiFi RSSI"];

    [self pushState:@"sensor.kiosk_wifi_ssid"
              state:wifi[@"ssid"]
               unit:@""
        friendlyName:@"Kiosk WiFi SSID"];

    [self pushState:@"sensor.kiosk_wifi_link_speed"
              state:[wifi[@"linkSpeed"] stringValue]
               unit:@"Mbps"
        friendlyName:@"Kiosk WiFi Link Speed"];

    long long storageFreeMB = [storage[@"free"] longLongValue] / (1024 * 1024);
    [self pushState:@"sensor.kiosk_storage_free"
              state:[NSString stringWithFormat:@"%lld", storageFreeMB]
               unit:@"MB"
        friendlyName:@"Kiosk Storage Free"];

    long long memoryFreeMB = [memory[@"free"] longLongValue] / (1024 * 1024);
    [self pushState:@"sensor.kiosk_memory_free"
              state:[NSString stringWithFormat:@"%lld", memoryFreeMB]
               unit:@"MB"
        friendlyName:@"Kiosk Memory Free"];

    [self pushState:@"sensor.kiosk_uptime"
              state:[telemetry[@"uptime"] stringValue]
               unit:@"s"
        friendlyName:@"Kiosk Uptime"];

    [self pushState:@"sensor.kiosk_network_rx_bytes"
              state:[network[@"rxBytes"] stringValue]
               unit:@"B"
        friendlyName:@"Kiosk Network RX"];

    [self pushState:@"sensor.kiosk_network_tx_bytes"
              state:[network[@"txBytes"] stringValue]
               unit:@"B"
        friendlyName:@"Kiosk Network TX"];
}

- (void)pushState:(NSString *)entityId
            state:(NSString *)state
             unit:(NSString *)unit
      friendlyName:(NSString *)friendlyName {
    NSString *path = [NSString stringWithFormat:@"/api/states/%@", entityId];
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:path]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.token]
        forHTTPHeaderField:@"Authorization"];

    NSDictionary *body = @{
        @"state": state ?: @"0",
        @"attributes": @{
            @"unit_of_measurement": unit ?: @"",
            @"friendly_name": friendlyName ?: @""
        }
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"TelemetryRelay: failed to push %@: %@", entityId, error.localizedDescription);
            }
        }];
    [task resume];
}

@end
