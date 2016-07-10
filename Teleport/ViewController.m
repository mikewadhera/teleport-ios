
@import AVFoundation;
@import CoreLocation;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"
#import "PreviewViewController.h"
#import "TPGeocoder.h"
#import "RecordTimer.h"
#import "JPSVolumeButtonHandler.h"
#import "TPUploadSession.h"

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
    TPStateRecordingCompleted,
    TPStateRecordingCanceling,
    TPStateRecordingCanceled
};
typedef void (^ AssertFromBlock)(TPState);

// Constants
static const AVCaptureDevicePosition TPViewportTopCamera                = AVCaptureDevicePositionFront;
static const AVCaptureDevicePosition TPViewportBottomCamera             = AVCaptureDevicePositionBack;
static const TPViewport              TPRecordFirstViewport              = TPViewportTop;
static const TPViewport              TPRecordSecondViewport             = TPViewportBottom;
static const NSTimeInterval          TPPreviewFadeInInterval            = 1.0;
static const NSTimeInterval          TPRecordFirstInterval              = 3.5;
static const NSTimeInterval          TPRecordSecondInterval             = TPRecordFirstInterval;
static const NSTimeInterval          TPRecordSecondGraceInterval        = TPPreviewFadeInInterval;
static const NSTimeInterval          TPRecordSecondGraceOpacity         = 0.9;
static const NSInteger               TPRecordBitrate                    = 7000000;
static const NSTimeInterval          TPProgressBarEarlyEndInterval      = 0.15;
#define                              TPProgressBarWidth                 floorf((self.bounds.size.width*0.05))
#define                              TPProgressBarTrackColor            [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:0.5]
#define                              TPProgressBarTrackHighlightColor   [UIColor redColor]
static const BOOL                    TPProgressBarTrackShouldHide       = YES;
#define                              TPProgressBarColor                 [UIColor redColor]
static const CGFloat                 TPSpinnerBarWidth                  = 5.0f;
#define                              TPSpinnerRadius                    sqrt(hypotf(bounds.size.width, bounds.size.height))*3.0
static const NSTimeInterval          TPSpinnerInterval                  = 0.3f;
#define                              TPSpinnerBarColor                  [UIColor colorWithWhite:0 alpha:0.25]
#define                              TPLocationAccuracy                 kCLLocationAccuracyBestForNavigation
static const CLLocationDistance      TPLocationDistanceFilter           = 100;
// Constants

// For debugging
#define stateFor(enum) [@[@"SessionStopped",@"SessionStopping",@"SessionStarting",@"SessionStarted",@"SessionConfigurationFailed",@"RecordingIdle",@"RecordingStarted",@"RecordingFirstStarting",@"RecordingFirstStarted",@"RecordingFirstCompleting",@"RecordingFirstCompleted",@"SessionConfigurationUpdated",@"RecordingSecondStarting",@"RecordingSecondStarted",@"RecordingSecondCompleting",@"RecordingSecondCompleted",@"RecordingCompleted",@"RecordingCanceling",@"RecordingCanceled"] objectAtIndex:enum]

@protocol RecordProgressBarViewDelegate <NSObject>

- (void)recordProgressBarViewTap;

@end

@interface RecordProgressBarView : UIView

@property (nonatomic, weak) id<RecordProgressBarViewDelegate> delegate;

-(void)reset;
-(void)start;
-(void)resume;
-(void)cancel;

@end

@interface ViewController () <IDCaptureSessionCoordinatorDelegate, CLLocationManagerDelegate, RecordProgressBarViewDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastKnownLocation;
@property (nonatomic) NSArray *lastKnownPlacemarks;
@property (nonatomic) TPGeocoder *geocoder;

@property (nonatomic) TPState status;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) RecordProgressBarView *recordBarView;
@property (nonatomic, copy) NSURL *firstVideoURL;
@property (nonatomic, copy) NSURL *secondVideoURL;
@property (nonatomic) CALayer *secondRecordingVisualCueLayer;
@property (nonatomic) CAShapeLayer *secondRecordingVisualCueSpinnerLayer;
@property (nonatomic, strong) TPUploadSession *uploadSession;

@end

