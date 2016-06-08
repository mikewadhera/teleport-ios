
@import AVFoundation;

#import "ViewController.h"

static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM( NSInteger, TPCameraSetupResult ) {
    TPCameraSetupResultSuccess,
    TPCameraSetupResultCameraNotAuthorized,
    TPCameraSetupResultSessionConfigurationFailed
};

typedef NS_ENUM( NSInteger, TPViewport ) {
    TPViewportTop,
    TPViewportBottom
};

static const AVCaptureDevicePosition TPViewportTopCamera = AVCaptureDevicePositionBack;
static const AVCaptureDevicePosition TPViewportBottomCamera = AVCaptureDevicePositionFront;
static const TPViewport TPInitialViewport = TPViewportTop;

@interface ViewController ()

@property (nonatomic) UIButton *recordButton;
@property (nonatomic) UIView *topView;
@property (nonatomic) UIView *bottomView;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;

// Utilities.
@property (nonatomic) TPCameraSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation ViewController
{
    TPViewport activeViewport;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Create the AV session
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    
    // Create the AV session queue
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    
    // Create the preview
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    // Top View
    int topViewW = self.view.frame.size.width;
    int topViewH = floor(self.view.frame.size.height / 2.0);
    int topViewX = 0;
    int topViewY = 0;
    _topView = [[UIView alloc] initWithFrame:CGRectMake(topViewX, topViewY, topViewW, topViewH)];
    [_topView setBackgroundColor:[UIColor greenColor]];
    
    // Buttom View
    int bottomViewW = self.view.frame.size.width;
    int bottomViewH = ceil(self.view.frame.size.height / 2.0);
    int bottomViewX = 0;
    int bottomViewY = floor(self.view.frame.size.height / 2.0);
    _bottomView = [[UIView alloc] initWithFrame:CGRectMake(bottomViewX, bottomViewY, bottomViewW, bottomViewH)];
    [_bottomView setBackgroundColor:[UIColor blackColor]];
    
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
    _recordButton.enabled = NO; // Not enabled until AV session is running
    
    // Add views
    [self.view addSubview:_bottomView];
    [self.view addSubview:_topView];
    [self.view addSubview:_recordButton];
    
    // Check camera access
    [self checkCameraStatus];
    
    // Initialize session and preview
    dispatch_async( self.sessionQueue, ^{
        [self initSession];
        dispatch_async( dispatch_get_main_queue(), ^{
            [self initPreview];
        } );
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    dispatch_async( self.sessionQueue, ^{
        switch ( self.setupResult )
        {
            case TPCameraSetupResultSuccess:
            {
                // Only setup observers and start the session running if setup succeeded.
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                break;
            }
            case TPCameraSetupResultCameraNotAuthorized:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    [self showCameraPermissionErrorDialog];
                } );
                break;
            }
            case TPCameraSetupResultSessionConfigurationFailed:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    [self showCameraCaptureErrorDialog];
                } );
                break;
            }
        }
    } );
}

- (void)viewDidDisappear:(BOOL)animated
{
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == TPCameraSetupResultSuccess ) {
            [self.session stopRunning];
            [self removeObservers];
        }
    } );
    
    [super viewDidDisappear:animated];
}

-(void)checkCameraStatus
{
    // Assume we have camera permission
    self.setupResult = TPCameraSetupResultSuccess;
    
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
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = TPCameraSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            self.setupResult = TPCameraSetupResultCameraNotAuthorized;
            break;
        }
    }

}

-(void)initSession
{
    if ( self.setupResult != TPCameraSetupResultSuccess ) {
        return;
    }
    
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    NSError *error = nil;
    
    AVCaptureDevicePosition initialCamera;
    
    switch (TPInitialViewport)
    {
        case TPViewportTop:
        {
            initialCamera = TPViewportTopCamera;
            break;
        }
        case TPViewportBottom:
        {
            initialCamera = TPViewportBottomCamera;
            break;
        }
    }
    
    AVCaptureDevice *videoDevice = [ViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:initialCamera];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    if ( ! videoDeviceInput ) {
        NSLog( @"Could not create video device input: %@", error );
    }
    
    [self.session beginConfiguration];
    
    if ( [self.session canAddInput:videoDeviceInput] ) {
        [ViewController setFlashMode:AVCaptureFlashModeOff forDevice:videoDevice];
        [self.session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
    }
    else {
        NSLog( @"Could not add video device input to the session" );
        self.setupResult = TPCameraSetupResultSessionConfigurationFailed;
    }
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    
    if ( ! audioDeviceInput ) {
        NSLog( @"Could not create audio device input: %@", error );
    }
    
    if ( [self.session canAddInput:audioDeviceInput] ) {
        [self.session addInput:audioDeviceInput];
    }
    else {
        NSLog( @"Could not add audio device input to the session" );
    }
    
    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ( [self.session canAddOutput:movieFileOutput] ) {
        [self.session addOutput:movieFileOutput];
        AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ( connection.isVideoStabilizationSupported ) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeOff;
        }
        self.movieFileOutput = movieFileOutput;
    }
    else {
        NSLog( @"Could not add movie file output to the session" );
        self.setupResult = TPCameraSetupResultSessionConfigurationFailed;
    }
    
    [self.session commitConfiguration];
}

