#import "KioskViewController.h"
#import "ScreensaverView.h"
#import "NetworkMonitor.h"
#import "DaemonBridge.h"
#import "SettingsViewController.h"

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

@implementation KioskViewController {
    WKWebView *_webView;
    ScreensaverView *_screensaver;
    NetworkMonitor *_networkMonitor;
    DaemonBridge *_daemonBridge;
    NSTimer *_wakeTimer;
    NSTimer *_idleTimer;
    BOOL _screensaverActive;
    BOOL _isConnected;
    NSString *_haBaseURL;
    NSString *_haToken;
    NSString *_dashboardPath;
    UIView *_hotspotView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self loadHAConfig];

    _networkMonitor = [[NetworkMonitor alloc] init];
    _daemonBridge = [[DaemonBridge alloc] init];

    [self setupWebView];

    UITapGestureRecognizer *settingsGesture = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(openSettings)];
    settingsGesture.numberOfTapsRequired = 3;

    UITapGestureRecognizer *settingsGesture4 = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(openSettings)];
    settingsGesture4.numberOfTapsRequired = 4;

    _hotspotView = [[UIView alloc] init];
    _hotspotView.backgroundColor = [UIColor clearColor];
    _hotspotView.translatesAutoresizingMaskIntoConstraints = NO;
    [_hotspotView addGestureRecognizer:settingsGesture];
    [_hotspotView addGestureRecognizer:settingsGesture4];
    [self.view addSubview:_hotspotView];

    [NSLayoutConstraint activateConstraints:@[
        [_hotspotView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_hotspotView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_hotspotView.widthAnchor constraintEqualToConstant:100],
        [_hotspotView.heightAnchor constraintEqualToConstant:100]
    ]];

    _screensaver = [[ScreensaverView alloc] initWithFrame:self.view.bounds];
    _screensaver.delegate = self;
    _screensaver.hidden = YES;
    [self.view addSubview:_screensaver];

    __weak typeof(self) weakSelf = self;
    _networkMonitor.onStateChange = ^(BOOL connected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleNetworkChange:connected];
        });
    };
    [_networkMonitor start];

    _wakeTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                  target:self
                                                selector:@selector(checkWake)
                                                userInfo:nil
                                                 repeats:YES];

    [self resetIdleTimer];
    [self loadDashboard];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _webView.frame = self.view.bounds;
    _screensaver.frame = self.view.bounds;
    [self.view bringSubviewToFront:_hotspotView];
    [self.view bringSubviewToFront:_screensaver];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> transitionContext) {
        self->_webView.frame = (CGRect){CGPointZero, size};
        self->_screensaver.frame = (CGRect){CGPointZero, size};
        [self.view layoutIfNeeded];
    } completion:nil];
}

#pragma mark - HA Configuration

- (void)loadHAConfig {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSDictionary *haConfig = prefs[@"ha"];
    
    _haBaseURL = haConfig[@"url"] ?: @"http://192.168.50.150:8123";
    _haToken = haConfig[@"token"] ?: @"";
    _dashboardPath = haConfig[@"dashboardPath"] ?: @"/bedroom-kiosk/0";
    
    NSLog(@"KioskViewController: Loaded HA config - URL: %@, Dashboard: %@", _haBaseURL, _dashboardPath);
}

#pragma mark - WKWebView Setup

- (void)setupWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"kiosk"];

NSString *escapedToken = [_haToken stringByReplacingOccurrencesOfString:@"\\"
                                                                withString:@"\\\\"];
escapedToken = [escapedToken stringByReplacingOccurrencesOfString:@"'"
                                                           withString:@"\\'"];
NSString *authJS = [NSString stringWithFormat:
    @"window._kioskToken = '%@';", escapedToken];
    WKUserScript *authScript = [[WKUserScript alloc]
        initWithSource:authJS
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
       forMainFrameOnly:YES];
    [ucc addUserScript:authScript];

    config.userContentController = ucc;

    _webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    _webView.navigationDelegate = self;
    _webView.allowsBackForwardNavigationGestures = NO;
    _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;

    // Lock the page in place (the "kiosk" feel). WKWebView's scroll view has
    // bounce enabled by default, which lets the page rubber-band (pull down and
    // spring back) — that native pan gesture cancels the DOM touch sequence, so
    // an injected swipe handler never sees a completed swipe. Disabling bounce
    // both locks the layout like other kiosks AND lets horizontal swipes reach
    // the page. The dashboard itself fits on screen (no real overflow to scroll).
    _webView.scrollView.bounces = NO;
    _webView.scrollView.alwaysBounceVertical = NO;
    _webView.scrollView.alwaysBounceHorizontal = NO;
    _webView.scrollView.showsVerticalScrollIndicator = NO;
    _webView.scrollView.showsHorizontalScrollIndicator = NO;

    NSString *interceptJS = [NSString stringWithFormat:
        @"(function() {"
        "  var origFetch = window.fetch;"
        "  window.fetch = function(url, opts) {"
        "    opts = opts || {};"
        "    opts.headers = opts.headers || {};"
        "    opts.headers['Authorization'] = 'Bearer %@';"
        "    return origFetch(url, opts);"
        "};"
        "  var origXHR = XMLHttpRequest.prototype.open;"
        "  XMLHttpRequest.prototype.open = function(method, url) {"
        "    this._url = url;"
        "    return origXHR.apply(this, arguments);"
        "};"
        "  XMLHttpRequest.prototype.send = function() {"
        "    this.setRequestHeader('Authorization', 'Bearer %@');"
        "    return XMLHttpRequest.prototype.send.apply(this, arguments);"
        "};"
        "})();", escapedToken, escapedToken];
    interceptJS = [interceptJS stringByReplacingOccurrencesOfString:@"******"
                                                           withString:[NSString stringWithFormat:@"Bearer %@", escapedToken]];
    WKUserScript *interceptScript = [[WKUserScript alloc]
        initWithSource:interceptJS
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
       forMainFrameOnly:YES];
    [ucc addUserScript:interceptScript];

    // iOS-12-safe horizontal swipe -> view navigation. Loads the bundled
    // Resources/SwipeNav.js (ES5) and injects it at document start, same as the
    // auth/intercept scripts. See SwipeNav.js for why the card can't be used.
    NSString *swipeNavPath =
        [[NSBundle mainBundle] pathForResource:@"SwipeNav" ofType:@"js"];
    if (swipeNavPath) {
        NSError *jsError = nil;
        NSString *swipeNavJS =
            [NSString stringWithContentsOfFile:swipeNavPath
                                      encoding:NSUTF8StringEncoding
                                         error:&jsError];
        if (swipeNavJS) {
            WKUserScript *swipeNavScript = [[WKUserScript alloc]
                initWithSource:swipeNavJS
                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
               forMainFrameOnly:YES];
            [ucc addUserScript:swipeNavScript];
            [self logDebug:[NSString stringWithFormat:
                @"SwipedNav.js injection registered (%lu bytes)",
                (unsigned long)swipeNavJS.length]];
        } else {
            [self logDebug:[NSString stringWithFormat:
                @"ERROR failed to read SwipeNav.js: %@",
                jsError.localizedDescription]];
        }
    } else {
        [self logDebug:@"ERROR SwipeNav.js not found in bundle"];
    }

    [self.view insertSubview:_webView atIndex:0];
}

