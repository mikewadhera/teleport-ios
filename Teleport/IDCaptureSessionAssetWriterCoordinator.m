//
//  IDCaptureSessionAssetWriterCoordinator.m
//  VideoCaptureDemo
//
//  Created by Adriaan Stellingwerff on 9/04/2015.
//  Copyright (c) 2015 Infoding. All rights reserved.
//

#import "IDCaptureSessionAssetWriterCoordinator.h"
#import "IDAssetWriterCoordinator.h"

static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM( NSInteger, RecordingStatus )
{
    RecordingStatusIdle = 0,
    RecordingStatusStartingRecording,
    RecordingStatusRecording,
    RecordingStatusStoppingRecording,
}; // internal state machine


@interface IDCaptureSessionAssetWriterCoordinator () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, IDAssetWriterCoordinatorDelegate>

// Core
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) dispatch_queue_t delegateCallbackQueue;
@property (nonatomic, weak) id<IDCaptureSessionCoordinatorDelegate> delegate;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

// Inputs
@property (nonatomic, strong) AVCaptureDeviceInput *cameraDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioDeviceInput;

// Outputs
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) dispatch_queue_t audioDataOutputQueue;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic, strong) AVCaptureConnection *audioConnection;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;
@property (nonatomic, strong) NSDictionary *videoCompressionSettings;
@property (nonatomic, strong) NSDictionary *audioCompressionSettings;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputVideoFormatDescription;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputAudioFormatDescription;
@property(nonatomic, retain) IDAssetWriterCoordinator *assetWriterCoordinator;

// Recording
@property (nonatomic, assign) RecordingStatus recordingStatus;
@property (nonatomic, strong) NSURL *recordingURL;

@end

@implementation IDCaptureSessionAssetWriterCoordinator

