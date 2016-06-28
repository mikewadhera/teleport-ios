
@import AVFoundation;
@import CoreLocation;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"
#import "PreviewViewController.h"
#import "TPGeocoder.h"

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

// Constants
static const AVCaptureDevicePosition TPViewportTopCamera                = AVCaptureDevicePositionFront;
static const AVCaptureDevicePosition TPViewportBottomCamera             = AVCaptureDevicePositionBack;
static const TPViewport              TPRecordFirstViewport              = TPViewportTop;
static const TPViewport              TPRecordSecondViewport             = TPViewportBottom;
static const NSTimeInterval          TPRecordFirstInterval              = 5.5;
static const NSTimeInterval          TPRecordSecondInterval             = TPRecordFirstInterval;
static const NSTimeInterval          TPRecordSecondGraceInterval        = 1.2;
static const NSTimeInterval          TPRecordSecondGraceOpacity         = 0.8;
#define                              TPProgressBarWidth                 10+floorf((self.view.bounds.size.width*0.10))
#define                              TPProgressBarTrackColor            [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:0.33]
#define                              TPProgressBarTrackHighlightColor   [UIColor redColor]
#define                              TPProgressBarColor                 [UIColor redColor]
static const CGFloat                 TPSpinnerBarWidth                  = 0.0f;
#define                              TPSpinnerRadius                    sqrt(hypotf(bounds.size.width, bounds.size.height))*3.0
static const NSTimeInterval          TPSpinnerInterval                  = 0.3f;
#define                              TPSpinnerBarColor                  [UIColor colorWithWhite:0 alpha:0.25]
#define                              TPLocationAccuracy                 kCLLocationAccuracyBestForNavigation
static const CLLocationDistance      TPLocationDistanceFilter           = 100;
// Constants

// For debugging
#define stateFor(enum) [@[@"SessionStopped",@"SessionStopping",@"SessionStarting",@"SessionStarted",@"SessionConfigurationFailed",@"RecordingIdle",@"RecordingStarted",@"RecordingFirstStarting",@"RecordingFirstStarted",@"RecordingFirstCompleting",@"RecordingFirstCompleted",@"SessionConfigurationUpdated",@"RecordingSecondStarting",@"RecordingSecondStarted",@"RecordingSecondCompleting",@"RecordingSecondCompleted",@"RecordingCompleted"] objectAtIndex:enum]

@interface ViewController () <IDCaptureSessionCoordinatorDelegate, CLLocationManagerDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastKnownLocation;
@property (nonatomic) CLLocationDirection lastKnownDirection;
@property (nonatomic) NSArray *lastKnownPlacemarks;
@property (nonatomic) TPGeocoder *geocoder;

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
    AVCaptureDevicePosition initialDevicePosition;
    NSTimer *firstRecordingStopTimer;
    NSTimer *secondRecordingStartGraceTimer;
    NSTimer *secondRecordingStopTimer;
    UITapGestureRecognizer *tapRecognizer;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // Create the location manager (needs to happen before auth check)
    _locationManager = [[CLLocationManager alloc] init];
    [_locationManager setDelegate:self];
    _locationManager.desiredAccuracy = TPLocationAccuracy;
    _locationManager.distanceFilter = TPLocationDistanceFilter;
    
    _geocoder = [[TPGeocoder alloc] init];
    
    // Check camera and GPS sensor access
    [self checkAuth];
    
    // Create the session coordinator
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
    
    // Preview
    [_previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.view.layer insertSublayer:_previewLayer atIndex:2];
    
    // Progress Bar
    _progressBarLayer = [CAShapeLayer layer];
    [self.view.layer insertSublayer:_progressBarLayer atIndex:5];
    [_progressBarLayer setStrokeColor:TPProgressBarColor.CGColor];
    [_progressBarLayer setLineWidth:TPProgressBarWidth];
    [_progressBarLayer setFillColor:[UIColor clearColor].CGColor];
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
    [_progressBarTrackLayer setLineWidth:TPProgressBarWidth];
    [_progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
    _progressBarTrackLayer.path = _progressBarLayer.path;
    tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectRecord:)];
    [self.view addGestureRecognizer:tapRecognizer];
    
    // Second Recording Visual Cue
    _secondRecordingVisualCueLayer = [CALayer layer];
    [self.view.layer insertSublayer:_secondRecordingVisualCueLayer atIndex:3];
    
    // Spinner
    _secondRecordingVisualCueSpinnerLayer = [CAShapeLayer layer];
    [_secondRecordingVisualCueLayer addSublayer:_secondRecordingVisualCueSpinnerLayer];
    _secondRecordingVisualCueSpinnerLayer.lineWidth = TPSpinnerBarWidth;
    _secondRecordingVisualCueSpinnerLayer.lineCap = kCALineCapRound;
    _secondRecordingVisualCueSpinnerLayer.fillColor = nil;
    CGRect bounds = bottomViewportRect;
    CGPoint center = CGPointMake(bounds.size.width/2, bounds.size.height/2);
    UIBezierPath *spinPath = [UIBezierPath bezierPathWithArcCenter:CGPointZero
                                                            radius:TPSpinnerRadius
                                                        startAngle:0
                                                          endAngle:(M_PI*2)
                                                         clockwise:true];
    _secondRecordingVisualCueSpinnerLayer.path = spinPath.CGPath;
    _secondRecordingVisualCueSpinnerLayer.position = center;
}

