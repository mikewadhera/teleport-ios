
@import AVFoundation;
@import CoreLocation;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"
#import "PreviewViewController.h"
#import "TPGeocoder.h"
#import "RecordTimer.h"
#import "JPSVolumeButtonHandler.h"
#import "TPUploadSession.h"
#import "Teleport-Swift.h"
#import "ListViewController.h"
#import "FRDLivelyButton.h"
#import "Teleport.h"

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
static const AVCaptureDevicePosition TPViewportTopCamera                = AVCaptureDevicePositionBack;
static const AVCaptureDevicePosition TPViewportBottomCamera             = AVCaptureDevicePositionFront;
static const TPViewport              TPRecordFirstViewport              = TPViewportTop;
static const TPViewport              TPRecordSecondViewport             = TPViewportBottom;
static const NSTimeInterval          TPRecordFirstInterval              = 5.0;
static const NSTimeInterval          TPRecordSecondInterval             = TPRecordFirstInterval;
static const NSTimeInterval          TPRecordSecondGraceInterval        = 1.0;
static const NSTimeInterval          TPRecordSecondGraceOpacity         = 0.9;
static const NSInteger               TPRecordBitrate                    = 6000000;
static const NSInteger               TPRecordFramerate                  = 60;
static const NSTimeInterval          TPProgressBarEarlyEndInterval      = 0.15;
#define                              TPProgressBarWidth                 floorf((self.bounds.size.width*0.09))
#define                              TPProgressBarTrackColor            [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:0.33]
#define                              TPProgressBarTrackHighlightColor   [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:1]
static const BOOL                    TPProgressBarTrackShouldHide       = NO;
#define                              TPProgressBarColor                 [UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:1]
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
-(CGFloat)barWidth;

@end

@interface ViewController () <IDCaptureSessionCoordinatorDelegate, CLLocationManagerDelegate, RecordProgressBarViewDelegate, UINavigationControllerDelegate, EasyTransitionDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic) TPGeocoder *geocoder;