- (instancetype)initWithDevicePosition:(AVCaptureDevicePosition)position
{
    self = [super init];
    if(self){
        _sessionQueue = dispatch_queue_create( "com.example.capturepipeline.session", DISPATCH_QUEUE_SERIAL );
        _devicePosition = position;
        _captureSession = [AVCaptureSession new];
        
        self.videoDataOutputQueue = dispatch_queue_create( "com.example.capturesession.videodata", DISPATCH_QUEUE_SERIAL );
        dispatch_set_target_queue( _videoDataOutputQueue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
        self.audioDataOutputQueue = dispatch_queue_create( "com.example.capturesession.audiodata", DISPATCH_QUEUE_SERIAL );
        
        [self updateSessionConfiguration];
    }
    return self;
}

- (void)setDelegate:(id<IDCaptureSessionCoordinatorDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue
{
    if(delegate && ( delegateCallbackQueue == NULL)){
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Caller must provide a delegateCallbackQueue" userInfo:nil];
    }
    @synchronized(self)
    {
        _delegate = delegate;
        if (delegateCallbackQueue != _delegateCallbackQueue){
            _delegateCallbackQueue = delegateCallbackQueue;
        }
    }
}

- (AVCaptureVideoPreviewLayer *)previewLayer
{
    if(!_previewLayer && _captureSession){
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
    }
    return _previewLayer;
}

#pragma mark - Session management

- (void)startRunning
{
    dispatch_sync( _sessionQueue, ^{
        [self addObservers];
        [_captureSession startRunning];
        _sessionRunning = [_captureSession isRunning];
    } );
}

- (void)stopRunning
{
    dispatch_sync( _sessionQueue, ^{
        // the captureSessionDidStopRunning method will stop recording if necessary as well, but we do it here so that the last video and audio samples are better aligned
        [self stopRecording]; // does nothing if we aren't currently recording
        [_captureSession stopRunning];
        [self removeObservers];
    } );
}

- (BOOL)isRunning
{
    return _captureSession.isRunning;
}

#pragma mark - Recording

- (void)startRecording
{
    @synchronized(self)
    {
        if(_recordingStatus != RecordingStatusIdle) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Already recording" userInfo:nil];
            return;
        }
        [self transitionToRecordingStatus:RecordingStatusStartingRecording error:nil];
    }
    
    _videoCompressionSettings = [_videoDataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie];
    if ( [[self delegate] respondsToSelector:@selector(coordinatorDesiredVideoOutputSettings)] ) {
        _videoCompressionSettings = [[self delegate] coordinatorDesiredVideoOutputSettings];
    }
    _audioCompressionSettings = [_audioDataOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie];
    if ( [[self delegate] respondsToSelector:@selector(coordinatorDesiredAudioOutputSettings)] ) {
        _audioCompressionSettings = [[self delegate] coordinatorDesiredAudioOutputSettings];
    }
    
    NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mp4"]];
    _recordingURL = [NSURL fileURLWithPath:outputFilePath];

    self.assetWriterCoordinator = [[IDAssetWriterCoordinator alloc] initWithURL:_recordingURL];
    if (self.outputAudioFormatDescription != nil) {
        [_assetWriterCoordinator addAudioTrackWithSourceFormatDescription:self.outputAudioFormatDescription settings:_audioCompressionSettings];
    }
    [_assetWriterCoordinator addVideoTrackWithSourceFormatDescription:self.outputVideoFormatDescription settings:_videoCompressionSettings];
    
    dispatch_queue_t callbackQueue = dispatch_queue_create( "com.example.capturesession.writercallback", DISPATCH_QUEUE_SERIAL ); // guarantee ordering of callbacks with a serial queue
    [_assetWriterCoordinator setDelegate:self callbackQueue:callbackQueue];
    [_assetWriterCoordinator prepareToRecord]; // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
}

- (BOOL)stopRecording
{
    @synchronized(self)
    {
        if (_recordingStatus != RecordingStatusRecording){
            return NO;
        }
        [self transitionToRecordingStatus:RecordingStatusStoppingRecording error:nil];
    }
    [self.assetWriterCoordinator finishRecording]; // asynchronous, will call us back with
    return YES;
}

-(void)setDevicePosition:(AVCaptureDevicePosition)devicePosition
{
    if (devicePosition == self.devicePosition) {
        return;
    }
    
    _devicePosition = devicePosition;
    
    [self updateSessionConfiguration]; // Need to reconfigure AVCaptureSession to pickup new input
}

#pragma mark - Private methods

-(void)updateSessionConfiguration
{
    [self.captureSession beginConfiguration];
    
    // Inputs
    if (self.cameraDeviceInput) [self.captureSession removeInput:self.cameraDeviceInput];
    [self addInputsToCaptureSession:self.captureSession];
    
    // Outputs
    if (self.videoDataOutput) [self.captureSession removeOutput:self.videoDataOutput];
    [self addDataOutputsToCaptureSession:self.captureSession];
    
    [self.captureSession commitConfiguration];
}

-(void)addInputsToCaptureSession:(AVCaptureSession *)captureSession
{
    // Video
    AVCaptureDevice *videoDevice = [IDCaptureSessionAssetWriterCoordinator deviceWithMediaType:AVMediaTypeVideo preferringPosition:self.devicePosition];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    if ( [self.captureSession canAddInput:videoDeviceInput] ) {
        [self.captureSession addInput:videoDeviceInput];
        self.cameraDeviceInput = videoDeviceInput;
    }
    else {
        [self.captureSession addInput:self.cameraDeviceInput];
        NSLog(@"failed to set device position: %ld", (long)self.devicePosition);
    }
    [[self class] configureCamera:videoDevice atPosition:self.devicePosition];
    
    // Audio
    if (_devicePosition == AVCaptureDevicePositionFront) {
        AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
        
        if ([self.captureSession canAddInput:audioDeviceInput])
        {
            [self.captureSession addInput:audioDeviceInput];
        } else {
            NSLog(@"failed to set audio input for device position: %ld", (long)self.devicePosition);
        }
    }
}

- (void)addDataOutputsToCaptureSession:(AVCaptureSession *)captureSession
{
    // Video
    self.videoDataOutput = [AVCaptureVideoDataOutput new];
    _videoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    _videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    [_videoDataOutput setSampleBufferDelegate:self queue:_videoDataOutputQueue];
    if( [captureSession canAddOutput:_videoDataOutput] ){
        [captureSession addOutput:_videoDataOutput];
    } else {
        NSLog(@"can't add output: %@", [_videoDataOutput description]);
        if ( [[self delegate] respondsToSelector:@selector(coordinatorSessionConfigurationDidFail:)] ) {
            [[self delegate] coordinatorSessionConfigurationDidFail:self];
        }
    }
    _videoConnection = [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    if ( [_videoConnection isVideoStabilizationSupported] ) {
        [_videoConnection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeStandard];
    }
    if (_devicePosition == AVCaptureDevicePositionFront) {
        if ( [_videoConnection isVideoOrientationSupported] ) {
            [_videoConnection setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
        }
        if ( [_videoConnection isVideoMirroringSupported] ) {
            [_videoConnection setVideoMirrored:YES];
        }
    }
    
    // Audio
    if (_devicePosition == AVCaptureDevicePositionFront) {
        self.audioDataOutput = [AVCaptureAudioDataOutput new];
        [_audioDataOutput setSampleBufferDelegate:self queue:_audioDataOutputQueue];
        if ( [captureSession canAddOutput:_audioDataOutput] ) {
            [captureSession addOutput:_audioDataOutput];
        } else {
            NSLog(@"can't add output: %@", [_audioDataOutput description]);
            if ( [[self delegate] respondsToSelector:@selector(coordinatorSessionConfigurationDidFail:)] ) {
                [[self delegate] coordinatorSessionConfigurationDidFail:self];
            }
        }
        _audioConnection = [_audioDataOutput connectionWithMediaType:AVMediaTypeAudio];
        _captureSession.sessionPreset = AVCaptureSessionPresetHigh; // Required for audio frames when using front HD format
    };
}

- (void)setupVideoPipelineWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription
{
    self.outputVideoFormatDescription = inputFormatDescription;
}

- (void)teardownVideoPipeline
{
    self.outputVideoFormatDescription = nil;
    self.outputAudioFormatDescription = nil;
}

#pragma mark - SampleBufferDelegate methods

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    if (connection == _videoConnection){
        if (self.outputVideoFormatDescription == nil) {
            // Don't render the first sample buffer.
            // This gives us one frame interval (33ms at 30fps) for setupVideoPipelineWithInputFormatDescription: to complete.
            // Ideally this would be done asynchronously to ensure frames don't back up on slower devices.
            
            //TODO: outputVideoFormatDescription should be updated whenever video configuration is changed (frame rate, etc.)
            //Currently we don't use the outputVideoFormatDescription in IDAssetWriterRecoredSession
            [self setupVideoPipelineWithInputFormatDescription:formatDescription];
        } else {
            self.outputVideoFormatDescription = formatDescription;
            @synchronized(self) {
                if(_recordingStatus == RecordingStatusRecording){
                    [_assetWriterCoordinator appendVideoSampleBuffer:sampleBuffer];
                }
            }
        }
    } else if ( connection == _audioConnection ){
        self.outputAudioFormatDescription = formatDescription;
        @synchronized( self ) {
            if(_recordingStatus == RecordingStatusRecording){
                [_assetWriterCoordinator appendAudioSampleBuffer:sampleBuffer];
            }
        }
    }
}

#pragma mark - IDAssetWriterCoordinatorDelegate methods

- (void)writerCoordinatorDidFinishPreparing:(IDAssetWriterCoordinator *)coordinator
{
    @synchronized(self)
    {
        if(_recordingStatus != RecordingStatusStartingRecording){
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected to be in StartingRecording state" userInfo:nil];
            return;
        }
        [self transitionToRecordingStatus:RecordingStatusRecording error:nil];
    }
}

- (void)writerCoordinator:(IDAssetWriterCoordinator *)recorder didFailWithError:(NSError *)error
{
    NSLog(error.description);
    @synchronized( self ) {
        self.assetWriterCoordinator = nil;
        [self transitionToRecordingStatus:RecordingStatusIdle error:error];
    }
}

- (void)writerCoordinatorDidFinishRecording:(IDAssetWriterCoordinator *)coordinator
{
    @synchronized( self )
    {
        if ( _recordingStatus != RecordingStatusStoppingRecording ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected to be in StoppingRecording state" userInfo:nil];
            return;
        }
        // No state transition, we are still in the process of stopping.
        // We will be stopped once we save to the assets library.
    }
    
    self.assetWriterCoordinator = nil;
    [self teardownVideoPipeline];
    
    @synchronized( self ) {
        [self transitionToRecordingStatus:RecordingStatusIdle error:nil];
    }
}


#pragma mark - Recording State Machine

// call under @synchonized( self )
- (void)transitionToRecordingStatus:(RecordingStatus)newStatus error:(NSError *)error
{
    RecordingStatus oldStatus = _recordingStatus;
    _recordingStatus = newStatus;
    
    if (newStatus != oldStatus){
        if (error && (newStatus == RecordingStatusIdle)){
            dispatch_async( self.delegateCallbackQueue, ^{
                @autoreleasepool
                {
                    [self.delegate coordinator:self didFinishRecordingToOutputFileURL:_recordingURL error:nil];
                }
            });
        } else {
            error = nil; // only the above delegate method takes an error
            if (oldStatus == RecordingStatusStartingRecording && newStatus == RecordingStatusRecording){
                dispatch_async( self.delegateCallbackQueue, ^{
                    @autoreleasepool
                    {
                        [self.delegate coordinatorDidBeginRecording:self];
                    }
                });
            } else if (oldStatus == RecordingStatusStoppingRecording && newStatus == RecordingStatusIdle) {
                dispatch_async( self.delegateCallbackQueue, ^{
                    @autoreleasepool
                    {
                        [self.delegate coordinator:self didFinishRecordingToOutputFileURL:_recordingURL error:nil];
                    }
                });
            }
        }
    }
}

#pragma mark KVO and Notifications

- (void)addObservers
{
    [_captureSession addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:_captureSession];
    // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
    // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
    // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
    // interruption reasons.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:_captureSession];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:_captureSession];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_captureSession removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            if ( [[self delegate] respondsToSelector:@selector(coordinatorSessionDidFinishStarting:running:)] ) {
                [[self delegate] coordinatorSessionDidFinishStarting:self running:isSessionRunning];
            }
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
                [_captureSession startRunning];
                self.sessionRunning = _captureSession.isRunning;
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
    }
    
    if ( showResumeButton ) {
        // Simply fade-in a button to enable the user to try to resume the session running.
    }
    
    dispatch_async( dispatch_get_main_queue(), ^{
        if ( [[self delegate] respondsToSelector:@selector(coordinatorSessionDidInterrupt:)] ) {
            [[self delegate] coordinatorSessionDidInterrupt:self];
        }
    } );
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
}