-(void)controllerResumedFromBackground
{
    switch ( _setupResult )
    {
        case TPCameraSetupResultSuccess:
        {
            @synchronized (self) {
                [self transitionToStatus:TPStateSessionStarting];
            }
            break;
        }
        case TPCameraSetupResultCameraNotAuthorized:
        {
            [self showCameraPermissionErrorDialog];
            break;
        }
    }
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
            @synchronized (self) {
                [self transitionToStatus:TPStateSessionStarting];
            }
            break;
        }
        case TPCameraSetupResultCameraNotAuthorized:
        {
            [self showCameraPermissionErrorDialog];
            break;
        }
    }
    
    // We don't observe resign-to-background as that behavior is implicity handled by coordinatorSessionDidInterrupt:
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerResumedFromBackground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    if ( _setupResult == TPCameraSetupResultSuccess ) {
        @synchronized (self) {
            [self transitionToStatus:TPStateSessionStopping];
        }
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)didSelectRecord:(UITapGestureRecognizer *)recognizer
{
    if (_status == TPStateRecordingIdle) {
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingFirstStarting];
        }
    } else {
        // HACK: We really shouldn't be dependant on temporal ordering of states
        @synchronized (self) {
            [self transitionToStatus:TPStateSessionStopping];
            [self transitionToStatus:TPStateSessionStarting];
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
    vc.placemarks = _lastKnownPlacemarks;
}

// call under @synchonized( self )
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
            
            [tapRecognizer setEnabled:NO];
            _lastKnownLocation = nil;
            _lastKnownDirection = kCLHeadingFilterNone;
            _lastKnownPlacemarks = nil;
            _firstVideoURL = nil;
            _secondVideoURL = nil;
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            [_locationManager startUpdatingLocation];
            [_locationManager startUpdatingHeading];
            [self moveLayer:_firstPlayerLayer to:TPRecordFirstViewport];
            [self moveLayer:_previewLayer to:TPRecordFirstViewport];
            [self moveLayer:_secondRecordingVisualCueLayer to:TPRecordSecondViewport];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [_progressBarTrackLayer setHidden:NO];
            [_progressBarLayer setHidden:YES];
            [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
            [_secondRecordingVisualCueLayer removeAllAnimations];
            [_secondRecordingVisualCueLayer setHidden:NO];
            [_secondRecordingVisualCueLayer setOpacity:1.0];
            [_secondRecordingVisualCueLayer setBackgroundColor:[UIColor blackColor].CGColor];
            [_progressBarTrackLayer setStrokeColor:TPProgressBarTrackColor.CGColor];
            _secondRecordingVisualCueSpinnerLayer.strokeColor = TPSpinnerBarColor.CGColor;
            _secondRecordingVisualCueSpinnerLayer.strokeStart = 0;
            _secondRecordingVisualCueSpinnerLayer.strokeEnd = 0;
            // These get hidden if we're coming back from preview
            if (_sessionCoordinator.devicePosition != TPViewportTopCamera) {
                [_previewLayer setHidden:YES];
                [_firstPlayerLayer setHidden:YES];
            }
            [CATransaction commit];
            
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [firstRecordingStopTimer invalidate];
            [secondRecordingStartGraceTimer invalidate];
            [secondRecordingStopTimer invalidate];
            [_locationManager stopUpdatingLocation];
            [_sessionCoordinator stopRunning];
            
        } else if (newStatus == TPStateSessionConfigurationFailed) {
            
            sessionConfigurationFailed = YES; // checked in viewWillAppear
        
        } else if (newStatus == TPStateSessionStarted) {
            
            // Switch camera config back if needed
            if (_sessionCoordinator.devicePosition != initialDevicePosition) {
                [_sessionCoordinator setDevicePosition:initialDevicePosition];
                [_previewLayer setHidden:NO];
                [_firstPlayerLayer setHidden:NO];
            }
            [tapRecognizer setEnabled:YES];
            [self transitionToStatus:TPStateRecordingIdle];
            
        } else if (newStatus == TPStateRecordingFirstStarting) {
            
            assertFrom(TPStateRecordingIdle);
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            [_progressBarTrackLayer setHidden:YES];
            [_progressBarLayer setHidden:NO];
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingFirstStarted) {
            
            [self startProgressBar];
            [self startSecondRecordingVisualCue];
            firstRecordingStopTimer = [NSTimer scheduledTimerWithTimeInterval:TPRecordFirstInterval
                                                                       target:self
                                                                     selector:@selector(stopFirstRecording)
                                                                     userInfo:nil
                                                                      repeats:NO];
            
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
            
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            [self moveLayer:_previewLayer to:TPRecordSecondViewport];
            [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
            [_secondRecordingVisualCueLayer setOpacity:TPRecordSecondGraceOpacity];
            secondRecordingStartGraceTimer = [NSTimer scheduledTimerWithTimeInterval:TPRecordSecondGraceInterval
                                                                              target:self
                                                                            selector:@selector(startSecondRecording)
                                                                            userInfo:nil
                                                                             repeats:NO];
            
        } else if (newStatus == TPStateRecordingSecondStarting) {
            
            assertFrom(TPStateSessionConfigurationUpdated);
            [_secondRecordingVisualCueLayer setHidden:YES];
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingSecondStarted) {
            
            [_firstPlayer play];
            [self resumeProgressBar];
            secondRecordingStopTimer = [NSTimer scheduledTimerWithTimeInterval:TPRecordSecondInterval
                                                                        target:self
                                                                      selector:@selector(stopSecondRecording)
                                                                      userInfo:nil
                                                                       repeats:NO];
            
        } else if (newStatus == TPStateRecordingSecondCompleting) {
            
            assertFrom(TPStateRecordingSecondStarted);
            [self pauseProgressBar];
            [[_previewLayer connection] setEnabled:NO]; // Freeze preview
            [_firstPlayer pause];
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingSecondCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleting);
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            [self resumeProgressBar];
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleted);
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [self performSegueWithIdentifier:@"ShowPreview" sender:self];

        }
    }
}

