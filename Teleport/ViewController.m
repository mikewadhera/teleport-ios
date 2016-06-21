
@import AVFoundation;
@import CoreLocation;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"
#import "PreviewViewController.h"
#import "TP3DFlyover.h"

typedef NS_ENUM( NSInteger, TPCameraSetupResult ) {
    TPCameraSetupResultSuccess,
    TPCameraSetupResultCameraNotAuthorized
};

typedef NS_ENUM( NSInteger, TPViewport ) {
    TPViewportTop,
    TPViewportBottom
};

typedef NS_ENUM( NSInteger, TPState ) {
    TPStateSessionStopped,
    TPStateSessionStopping,
    TPStateSessionStarting,
    TPStateSessionStarted,
    TPStateSessionConfigurationFailed,
    TPStateRecordingIdle,
    TPStateRecordingStarted,
    TPStateRecordingFirstStarting,
    TPStateRecordingFirstStarted,
    TPStateRecordingFirstCompleting,
    TPStateRecordingFirstCompleted,
    TPStateSessionConfigurationUpdated,
    TPStateRecordingSecondStarting,
    TPStateRecordingSecondStarted,
    TPStateRecordingSecondCompleting,
    TPStateRecordingSecondCompleted,
    TPStateRecordingCompleted
};
typedef void (^ AssertFromBlock)(TPState);

// For debugging
#define stateFor(enum) [@[@"SessionStopped",@"SessionStopping",@"SessionStarting",@"SessionStarted",@"SessionConfigurationFailed",@"RecordingIdle",@"RecordingStarted",@"RecordingFirstStarting",@"RecordingFirstStarted",@"RecordingFirstCompleting",@"RecordingFirstCompleted",@"SessionConfigurationUpdated",@"RecordingSecondStarting",@"RecordingSecondStarted",@"RecordingSecondCompleting",@"RecordingSecondCompleted",@"RecordingCompleted"] objectAtIndex:enum]

// Constants
static const AVCaptureDevicePosition TPViewportTopCamera        = AVCaptureDevicePositionBack;
static const AVCaptureDevicePosition TPViewportBottomCamera     = AVCaptureDevicePositionFront;
static const TPViewport TPRecordFirstViewport                   = TPViewportTop;
static const TPViewport TPRecordSecondViewport                  = TPViewportBottom;
static const NSTimeInterval TPRecordFirstInterval               = 5.0;
static const NSTimeInterval TPRecordSecondInterval              = TPRecordFirstInterval;
static const NSTimeInterval TPRecordSecondGraceInterval         = 0.8;
static const NSTimeInterval TPRecordSecondGraceOpacity          = 0.94;
static const NSTimeInterval TPCameraChangeLatencyHintInterval   = 0.6;
static const CGFloat TPProgressBarWidth                         = 39.0f;
#define      TPProgressBarTrackColor                            [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:0.33]
#define      TPProgressBarTrackHighlightColor                   [UIColor redColor]
#define      TPProgressBarColor                                 [UIColor redColor]
static const CGFloat TPSpinnerBarWidth                          = 4.0f;
static const CGFloat TPSpinnerDuration                          = TPCameraChangeLatencyHintInterval;
static const CGFloat TPEncodeBitrate                            = 6000000;
static const CGFloat TPEncodeWidth                              = 1280;
static const CGFloat TPEncodeHeight                             = 960;
#define      TPLocationAccuracy                                 kCLLocationAccuracyBestForNavigation
static const CLLocationDistance TPLocationDistanceFilter        = 100;
// Constants

@interface ViewController () <IDCaptureSessionCoordinatorDelegate, CLLocationManagerDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastKnownLocation;
@property (nonatomic) CLLocationDirection lastKnownDirection;
@property (nonatomic) TP3DFlyover *flyover;

