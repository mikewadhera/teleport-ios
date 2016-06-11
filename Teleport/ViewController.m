
@import AVFoundation;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"

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
static const AVCaptureDevicePosition TPViewportTopCamera        = AVCaptureDevicePositionFront;
static const AVCaptureDevicePosition TPViewportBottomCamera     = AVCaptureDevicePositionBack;
static const TPViewport TPRecordFirstViewport                   = TPViewportTop;
static const TPViewport TPRecordSecondViewport                  = TPViewportBottom;
static const NSTimeInterval TPRecordFirstInterval               = 5;
static const NSTimeInterval TPRecordSecondInterval              = TPRecordFirstInterval;
static const NSInteger TPEncodeWidth                            = 376;
static const NSInteger TPEncodeHeight                           = TPEncodeWidth;
static const CGFloat TPProgressBarWidth                         = 20.0f;
static const CGFloat TPSpinnerBarWidth                          = 4.0f;
static const CGFloat TPSpinnerDuration                          = 0.3f;
// Constants

@interface ViewController () <IDCaptureSessionCoordinatorDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;

@property (nonatomic) TPState status;
@property (nonatomic) UIButton *recordButton;
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
    
    // Check camera access
    [self checkCameraAuth];
    
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
    
    // Record Button
    int recordButtonW = 44;
    int recordButtonH = 44;
    int recordButtonX = 0;
    int recordButtonY = 0;
    _recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _recordButton.frame = CGRectMake(recordButtonX, recordButtonY, recordButtonW, recordButtonH);
    _recordButton.center = [self.view convertPoint:self.view.center fromView:self.view.superview];
    _recordButton.layer.cornerRadius = 0.5 * recordButtonW;
    _recordButton.clipsToBounds = YES;
    [_recordButton setImage:[UIImage imageNamed:@"record.png"] forState:UIControlStateNormal];
    [_recordButton addTarget:self action:@selector(didTapRecord:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_recordButton];
    
    // Player
    [self.view.layer insertSublayer:_firstPlayerLayer atIndex:0];
    [self moveLayer:_firstPlayerLayer to:TPRecordFirstViewport];
    
    // Preview
    [_previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.view.layer insertSublayer:_previewLayer atIndex:1];
    [self moveLayer:_previewLayer to:TPRecordFirstViewport];
    
    // Progress Bar
    _progressBarLayer = [CAShapeLayer layer];
    [self.view.layer insertSublayer:_progressBarLayer atIndex:4];
    [_progressBarLayer setStrokeColor:[UIColor redColor].CGColor];
    [_progressBarLayer setLineWidth:TPProgressBarWidth];
    [_progressBarLayer setFillColor:[UIColor clearColor].CGColor];
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.view.bounds];
    _progressBarLayer.path = path.CGPath;
    _progressBarTrackLayer = [CAShapeLayer layer];
    [self.view.layer insertSublayer:_progressBarTrackLayer atIndex:3];
    [_progressBarTrackLayer setStrokeColor:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.0].CGColor];
    [_progressBarTrackLayer setLineWidth:TPProgressBarWidth];
    [_progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
    _progressBarTrackLayer.path = _progressBarLayer.path;
    
    // Second Recording Visual Cue
    _secondRecordingVisualCueLayer = [CALayer layer];
    [self.view.layer insertSublayer:_secondRecordingVisualCueLayer atIndex:2];
    [_secondRecordingVisualCueLayer setBackgroundColor:[UIColor blackColor].CGColor];
    [self moveLayer:_secondRecordingVisualCueLayer to:TPRecordSecondViewport];
    _secondRecordingVisualCueSpinnerLayer = [CAShapeLayer layer];
    [_secondRecordingVisualCueLayer addSublayer:_secondRecordingVisualCueSpinnerLayer];
    _secondRecordingVisualCueSpinnerLayer.lineWidth = TPSpinnerBarWidth;
    _secondRecordingVisualCueSpinnerLayer.fillColor = nil;
    _secondRecordingVisualCueSpinnerLayer.strokeColor = [UIColor colorWithWhite:0.0 alpha:0.33].CGColor;
    CGRect bounds = _secondRecordingVisualCueLayer.bounds;
    CGPoint center = CGPointMake(bounds.size.width/2, bounds.size.height/2);
    CGFloat radius = 44;
    CGFloat startAngle = -M_PI_2;
    CGFloat endAngle = startAngle + (M_PI*2);
    UIBezierPath *spinPath = [UIBezierPath bezierPathWithArcCenter:CGPointZero radius:radius startAngle:startAngle endAngle:endAngle clockwise:true];
    _secondRecordingVisualCueSpinnerLayer.path = spinPath.CGPath;
    _secondRecordingVisualCueSpinnerLayer.position = center;
    [_secondRecordingVisualCueSpinnerLayer setHidden:YES];
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

-(void)checkCameraAuth
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
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    _setupResult = TPCameraSetupResultCameraNotAuthorized;
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

-(void)didTapRecord:(id)button
{
    [self transitionToStatus:TPStateRecordingFirstStarting];
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
            
            [self hideProgressBar];
            _recordButton.enabled = NO;
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            [self hideProgressBar];
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            _recordButton.enabled = NO;
            [_sessionCoordinator stopRunning];
            
        } else if (newStatus == TPStateSessionConfigurationFailed) {
            
            _recordButton.enabled = NO;
            sessionConfigurationFailed = YES; // checked in viewWillAppear
        
        } else if (newStatus == TPStateSessionStarted) {
            
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            _recordButton.enabled = YES;
            [self transitionToStatus:TPStateRecordingIdle];
            
        } else if (newStatus == TPStateRecordingFirstStarting) {
            
            assertFrom(TPStateRecordingIdle);
            _recordButton.hidden = YES;
            [self startRecordVisualCue];
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
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_firstVideoURL];
            [_firstPlayer replaceCurrentItemWithPlayerItem:item];
            [self transitionToStatus:TPStateSessionConfigurationUpdated];
            
        } else if (newStatus == TPStateSessionConfigurationUpdated) {
            
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
            [self transitionToStatus:TPStateRecordingSecondStarting];
            
        } else if (newStatus == TPStateRecordingSecondStarting) {
            
            assertFrom(TPStateSessionConfigurationUpdated);
            [self moveLayer:_previewLayer to:TPRecordSecondViewport];
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
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingSecondCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleting);
            [self resumeProgressBar];
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleted);
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [self hideProgressBar];
            [self transitionToStatus:TPStateRecordingIdle];

        }
    }
}

