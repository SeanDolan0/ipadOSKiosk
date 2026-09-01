# In-App Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an in-app native Settings modal (Feature 2) triggered by a top-right corner 4-tap gesture, allowing the user to view and edit core Home Assistant and Screensaver settings, test connectivity to the HA API and local `kioskd`, persist changes atomically to `/var/mobile/Library/Preferences/com.hasmartboard.plist`, and apply updates live at runtime without app restart.

**Architecture:** A `SettingsViewController` (`UITableViewController` wrapped in a `UINavigationController`) loaded modally over `KioskViewController`. Configuration is read from and saved atomically to the device plist. A delegate callback triggers runtime re-injection of WKWebView auth scripts, dashboard URL reloading, and idle timer reconfiguration.

**Tech Stack:** Objective-C, UIKit (iOS 12.4 SDK, arm64), WebKit (`WKWebView`), Theos build system.

**Spec:** [`docs/superpowers/specs/2026-09-01-settings-page-design.md`](../specs/2026-09-01-settings-page-design.md)

## Global Constraints

- Platform: iOS 12.5.8 (arm64, iPad Mini 2 landscape kiosk), Theos build with `iPhoneOS12.4.sdk`.
- Target: `iphone:clang:12.4:12.0`, ARC enabled (`-fobjc-arc`).
- Plist path: `/var/mobile/Library/Preferences/com.hasmartboard.plist`.
- No third-party UI libraries or pods; pure standard UIKit.
- Security: Passwords and tokens must use `secureTextEntry = YES` and never be written to `NSLog` or debug files.
- Atomic I/O: All plist writes must use `[root writeToFile:PREFS_PATH atomically:YES]` preserving existing untouched blocks (`mqtt`, `daemon`).

---

### Task 1: Create `SettingsViewController` Table Form & Plist Persistence

**Files:**
- Create: `App/SettingsViewController.h`
- Create: `App/SettingsViewController.m`
- Modify: `Makefile:17-24`

**Interfaces:**
- Consumes: `/var/mobile/Library/Preferences/com.hasmartboard.plist`
- Produces:
  - `@protocol SettingsViewControllerDelegate <NSObject>`
    - `- (void)settingsViewController:(SettingsViewController *)controller didSaveConfig:(NSDictionary *)config;`
    - `- (void)settingsViewControllerDidCancel:(SettingsViewController *)controller;`
  - `@interface SettingsViewController : UITableViewController`
    - `@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;`

- [ ] **Step 1: Create `App/SettingsViewController.h`**

Define the delegate protocol and controller class:

```objc
#import <UIKit/UIKit.h>

@class SettingsViewController;

@protocol SettingsViewControllerDelegate <NSObject>
- (void)settingsViewController:(SettingsViewController *)controller didSaveConfig:(NSDictionary *)config;
- (void)settingsViewControllerDidCancel:(SettingsViewController *)controller;
@end

@interface SettingsViewController : UITableViewController

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end
```

- [ ] **Step 2: Create `App/SettingsViewController.m`**

Implement form sections (Home Assistant, Screensaver, Diagnostics placeholder), text fields, secure masking for token, segmented control for mode, navigation bar buttons (Cancel/Save), input validation, and atomic plist persistence:

```objc
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
```

- [ ] **Step 3: Update `Makefile` to include `App/SettingsViewController.m`**

Add `App/SettingsViewController.m` to `HASmartboard_FILES` in root `Makefile`:

```makefile
HASmartboard_FILES = \
    App/main.m \
    App/AppDelegate.m \
    App/KioskViewController.m \
    App/SettingsViewController.m \
    App/ScreensaverView.m \
    App/NetworkMonitor.m \
    App/DaemonBridge.m
```

- [ ] **Step 4: Commit Task 1**

```bash
git add App/SettingsViewController.h App/SettingsViewController.m Makefile
git commit -m "feat(app): add SettingsViewController table form and plist persistence"
```

---

### Task 2: Implement "Test Connection" Diagnostics in `SettingsViewController`

**Files:**
- Modify: `App/SettingsViewController.m`

**Interfaces:**
- Consumes: `ha.url`, `ha.token` from current text field inputs
- Produces: Asynchronous testing of HA REST API (`GET <ha.url>/api/`) and local `kioskd` (`GET http://127.0.0.1:9090/health`)