@property (nonatomic) TPState status;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) NSURL *firstVideoURL;
@property (nonatomic) NSURL *secondVideoURL;
@property (nonatomic) CAShapeLayer *progressBarLayer;
@property (nonatomic) CAShapeLayer *progressBarTrackLayer;
@property (nonatomic) CALayer *secondRecordingVisualCueLayer;
@property (nonatomic) CAShapeLayer *secondRecordingVisualCueSpinnerLayer;

@end

@implementation ViewController
{
    CGRect topViewportRect;
    CGRect bottomViewportRect;
    BOOL sessionConfigurationFailed;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Create the location manager (needs to happen before auth check)
    _locationManager = [[CLLocationManager alloc] init];
    [_locationManager setDelegate:self];
    _locationManager.desiredAccuracy = TPLocationAccuracy;
    _locationManager.distanceFilter = TPLocationDistanceFilter;
    
    // Check camera and GPS sensor access
    [self checkAuth];
    
    // Create the session coordinator
    AVCaptureDevicePosition initialDevicePosition;
    switch (TPRecordFirstViewport)
    {
        case TPViewportTop:
        {
            initialDevicePosition = TPViewportTopCamera;
            break;
        }
        case TPViewportBottom:
        {
            initialDevicePosition = TPViewportBottomCamera;
            break;
        }
    }
    _sessionCoordinator = [[IDCaptureSessionAssetWriterCoordinator alloc] initWithDevicePosition:initialDevicePosition];
    [_sessionCoordinator setDelegate:self callbackQueue:dispatch_get_main_queue()];
    
    // Create the preview
    _previewLayer = _sessionCoordinator.previewLayer;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    // Create the player
    _firstPlayer = [[AVPlayer alloc] init];
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    // Always muted
    _firstPlayer.muted = YES;
    
    // Calculate Viewports
    int topViewW = self.view.frame.size.width;
    int topViewH = ceil(self.view.frame.size.height / 2.0);
    int topViewX = 0;
    int topViewY = 0;
    topViewportRect = CGRectMake(topViewX, topViewY, topViewW, topViewH);
    
    int bottomViewW = self.view.frame.size.width;
    int bottomViewH = ceil(self.view.frame.size.height / 2.0);
    int bottomViewX = 0;
    int bottomViewY = floor(self.view.frame.size.height / 2.0);
    bottomViewportRect = CGRectMake(bottomViewX, bottomViewY, bottomViewW, bottomViewH);
    
    // Player
    [self.view.layer insertSublayer:_firstPlayerLayer atIndex:0];
    [self moveLayer:_firstPlayerLayer to:TPRecordFirstViewport];
    
    // Preview
    [_previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.view.layer insertSublayer:_previewLayer atIndex:2];
    [self moveLayer:_previewLayer to:TPRecordFirstViewport];
    
    // Progress Bar
    _progressBarLayer = [CAShapeLayer layer];
    [self.view.layer insertSublayer:_progressBarLayer atIndex:5];
    [_progressBarLayer setStrokeColor:TPProgressBarColor.CGColor];
    [_progressBarLayer setLineWidth:TPProgressBarWidth];
    [_progressBarLayer setFillColor:[UIColor clearColor].CGColor];
    [_progressBarLayer setHidden:YES];
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGSize screenSize = self.view.bounds.size;
    CGPoint pointA = CGPointMake(screenSize.width/2, 0);
    CGPoint pointB = CGPointMake(screenSize.width, 0);
    CGPoint pointC = CGPointMake(screenSize.width, screenSize.height);
    CGPoint pointD = CGPointMake(0, screenSize.height);
    CGPoint pointE = CGPointMake(0, 0);
    [path moveToPoint:pointA];
    [path addLineToPoint:pointE];
    [path addLineToPoint:pointD];
    [path addLineToPoint:pointC];
    [path addLineToPoint:pointB];
    [path addLineToPoint:pointA];
    _progressBarLayer.path = path.CGPath;
    _progressBarTrackLayer = [CAShapeLayer layer];
    [self.view.layer insertSublayer:_progressBarTrackLayer atIndex:4];
    [_progressBarTrackLayer setStrokeColor:TPProgressBarTrackColor.CGColor];
    [_progressBarTrackLayer setLineWidth:TPProgressBarWidth];
    [_progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
    _progressBarTrackLayer.path = _progressBarLayer.path;
    UILongPressGestureRecognizer *tapRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    tapRecognizer.minimumPressDuration = 0;
    [self.view addGestureRecognizer:tapRecognizer];
    
    // Second Recording Visual Cue
    _secondRecordingVisualCueLayer = [CALayer layer];
    [self.view.layer insertSublayer:_secondRecordingVisualCueLayer atIndex:3];
    [_secondRecordingVisualCueLayer setBackgroundColor:[UIColor blackColor].CGColor];
    [self moveLayer:_secondRecordingVisualCueLayer to:TPRecordSecondViewport];
    _secondRecordingVisualCueSpinnerLayer = [CAShapeLayer layer];
    [_secondRecordingVisualCueLayer addSublayer:_secondRecordingVisualCueSpinnerLayer];
    _secondRecordingVisualCueSpinnerLayer.lineWidth = TPSpinnerBarWidth;
    _secondRecordingVisualCueSpinnerLayer.fillColor = nil;
    _secondRecordingVisualCueSpinnerLayer.strokeColor = [UIColor colorWithWhite:0.0 alpha:0.20].CGColor;
    CGRect bounds = _secondRecordingVisualCueLayer.bounds;
    CGPoint center = CGPointMake(bounds.size.width/2, bounds.size.height/2);
    CGFloat radius = 44;
    CGFloat startAngle = -M_PI_2;
    CGFloat endAngle = startAngle + (M_PI*2);
    UIBezierPath *spinPath = [UIBezierPath bezierPathWithArcCenter:CGPointZero radius:radius startAngle:startAngle endAngle:endAngle clockwise:true];
    _secondRecordingVisualCueSpinnerLayer.path = spinPath.CGPath;
    _secondRecordingVisualCueSpinnerLayer.position = center;
    [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
    
    // Flyover
    _flyover = [[TP3DFlyover alloc] init];
    [_flyover.mapView setFrame:self.view.bounds];
    _flyover.mapView.alpha = 0;
    [self.view addSubview:_flyover.mapView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (sessionConfigurationFailed) {
        [self showCameraCaptureErrorDialog];
    }
    
    switch ( _setupResult )
    {
        case TPCameraSetupResultSuccess:
        {
            [self transitionToStatus:TPStateSessionStarting];
            break;
        }
        case TPCameraSetupResultCameraNotAuthorized:
        {
            [self showCameraPermissionErrorDialog];
            break;
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    if ( _setupResult == TPCameraSetupResultSuccess ) {
        [self transitionToStatus:TPStateSessionStopping];
    }
    
    [super viewDidDisappear:animated];
}

- (void)longPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer
{
    if (longPressGestureRecognizer.state == UIGestureRecognizerStateBegan || longPressGestureRecognizer.state == UIGestureRecognizerStateChanged)
    {
        [_progressBarTrackLayer setStrokeColor:TPProgressBarTrackHighlightColor.CGColor];
    }
    else if (longPressGestureRecognizer.state == UIGestureRecognizerStateEnded)
    {
        if (_status == TPStateRecordingIdle) {
            [_progressBarTrackLayer setHidden:YES];
            [_progressBarLayer setHidden:NO];
            [self transitionToStatus:TPStateRecordingFirstStarting];
        }
    }
}

-(void)checkAuth
{
    // Assume we have camera permission
    _setupResult = TPCameraSetupResultSuccess;
    
    // Check video permission status. Video access is required and audio access is optional.
    // If audio access is denied, audio is not recorded during movie recording.
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
    {
        case AVAuthorizationStatusAuthorized:
        {
            // The user has previously granted access to the camera.
            [self.locationManager requestWhenInUseAuthorization];
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    _setupResult = TPCameraSetupResultCameraNotAuthorized;
                } else {
                    [self.locationManager requestWhenInUseAuthorization];
                }
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            _setupResult = TPCameraSetupResultCameraNotAuthorized;
            break;
        }
    }
}

- (void)moveLayer:(CALayer*)layer to:(TPViewport)viewport
{
    CGRect targetFrame;
    switch (viewport)
    {
        case TPViewportTop:
        {
            targetFrame = topViewportRect;
            break;
        }
        case TPViewportBottom:
        {
            targetFrame = bottomViewportRect;
            break;
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setFrame:targetFrame];
    [CATransaction commit];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    PreviewViewController *vc = [segue destinationViewController];
    vc.firstVideoURL = _firstVideoURL;
    vc.secondVideoURL = _secondVideoURL;
    vc.location = _lastKnownLocation;
    vc.direction = _lastKnownDirection;
    vc.flyover = _flyover;
}

-(void)transitionToStatus:(TPState)newStatus
{
    TPState oldStatus = _status;
    _status = newStatus;
    
    //NSLog(@"%ld --> %ld", oldStatus, newStatus);
    NSLog(@"%@", stateFor(newStatus));
    
    AssertFromBlock assertFrom = ^(TPState fromState) {
        if (oldStatus != fromState) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString
                                                   stringWithFormat:@"Unexpected transition: %@ to %@",
                                                   stateFor(oldStatus),
                                                   stateFor(newStatus)]
                                         userInfo:nil];
        }
    };
    
    if (oldStatus != newStatus) {
        if (newStatus == TPStateSessionStarting) {
            
            [_locationManager startUpdatingLocation];
            [_locationManager startUpdatingHeading];
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [_sessionCoordinator stopRunning];
            
        } else if (newStatus == TPStateSessionConfigurationFailed) {
            
            sessionConfigurationFailed = YES; // checked in viewWillAppear
        
        } else if (newStatus == TPStateSessionStarted) {
            
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            [self transitionToStatus:TPStateRecordingIdle];
            
        } else if (newStatus == TPStateRecordingFirstStarting) {
            
            assertFrom(TPStateRecordingIdle);
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingFirstStarted) {
            
            [self startProgressBar];
            [self startSecondRecordingVisualCue];
            [self transitionToStatus:TPStateRecordingFirstCompleting
                               after:TPRecordFirstInterval];
            
        } else if (newStatus == TPStateRecordingFirstCompleting) {
            
            assertFrom(TPStateRecordingFirstStarted);
            [self pauseProgressBar];
            [self showSpinner];
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingFirstCompleted) {
            
            assertFrom(TPStateRecordingFirstCompleting);
            [self transitionToStatus:TPStateSessionConfigurationUpdated];
            
        } else if (newStatus == TPStateSessionConfigurationUpdated) {
            
            [_firstPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem
                                                            playerItemWithAsset:[AVAsset
                                                                                 assetWithURL:_firstVideoURL]]];
            [_firstPlayer seekToTime:kCMTimeZero];
            AVCaptureDevicePosition targetCamera;
            switch (TPRecordSecondViewport)
            {
                case TPViewportTop:
                {
                    targetCamera = TPViewportTopCamera;
                    break;
                }
                case TPViewportBottom:
                {
                    targetCamera = TPViewportBottomCamera;
                    break;
                }
            }
            // -setDevicePosition is long running / blocks this thread
            // Involves updating the underlying session's configuration
            // which can take 600ms+ on iPhone6
            [_sessionCoordinator setDevicePosition:targetCamera];
            [self moveLayer:_previewLayer to:TPRecordSecondViewport];
            [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
            [_secondRecordingVisualCueLayer setOpacity:TPRecordSecondGraceOpacity];
            [self transitionToStatus:TPStateRecordingSecondStarting after:TPRecordSecondGraceInterval];
            
        } else if (newStatus == TPStateRecordingSecondStarting) {
            
            assertFrom(TPStateSessionConfigurationUpdated);
            [_secondRecordingVisualCueLayer setHidden:YES];
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingSecondStarted) {
            
            [_firstPlayer play];
            [self resumeProgressBar];
            [self transitionToStatus:TPStateRecordingSecondCompleting after:TPRecordSecondInterval];
            
        } else if (newStatus == TPStateRecordingSecondCompleting) {
            
            assertFrom(TPStateRecordingSecondStarted);
            [self pauseProgressBar];
            [[_previewLayer connection] setEnabled:NO]; // Freeze preview
            [_firstPlayer pause];
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingSecondCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleting);
            [self resumeProgressBar];
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleted);
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [self transitionToStatus:TPStateRecordingIdle];
            [self performSegueWithIdentifier:@"ShowPreview" sender:self];

        }
    }
}

