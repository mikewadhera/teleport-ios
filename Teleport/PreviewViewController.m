
@import AVFoundation;
@import MapKit;

#import "PreviewViewController.h"
#import "TP3DFlyover.h"

static const NSTimeInterval TPPlaybackInterval = 5.0;
static const NSInteger TPPlaybackMaxLoopCount = 100;
static const NSTimeInterval TPFlyoverInterval = 3.09;
static const NSTimeInterval TPFlyoverCutFadeInterval = 0.2;

@interface PreviewViewController ()

@property (nonatomic) UIView *playerView;
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
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.frame = topViewportRect;
    _firstPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _firstPlayer.muted = YES; // Always muted
    NSLog(@"%f", [[[_firstPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    
    _secondPlayer = [AVPlayer new];
    _secondPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_secondPlayer];
    _secondPlayerLayer.frame = bottomViewportRect;
    _secondPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _secondPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    NSLog(@"%f", [[[_secondPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    
    _playerView = [[UIView alloc] initWithFrame:self.view.bounds];
    [_playerView.layer addSublayer:_firstPlayerLayer];
    [_playerView.layer addSublayer:_secondPlayerLayer];
    
    [self.view addSubview:_playerView];
    [self addVideosToPlayers];
    [self playVideos];
    
//    [_flyover.mapView removeFromSuperview];
//    [_flyover.mapView setFrame:self.view.bounds];
//    [self.view addSubview:_flyover.mapView];
//    _flyover.mapView.alpha = 1;
//    [_flyover start];
//    
//    [self performSelector:@selector(playVideo) withObject:nil afterDelay:TPFlyoverInterval];
}

-(void)addVideosToPlayers
{
    // Create a composition to ensure smooth looping
    AVMutableComposition *firstComposition = [AVMutableComposition composition];
    AVMutableComposition *secondComposition = [AVMutableComposition composition];
    AVAsset *firstAsset = [AVURLAsset URLAssetWithURL:_firstVideoURL options:nil];
    AVAsset *secondAsset = [AVURLAsset URLAssetWithURL:_secondVideoURL options:nil];
    CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(TPPlaybackInterval, 1));
    for (NSUInteger i = 0; i < TPPlaybackMaxLoopCount; i++) {
        [firstComposition insertTimeRange:timeRange ofAsset:firstAsset atTime:firstComposition.duration error:nil];
        [secondComposition insertTimeRange:timeRange ofAsset:secondAsset atTime:secondComposition.duration error:nil];
    }
    
    // Orientation fix
    AVAssetTrack *firstAssetVideoTrack = [firstAsset tracksWithMediaType:AVMediaTypeVideo].lastObject;
    AVMutableCompositionTrack *firstCompositionVideoTrack = [firstComposition tracksWithMediaType:AVMediaTypeVideo].lastObject;
    if (firstAssetVideoTrack && firstCompositionVideoTrack) {
        [firstCompositionVideoTrack setPreferredTransform:firstAssetVideoTrack.preferredTransform];
    }
    AVAssetTrack *secondAssetVideoTrack = [secondAsset tracksWithMediaType:AVMediaTypeVideo].lastObject;
    AVMutableCompositionTrack *secondCompositionVideoTrack = [secondComposition tracksWithMediaType:AVMediaTypeVideo].lastObject;
    if (secondAssetVideoTrack && secondCompositionVideoTrack) {
        [secondCompositionVideoTrack setPreferredTransform:secondAssetVideoTrack.preferredTransform];
    }
    
    [_firstPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithAsset:firstComposition]];
    [_secondPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithAsset:secondComposition]];
}

-(void)playVideos
{
    [_firstPlayer play];
    [_secondPlayer play];
//    [UIView transitionFromView:_flyover.mapView
//                        toView:_playerView
//                      duration:TPFlyoverCutFadeInterval
//                       options:UIViewAnimationOptionTransitionCrossDissolve
//                    completion:^(BOOL finished) {
//                        [_flyover.mapView removeFromSuperview];
//                    }];
}

@end