-(void)stopFirstRecording
{
    @synchronized (self) {
        [self transitionToStatus:TPStateRecordingFirstCompleting];
    }
}

-(void)startSecondRecording
{
    @synchronized (self) {
        [self transitionToStatus:TPStateRecordingSecondStarting];
    }
}

-(void)stopSecondRecording
{
    @synchronized (self) {
        [self transitionToStatus:TPStateRecordingSecondCompleting];
    }
}

-(void)startSecondRecordingVisualCue
{
    CABasicAnimation *anime = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    anime.fromValue = (id)[_secondRecordingVisualCueLayer backgroundColor];
    _secondRecordingVisualCueLayer.backgroundColor = [UIColor whiteColor].CGColor;
    anime.toValue = (id)[UIColor whiteColor].CGColor;
    anime.duration = TPRecordFirstInterval;
    anime.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
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
    _progressBarLayer.speed = 1.0;
    _progressBarLayer.timeOffset = 0.0;
    _progressBarLayer.beginTime = 0.0;
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
    @synchronized (self) {
        [self transitionToStatus:TPStateSessionConfigurationFailed];
    }
}

-(void)coordinatorSessionDidFinishStarting:(IDCaptureSessionAssetWriterCoordinator *)coordinator running:(BOOL)isRunning
{
    if (isRunning) {
        @synchronized (self) {
            [self transitionToStatus:TPStateSessionStarted];
        }
    }
}