-(void)transitionToStatus:(TPState)newStatus after:(NSTimeInterval)delay
{
    [self performBlock:^{
        [self transitionToStatus:newStatus];
    } afterDelay:delay];
}

-(void)startSecondRecordingVisualCue
{
    CABasicAnimation *anime = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    anime.fromValue = (id)[_secondRecordingVisualCueLayer backgroundColor];
    _secondRecordingVisualCueLayer.backgroundColor = [UIColor whiteColor].CGColor;
    anime.toValue = (id)[UIColor whiteColor].CGColor;
    anime.duration = TPRecordFirstInterval;
    anime.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    //anime.autoreverses = YES;
    [_secondRecordingVisualCueLayer addAnimation:anime forKey:@"myColor"];
}

-(void)startProgressBar
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = [NSNumber numberWithFloat:1.0f];
    _progressBarLayer.strokeEnd = 0.0;
    animation.toValue = [NSNumber numberWithFloat:0.0f];
    animation.duration = TPRecordFirstInterval + TPRecordSecondInterval;
    [_progressBarLayer addAnimation:animation forKey:@"myStroke"];
}

-(void)pauseProgressBar
{
    CFTimeInterval pausedTime = [_progressBarLayer convertTime:CACurrentMediaTime() fromLayer:nil];
    _progressBarLayer.speed = 0.0;
    _progressBarLayer.timeOffset = pausedTime;
}