# pragma mark - Helpers

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

+ (void)configureCamera:(AVCaptureDevice *)videoDevice atPosition:(AVCaptureDevicePosition)position
{
    for(AVCaptureDeviceFormat *vFormat in [videoDevice formats] )
    {
        CMFormatDescriptionRef description= vFormat.formatDescription;
        float maxrate=((AVFrameRateRange*)[vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        
        // HACK: need a better way to get this format
        int targetHeight = 1936;
        if (position == AVCaptureDevicePositionFront) targetHeight = 960;
        
        // NSLog(@"formats  %@ %@ %@ %@",vFormat.mediaType,vFormat.formatDescription,vFormat.videoSupportedFrameRateRanges, vFormat.videoBinned == YES ? @"Binned" : @"");
        
        if(maxrate>29 &&
           CMVideoFormatDescriptionGetDimensions(description).height == targetHeight &&
           CMFormatDescriptionGetMediaSubType(description)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        {
            if ( YES == [videoDevice lockForConfiguration:NULL] )
            {
                videoDevice.activeFormat = vFormat;
                [videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1,position == AVCaptureDevicePositionFront?30:30)];
                [videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1,position == AVCaptureDevicePositionFront?30:30)];
                if ( videoDevice.hasFlash ) videoDevice.flashMode = AVCaptureFlashModeOff;
                //if (position == AVCaptureDevicePositionFront) {
                    [videoDevice setAutomaticallyAdjustsVideoHDREnabled:NO];
                    //[videoDevice setVideoHDREnabled:YES];
                //}
                [videoDevice unlockForConfiguration];
                
                //NSLog(@"formats  %@ %@ %@ %@",vFormat.mediaType,vFormat.formatDescription,vFormat.videoSupportedFrameRateRanges, vFormat.videoBinned == YES ? @"Binned" : @"");
            } else {
                NSLog( @"Could not lock device for configuration");
            }
        }
    }
}


@end