#pragma mark - Dashboard Loading

- (void)loadDashboard {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", _haBaseURL, _dashboardPath];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [_webView loadRequest:request];
}

- (void)reloadDashboard {
    [_webView reload];
}

#pragma mark - Network State

- (void)handleNetworkChange:(BOOL)connected {
    _isConnected = connected;
    if (connected) {
        [self reloadDashboard];
    }
}

#pragma mark - Wake Polling

- (void)checkWake {
    [_daemonBridge checkWakeWithCompletion:^(BOOL shouldWake) {
        if (shouldWake && self->_screensaverActive) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissScreensaver];
            });
        }
    }];
}

#pragma mark - Screensaver

- (void)resetIdleTimer {
    [_idleTimer invalidate];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.hasmartboard.plist"];
    NSTimeInterval timeout = 300;
    NSNumber *customTimeout = prefs[@"screensaver"][@"idleTimeout"];
    if (customTimeout) timeout = [customTimeout doubleValue];

    _idleTimer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                                 target:self
                                               selector:@selector(showScreensaver)
                                               userInfo:nil
                                                repeats:NO];
}

- (void)showScreensaver {
    if (_screensaverActive) return;
    _screensaverActive = YES;

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.hasmartboard.plist"];
    NSString *mode = prefs[@"screensaver"][@"mode"] ?: @"clock";
    NSArray *photoURLs = prefs[@"screensaver"][@"photoURLs"];
    float dimBrightness = [prefs[@"screensaver"][@"dimBrightness"] floatValue];
    if (dimBrightness <= 0) dimBrightness = 0.1;

    [_screensaver configureWithMode:mode photoURLs:photoURLs dimBrightness:dimBrightness];
    _screensaver.hidden = NO;
    [_screensaver fadeIn];
}

- (void)dismissScreensaver {
    if (!_screensaverActive) return;
    _screensaverActive = NO;
    [_screensaver fadeOut];
    [self resetIdleTimer];
}

#pragma mark - Settings

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
        [self.view sendSubviewToBack:self->_webView];
        [self loadDashboard];
    }

    // Apply screensaver updates immediately
    [self resetIdleTimer];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"KioskViewController: dashboard loaded");
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
    NSLog(@"KioskViewController: navigation failed: %@", error.localizedDescription);
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    NSLog(@"KioskViewController: provisional navigation failed: %@", error.localizedDescription);
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"kiosk"]) return;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    
    NSDictionary *body = message.body;
    NSString *type = body[@"type"];
    if (!type) return;

    if ([type isEqualToString:@"swipeDiag"]) {
        // Temporary debug relay: dump the swipe-handler diagnostics to a file the
        // host can read (the app's own NSLog isn't captured to a log file here).
        [self logDebug:[NSString stringWithFormat:@"swipeDiag: %@", body]];
        return;
    }

    if ([type isEqualToString:@"setBrightness"]) {
        float value = [body[@"value"] floatValue];
        [self postCommand:@"setBrightness" value:[NSString stringWithFormat:@"%.2f", value]];
    }
    else if ([type isEqualToString:@"setVolume"]) {
        float value = [body[@"value"] floatValue];
        [self postCommand:@"setVolume" value:[NSString stringWithFormat:@"%.2f", value]];
    }
    else if ([type isEqualToString:@"wake"]) {
        [self dismissScreensaver];
    }
}

#pragma mark - Debug Log Helper

// Temporary: appends a line to a fixed debug log file so diagnostics are readable
// from the host (the app's NSLog isn't captured to /var/log/hasmartboard.log).
// Remove with the swipeDiag relay once the swipe feature is confirmed.
- (void)logDebug:(NSString *)line {
    NSString *path = @"/var/mobile/Library/hasmartboard-debug.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) {
        [fh seekToEndOfFile];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@\n",
                           [NSDate date], line];
        [fh writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

#pragma mark - Daemon Command Helper

- (void)postCommand:(NSString *)action value:(NSString *)value {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9090/command"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{@"action": action, @"value": value ?: @""};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"KioskViewController: command failed: %@", error.localizedDescription);
            }
        }];
    [task resume];
}

- (void)dealloc {
    [_wakeTimer invalidate];
    [_idleTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
