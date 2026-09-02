#import "ScreensaverView.h"

@interface ScreensaverView ()
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) NSTimer *photoTimer;
@property (nonatomic, strong) NSArray<NSString *> *photoURLs;
@property (nonatomic, assign) NSInteger currentPhotoIndex;
@property (nonatomic, copy) NSString *currentMode;
@property (nonatomic, assign) float dimBrightness;
@end

@implementation ScreensaverView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.opaque = YES;
        [self setupSubviews];
        [self setupGesture];
    }
    return self;
}

- (void)setupSubviews {
    _clockLabel = [[UILabel alloc] init];
    _clockLabel.textColor = [UIColor whiteColor];
    _clockLabel.textAlignment = NSTextAlignmentCenter;
    _clockLabel.font = [UIFont monospacedDigitSystemFontOfSize:80 weight:UIFontWeightThin];
    _clockLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_clockLabel];

    _dateLabel = [[UILabel alloc] init];
    _dateLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    _dateLabel.textAlignment = NSTextAlignmentCenter;
    _dateLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_dateLabel];

    _photoView = [[UIImageView alloc] init];
    _photoView.contentMode = UIViewContentModeScaleAspectFill;
    _photoView.clipsToBounds = YES;
    _photoView.translatesAutoresizingMaskIntoConstraints = NO;
    _photoView.hidden = YES;
    [self addSubview:_photoView];

    [NSLayoutConstraint activateConstraints:@[
        [_clockLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_clockLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
        [_dateLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_dateLabel.topAnchor constraintEqualToAnchor:_clockLabel.bottomAnchor constant:10],
        [_photoView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_photoView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_photoView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_photoView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

- (void)setupGesture {
    UITapGestureRecognizer *wakeTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleTap:)];
    wakeTap.numberOfTapsRequired = 1;

    UITapGestureRecognizer *settingsTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSettingsTap:)];
    settingsTap.numberOfTapsRequired = 3;

    UITapGestureRecognizer *settingsTap4 = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSettingsTap:)];
    settingsTap4.numberOfTapsRequired = 4;

    [wakeTap requireGestureRecognizerToFail:settingsTap];
    [wakeTap requireGestureRecognizerToFail:settingsTap4];

    [self addGestureRecognizer:settingsTap];
    [self addGestureRecognizer:settingsTap4];
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

#pragma mark - Configuration

- (void)configureWithMode:(NSString *)mode
                photoURLs:(NSArray<NSString *> *)photoURLs
            dimBrightness:(float)dimBrightness {
    _currentMode = mode;
    _photoURLs = photoURLs;
    _dimBrightness = dimBrightness;
    _currentPhotoIndex = 0;

    BOOL isClock = [mode isEqualToString:@"clock"];
    BOOL isPhoto = [mode isEqualToString:@"photo"];

    _clockLabel.hidden = !isClock;
    _dateLabel.hidden = !isClock;
    _photoView.hidden = !isPhoto;

    if (isClock) {
        [self startClockUpdates];
    }
    if (isPhoto && photoURLs.count > 0) {
        [self startPhotoRotation];
    }
}

#pragma mark - Clock Mode

- (void)startClockUpdates {
    [_clockTimer invalidate];
    [self updateClock];
    _clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(updateClock)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)updateClock {
    NSDateFormatter *timeFmt = [[NSDateFormatter alloc] init];
    timeFmt.dateFormat = @"HH:mm";
    _clockLabel.text = [timeFmt stringFromDate:[NSDate date]];

    NSDateFormatter *dateFmt = [[NSDateFormatter alloc] init];
    dateFmt.dateFormat = @"EEEE, MMMM d";
    _dateLabel.text = [dateFmt stringFromDate:[NSDate date]];
}

#pragma mark - Photo Mode

- (void)startPhotoRotation {
    [_photoTimer invalidate];
    [self loadCurrentPhoto];
    _photoTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                  target:self
                                                selector:@selector(nextPhoto)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)nextPhoto {
    _currentPhotoIndex = (_currentPhotoIndex + 1) % _photoURLs.count;

    [UIView transitionWithView:_photoView
                      duration:1.0
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        [self loadCurrentPhoto];
                    }
                    completion:nil];
}

- (void)loadCurrentPhoto {
    if (_currentPhotoIndex >= (NSInteger)_photoURLs.count) return;
    NSURL *url = [NSURL URLWithString:_photoURLs[_currentPhotoIndex]];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.photoView.image = [UIImage imageWithData:data];
                });
            }
        }];
    [task resume];
}

#pragma mark - Animations

- (void)fadeIn {
    self.alpha = 0.0;
    [UIView animateWithDuration:0.5 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)fadeOut {
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.alpha = 0.0;
                     }
                     completion:^(BOOL finished) {
                         self.hidden = YES;
                         self.alpha = 1.0;
                         [self.clockTimer invalidate];
                         [self.photoTimer invalidate];
                     }];
}

- (void)dealloc {
    [_clockTimer invalidate];
    [_photoTimer invalidate];
}

@end