-(void)transitionToStatus:(TPState)newStatus after:(NSTimeInterval)delay
{
    [self performBlock:^{
        [self transitionToStatus:newStatus];
    } afterDelay:TPRecordFirstInterval];
}

-(void)startRecordVisualCue
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = [NSNumber numberWithFloat:0.0f];
    animation.toValue = [NSNumber numberWithFloat:1.0f];
    animation.duration = 0.3;
    [_progressBarTrackLayer addAnimation:animation forKey:@"myOpacity"];
}

-(void)startSecondRecordingVisualCue
{
    CABasicAnimation *anime = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    anime.fromValue = (id)[_secondRecordingVisualCueLayer backgroundColor];
    _secondRecordingVisualCueLayer.backgroundColor = [UIColor whiteColor].CGColor;
    anime.toValue = (id)[UIColor whiteColor].CGColor;
    anime.duration = TPRecordFirstInterval;
    //anime.autoreverses = YES;
    [_secondRecordingVisualCueLayer addAnimation:anime forKey:@"myColor"];
}

-(void)startProgressBar
{
    [_progressBarTrackLayer setHidden:NO];
    [_progressBarLayer setHidden:NO];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = [NSNumber numberWithFloat:0.0f];
    animation.toValue = [NSNumber numberWithFloat:1.0f];
    animation.duration = TPRecordFirstInterval + TPRecordSecondInterval;
    [_progressBarLayer addAnimation:animation forKey:@"myStroke"];
}

-(void)pauseProgressBar
{
    CFTimeInterval pausedTime = [_progressBarLayer convertTime:CACurrentMediaTime() fromLayer:nil];
    _progressBarLayer.speed = 0.0;
    _progressBarLayer.timeOffset = pausedTime;
}

-(void)hideProgressBar
{
    [_progressBarLayer setHidden:YES];
    [_progressBarTrackLayer setHidden:YES];
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
    return [NSDictionary dictionaryWithObjectsAndKeys:
            AVVideoCodecH264, AVVideoCodecKey,
            [NSNumber numberWithInt:TPEncodeWidth], AVVideoWidthKey,
            [NSNumber numberWithInt:TPEncodeHeight], AVVideoHeightKey,
            AVVideoScalingModeResizeAspectFill,AVVideoScalingModeKey,
            nil];
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