- (void)initPreview
{
    switch (TPInitialViewport)
    {
        case TPViewportTop:
        {
            [self movePreview:self.topView];
            break;
        }
        case TPViewportBottom:
        {
            [self movePreview:self.bottomView];
            break;
        }
    }
}

- (void)updateViewport:(TPViewport)viewport
{
    if (viewport == activeViewport) {
        return;
    }
    
    activeViewport = viewport;
    AVCaptureDevicePosition camera;
    
    switch (activeViewport)
    {
        case TPViewportTop:
        {
            camera = TPViewportTopCamera;
            [self movePreview:self.topView];
            break;
        }
        case TPViewportBottom:
        {
            camera = TPViewportBottomCamera;
            [self movePreview:self.bottomView];
            break;
        }
    }
    
    dispatch_async(self.sessionQueue, ^{
        [self updateSession:camera];
        dispatch_async( dispatch_get_main_queue(), ^{
            // TODO: Update UI
        } );
    });
}

-(void)updateSession:(AVCaptureDevicePosition)camera
{
    AVCaptureDevice *videoDevice = [ViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:camera];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    
    [self.session beginConfiguration];
    
    // Remove the existing device input first
    [self.session removeInput:self.videoDeviceInput];
    
    if ( [self.session canAddInput:videoDeviceInput] ) {
        [ViewController setFlashMode:AVCaptureFlashModeOff forDevice:videoDevice];
        [self.session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
    }
    else {
        [self.session addInput:self.videoDeviceInput];
    }
    
    AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    if ( connection.isVideoStabilizationSupported ) {
        connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeOff;
    }
    
    [self.session commitConfiguration];
}

- (void)movePreview:(UIView*)theView
{
    [self.previewLayer removeFromSuperlayer];
    self.previewLayer.frame = theView.bounds;
    [theView.layer addSublayer:self.previewLayer];
}


-(void)didTapRecord:(id)button
{
    NSLog(@"HERE");
    [self updateViewport:TPViewportBottom];
}

#pragma mark KVO and Notifications

- (void)addObservers
{
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
    // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
    // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
    // interruption reasons.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
            // self.cameraButton.enabled = isSessionRunning && ( [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1 );
            _recordButton.enabled = isSessionRunning;
            // self.stillButton.enabled = isSessionRunning;
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    // Automatically try to restart the session running if media services were reset and the last start running succeeded.
    // Otherwise, enable the user to try to resume the session running.
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                    // self.resumeButton.hidden = NO;
                } );
            }
        } );
    }
    else {
        // self.resumeButton.hidden = NO;
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    // In some scenarios we want to enable the user to resume the session running.
    // For example, if music playback is initiated via control center while using AVCam,
    // then the user can let AVCam resume the session running, which will stop music playback.
    // Note that stopping music playback in control center will not automatically resume the session running.
    // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
    BOOL showResumeButton = NO;
    
    // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
    
    if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
        reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
        showResumeButton = YES;
    }
    else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
        // Simply fade-in a label to inform the user that the camera is unavailable.
        // self.cameraUnavailableLabel.hidden = NO;
        // self.cameraUnavailableLabel.alpha = 0.0;
        // [UIView animateWithDuration:0.25 animations:^{
            // self.cameraUnavailableLabel.alpha = 1.0;
        // }];
    }
    
    if ( showResumeButton ) {
        // Simply fade-in a button to enable the user to try to resume the session running.
        // self.resumeButton.hidden = NO;
        // self.resumeButton.alpha = 0.0;
        // [UIView animateWithDuration:0.25 animations:^{
            // self.resumeButton.alpha = 1.0;
        // }];
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
    
//    if ( ! self.resumeButton.hidden ) {
//        [UIView animateWithDuration:0.25 animations:^{
//            self.resumeButton.alpha = 0.0;
//        } completion:^( BOOL finished ) {
//            self.resumeButton.hidden = YES;
//        }];
//    }
//    if ( ! self.cameraUnavailableLabel.hidden ) {
//        [UIView animateWithDuration:0.25 animations:^{
//            self.cameraUnavailableLabel.alpha = 0.0;
//        } completion:^( BOOL finished ) {
//            self.cameraUnavailableLabel.hidden = YES;
//        }];
//    }
}

#pragma mark Actions

- (IBAction)resumeInterruptedSession:(id)sender
{
    dispatch_async( self.sessionQueue, ^{
        // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
        // A failure to start the session running will be communicated via a session runtime error notification.
        // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
        // session runtime error handler if we aren't trying to resume the session running.
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if ( ! self.session.isRunning ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = @"Unable to resume";
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Session Error" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
        }
        else {
            dispatch_async( dispatch_get_main_queue(), ^{
                // self.resumeButton.hidden = YES;
            } );
        }
    } );
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

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == position ) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if ( device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

@end