-(void)resumeProgressBar
{
    CFTimeInterval pausedTime = [_progressBarLayer timeOffset];
    _progressBarLayer.speed = 1.0;
    _progressBarLayer.timeOffset = 0.0;
    _progressBarLayer.beginTime = 0.0;
    CFTimeInterval timeSincePause = [_progressBarLayer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    _progressBarLayer.beginTime = timeSincePause;
}

-(void)showSpinner
{
    [_secondRecordingVisualCueSpinnerLayer setHidden:NO];
    [[self class] addSpinnerAnimations:_secondRecordingVisualCueSpinnerLayer];
}

#pragma mark = IDCaptureSessionAssetWriterCoordinatorDelegate methods

- (void)coordinatorSessionConfigurationDidFail:(IDCaptureSessionAssetWriterCoordinator *)coordinator
{
    [self transitionToStatus:TPStateSessionConfigurationFailed];
}

-(void)coordinatorSessionDidFinishStarting:(IDCaptureSessionAssetWriterCoordinator *)coordinator running:(BOOL)isRunning
{
    if (isRunning) {
        [self transitionToStatus:TPStateSessionStarted];
    }
}

- (NSDictionary*)coordinatorDesiredVideoOutputSettings
{
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(TPEncodeBitrate) };
    return @{
              AVVideoCodecKey : AVVideoCodecH264,
              AVVideoWidthKey : @(TPEncodeWidth),
              AVVideoHeightKey : @(TPEncodeHeight),
              AVVideoScalingModeKey:AVVideoScalingModeResizeAspectFill,
              AVVideoCompressionPropertiesKey : compressionProperties
            };
}

