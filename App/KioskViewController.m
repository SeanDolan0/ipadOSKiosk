#import "KioskViewController.h"
#import "ScreensaverView.h"
#import "NetworkMonitor.h"
#import "DaemonBridge.h"
#import "TelemetryRelay.h"

#define TELEMETRY_INTERVAL 30
#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

@implementation KioskViewController {
    WKWebView *_webView;
    ScreensaverView *_screensaver;
    NetworkMonitor *_networkMonitor;
    DaemonBridge *_daemonBridge;
    TelemetryRelay *_telemetryRelay;
    NSTimer *_telemetryTimer;
    NSTimer *_idleTimer;
    BOOL _screensaverActive;
    BOOL _isConnected;
    NSString *_haBaseURL;
    NSString *_haToken;
    NSString *_dashboardPath;
    UILabel *_orientationDiagnostics;
    NSUInteger _layoutCount;
    NSUInteger _transitionCount;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self loadHAConfig];

    _networkMonitor = [[NetworkMonitor alloc] init];
    _daemonBridge = [[DaemonBridge alloc] init];
    _telemetryRelay = [[TelemetryRelay alloc] initWithBaseURL:_haBaseURL
                                                       token:_haToken];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    [self setupOrientationDiagnostics];

    [self setupWebView];

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

    _telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:TELEMETRY_INTERVAL
                                                      target:self
                                                    selector:@selector(fetchAndRelayTelemetry)
                                                    userInfo:nil
                                                     repeats:YES];

    [self resetIdleTimer];
    [self loadDashboard];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updateOrientationDiagnostics];
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateOrientationDiagnostics];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _layoutCount++;
    _webView.frame = self.view.bounds;
    _screensaver.frame = self.view.bounds;
    [self updateOrientationDiagnostics];
}

- (void)setupOrientationDiagnostics {
    _orientationDiagnostics = [[UILabel alloc] initWithFrame:CGRectZero];
    _orientationDiagnostics.numberOfLines = 0;
    _orientationDiagnostics.textColor = [UIColor whiteColor];
    _orientationDiagnostics.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    _orientationDiagnostics.font = [UIFont systemFontOfSize:12.0];
    _orientationDiagnostics.textAlignment = NSTextAlignmentLeft;
    _orientationDiagnostics.layer.cornerRadius = 4.0;
    _orientationDiagnostics.clipsToBounds = YES;
    _orientationDiagnostics.hidden = NO;
    [self.view addSubview:_orientationDiagnostics];
}

- (NSString *)orientationName:(UIDeviceOrientation)orientation {
    switch (orientation) {
        case UIDeviceOrientationPortrait: return @"Portrait";
        case UIDeviceOrientationPortraitUpsideDown: return @"PortraitUpsideDown";
        case UIDeviceOrientationLandscapeLeft: return @"LandscapeLeft";
        case UIDeviceOrientationLandscapeRight: return @"LandscapeRight";
        case UIDeviceOrientationFaceUp: return @"FaceUp";
        case UIDeviceOrientationFaceDown: return @"FaceDown";
        default: return @"Unknown";
    }
}

- (NSString *)interfaceOrientationName:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortrait: return @"Portrait";
        case UIInterfaceOrientationPortraitUpsideDown: return @"PortraitUpsideDown";
        case UIInterfaceOrientationLandscapeLeft: return @"LandscapeLeft";
        case UIInterfaceOrientationLandscapeRight: return @"LandscapeRight";
        default: return @"Unknown";
    }
}

- (void)updateOrientationDiagnostics {
    if (!_orientationDiagnostics) return;

    UIInterfaceOrientation statusBarOrientation =
        [UIApplication sharedApplication].statusBarOrientation;
    NSString *deviceOrientation = [self orientationName:[UIDevice currentDevice].orientation];
    NSString *statusOrientation = [self interfaceOrientationName:statusBarOrientation];
    UIInterfaceOrientationMask supported = [self supportedInterfaceOrientations];

    _orientationDiagnostics.text = [NSString stringWithFormat:
        @"Device: %@\nStatus: %@\nView: %.0f x %.0f\nLayout: %lu  Transition: %lu\nMask: 0x%lx",
        deviceOrientation,
        statusOrientation,
        self.view.bounds.size.width,
        self.view.bounds.size.height,
        (unsigned long)_layoutCount,
        (unsigned long)_transitionCount,
        (unsigned long)supported];
    [_orientationDiagnostics sizeToFit];
    CGRect frame = _orientationDiagnostics.frame;
    frame.origin = CGPointMake(8.0, 8.0);
    frame.size.width += 12.0;
    frame.size.height += 8.0;
    _orientationDiagnostics.frame = frame;
    [self.view bringSubviewToFront:_orientationDiagnostics];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    _transitionCount++;

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
    _dashboardPath = haConfig[@"dashboardPath"] ?: @"/lovelace/0";
    
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

#pragma mark - Telemetry

- (void)fetchAndRelayTelemetry {
    [_daemonBridge fetchTelemetryWithCompletion:^(NSDictionary *telemetry) {
        if (telemetry) {
            [self->_telemetryRelay relayTelemetry:telemetry];
        }
    }];

    [_daemonBridge checkWakeWithCompletion:^(BOOL shouldWake) {
        if (shouldWake && self->_screensaverActive) {
            [self dismissScreensaver];
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

#pragma mark - ScreensaverViewDelegate

- (void)screensaverDidReceiveTouch {
    [self dismissScreensaver];
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
    [_telemetryTimer invalidate];
    [_idleTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

@end
