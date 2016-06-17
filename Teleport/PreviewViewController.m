
@import AVFoundation;

#import "PreviewViewController.h"

static const NSTimeInterval TPVideoLengthInterval   = 4;
static const int TPCompositionEncodeWidth           = 376;
static const int TPCompositionEncodeHeight          = 668;
static const int TPCompositionEncodeFrameRate       = 30;

@interface PreviewViewController ()

@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) AVPlayer *secondPlayer;
@property (nonatomic) AVPlayerLayer *secondPlayerLayer;
@property (nonatomic) NSURL *videoURL;

@end

@implementation PreviewViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    NSNumber *fileSizeValue = nil;
    [_firstVideoURL getResourceValue:&fileSizeValue
                       forKey:NSURLFileSizeKey
                        error:nil];
    if (fileSizeValue) {
        NSLog(@"value for %@ is %f", _firstVideoURL, [fileSizeValue floatValue]/1024.0f/1024.0f);
    }
    NSNumber *fileSizeValue2 = nil;
    [_secondVideoURL getResourceValue:&fileSizeValue2
                              forKey:NSURLFileSizeKey
                               error:nil];
    if (fileSizeValue2) {
        NSLog(@"value for %@ is %f", _secondVideoURL, [fileSizeValue2 floatValue]/1024.0f/1024.0f);
    }
    
    
    // Calculate Viewports
    int topViewW = self.view.frame.size.width;
    int topViewH = ceil(self.view.frame.size.height / 2.0);
    int topViewX = 0;
    int topViewY = 0;
    CGRect topViewportRect = CGRectMake(topViewX, topViewY, topViewW, topViewH);
    
    int bottomViewW = self.view.frame.size.width;
    int bottomViewH = ceil(self.view.frame.size.height / 2.0);
    int bottomViewX = 0;
    int bottomViewY = floor(self.view.frame.size.height / 2.0);
    CGRect bottomViewportRect = CGRectMake(bottomViewX, bottomViewY, bottomViewW, bottomViewH);
    
    _firstPlayer = [AVPlayer new];
    [_firstPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:_firstVideoURL]];
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.frame = topViewportRect;
    _firstPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _firstPlayer.muted = YES; // Always muted
    NSLog(@"%f", [[[_firstPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    
    _secondPlayer = [AVPlayer new];
    [_secondPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:_secondVideoURL]];
    _secondPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_secondPlayer];
    _secondPlayerLayer.frame = bottomViewportRect;
    _secondPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _secondPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    NSLog(@"%f", [[[_secondPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    
    [self.view.layer addSublayer:_firstPlayerLayer];
    [self.view.layer addSublayer:_secondPlayerLayer];
    
    [_firstPlayer play];
    [_secondPlayer play];
    
    //[self composeVideo];
}

-(void)composeVideo
{
    AVMutableComposition *mixComposition = [[AVMutableComposition alloc] init];
    
    AVURLAsset *firstAsset = [AVURLAsset URLAssetWithURL:_firstVideoURL options:nil];
    AVAssetTrack *firstVideoAssetTrack = [[firstAsset tracksWithMediaType:AVMediaTypeVideo] lastObject];
    
    AVURLAsset *secondAsset = [AVURLAsset URLAssetWithURL:_secondVideoURL options:nil];
    AVAssetTrack *secondVideoAssetTrack = [[secondAsset tracksWithMediaType:AVMediaTypeVideo] lastObject];
    
    AVMutableCompositionTrack *firstTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                        preferredTrackID:kCMPersistentTrackID_Invalid];
    [firstTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake(TPVideoLengthInterval, 1))
                        ofTrack:firstVideoAssetTrack
                         atTime:kCMTimeZero
                          error:nil];
    
    
    AVMutableCompositionTrack *secondTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                         preferredTrackID:kCMPersistentTrackID_Invalid];
    [secondTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake(TPVideoLengthInterval, 1))
                         ofTrack:secondVideoAssetTrack
                          atTime:kCMTimeZero
                           error:nil];
    
    AVMutableVideoCompositionInstruction *mainInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    mainInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(TPVideoLengthInterval, 1));
    
    AVMutableVideoCompositionLayerInstruction *firstlayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:firstTrack];
    CGAffineTransform firstScale = CGAffineTransformMakeScale(1.0f, 1.0f);
    CGAffineTransform firstMove = CGAffineTransformMakeTranslation(0, 0);
    [firstlayerInstruction setTransform:CGAffineTransformConcat(firstScale, firstMove) atTime:kCMTimeZero];
    
    AVMutableVideoCompositionLayerInstruction *secondlayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:secondTrack];
    CGAffineTransform secondScale = CGAffineTransformMakeScale(1.0f, 1.0f);
    CGAffineTransform secondMove = CGAffineTransformMakeTranslation(0, firstAsset.naturalSize.height);
    [secondlayerInstruction setTransform:CGAffineTransformConcat(secondScale, secondMove) atTime:kCMTimeZero];
    
    mainInstruction.layerInstructions = [NSArray arrayWithObjects:firstlayerInstruction, secondlayerInstruction, nil];
    
    AVMutableVideoComposition *mainCompositionInst = [AVMutableVideoComposition videoComposition];
    mainCompositionInst.instructions = [NSArray arrayWithObject:mainInstruction];
    mainCompositionInst.frameDuration = CMTimeMake(1, TPCompositionEncodeFrameRate);
    mainCompositionInst.renderSize = CGSizeMake(TPCompositionEncodeWidth, TPCompositionEncodeHeight);
    
    NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
    
    _videoURL = [NSURL fileURLWithPath:outputFilePath];
    
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                      presetName:AVAssetExportPresetHighestQuality];
    exporter.outputURL = _videoURL;
    [exporter setVideoComposition:mainCompositionInst];
    exporter.outputFileType = AVFileTypeQuickTimeMovie;
    
//    [exporter exportAsynchronouslyWithCompletionHandler:^
//    {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [_player replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:_videoURL]];
//            [_player seekToTime:kCMTimeZero];
//            [_player play];
//        });
//    }];
}

@end