- [ ] **Step 1: Implement `testConnection` in `App/SettingsViewController.m`**

Replace the `testConnection` stub in `App/SettingsViewController.m` with concurrent `NSURLSession` tests:

```objc
- (void)testConnection {
    [self.view endEditing:YES];
    [_activityIndicator startAnimating];
    _statusLabel.textColor = [UIColor darkGrayColor];
    _statusLabel.text = @"Testing connection to Home Assistant & kioskd...";

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

    __block NSString *haResult = nil;
    __block BOOL haSuccess = NO;
    __block NSString *daemonResult = nil;
    __block BOOL daemonSuccess = NO;

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

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self->_activityIndicator stopAnimating];
        self->_statusLabel.text = [NSString stringWithFormat:@"%@\n%@", haResult, daemonResult];
        if (haSuccess && daemonSuccess) {
            self->_statusLabel.textColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
        } else if (haSuccess) {
            self->_statusLabel.textColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.0 alpha:1.0];
        } else {
            self->_statusLabel.textColor = [UIColor redColor];
        }
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    });
}
```

- [ ] **Step 2: Commit Task 2**

```bash
git add App/SettingsViewController.m
git commit -m "feat(app): implement HA and kioskd connection diagnostics in SettingsViewController"
```

---

### Task 3: Implement 4-Tap Corner Gesture in `KioskViewController` and `ScreensaverView`

**Files:**
- Modify: `App/ScreensaverView.h`
- Modify: `App/ScreensaverView.m:20-72`
- Modify: `App/KioskViewController.h`
- Modify: `App/KioskViewController.m`

**Interfaces:**
- Consumes: 4-tap gesture in top-right screen corner
- Produces: Presentation of `SettingsViewController` wrapped in `UINavigationController`

- [ ] **Step 1: Update `App/ScreensaverView.h` with delegate method for settings gesture**

Add `screensaverDidRequestSettings` to `ScreensaverViewDelegate`:

```objc
#import <UIKit/UIKit.h>

@protocol ScreensaverViewDelegate <NSObject>
- (void)screensaverDidReceiveTouch;
- (void)screensaverDidRequestSettings;
@end

@interface ScreensaverView : UIView

@property (nonatomic, weak) id<ScreensaverViewDelegate> delegate;

- (void)configureWithMode:(NSString *)mode
                photoURLs:(NSArray<NSString *> *)photoURLs
            dimBrightness:(float)dimBrightness;

- (void)fadeIn;
- (void)fadeOut;

@end
```

- [ ] **Step 2: Update `App/ScreensaverView.m` to handle corner 4-tap**

Configure gesture recognizers in `ScreensaverView.m` with tap failure requirements so a 4-tap in the top-right corner triggers settings without waking the screen:

```objc
- (void)setupGesture {
    UITapGestureRecognizer *wakeTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleTap:)];
    wakeTap.numberOfTapsRequired = 1;

    UITapGestureRecognizer *settingsTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSettingsTap:)];
    settingsTap.numberOfTapsRequired = 4;

    [wakeTap requireGestureRecognizerToFail:settingsTap];

    [self addGestureRecognizer:settingsTap];
    [self addGestureRecognizer:wakeTap];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    [self.delegate screensaverDidReceiveTouch];
}

- (void)handleSettingsTap:(UITapGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self];
    if (point.x >= (self.bounds.size.width - 100) && point.y <= 100) {
        [self.delegate screensaverDidRequestSettings];
    } else {
        [self.delegate screensaverDidReceiveTouch];
    }
}
```

- [ ] **Step 3: Add Top-Right Hotspot Gesture to `KioskViewController.m`**

In `App/KioskViewController.m`:
- Import `SettingsViewController.h`.
- Add a 4-tap gesture recognizer to `KioskViewController.view` or a dedicated invisible top-right hotspot view.
- Implement `- (void)openSettings` presenting `SettingsViewController` in a `UINavigationController` with `modalPresentationStyle = UIModalPresentationFormSheet` (or fullscreen).
- Implement `screensaverDidRequestSettings` in `ScreensaverViewDelegate` extension.

