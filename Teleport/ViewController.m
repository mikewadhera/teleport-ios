
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
    TPStateRecordingSecondStarting,
    TPStateRecordingSecondStarted,
    TPStateRecordingSecondCompleting,
    TPStateRecordingSecondCompleted,
    TPStateRecordingCompleted
};
typedef void (^ AssertFromBlock)(TPState);

// For debugging
#define stateFor(enum) [@[@"SessionStopped",@"SessionStopping",@"SessionStarting",@"SessionStarted",@"SessionConfigurationFailed",@"RecordingIdle",@"RecordingStarted",@"RecordingFirstStarting",@"RecordingFirstStarted",@"RecordingFirstCompleting",@"RecordingFirstCompleted",@"RecordingSecondStarting",@"RecordingSecondStarted",@"RecordingSecondCompleting",@"RecordingSecondCompleted",@"RecordingCompleted"] objectAtIndex:enum]

// Constants
static const AVCaptureDevicePosition TPViewportTopCamera        = AVCaptureDevicePositionBack;
static const AVCaptureDevicePosition TPViewportBottomCamera     = AVCaptureDevicePositionFront;
static const TPViewport TPRecordFirstViewport                   = TPViewportTop;
static const TPViewport TPRecordSecondViewport                  = TPViewportBottom;
static const NSTimeInterval TPRecordFirstInterval               = 5;
static const NSTimeInterval TPRecordSecondInterval              = TPRecordFirstInterval;
static const NSInteger TPEncodeWidth                            = 376;
static const NSInteger TPEncodeHeight                           = TPEncodeWidth;
static const CGFloat TPProgressBarWidth                         = 20.0f;
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

@end

@implementation ViewController
{
    CGRect topViewportRect;
    CGRect bottomViewportRect;
    BOOL sessionConfigurationFailed;
    UIActivityIndicatorView *spinner;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view setBackgroundColor:[UIColor blackColor]];
    
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
    
    // Progress
    _progressBarLayer = [CAShapeLayer layer];
    [_progressBarLayer setStrokeColor:[UIColor redColor].CGColor];
    [_progressBarLayer setLineWidth:TPProgressBarWidth];
    [_progressBarLayer setFillColor:[UIColor clearColor].CGColor];
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.view.bounds];
    _progressBarLayer.path = path.CGPath;
    _progressBarTrackLayer = [CAShapeLayer layer];
    [_progressBarTrackLayer setStrokeColor:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.2].CGColor];
    [_progressBarTrackLayer setLineWidth:TPProgressBarWidth];
    [_progressBarTrackLayer setFillColor:[UIColor clearColor].CGColor];
    _progressBarTrackLayer.path = _progressBarLayer.path;
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
            
            _recordButton.enabled = NO;
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
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
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingFirstCompleted) {
            
            assertFrom(TPStateRecordingFirstCompleting);
            [self transitionToStatus:TPStateRecordingSecondStarting];
            
        } else if (newStatus == TPStateRecordingSecondStarting) {
            
            assertFrom(TPStateRecordingFirstCompleted);
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_firstVideoURL];
            [_firstPlayer replaceCurrentItemWithPlayerItem:item];
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
            [_sessionCoordinator setDevicePosition:targetCamera];
            [self moveLayer:_previewLayer to:TPRecordSecondViewport];
            [_sessionCoordinator startRecording];
            
        } else if (newStatus == TPStateRecordingSecondStarted) {
            
            [spinner removeFromSuperview];
            [_firstPlayer play];
            [self resumeProgressBar];
            [self transitionToStatus:TPStateRecordingSecondCompleting after:TPRecordSecondInterval];
            
        } else if (newStatus == TPStateRecordingSecondCompleting) {
            
            assertFrom(TPStateRecordingSecondStarted);
            [self pauseProgressBar];
            [_sessionCoordinator stopRecording];
            
        } else if (newStatus == TPStateRecordingSecondCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleting);
            [self resumeProgressBar];
            [[_previewLayer connection] setEnabled:NO]; // Freeze preview
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondCompleted);
            [UIApplication sharedApplication].idleTimerDisabled = NO;
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
    [self.view.layer insertSublayer:_progressBarTrackLayer atIndex:3];
}

-(void)startSecondRecordingVisualCue
{
    [UIView animateWithDuration:TPRecordFirstInterval
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self.view.layer.backgroundColor = [UIColor whiteColor].CGColor;
                     } completion:^ (BOOL completed){
                         spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                         [spinner startAnimating];
                         [spinner setFrame:bottomViewportRect];
                         [self.view addSubview:spinner];
                     }];
}

-(void)startProgressBar
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = [NSNumber numberWithFloat:0.0f];
    animation.toValue = [NSNumber numberWithFloat:1.0f];
    animation.duration = TPRecordFirstInterval + TPRecordSecondInterval;
    [_progressBarLayer addAnimation:animation forKey:@"myStroke"];
    [self.view.layer insertSublayer:_progressBarLayer atIndex:4];
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

@end