@implementation ViewController
{
    CGRect topViewportRect;
    CGRect bottomViewportRect;
    BOOL sessionConfigurationFailed;
    RecordTimer *firstRecordingStopTimer;
    RecordTimer *secondRecordingStartTimer;
    RecordTimer *secondRecordingStopTimer;
    JPSVolumeButtonHandler *volumeHandler;
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
    _sessionCoordinator = [[IDCaptureSessionAssetWriterCoordinator alloc] initWithDevicePosition:[self cameraForViewport:TPRecordFirstViewport]];
    [_sessionCoordinator setDelegate:self callbackQueue:dispatch_get_main_queue()];
    
    // Create the preview
    _previewLayer = _sessionCoordinator.previewLayer;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    
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
    
    // Second Recording Visual Cue
    _secondRecordingVisualCueLayer = [CALayer layer];
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
    
    // Record Bar
    _recordBarView = [[RecordProgressBarView alloc] initWithFrame:self.view.bounds];
    _recordBarView.delegate = self;
    
    [self.view.layer insertSublayer:_previewLayer atIndex:0];
    [self.view.layer insertSublayer:_firstPlayerLayer atIndex:1];
    [self.view.layer insertSublayer:_secondRecordingVisualCueLayer atIndex:2];
    [self.view addSubview:_recordBarView];
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
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    if (sessionConfigurationFailed) {
        [self showCameraCaptureErrorDialog];
    }
    
    switch ( _setupResult )
    {
        case TPCameraSetupResultSuccess:
        {
            // Volume Handler
            volumeHandler = [JPSVolumeButtonHandler volumeButtonHandlerWithUpBlock:^{
                [self toggleRecording];
            } downBlock:^{
                [self toggleRecording];
            }];
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
    
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    if ( _setupResult == TPCameraSetupResultSuccess ) {
        @synchronized (self) {
            volumeHandler = nil;
            [self transitionToStatus:TPStateSessionStopping];
        }
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
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

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    PreviewViewController *vc = [segue destinationViewController];
    vc.firstVideoURL = _firstVideoURL;
    vc.secondVideoURL = _secondVideoURL;
    vc.location = _lastKnownLocation;
    vc.placemarks = _lastKnownPlacemarks;
}

-(void)reset
{
    // Set initial frames and view states
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_firstPlayerLayer setFrame:CGRectZero]; // Off-screen
    [_previewLayer setFrame:[self frameForViewport:TPRecordFirstViewport]];
    [_secondRecordingVisualCueLayer setFrame:[self frameForViewport:TPRecordSecondViewport]];
    [_recordBarView reset];
    [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
    [_secondRecordingVisualCueLayer removeAllAnimations];
    [_secondRecordingVisualCueLayer setHidden:NO];
    [_secondRecordingVisualCueLayer setOpacity:1.0];
    [_secondRecordingVisualCueLayer setBackgroundColor:[UIColor blackColor].CGColor];
    _secondRecordingVisualCueSpinnerLayer.strokeColor = TPSpinnerBarColor.CGColor;
    _secondRecordingVisualCueSpinnerLayer.strokeStart = 0;
    _secondRecordingVisualCueSpinnerLayer.strokeEnd = 0;
    [CATransaction commit];
    
    // Clear player and enable preview
    [_firstPlayer replaceCurrentItemWithPlayerItem:nil];
    [_sessionCoordinator.previewLayer.connection setEnabled:YES];
    
    // Reset record bar
    [_recordBarView reset];
    
    // Fade-in preview
    _previewLayer.opacity = 0.0;
    // Switch camera if needed
    if (_sessionCoordinator.devicePosition != [self cameraForViewport:TPRecordFirstViewport]) {
        [_sessionCoordinator setDevicePosition:[self cameraForViewport:TPRecordFirstViewport]];
    }
    [CATransaction begin];
    [CATransaction setAnimationDuration:1.0f];
    _previewLayer.opacity = 1.0;
    [CATransaction commit];
}

-(BOOL)cancelRecording
{
    [self stopTimers];
    [_recordBarView cancel];
    [_firstPlayer pause];
    [_sessionCoordinator.previewLayer.connection setEnabled:NO];
    return [_sessionCoordinator stopRecording];
}

-(void)toggleRecording
{
    if (_status == TPStateRecordingIdle) {
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingFirstStarting];
        }
    } else {
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingCanceling];
        }
    }
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
            
            // Initialize session-owned state
            // Note: We never clear these on stop so we can reference in cleanup code
            _lastKnownLocation = nil;
            _lastKnownPlacemarks = nil;
            _firstVideoURL = nil;
            _secondVideoURL = nil;
            
            // Set initial views
            [self reset];
            
            // Start polling
            [_locationManager startUpdatingLocation];
            
            // Disable recording
            [_recordBarView setUserInteractionEnabled:NO];
            
            // Start session
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            // Cancel recording
            [self cancelRecording];
            
            // Stop polling
            [_locationManager stopUpdatingLocation];
            
            // Stop session
            [_sessionCoordinator stopRunning];
            
        } else if (newStatus == TPStateSessionConfigurationFailed) {
            
            sessionConfigurationFailed = YES; // checked in viewWillAppear
        
        } else if (newStatus == TPStateSessionStarted) {
            
            // Enable recording
            [_recordBarView setUserInteractionEnabled:YES];
            
            [self transitionToStatus:TPStateRecordingIdle];
            
        } else if (newStatus == TPStateRecordingFirstStarting) {
            
            assertFrom(TPStateRecordingIdle);
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingFirstStarted) {
            
            [_recordBarView start];
            [self startSecondRecordingVisualCue];
            firstRecordingStopTimer = [RecordTimer scheduleTimerWithTimeInterval:TPRecordFirstInterval block:^{
                @synchronized (self) {
                    [self transitionToStatus:TPStateRecordingFirstCompleting];
                }
            }];
            
        } else if (newStatus == TPStateRecordingFirstCompleting) {
            
            assertFrom(TPStateRecordingFirstStarted);
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingFirstCompleted) {
            
            assertFrom(TPStateRecordingFirstCompleting);
            [self transitionToStatus:TPStateSessionConfigurationUpdated];
            
        } else if (newStatus == TPStateSessionConfigurationUpdated) {
            
            // Vibrate
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            
            // Disable layer setFrame animations
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            
            // Load and show first recording
            [_firstPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem
                                                            playerItemWithAsset:[AVAsset
                                                                                 assetWithURL:_firstVideoURL]]];
            [_firstPlayer seekToTime:kCMTimeZero];
            [_firstPlayerLayer setFrame:[self frameForViewport:TPRecordFirstViewport]];
            
            // Switch camera configuration
            // Note: -setDevicePosition is long running
            [_sessionCoordinator setDevicePosition:[self cameraForViewport:TPRecordSecondViewport]];
            
            // Show new camera's preview
            [_sessionCoordinator.previewLayer.connection setEnabled:YES];
            [_previewLayer setFrame:[self frameForViewport:TPRecordSecondViewport]];
            
            [CATransaction commit];
            
            // Enter Grace period
            // Set camera preview barely visible
            [_secondRecordingVisualCueLayer setOpacity:TPRecordSecondGraceOpacity];
            secondRecordingStartTimer = [RecordTimer scheduleTimerWithTimeInterval:TPRecordSecondGraceInterval block: ^{
                // Exit Grace period
                // Show new camera preview, start first clip,
                // continue progress bar and transition to recording
                [_secondRecordingVisualCueLayer setHidden:YES];
                [_firstPlayer play];
                [_recordBarView resume];
                @synchronized (self) {
                    [self transitionToStatus:TPStateRecordingSecondStarting];
                }
            }];
            
        } else if (newStatus == TPStateRecordingSecondStarting) {
            
            assertFrom(TPStateSessionConfigurationUpdated);
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingSecondStarted) {
            
            secondRecordingStopTimer = [RecordTimer scheduleTimerWithTimeInterval:TPRecordSecondInterval block:^{
                @synchronized (self) {
                    [self transitionToStatus:TPStateRecordingSecondCompleting];
                }
            }];
            
        } else if (newStatus == TPStateRecordingSecondCompleting) {
            
            assertFrom(TPStateRecordingSecondStarted);
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingSecondCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleting);
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleted);
            [self performSegueWithIdentifier:@"ShowPreview" sender:self];

        } else if (newStatus == TPStateRecordingCanceling) {
            
            BOOL anyRecorded = [self cancelRecording];
            [self reset];
            // Cleanup first canceled recording (if any)
            // We wait to do this after -reset as player shows file
            if (_firstVideoURL) [[NSFileManager defaultManager] removeItemAtPath:[_firstVideoURL path] error:nil];
            
            // Check if -cancelRecording returned NO, if so we are responsible for transitioning to Canceled
            // In the normal case we are transitioned to Canceled by coordinator's didFinishRecordingToOutputFileURL
            // which gets call backed after the canceled in-flight recording finishes
            if (!anyRecorded) {
                [self transitionToStatus:TPStateRecordingCanceled];
            }
        
        } else if (newStatus == TPStateRecordingCanceled) {
            
            assertFrom(TPStateRecordingCanceling);
            [self transitionToStatus:TPStateRecordingIdle];
            
        }
    }
}