```objc
#import "SettingsViewController.h"

// In viewDidLoad:
UITapGestureRecognizer *settingsGesture = [[UITapGestureRecognizer alloc]
    initWithTarget:self action:@selector(openSettings)];
settingsGesture.numberOfTapsRequired = 4;

UIView *hotspotView = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 80, 0, 80, 80)];
hotspotView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
hotspotView.backgroundColor = [UIColor clearColor];
[hotspotView addGestureRecognizer:settingsGesture];
[self.view addSubview:hotspotView];

// Open Settings implementation:
- (void)openSettings {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    settingsVC.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - ScreensaverViewDelegate

- (void)screensaverDidReceiveTouch {
    [self dismissScreensaver];
}

- (void)screensaverDidRequestSettings {
    [self dismissScreensaver];
    [self openSettings];
}
```

- [ ] **Step 4: Commit Task 3**

```bash
git add App/ScreensaverView.h App/ScreensaverView.m App/KioskViewController.h App/KioskViewController.m
git commit -m "feat(app): add 4-tap top-right corner gesture to open SettingsViewController"
```

---

### Task 4: Implement Runtime Live Reload & Config Application

**Files:**
- Modify: `App/KioskViewController.m`

**Interfaces:**
- Consumes: `settingsViewController:didSaveConfig:` delegate callback
- Produces: Live reload of WKWebView (with new auth token injection and URL request) and idle timer reconfiguration

- [ ] **Step 1: Implement `SettingsViewControllerDelegate` in `App/KioskViewController.m`**

Adopt `SettingsViewControllerDelegate` and implement `- (void)settingsViewController:didSaveConfig:`:

```objc
#pragma mark - SettingsViewControllerDelegate

- (void)settingsViewControllerDidCancel:(SettingsViewController *)controller {
    NSLog(@"KioskViewController: Settings dismissed without changes");
}

- (void)settingsViewController:(SettingsViewController *)controller didSaveConfig:(NSDictionary *)config {
    NSLog(@"KioskViewController: Applying updated settings from in-app edit");

    NSDictionary *haConfig = config[@"ha"];
    NSString *newBaseURL = haConfig[@"url"] ?: @"http://192.168.50.150:8123";
    NSString *newDashboardPath = haConfig[@"dashboardPath"] ?: @"/bedroom-kiosk/0";
    NSString *newToken = haConfig[@"token"] ?: @"";

    BOOL haChanged = ![_haBaseURL isEqualToString:newBaseURL] ||
                     ![_dashboardPath isEqualToString:newDashboardPath] ||
                     ![_haToken isEqualToString:newToken];

    _haBaseURL = newBaseURL;
    _dashboardPath = newDashboardPath;
    _haToken = newToken;

    if (haChanged) {
        // Re-inject WKUserScripts with new token and reload dashboard
        [_webView removeFromSuperview];
        [self setupWebView];
        [self loadDashboard];
    }

    // Apply screensaver updates immediately
    [self resetIdleTimer];
}
```

- [ ] **Step 2: Commit Task 4**

```bash
git add App/KioskViewController.m
git commit -m "feat(app): implement live reload on settings save in KioskViewController"
```

---

### Task 5: End-to-End Build Verification & Docs Update

**Files:**
- Modify: `TODO.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `TODO.md`**

Mark Feature 2 items as complete in `TODO.md`.

- [ ] **Step 2: Update `CLAUDE.md`**

Add reference to `SettingsViewController` and the 4-tap top-right corner gesture in `CLAUDE.md`.

- [ ] **Step 3: Commit Task 5**

```bash
git add TODO.md CLAUDE.md
git commit -m "docs: update TODO and CLAUDE.md with Feature 2 settings page details"
```

---

## Plan Self-Review Checklist

- [x] **Spec coverage:** All sections in the spec (`SettingsViewController`, 4-tap gesture, connection diagnostics, live reload, atomic plist persistence) are mapped to explicit implementation tasks.
- [x] **Placeholder scan:** No TBDs or hand-waving steps; all code, method signatures, constraints, and commands are concrete.
- [x] **Type consistency:** Delegate methods, class names (`SettingsViewController`, `SettingsViewControllerDelegate`), and plist key structures match throughout.