- (void)coordinatorDidBeginRecording:(IDCaptureSessionAssetWriterCoordinator *)coordinator
{
    if (_status == TPStateRecordingFirstStarting) {
        [self transitionToStatus:TPStateRecordingFirstStarted];
    } else if (_status == TPStateRecordingSecondStarting) {
        [self transitionToStatus:TPStateRecordingSecondStarted];
    }
}

- (void)coordinator:(IDCaptureSessionAssetWriterCoordinator *)coordinator didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error
{
    BOOL success = YES;
    if ( error ) {
        NSLog( @"Movie file finishing error: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        if (_status == TPStateRecordingFirstCompleting) {
            _firstVideoURL = outputFileURL;
            [self transitionToStatus:TPStateRecordingFirstCompleted];
        } else if (_status == TPStateRecordingSecondCompleting) {
            _secondVideoURL = outputFileURL;
            [self transitionToStatus:TPStateRecordingSecondCompleted];
        }
    }
}

#pragma mark = CLLocationManager methods

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    _lastKnownLocation = newLocation;
    // Pre-load flyover
    _flyover.location = _lastKnownLocation;
    [_flyover preload];
    NSLog(@"NewLocation %f %f", newLocation.coordinate.latitude, newLocation.coordinate.longitude);
    [_locationManager stopUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading
{
    _lastKnownDirection = [newHeading trueHeading];
    _flyover.direction = _lastKnownDirection;
    [_flyover preload];
    NSLog(@"NewHeading %f", [newHeading trueHeading]);
    [_locationManager stopUpdatingHeading];
}

#pragma mark Helpers

-(void)showCameraPermissionErrorDialog
{
    NSString *message = @"Teleport doesn't have permission to use the camera, please enable in settings";
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Camera Permissions" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    // Provide quick access to Settings.
    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
    }];
    [alertController addAction:settingsAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

-(void)showCameraCaptureErrorDialog
{
    NSString *message = @"Unable to capture video";
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Camera Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)performBlock:(void (^)(void))block
          afterDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(fireBlockAfterDelay:)
               withObject:[block copy]
               afterDelay:delay];
}

