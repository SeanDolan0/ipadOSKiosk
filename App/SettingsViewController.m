#import "SettingsViewController.h"
#import "MQTTClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

@interface SettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *haURLField;
@property (nonatomic, strong) UITextField *haPathField;
@property (nonatomic, strong) UITextField *haTokenField;

@property (nonatomic, strong) UISwitch *mqttEnabledSwitch;
@property (nonatomic, strong) UITextField *mqttHostField;
@property (nonatomic, strong) UITextField *mqttPortField;
@property (nonatomic, strong) UITextField *mqttUserField;
@property (nonatomic, strong) UITextField *mqttPassField;
@property (nonatomic, strong) UITextField *mqttPrefixField;
@property (nonatomic, strong) UITextField *mqttClientIdField;
@property (nonatomic, strong) UITextField *mqttIntervalField;
@property (nonatomic, strong) UIActivityIndicatorView *mqttActivityIndicator;
@property (nonatomic, strong) UILabel *mqttStatusLabel;

@property (nonatomic, strong) UITextField *idleTimeoutField;
@property (nonatomic, strong) UISegmentedControl *screensaverModeControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) NSMutableDictionary *loadedPrefs;
@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Kiosk Settings";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self
                             action:@selector(handleCancel)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(handleSave)];

    [self loadExistingConfig];
    [self setupControls];
}

- (void)loadExistingConfig {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    if (prefs) {
        _loadedPrefs = [prefs mutableCopy];
    } else {
        _loadedPrefs = [NSMutableDictionary dictionary];
    }
}