-(void)stopTimers
{
    [firstRecordingStopTimer invalidate];
    [secondRecordingStartTimer invalidate];
    [secondRecordingStopTimer invalidate];
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

#pragma mark = RecordProgressBarViewDelegate methods

- (void)recordProgressBarViewTap
{
    [self toggleRecording];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    if (flag) [_sessionCoordinator.previewLayer.connection setEnabled:NO]; // Freeze preview
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
//              AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
              AVVideoCompressionPropertiesKey : @{ AVVideoAverageBitRateKey : @(TPRecordBitrate),
                                                       AVVideoExpectedSourceFrameRateKey : @(60),
                                                       AVVideoMaxKeyFrameIntervalKey : @(60),
                                                        AVVideoAllowFrameReorderingKey : @YES }

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
    } else {
        // Assume rogue recording - cancel
        @synchronized (self) {
            [self transitionToStatus:TPStateRecordingCanceling];
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
        } else if (_status == TPStateRecordingCanceling) {
            // Cleanup current canceled recording
            [[NSFileManager defaultManager] removeItemAtPath:[outputFileURL path] error:nil];
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingCanceled];
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

#pragma mark Helpers

-(CGRect)frameForViewport:(TPViewport)viewport
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
    return targetFrame;
}

-(AVCaptureDevicePosition)cameraForViewport:(TPViewport)viewport
{
    AVCaptureDevicePosition targetCamera;
    switch (viewport)
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
    return targetCamera;
}

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

@implementation RecordProgressBarView
{
    CAShapeLayer *progressBarLayer;
    CAShapeLayer *progressBarTrackLayer;
    UITapGestureRecognizer *tapRecognizer;
}

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        progressBarLayer = [CAShapeLayer layer];
        [self.layer insertSublayer:progressBarLayer atIndex:1];
        [progressBarLayer setStrokeColor:TPProgressBarColor.CGColor];
        [progressBarLayer setLineWidth:TPProgressBarWidth];
        [progressBarLayer setFillColor:[UIColor clearColor].CGColor];
        UIBezierPath *path = [UIBezierPath bezierPath];
        CGSize screenSize = frame.size;
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
        progressBarLayer.path = path.CGPath;
        progressBarTrackLayer = [CAShapeLayer layer];
        [self.layer insertSublayer:progressBarTrackLayer atIndex:0];
        [progressBarTrackLayer setStrokeColor:TPProgressBarTrackColor.CGColor];
        [progressBarTrackLayer setLineWidth:TPProgressBarWidth];
        [progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
        progressBarTrackLayer.path = progressBarLayer.path;
        tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectRecord:)];
        [self addGestureRecognizer:tapRecognizer];
        [self reset];
    }
    return self;
}

