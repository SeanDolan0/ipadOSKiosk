#import "SettingsViewController.h"

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

@interface SettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *haURLField;
@property (nonatomic, strong) UITextField *haPathField;
@property (nonatomic, strong) UITextField *haTokenField;
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
    NSDictionary *screensaver = _loadedPrefs[@"screensaver"] ?: @{};

    _haURLField = [[UITextField alloc] initWithFrame:CGRectMake(120, 7, 240, 30)];
    _haURLField.placeholder = @"http://192.168.50.150:8123";
    _haURLField.text = ha[@"url"] ?: @"";
    _haURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haURLField.keyboardType = UIKeyboardTypeURL;
    _haURLField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haURLField.delegate = self;

    _haPathField = [[UITextField alloc] initWithFrame:CGRectMake(120, 7, 240, 30)];
    _haPathField.placeholder = @"/bedroom-kiosk/0";
    _haPathField.text = ha[@"dashboardPath"] ?: @"";
    _haPathField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haPathField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haPathField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haPathField.delegate = self;

    _haTokenField = [[UITextField alloc] initWithFrame:CGRectMake(120, 7, 240, 30)];
    _haTokenField.placeholder = @"Long-lived access token";
    _haTokenField.text = ha[@"token"] ?: @"";
    _haTokenField.secureTextEntry = YES;
    _haTokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    _haTokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _haTokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _haTokenField.delegate = self;

    _idleTimeoutField = [[UITextField alloc] initWithFrame:CGRectMake(160, 7, 200, 30)];
    _idleTimeoutField.placeholder = @"300";
    NSNumber *timeoutNum = screensaver[@"idleTimeout"] ?: @(300);
    _idleTimeoutField.text = [timeoutNum stringValue];
    _idleTimeoutField.keyboardType = UIKeyboardTypeNumberPad;
    _idleTimeoutField.delegate = self;

    _screensaverModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Clock", @"Photo"]];
    _screensaverModeControl.frame = CGRectMake(160, 7, 180, 30);
    NSString *mode = screensaver[@"mode"] ?: @"clock";
    _screensaverModeControl.selectedSegmentIndex = [mode isEqualToString:@"photo"] ? 1 : 0;

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
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // HA: URL, Path, Token
    if (section == 1) return 2; // Screensaver: Timeout, Mode
    if (section == 2) return 2; // Diagnostics: Test button, Status
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Home Assistant";
    if (section == 1) return @"Screensaver";
    if (section == 2) return @"Diagnostics";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Token is injected into the webview for dashboard authorization.";
    if (section == 1) return @"Idle timeout in seconds before screensaver activates.";
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
                [_haURLField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:20],
                [_haURLField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haURLField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Path";
            [cell.contentView addSubview:_haPathField];
            _haPathField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_haPathField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:20],
                [_haPathField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haPathField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Token";
            [cell.contentView addSubview:_haTokenField];
            _haTokenField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_haTokenField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:20],
                [_haTokenField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [_haTokenField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Timeout (sec)";
            [cell.contentView addSubview:_idleTimeoutField];
            _idleTimeoutField.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [_idleTimeoutField.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:20],
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
    } else if (indexPath.section == 2) {
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
    if (indexPath.section == 2 && indexPath.row == 0) {
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

    NSMutableDictionary *ha = [root[@"ha"] mutableCopy] ?: [NSMutableDictionary dictionary];
    ha[@"url"] = urlString;
    ha[@"dashboardPath"] = pathString;
    ha[@"token"] = tokenString ?: @"";
    root[@"ha"] = ha;

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

    [self.delegate settingsViewController:self didSaveConfig:root];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)testConnection {
    // Implemented in Task 2
}

@end
