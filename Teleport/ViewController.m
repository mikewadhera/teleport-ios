
@import AVFoundation;
@import Photos;

#import "ViewController.h"
#import "IDCaptureSessionAssetWriterCoordinator.h"

typedef NS_ENUM( NSInteger, TPCameraSetupResult ) {
    TPCameraSetupResultSuccess,
    TPCameraSetupResultCameraNotAuthorized,
    TPCameraSetupResultSessionConfigurationFailed
};

typedef NS_ENUM( NSInteger, TPViewport ) {
    TPViewportTop,
    TPViewportBottom
};

typedef NS_ENUM( NSInteger, TPRecording ) {
    TPRecordingIdle,
    TPRecordingFirst,
    TPRecordingFirstFinished,
    TPRecordingFirstFailed,
    TPRecordingSecond,
    TPRecordingSecondFinished,
    TPRecordingSecondFailed,
    TPRecordingComplete
};

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

@property (nonatomic) TPRecording recordingStatus;
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
    _recordButton.enabled = NO; // Not enabled until session is running (in coordinator delegate)
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
    
    switch ( _setupResult )
    {
        case TPCameraSetupResultSuccess:
        {
            // Only start the session running if setup succeeded
            [_sessionCoordinator startRunning];
            break;
        }
        case TPCameraSetupResultCameraNotAuthorized:
        {
            [self showCameraPermissionErrorDialog];
            break;
        }
        case TPCameraSetupResultSessionConfigurationFailed:
        {
            [self showCameraCaptureErrorDialog];
            break;
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    if ( _setupResult == TPCameraSetupResultSuccess ) {
        [_sessionCoordinator stopRunning];
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

- (void)updateViewport:(TPViewport)viewport
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
    [_sessionCoordinator setDevicePosition:targetCamera];
    [self moveLayer:_previewLayer to:viewport];
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
    [self transitionToRecordingStatus:TPRecordingFirst];
}

-(void)transitionToRecordingStatus:(TPRecording)newStatus
{
    TPRecording oldStatus = _recordingStatus;
    _recordingStatus = newStatus;
    
    NSLog(@"%ld --> %ld", oldStatus, newStatus);
    
    dispatch_block_t halt = ^{
        [self throwFatalTransitionErrorFrom:oldStatus to:newStatus];
    };
    
    if (oldStatus != newStatus) {
        if (newStatus == TPRecordingFirst) {
            
            if (oldStatus != TPRecordingIdle) {
                halt();
            } else {
                [UIApplication sharedApplication].idleTimerDisabled = YES;
                _recordButton.hidden = YES;
                [_sessionCoordinator startRecording];
                [_sessionCoordinator performSelector:@selector(stopRecording) withObject:nil afterDelay:TPRecordFirstInterval];
            }
            
        } else if (newStatus == TPRecordingFirstFinished) {
            
            if (oldStatus != TPRecordingFirst) {
                halt();
            } else {
                [self transitionToRecordingStatus:TPRecordingSecond];
            }
            
        } else if (newStatus == TPRecordingSecond) {
            
            if (oldStatus != TPRecordingFirstFinished) {
                halt();
            } else {
                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_firstVideoURL];
                [_firstPlayer replaceCurrentItemWithPlayerItem:item];
                [self updateViewport:TPRecordSecondViewport];
                [_firstPlayer play];
                [_sessionCoordinator startRecording];
                [_sessionCoordinator performSelector:@selector(stopRecording) withObject:nil afterDelay:TPRecordSecondInterval];
            }
            
        } else if (newStatus == TPRecordingSecondFinished) {
            
            if (oldStatus != TPRecordingSecond) {
                halt();
            } else {
                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_secondVideoURL];
                [_secondPlayer replaceCurrentItemWithPlayerItem:item];
                [_secondPlayer play];
                [_previewLayer removeFromSuperlayer];
                [self transitionToRecordingStatus:TPRecordingComplete];
            }
            
        } else if (newStatus == TPRecordingComplete) {
            
            if (oldStatus != TPRecordingSecondFinished) {
                halt();
            } else {
                [UIApplication sharedApplication].idleTimerDisabled = NO;
                [self transitionToRecordingStatus:TPRecordingIdle];
            }
        }
    }
}

#pragma mark = IDCaptureSessionAssetWriterCoordinatorDelegate methods

- (void)coordinatorSessionConfigurationDidFail:(IDCaptureSessionAssetWriterCoordinator *)coordinator
{
    _setupResult = TPCameraSetupResultSessionConfigurationFailed;
}

-(void)coordinatorSessionDidFinishStarting:(IDCaptureSessionAssetWriterCoordinator *)coordinator running:(BOOL)isRunning
{
    _recordButton.enabled = isRunning;
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
        if (_recordingStatus == TPRecordingFirst) {
            _firstVideoURL = outputFileURL;
            [self saveToPhotoRoll:_firstVideoURL];
            [self transitionToRecordingStatus:TPRecordingFirstFinished];
        } else if (_recordingStatus == TPRecordingSecond) {
            _secondVideoURL = outputFileURL;
            [self saveToPhotoRoll:_secondVideoURL];
            [self transitionToRecordingStatus:TPRecordingSecondFinished];
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

-(void)throwFatalTransitionErrorFrom:(TPRecording)t1 to:(TPRecording)t2
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"Tried to transition from %ld to %ld", (long)t1, t2]
                                 userInfo:nil];
    return;
}

-(void)saveToPhotoRoll:(NSURL*)outputFileURL
{
    // Check authorization status.
    [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
        if ( status == PHAuthorizationStatusAuthorized ) {
            // Save the movie file to the photo library and cleanup.
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:outputFileURL];
            } completionHandler:^( BOOL success, NSError *error ) {
                if ( ! success ) {
                    NSLog( @"Could not save movie to photo library: %@", error );
                }
            }];
        }
    }];
}

@end
