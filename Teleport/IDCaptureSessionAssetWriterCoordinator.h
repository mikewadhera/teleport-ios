//
//  IDCaptureSessionAssetWriterCoordinator.h
//  VideoCaptureDemo
//
//  Created by Adriaan Stellingwerff on 9/04/2015.
//  Copyright (c) 2015 Infoding. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol IDCaptureSessionCoordinatorDelegate;
@protocol IDCaptureSessionAssetWriterCoordinatorDelegate;

@interface IDCaptureSessionAssetWriterCoordinator : NSObject

@property (nonatomic, assign, readonly) AVCaptureDevicePosition devicePosition;

- (instancetype)initWithDevicePosition:(AVCaptureDevicePosition)position;

- (void)setDelegate:(id<IDCaptureSessionCoordinatorDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue;

-(void)setDevicePosition:(AVCaptureDevicePosition)devicePosition;

- (void)startRunning;
- (void)stopRunning;

- (void)startRecording;
- (void)stopRecording;

- (AVCaptureVideoPreviewLayer *)previewLayer;

@end

@protocol IDCaptureSessionCoordinatorDelegate <NSObject>

@required

- (void)coordinatorDidBeginRecording:(IDCaptureSessionAssetWriterCoordinator *)coordinator;
- (void)coordinator:(IDCaptureSessionAssetWriterCoordinator *)coordinator didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error;

@optional

- (void)coordinatorSessionDidFinishStarting:(IDCaptureSessionAssetWriterCoordinator *)coordinator running:(BOOL)isRunning;
- (void)coordinatorSessionDidInterrupt:(IDCaptureSessionAssetWriterCoordinator *)coordinator;
- (void)coordinatorSessionConfigurationDidFail:(IDCaptureSessionAssetWriterCoordinator *)coordinator;
- (NSDictionary*)coordinatorDesiredVideoOutputSettings;
- (NSDictionary*)coordinatorDesiredAudioOutputSettings;

@end