- (void)fireBlockAfterDelay:(void (^)(void))block {
    block();
}

+(void)addSpinnerAnimations:(CAShapeLayer*)spinnerLayer
{
    CABasicAnimation *strokeEnd = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    strokeEnd.fromValue = [NSNumber numberWithInt:0];
    strokeEnd.toValue = [NSNumber numberWithInt:1];
    strokeEnd.duration = TPSpinnerDuration;
    strokeEnd.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    CAAnimationGroup *strokeEndGroup = [CAAnimationGroup new];
    strokeEndGroup.duration = TPSpinnerDuration;
    strokeEndGroup.repeatCount = MAXFLOAT;
    strokeEndGroup.animations = @[ strokeEnd ];
    
    [spinnerLayer addAnimation:strokeEndGroup forKey:@"myStrokeEnd"];
    
    CABasicAnimation *strokeStart = [CABasicAnimation animationWithKeyPath:@"strokeStart"];
    strokeStart.beginTime = TPSpinnerDuration;
    strokeStart.fromValue = [NSNumber numberWithInt:0];
    strokeStart.toValue = [NSNumber numberWithInt:1];
    strokeStart.duration = TPSpinnerDuration;
    strokeStart.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    CAAnimationGroup *strokeStartGroup = [CAAnimationGroup new];
    strokeStartGroup.duration = TPSpinnerDuration + 0.5;
    strokeStartGroup.repeatCount = MAXFLOAT;
    strokeStartGroup.animations = @[ strokeStart ];
    
    [spinnerLayer addAnimation:strokeStartGroup forKey:@"myStrokeStart"];
    
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = [NSNumber numberWithInt:0];
    rotation.toValue = [NSNumber numberWithInt:M_PI * 2];
    rotation.duration = TPSpinnerDuration*2;
    rotation.repeatCount = MAXFLOAT;
    
    //[spinnerLayer addAnimation:rotation forKey:@"myRotation"];
}

@end
