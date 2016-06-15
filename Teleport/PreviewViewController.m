
@import AVFoundation;

#import "PreviewViewController.h"

static const NSTimeInterval TPVideoLengthInterval   = 4;
static const int TPCompositionEncodeWidth           = 376;
static const int TPCompositionEncodeHeight          = 668;
static const int TPCompositionEncodeFrameRate       = 30;

@interface PreviewViewController ()

@property (nonatomic) AVPlayer *player;
@property (nonatomic) AVPlayerLayer *playerLayer;
@property (nonatomic) NSURL *videoURL;

@end

@implementation PreviewViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    _player = [AVPlayer new];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = self.view.bounds;
    _playerLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    [self.view.layer addSublayer:_playerLayer];
    
    [self composeVideo];
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
    
    [exporter exportAsynchronouslyWithCompletionHandler:^
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_player replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:_videoURL]];
            [_player seekToTime:kCMTimeZero];
            [_player play];
        });
    }];
}

@end
