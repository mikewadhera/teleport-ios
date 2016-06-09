
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
    TPStateRecordingFirst,
    TPStateRecordingFirstFinished,
    TPStateRecordingFirstFailed,
    TPStateRecordingSecond,
    TPStateRecordingSecondFinished,
    TPStateRecordingSecondFailed,
    TPStateRecordingCompleted
};
typedef void (^ AssertFromBlock)(TPState);

// Constants
static const AVCaptureDevicePosition TPViewportTopCamera        = AVCaptureDevicePositionBack;
static const AVCaptureDevicePosition TPViewportBottomCamera     = AVCaptureDevicePositionFront;
static const TPViewport TPRecordFirstViewport                   = TPViewportTop;
static const TPViewport TPRecordSecondViewport                  = TPViewportBottom;
static const NSTimeInterval TPRecordFirstInterval               = 3;
static const NSTimeInterval TPRecordSecondInterval              = TPRecordFirstInterval;
static const NSInteger TPEncodeWidth                            = 376;
static const NSInteger TPEncodeHeight                           = TPEncodeWidth;
// Constants

@interface ViewController () <IDCaptureSessionCoordinatorDelegate>

@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, strong) IDCaptureSessionAssetWriterCoordinator *sessionCoordinator;

@property (nonatomic) TPState status;
@property (nonatomic) UIButton *recordButton;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayer *secondPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) AVPlayerLayer *secondPlayerLayer;
@property (nonatomic) NSURL *firstVideoURL;
@property (nonatomic) NSURL *secondVideoURL;

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
    
    // Create the players
    _firstPlayer = [[AVPlayer alloc] init];
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _secondPlayer = [[AVPlayer alloc] init];
    _secondPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_secondPlayer];
    _secondPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    // Calculate Viewports
    int topViewW = self.view.frame.size.width;
    int topViewH = floor(self.view.frame.size.height / 2.0);
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
    
    // Players
    [self.view.layer insertSublayer:_firstPlayerLayer atIndex:0];
    [self moveLayer:_firstPlayerLayer to:TPRecordFirstViewport];
    [self.view.layer insertSublayer:_secondPlayerLayer atIndex:1];
    [self moveLayer:_secondPlayerLayer to:TPRecordSecondViewport];
    
    // Preview
    [self.view.layer insertSublayer:_previewLayer atIndex:2];
    [self moveLayer:_previewLayer to:TPRecordFirstViewport];
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
    [self transitionToStatus:TPStateRecordingFirst];
}

-(void)transitionToStatus:(TPState)newStatus
{
    TPState oldStatus = _status;
    _status = newStatus;
    
    NSLog(@"%ld --> %ld", oldStatus, newStatus);
    
    AssertFromBlock assertFrom = ^(TPState fromState) {
        if (oldStatus != fromState) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString
                                                   stringWithFormat:@"Unexpected transition: %ld to %ld", oldStatus, newStatus]
                                         userInfo:nil];
        }
    };
    
    if (oldStatus != newStatus) {
        if (newStatus == TPStateSessionStarting) {
            
            _recordButton.enabled = NO;
            [_sessionCoordinator startRunning];
            
        } else if (newStatus == TPStateSessionStopping) {
            
            _recordButton.enabled = NO;
            [_sessionCoordinator stopRunning];
            
            
        } else if (newStatus == TPStateSessionConfigurationFailed) {
            
            _recordButton.enabled = NO;
            sessionConfigurationFailed = YES; // checked in viewWillAppear
        
        } else if (newStatus == TPStateSessionStarted) {
            
            _recordButton.enabled = YES;
            [self transitionToStatus:TPStateRecordingIdle];
            
        } else if (newStatus == TPStateRecordingFirst) {
            
            assertFrom(TPStateRecordingIdle);
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            _recordButton.hidden = YES;
            [_sessionCoordinator startRecording];
            [_sessionCoordinator performSelector:@selector(stopRecording) withObject:nil afterDelay:TPRecordFirstInterval];
            
        } else if (newStatus == TPStateRecordingFirstFinished) {
            
            assertFrom(TPStateRecordingFirst);
            [self transitionToStatus:TPStateRecordingSecond];
            
        } else if (newStatus == TPStateRecordingSecond) {
            
            assertFrom(TPStateRecordingFirstFinished);
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
            [_firstPlayer play];
            [_sessionCoordinator startRecording];
            [_sessionCoordinator performSelector:@selector(stopRecording) withObject:nil afterDelay:TPRecordSecondInterval];
            
        } else if (newStatus == TPStateRecordingSecondFinished) {
            
            assertFrom(TPStateRecordingSecond);
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_secondVideoURL];
            [_secondPlayer replaceCurrentItemWithPlayerItem:item];
            [_secondPlayer play];
            [_previewLayer removeFromSuperlayer];
            [self transitionToStatus:TPStateRecordingCompleted];
            
        } else if (newStatus == TPStateRecordingCompleted) {
            
            assertFrom(TPStateRecordingSecondFinished);
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [self transitionToStatus:TPStateRecordingIdle];

        }
    }
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
    
}

- (void)coordinator:(IDCaptureSessionAssetWriterCoordinator *)coordinator didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error
{
    BOOL success = YES;
    if ( error ) {
        NSLog( @"Movie file finishing error: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        if (_status == TPStateRecordingFirst) {
            _firstVideoURL = outputFileURL;
            [self transitionToStatus:TPStateRecordingFirstFinished];
        } else if (_status == TPStateRecordingSecond) {
            _secondVideoURL = outputFileURL;
            [self transitionToStatus:TPStateRecordingSecondFinished];
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

@end