-(void)reset
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [progressBarTrackLayer setHidden:NO];
    [progressBarLayer setHidden:YES];
    [progressBarLayer setStrokeEnd:1.0];
    [CATransaction commit];
}

-(void)animateStrokeFrom:(CGFloat)fromValue to:(CGFloat)toValue duration:(NSTimeInterval)duration
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.delegate = self.delegate;
    animation.fromValue = [NSNumber numberWithFloat:fromValue];
    progressBarLayer.strokeEnd = toValue;
    animation.toValue = [NSNumber numberWithFloat:toValue];
    animation.duration = duration;
    progressBarLayer.speed = 1.0;
    progressBarLayer.timeOffset = 0.0;
    progressBarLayer.beginTime = 0.0;
    [progressBarLayer addAnimation:animation forKey:nil];
}

-(void)start
{
    [progressBarTrackLayer setHidden:TPProgressBarTrackShouldHide];
    [progressBarLayer setHidden:NO];
    [self animateStrokeFrom:1.0 to:0.5 duration:TPRecordFirstInterval-TPProgressBarEarlyEndInterval];
}

-(void)resume
{
    [self animateStrokeFrom:0.5 to:0.0 duration:TPRecordSecondInterval-TPProgressBarEarlyEndInterval];
}

-(void)cancel
{
    progressBarLayer.speed = 0.0;
    [progressBarLayer removeAllAnimations];
    [self reset];
}

-(void)didSelectRecord:(id)sender
{
    [self.delegate recordProgressBarViewTap];
}

@end