- (void)coordinatorSessionDidInterrupt:(IDCaptureSessionAssetWriterCoordinator *)coordinator
{
    @synchronized (self) {
        [self transitionToStatus:TPStateSessionStopping];
    }
}

- (NSDictionary*)coordinatorDesiredVideoOutputSettings
{
    return @{
              AVVideoCodecKey : AVVideoCodecH264,
//              AVVideoWidthKey : @(1280),
//              AVVideoHeightKey : @(960),
//              AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill
            };
}

- (void)coordinatorDidBeginRecording:(IDCaptureSessionAssetWriterCoordinator *)coordinator
{
    if (_status == TPStateRecordingFirstStarting) {
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingFirstStarted];
        }
    } else if (_status == TPStateRecordingSecondStarting) {
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingSecondStarted];
        }
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
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingFirstCompleted];
            }
        } else if (_status == TPStateRecordingSecondCompleting) {
            _secondVideoURL = outputFileURL;
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingSecondCompleted];
            }
        }
    }
}

#pragma mark = CLLocationManager methods

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    _lastKnownLocation = newLocation;
    NSLog(@"NewLocation %f %f", newLocation.coordinate.latitude, newLocation.coordinate.longitude);
    [_geocoder reverseGeocode:_lastKnownLocation completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to reverse geocode: %f %f", newLocation.coordinate.latitude, newLocation.coordinate.longitude);
        }
        _lastKnownPlacemarks = placemarks;
    }];
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading
{
    _lastKnownDirection = [newHeading trueHeading];
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

+(void)addSpinnerAnimations:(CAShapeLayer*)spinnerLayer
{
    CAKeyframeAnimation *rotateAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation"];
    rotateAnimation.values = @[
                               @0,
                               @(M_PI),
                               @(2 * M_PI)
                               ];
    
    CABasicAnimation *headAnimation = [CABasicAnimation animation];
    headAnimation.keyPath = @"strokeStart";
    headAnimation.duration = TPSpinnerInterval;
    headAnimation.fromValue = @0;
    headAnimation.toValue = @.25;
    
    CABasicAnimation *tailAnimation = [CABasicAnimation animation];
    tailAnimation.keyPath = @"strokeEnd";
    tailAnimation.duration = TPSpinnerInterval;
    tailAnimation.fromValue = @0;
    tailAnimation.toValue = @1;
    
    CABasicAnimation *endHeadAnimation = [CABasicAnimation animation];
    endHeadAnimation.keyPath = @"strokeStart";
    endHeadAnimation.beginTime = TPSpinnerInterval;
    endHeadAnimation.duration = TPSpinnerInterval;
    endHeadAnimation.fromValue = @.25;
    endHeadAnimation.toValue = @1;
    
    CABasicAnimation *endTailAnimation = [CABasicAnimation animation];
    endTailAnimation.keyPath = @"strokeEnd";
    endTailAnimation.beginTime = TPSpinnerInterval;
    endTailAnimation.duration = TPSpinnerInterval;
    endTailAnimation.fromValue = @1;
    endTailAnimation.toValue = @1;
    
    CAAnimationGroup *animations = [CAAnimationGroup animation];
    animations.duration = TPSpinnerInterval*2;
    animations.animations = @[
                              rotateAnimation,
                              headAnimation,
                              tailAnimation,
                              endHeadAnimation,
                              endTailAnimation
                              ];
    animations.repeatCount = INFINITY;
    
    [spinnerLayer addAnimation:animations forKey:@"animations"];
}

@end