@property (nonatomic) TPState status;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) RecordProgressBarView *recordBarView;
@property (nonatomic) CALayer *secondRecordingVisualCueLayer;
@property (nonatomic, strong) TPUploadSession *uploadSession;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) EasyTransition *transition;
@property (nonatomic, strong) Teleport *teleport;

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
    NSTimer *statusLabelTimer;
    FRDLivelyButton *button;
    UINavigationController *menuNavController;
    ListViewController *menuController;
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
    _previewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    _previewLayer.transform = CATransform3DMakeRotation(90.0 / 180.0 * M_PI, 0.0, 0.0, 1.0);
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
    
    // Visual Cues
    _secondRecordingVisualCueLayer = [CALayer layer];
    
    // Record Bar
    _recordBarView = [[RecordProgressBarView alloc] initWithFrame:self.view.bounds];
    _recordBarView.delegate = self;
    
    // Status Label
    CGFloat barWidth = [_recordBarView barWidth];
    CGFloat barPadding = 10;
    CGFloat labelHeight = 10;
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(barWidth+barPadding,
                                                             self.view.bounds.size.height - barWidth - barPadding - labelHeight,
                                                             self.view.bounds.size.width - (2*barWidth)-barPadding,
                                                             labelHeight)];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.font = [UIFont systemFontOfSize:13.5];
    
    [self.view.layer insertSublayer:_previewLayer atIndex:0];
    [self.view.layer insertSublayer:_firstPlayerLayer atIndex:1];
    [self.view.layer insertSublayer:_secondRecordingVisualCueLayer atIndex:2];
    [self.view addSubview:_recordBarView];
    [self.view addSubview:_statusLabel];
    
    // Menu
    menuNavController = [self.storyboard instantiateViewControllerWithIdentifier:@"menu"];
    menuNavController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    menuNavController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    menuController = [[menuNavController viewControllers] firstObject];
    
    // Button
    NSInteger buttonSize = 44;
    button = [[FRDLivelyButton alloc] initWithFrame:CGRectMake(self.view.bounds.size.width-barWidth-barPadding-buttonSize,
                                                               self.view.bounds.size.height-barWidth-barPadding-buttonSize+8,
                                                               buttonSize,
                                                               buttonSize)];
    [button setStyle:kFRDLivelyButtonStyleHamburger animated:NO];
    [button setOptions:@{ kFRDLivelyButtonLineWidth: @(3.0f),
                          kFRDLivelyButtonHighlightedColor: [UIColor colorWithWhite:0.8 alpha:1.0],
                          kFRDLivelyButtonColor: [UIColor darkGrayColor]
                          }];
    [button addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
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
    
    // Update status lable on minute change
    [self addStatusLabelMinuteChangeTimer];
    
    // We don't observe resign-to-background as that behavior is implicity handled by coordinatorSessionDidInterrupt:
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerResumedFromBackground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [button setHidden:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    if ( _setupResult == TPCameraSetupResultSuccess ) {
        @synchronized (self) {
            [self transitionToStatus:TPStateSessionStopping];
        }
    }
    
    [statusLabelTimer invalidate];
    
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

-(void)addVolumeHandler
{
    volumeHandler = [JPSVolumeButtonHandler volumeButtonHandlerWithUpBlock:^{
        [self toggleRecording];
    } downBlock:^{
        [self toggleRecording];
    }];
}


-(void)removeVolumeHandler
{
    volumeHandler = nil;
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    PreviewViewController *vc = [segue destinationViewController];
    vc.teleport = _teleport;
    vc.menuEnabled = YES;
    vc.onAdvanceHandler = ^{
        [self openMenuAnimated:NO completion:^{
            [menuController.tableView reloadData];
        }];
    };
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
    [_secondRecordingVisualCueLayer removeAllAnimations];
    [_secondRecordingVisualCueLayer setHidden:NO];
    [_secondRecordingVisualCueLayer setOpacity:1.0];
    [_secondRecordingVisualCueLayer setBackgroundColor:[UIColor blackColor].CGColor];
    _statusLabel.hidden = NO;
    _statusLabel.text = nil;
    [self updateStatusLabel];
    button.hidden = NO;
    [CATransaction commit];
    
    // Clear player and enable preview
    [_firstPlayer replaceCurrentItemWithPlayerItem:nil];
    [_sessionCoordinator.previewLayer.connection setEnabled:YES];
    
    // Reset record bar
    [_recordBarView reset];
    
    // Switch camera if needed
    if (_sessionCoordinator.devicePosition != [self cameraForViewport:TPRecordFirstViewport]) {
        [_sessionCoordinator setDevicePosition:[self cameraForViewport:TPRecordFirstViewport]];
    }
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

-(void)openMenu
{
    [self openMenuAnimated:YES completion:nil];
}

-(void)openMenuAnimated:(BOOL)animated completion:(dispatch_block_t)completion
{
    // Manually add/remove volume handler since we don't tear down session
    [self removeVolumeHandler];
    __block typeof(self) weakSelf = self;
    menuController.onDismissHandler = ^{
        [weakSelf addVolumeHandler];
    };
    [self presentViewController:menuNavController animated:animated completion:completion];
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
            
            // New teleport
            _teleport = [Teleport new];
            _teleport.id = [[NSUUID UUID] UUIDString];
            
            // Set initial views
            [self reset];
            
            // Start polling
            [_locationManager startUpdatingLocation];
            
            // Add volume handler
            [self addVolumeHandler];
            
            // Start session
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            // Cancel recording
            [self cancelRecording];
            
            // Stop polling
            [_locationManager stopUpdatingLocation];
            
            // Remove volume handler
            [self removeVolumeHandler];
            
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
            
            // Record Timestamp
            _teleport.timestamp = [NSDate date];
            
            // Start recording
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingFirstStarted) {
            
            [button setHidden:YES];
            [_statusLabel setHidden:YES];
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
            NSURL *firstVideoURL = [NSURL fileURLWithPath:[_teleport pathForVideo1]];
            [_firstPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem
                                                            playerItemWithAsset:[AVAsset assetWithURL:firstVideoURL]]];
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
            // Cleanup first canceled recording cache (if any)
            // We wait to do this after -reset as player shows file
            [Teleport cleanupCaches:_teleport];
            
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
    anime.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    //anime.autoreverses = YES;
    [_secondRecordingVisualCueLayer addAnimation:anime forKey:@"myColor"];
}

-(void)updateStatusLabel
{
    NSString *time;
    NSDateFormatter *dateformater = [[NSDateFormatter alloc] init];
    [dateformater setDateFormat:@"h:mm a"];
    time = [dateformater stringFromDate:[NSDate date]];
    if (_teleport.location) {
        BOOL animate = NO;
        if (_statusLabel.text == nil) {
            animate = YES;
        }
        _statusLabel.text = [NSString stringWithFormat:@"%@ • %@", _teleport.location, time];
        if (animate) {
            _statusLabel.alpha = 0.0;
            [UIView animateWithDuration:0.25 animations:^{
                _statusLabel.alpha = 1.0;
            }];
        }
    }
}

-(void)addStatusLabelMinuteChangeTimer
{
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *components = [calendar components:NSSecondCalendarUnit fromDate:[NSDate date]];
    NSInteger currentSecond = [components second];
    
    //+1 to ensure we fire right after the minute change
    NSDate *fireDate = [[NSDate date] dateByAddingTimeInterval:60 - currentSecond + 1];
    statusLabelTimer = [[NSTimer alloc] initWithFireDate:fireDate
                                               interval:60
                                                 target:self
                                               selector:@selector(updateStatusLabel)
                                               userInfo:nil
                                                repeats:YES];
    
    [[NSRunLoop mainRunLoop] addTimer:statusLabelTimer forMode:NSDefaultRunLoopMode];
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
                                                       AVVideoExpectedSourceFrameRateKey : @(TPRecordFramerate),
                                                       AVVideoMaxKeyFrameIntervalKey : @(TPRecordFramerate),
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
        // Cache then cleanup recording
        dispatch_block_t cleanup = ^{
            [[NSFileManager defaultManager] removeItemAtPath:[outputFileURL path] error:nil];
        };
        if (_status == TPStateRecordingFirstCompleting) {
            [Teleport cacheVideo1:_teleport URL:outputFileURL];
            cleanup();
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingFirstCompleted];
            }
        } else if (_status == TPStateRecordingSecondCompleting) {
            [Teleport cacheVideo2:_teleport URL:outputFileURL];
            cleanup();
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingSecondCompleted];
            }
        } else if (_status == TPStateRecordingCanceling) {
            cleanup();
            @synchronized (self) {
                [self transitionToStatus:TPStateRecordingCanceled];
            }
        }
    }
}