- (void)setupControls {
    NSDictionary *ha = _loadedPrefs[@"ha"] ?: @{};
    NSDictionary *mqtt = _loadedPrefs[@"mqtt"] ?: @{};
    NSDictionary *screensaver = _loadedPrefs[@"screensaver"] ?: @{};

    // Home Assistant
    _haURLField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _haURLField.placeholder = @"http://192.168.50.150:8123";
    _haURLField.text = ha[@"url"] ?: @"";
    _haURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haURLField.keyboardType = UIKeyboardTypeURL;
    _haURLField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haURLField.delegate = self;

    _haPathField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _haPathField.placeholder = @"/bedroom-kiosk/0";
    _haPathField.text = ha[@"dashboardPath"] ?: @"";
    _haPathField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haPathField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haPathField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haPathField.delegate = self;

    _haTokenField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _haTokenField.placeholder = @"Long-lived access token";
    _haTokenField.text = ha[@"token"] ?: @"";
    _haTokenField.secureTextEntry = YES;
    _haTokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haTokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haTokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haTokenField.delegate = self;

    // MQTT Telemetry
    _mqttEnabledSwitch = [[UISwitch alloc] init];
    if (mqtt[@"enabled"] != nil) {
        _mqttEnabledSwitch.on = [mqtt[@"enabled"] boolValue];
    } else {
        _mqttEnabledSwitch.on = YES;
    }

    _mqttHostField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttHostField.placeholder = @"192.168.50.150";
    _mqttHostField.text = mqtt[@"host"] ?: @"";
    _mqttHostField.autocorrectionType = UITextAutocorrectionTypeNo;
    _mqttHostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mqttHostField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mqttHostField.delegate = self;

    _mqttPortField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttPortField.placeholder = @"1883";
    NSNumber *portNum = mqtt[@"port"] ?: @(1883);
    _mqttPortField.text = [portNum stringValue];
    _mqttPortField.keyboardType = UIKeyboardTypeNumberPad;
    _mqttPortField.delegate = self;

    _mqttUserField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttUserField.placeholder = @"kiosk";
    _mqttUserField.text = mqtt[@"user"] ?: @"";
    _mqttUserField.autocorrectionType = UITextAutocorrectionTypeNo;
    _mqttUserField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mqttUserField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mqttUserField.delegate = self;

    _mqttPassField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttPassField.placeholder = @"Password";
    _mqttPassField.text = mqtt[@"pass"] ?: @"";
    _mqttPassField.secureTextEntry = YES;
    _mqttPassField.autocorrectionType = UITextAutocorrectionTypeNo;
    _mqttPassField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mqttPassField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mqttPassField.delegate = self;

    _mqttPrefixField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttPrefixField.placeholder = @"kiosk";
    _mqttPrefixField.text = mqtt[@"prefix"] ?: @"";
    _mqttPrefixField.autocorrectionType = UITextAutocorrectionTypeNo;
    _mqttPrefixField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mqttPrefixField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mqttPrefixField.delegate = self;

    _mqttClientIdField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttClientIdField.placeholder = @"hasmartboard-ipad";
    _mqttClientIdField.text = mqtt[@"clientId"] ?: @"";
    _mqttClientIdField.autocorrectionType = UITextAutocorrectionTypeNo;
    _mqttClientIdField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mqttClientIdField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _mqttClientIdField.delegate = self;

    _mqttIntervalField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _mqttIntervalField.placeholder = @"30";
    NSNumber *intervalNum = mqtt[@"interval"] ?: @(30);
    _mqttIntervalField.text = [intervalNum stringValue];
    _mqttIntervalField.keyboardType = UIKeyboardTypeNumberPad;
    _mqttIntervalField.delegate = self;

    _mqttStatusLabel = [[UILabel alloc] init];
    _mqttStatusLabel.numberOfLines = 0;
    _mqttStatusLabel.font = [UIFont systemFontOfSize:13];
    _mqttStatusLabel.textColor = [UIColor darkGrayColor];
    _mqttStatusLabel.textAlignment = NSTextAlignmentCenter;
    _mqttStatusLabel.text = @"Ready to test MQTT";

    _mqttActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _mqttActivityIndicator.hidesWhenStopped = YES;

    // Screensaver
    _idleTimeoutField = [[UITextField alloc] initWithFrame:CGRectMake(130, 7, 230, 30)];
    _idleTimeoutField.placeholder = @"300";
    NSNumber *timeoutNum = screensaver[@"idleTimeout"] ?: @(300);
    _idleTimeoutField.text = [timeoutNum stringValue];
    _idleTimeoutField.keyboardType = UIKeyboardTypeNumberPad;
    _idleTimeoutField.delegate = self;

    _screensaverModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Clock", @"Photo"]];
    _screensaverModeControl.frame = CGRectMake(160, 7, 180, 30);
    NSString *mode = screensaver[@"mode"] ?: @"clock";
    _screensaverModeControl.selectedSegmentIndex = [mode isEqualToString:@"photo"] ? 1 : 0;

    // Diagnostics
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.numberOfLines = 0;
    _statusLabel.font = [UIFont systemFontOfSize:13];
    _statusLabel.textColor = [UIColor darkGrayColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Ready to test";

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _activityIndicator.hidesWhenStopped = YES;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;  // HA: URL, Path, Token
    if (section == 1) return 10; // MQTT: Enabled, Host, Port, User, Pass, Prefix, ClientId, Interval, Test Button, Status
    if (section == 2) return 2;  // Screensaver: Timeout, Mode
    if (section == 3) return 2;  // Diagnostics: Test button, Status
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Home Assistant";
    if (section == 1) return @"MQTT Telemetry";
    if (section == 2) return @"Screensaver";
    if (section == 3) return @"Diagnostics";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Token is injected into the webview for dashboard authorization.";
    if (section == 1) return @"Configures the MQTT background telemetry client in kioskd.";
    if (section == 2) return @"Idle timeout in seconds before screensaver activates.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"URL";
            [cell.contentView addSubview:_haURLField];
            _haURLField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_haURLField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_haURLField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haURLField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Path";
            [cell.contentView addSubview:_haPathField];
            _haPathField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_haPathField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_haPathField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haPathField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Token";
            [cell.contentView addSubview:_haTokenField];
            _haTokenField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_haTokenField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_haTokenField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haTokenField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable MQTT";
            cell.accessoryView = _mqttEnabledSwitch;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Host";
            [cell.contentView addSubview:_mqttHostField];
            _mqttHostField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttHostField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttHostField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttHostField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Port";
            [cell.contentView addSubview:_mqttPortField];
            _mqttPortField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttPortField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttPortField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttPortField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Username";
            [cell.contentView addSubview:_mqttUserField];
            _mqttUserField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttUserField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttUserField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttUserField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Password";
            [cell.contentView addSubview:_mqttPassField];
            _mqttPassField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttPassField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttPassField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttPassField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"Prefix";
            [cell.contentView addSubview:_mqttPrefixField];
            _mqttPrefixField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttPrefixField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttPrefixField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttPrefixField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"Client ID";
            [cell.contentView addSubview:_mqttClientIdField];
            _mqttClientIdField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttClientIdField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttClientIdField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttClientIdField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 7) {
            cell.textLabel.text = @"Interval (sec)";
            [cell.contentView addSubview:_mqttIntervalField];
            _mqttIntervalField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttIntervalField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_mqttIntervalField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttIntervalField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 8) {
            cell.textLabel.text = @"Test MQTT Connection";
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryView = _mqttActivityIndicator;
        } else if (indexPath.row == 9) {
            [cell.contentView addSubview:_mqttStatusLabel];
            _mqttStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_mqttStatusLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
                [_mqttStatusLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_mqttStatusLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
                [_mqttStatusLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
            ]];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Timeout (sec)";
            [cell.contentView addSubview:_idleTimeoutField];
            _idleTimeoutField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_idleTimeoutField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:130],
                [_idleTimeoutField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_idleTimeoutField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Mode";
            [cell.contentView addSubview:_screensaverModeControl];
            _screensaverModeControl.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_screensaverModeControl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_screensaverModeControl.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Test Connection";
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryView = _activityIndicator;
        } else if (indexPath.row == 1) {
            [cell.contentView addSubview:_statusLabel];
            _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_statusLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
                [_statusLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_statusLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
                [_statusLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
            ]];
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 8) {
        [self testMQTTConnection];
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        [self testConnection];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Actions

- (void)handleCancel {
    [self.view endEditing:YES];
    [self.delegate settingsViewControllerDidCancel:self];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleSave {
    [self.view endEditing:YES];

    NSString *urlString = [_haURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (urlString.length == 0 || (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"])) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid URL"
                                                                       message:@"Home Assistant URL must begin with http:// or https://"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *pathString = [_haPathField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![pathString hasPrefix:@"/"]) {
        pathString = [NSString stringWithFormat:@"/%@", pathString];
    }

    NSString *tokenString = [_haTokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSInteger timeout = [_idleTimeoutField.text integerValue];
    if (timeout <= 0) timeout = 300;

    NSString *modeString = (_screensaverModeControl.selectedSegmentIndex == 1) ? @"photo" : @"clock";

    // Build mutable root config preserving existing keys
    NSMutableDictionary *root = [_loadedPrefs mutableCopy] ?: [NSMutableDictionary dictionary];

    // Home Assistant
    NSMutableDictionary *ha = [root[@"ha"] mutableCopy] ?: [NSMutableDictionary dictionary];
    ha[@"url"] = urlString;
    ha[@"dashboardPath"] = pathString;
    ha[@"token"] = tokenString ?: @"";
    root[@"ha"] = ha;

    // MQTT
    NSMutableDictionary *mqtt = [root[@"mqtt"] mutableCopy] ?: [NSMutableDictionary dictionary];
    mqtt[@"enabled"] = @(_mqttEnabledSwitch.isOn);
    mqtt[@"host"] = [_mqttHostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSInteger port = [_mqttPortField.text integerValue];
    mqtt[@"port"] = @(port > 0 ? port : 1883);
    mqtt[@"user"] = [_mqttUserField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    mqtt[@"pass"] = _mqttPassField.text ?: @"";
    NSString *prefix = [_mqttPrefixField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    mqtt[@"prefix"] = prefix.length > 0 ? prefix : @"kiosk";
    NSString *clientId = [_mqttClientIdField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    mqtt[@"clientId"] = clientId.length > 0 ? clientId : @"hasmartboard-ipad";
    NSInteger interval = [_mqttIntervalField.text integerValue];
    mqtt[@"interval"] = @(interval > 0 ? interval : 30);
    root[@"mqtt"] = mqtt;

    // Screensaver
    NSMutableDictionary *screensaver = [root[@"screensaver"] mutableCopy] ?: [NSMutableDictionary dictionary];
    screensaver[@"idleTimeout"] = @(timeout);
    screensaver[@"mode"] = modeString;
    root[@"screensaver"] = screensaver;

    BOOL success = [root writeToFile:PREFS_PATH atomically:YES];
    if (!success) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Error"
                                                                       message:@"Failed to write settings to plist file."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Notify kioskd to reload config
    NSURL *cmdURL = [NSURL URLWithString:@"http://127.0.0.1:9090/command"];
    NSMutableURLRequest *cmdReq = [NSMutableURLRequest requestWithURL:cmdURL];
    cmdReq.HTTPMethod = @"POST";
    [cmdReq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    cmdReq.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"action": @"restartDaemon"} options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:cmdReq] resume];

    [self.delegate settingsViewController:self didSaveConfig:root];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)testMQTTConnection {
    if (self.mqttActivityIndicator.isAnimating) return;

    [self.view endEditing:YES];
    [_mqttActivityIndicator startAnimating];
    _mqttStatusLabel.textColor = [UIColor darkGrayColor];
    _mqttStatusLabel.text = @"Connecting to MQTT broker...";

    NSString *host = [_mqttHostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger port = [_mqttPortField.text integerValue];
    if (port <= 0) port = 1883;

    NSString *user = [_mqttUserField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pass = _mqttPassField.text ?: @"";
    NSString *clientId = [_mqttClientIdField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clientId.length == 0) clientId = @"hasmartboard-ipad";
    NSString *testClientId = [NSString stringWithFormat:@"%@-test", clientId];

    if (host.length == 0) {
        [_mqttActivityIndicator stopAnimating];
        _mqttStatusLabel.textColor = [UIColor redColor];
        _mqttStatusLabel.text = @"❌ Host is empty";
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MQTTClient client;
        memset(&client, 0, sizeof(client));
        client.sockfd = -1;
        snprintf(client.host, sizeof(client.host), "%s", host.UTF8String);
        client.port = (int)port;
        snprintf(client.username, sizeof(client.username), "%s", user.UTF8String);
        snprintf(client.password, sizeof(client.password), "%s", pass.UTF8String);
        snprintf(client.clientId, sizeof(client.clientId), "%s", testClientId.UTF8String);
        client.keepalive = 10;

        int rc = mqttConnect(&client);
        NSString *resultText = nil;
        BOOL isOk = NO;

        if (rc == 0) {
            isOk = YES;
            resultText = [NSString stringWithFormat:@"✅ Connected & Authorized (%@:%ld)", host, (long)port];
            mqttClose(&client);
        } else if (rc == -1 || rc == -2) {
            resultText = [NSString stringWithFormat:@"❌ Cannot reach %@:%ld (Network/Host Unreachable)", host, (long)port];
        } else if (rc == -5) {
            resultText = @"❌ Broker did not reply with CONNACK";
        } else if (rc == -6) {
            resultText = @"❌ Authentication failed (Check user/password)";
        } else {
            resultText = [NSString stringWithFormat:@"❌ Connection failed (code %d)", rc];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf.mqttActivityIndicator stopAnimating];
            strongSelf.mqttStatusLabel.text = resultText;
            strongSelf.mqttStatusLabel.textColor = isOk ? [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0] : [UIColor redColor];
            [strongSelf.tableView beginUpdates];
            [strongSelf.tableView endUpdates];
        });
    });
}

- (void)testConnection {
    if (self.activityIndicator.isAnimating) return;

    [self.view endEditing:YES];
    [_activityIndicator startAnimating];
    _statusLabel.textColor = [UIColor darkGrayColor];
    _statusLabel.text = @"Testing connection...";

    NSString *haURLString = [_haURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *token = [_haTokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (haURLString.length == 0) {
        [_activityIndicator stopAnimating];
        _statusLabel.textColor = [UIColor redColor];
        _statusLabel.text = @"❌ Home Assistant URL is empty";
        return;
    }

    NSString *apiURLString = [NSString stringWithFormat:@"%@/api/", [haURLString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
    NSURL *haURL = [NSURL URLWithString:apiURLString];
    if (!haURL) {
        [_activityIndicator stopAnimating];
        _statusLabel.textColor = [UIColor redColor];
        _statusLabel.text = @"❌ Invalid Home Assistant URL format";
        return;
    }

    NSMutableURLRequest *haReq = [NSMutableURLRequest requestWithURL:haURL
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                     timeoutInterval:5.0];
    if (token.length > 0) {
        [haReq setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    NSURL *daemonURL = [NSURL URLWithString:@"http://127.0.0.1:9090/health"];
    NSURLRequest *daemonReq = [NSURLRequest requestWithURL:daemonURL
                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                           timeoutInterval:3.0];

    NSString *mqttHost = [_mqttHostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger mqttPort = [_mqttPortField.text integerValue];
    if (mqttPort <= 0) mqttPort = 1883;
    NSString *mqttUser = [_mqttUserField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *mqttPass = _mqttPassField.text ?: @"";
    NSString *mqttClientId = [_mqttClientIdField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (mqttClientId.length == 0) mqttClientId = @"hasmartboard-ipad";
    NSString *testClientId = [NSString stringWithFormat:@"%@-test", mqttClientId];
    BOOL mqttEnabled = _mqttEnabledSwitch.isOn;

    __block NSString *haResult = nil;
    __block BOOL haSuccess = NO;
    __block NSString *daemonResult = nil;
    __block BOOL daemonSuccess = NO;
    __block NSString *mqttResult = nil;
    __block BOOL mqttSuccess = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_group_t group = dispatch_group_create();

    // 1. HA Test
    dispatch_group_enter(group);
    NSURLSessionDataTask *haTask = [[NSURLSession sharedSession]
        dataTaskWithRequest:haReq
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (error) {
                haResult = [NSString stringWithFormat:@"❌ HA: %@", error.localizedDescription];
            } else if (httpResp.statusCode == 200) {
                haSuccess = YES;
                haResult = @"✅ HA: Connected (200 OK)";
            } else if (httpResp.statusCode == 401) {
                haResult = @"❌ HA: 401 Unauthorized (Check Token)";
            } else {
                haResult = [NSString stringWithFormat:@"⚠️ HA: HTTP %ld", (long)httpResp.statusCode];
            }
            dispatch_group_leave(group);
        }];
    [haTask resume];

    // 2. kioskd Test
    dispatch_group_enter(group);
    NSURLSessionDataTask *daemonTask = [[NSURLSession sharedSession]
        dataTaskWithRequest:daemonReq
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (!error && httpResp.statusCode == 200) {
                daemonSuccess = YES;
                daemonResult = @"✅ kioskd: Running";
            } else {
                daemonResult = @"⚠️ kioskd: Not responding";
            }
            dispatch_group_leave(group);
        }];
    [daemonTask resume];

    // 3. MQTT Test (Full Protocol Handshake)
    if (mqttEnabled && mqttHost.length > 0) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            MQTTClient client;
            memset(&client, 0, sizeof(client));
            client.sockfd = -1;
            snprintf(client.host, sizeof(client.host), "%s", mqttHost.UTF8String);
            client.port = (int)mqttPort;
            snprintf(client.username, sizeof(client.username), "%s", mqttUser.UTF8String);
            snprintf(client.password, sizeof(client.password), "%s", mqttPass.UTF8String);
            snprintf(client.clientId, sizeof(client.clientId), "%s", testClientId.UTF8String);
            client.keepalive = 10;

            int rc = mqttConnect(&client);
            if (rc == 0) {
                mqttSuccess = YES;
                mqttResult = [NSString stringWithFormat:@"✅ MQTT: Connected (%@:%ld)", mqttHost, (long)mqttPort];
                mqttClose(&client);
            } else if (rc == -6) {
                mqttResult = @"❌ MQTT: Auth Failed (Check user/pass)";
            } else {
                mqttResult = [NSString stringWithFormat:@"❌ MQTT: Connect failed (code %d)", rc];
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.activityIndicator stopAnimating];

        NSMutableArray *results = [NSMutableArray array];
        if (haResult) [results addObject:haResult];
        if (mqttResult) [results addObject:mqttResult];
        if (daemonResult) [results addObject:daemonResult];

        strongSelf.statusLabel.text = [results componentsJoinedByString:@"\n"];

        BOOL allOk = haSuccess && daemonSuccess && (!mqttEnabled || mqttHost.length == 0 || mqttSuccess);
        if (allOk) {
            strongSelf.statusLabel.textColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
        } else if (haSuccess || mqttSuccess || daemonSuccess) {
            strongSelf.statusLabel.textColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.0 alpha:1.0];
        } else {
            strongSelf.statusLabel.textColor = [UIColor redColor];
        }
        [strongSelf.tableView beginUpdates];
        [strongSelf.tableView endUpdates];
    });
}

@end