#pragma mark = EasyTransitionDelegate methods

-(void)transitionWillDismiss
{
    
}

#pragma mark = CLLocationManager methods

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    _teleport.latitude = newLocation.coordinate.latitude;
    _teleport.longitude = newLocation.coordinate.longitude;
    NSLog(@"NewLocation %f %f", newLocation.coordinate.latitude, newLocation.coordinate.longitude);
    [_geocoder reverseGeocode:newLocation completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to reverse geocode: %f %f", newLocation.coordinate.latitude, newLocation.coordinate.longitude);
        }
        CLPlacemark *firstPlacemark = [placemarks firstObject];
        NSString *location;
        location = [firstPlacemark subLocality];
        _teleport.location = location;
        [self updateStatusLabel];
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
        [path addLineToPoint:pointB];
        [path addLineToPoint:pointC];
        [path addLineToPoint:pointD];
        [path addLineToPoint:pointE];
        [path addLineToPoint:pointA];
        progressBarLayer.path = path.CGPath;
        progressBarTrackLayer = [CAShapeLayer layer];
        [self.layer insertSublayer:progressBarTrackLayer atIndex:0];
        [progressBarTrackLayer setStrokeColor:TPProgressBarTrackColor.CGColor];
        [progressBarTrackLayer setLineWidth:TPProgressBarWidth];
        [progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
        progressBarTrackLayer.path = progressBarLayer.path;
        tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectRecord:)];
        //[self addGestureRecognizer:tapRecognizer];
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
    [progressBarLayer setStrokeStart:0.0];
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
    [progressBarLayer setHidden:NO];
    [progressBarTrackLayer setHidden:TPProgressBarTrackShouldHide];
    [self animateStrokeFrom:0.0 to:0.5 duration:TPRecordFirstInterval-TPProgressBarEarlyEndInterval];
}

-(void)resume
{
    [self animateStrokeFrom:0.5 to:1.0 duration:TPRecordSecondInterval-TPProgressBarEarlyEndInterval];
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

-(CGFloat)barWidth
{
    return progressBarLayer.lineWidth;
}

@end
