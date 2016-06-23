
@import AVFoundation;
@import CoreLocation;

#import "PreviewViewController.h"

static const NSTimeInterval TPPlaybackInterval = 5.0;
static const NSInteger TPPlaybackMaxLoopCount = 100;

@interface PreviewViewController ()

@property (nonatomic) UIView *playerView;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) AVPlayer *secondPlayer;
@property (nonatomic) AVPlayerLayer *secondPlayerLayer;
@property (nonatomic) NSURL *videoURL;
@property (nonatomic) UIButton *advanceButton;
@property (nonatomic) UIButton *cancelButton;

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
    
    // Player
    _firstPlayer = [AVPlayer new];
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.frame = topViewportRect;
    _firstPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _firstPlayer.muted = YES; // Always muted
    
    _secondPlayer = [AVPlayer new];
    _secondPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_secondPlayer];
    _secondPlayerLayer.frame = bottomViewportRect;
    _secondPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _secondPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    _playerView = [[UIView alloc] initWithFrame:self.view.bounds];
    [_playerView.layer addSublayer:_firstPlayerLayer];
    [_playerView.layer addSublayer:_secondPlayerLayer];
    [self.view addSubview:_playerView];
    
    // Buttons
    _advanceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CLPlacemark *mark = [_placemarks firstObject];
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"h:mm a"];
    NSString *title = [NSString stringWithFormat:@"📍%@, %@  🕒 %@ ", [mark subLocality], [mark subAdministrativeArea], [dateFormatter stringFromDate:date]];
    [_advanceButton setBackgroundColor:[UIColor colorWithWhite:0.10 alpha:0.9]];
    UIImage *image = [UIImage imageNamed:@"chevron.png"];
    [_advanceButton setImage:image forState:UIControlStateNormal];
    [_advanceButton setTitle:title forState:UIControlStateNormal];
    _advanceButton.titleLabel.font = [UIFont systemFontOfSize:12];
    _advanceButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _advanceButton.contentEdgeInsets = UIEdgeInsetsMake(0, -image.size.width+10, 0, 0);
    _advanceButton.imageEdgeInsets = UIEdgeInsetsMake(0, self.view.bounds.size.width-18, 0, 0);
    [_advanceButton setFrame:CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, 44)];
    [_playerView addSubview:_advanceButton];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _cancelButton.alpha = 0.77;
    UIImage *cancelImage = [UIImage imageNamed:@"x.png"];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(25, 24, 44, 44)];
    [_playerView addSubview:_cancelButton];
    
    [self addVideosToPlayers];
    [self playVideos];
    
    [UIView animateWithDuration:1.0 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [_advanceButton setFrame:CGRectMake(0, self.view.bounds.size.height-44, self.view.bounds.size.width, 44)];
    } completion:nil];
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
    
    NSLog(@"%f", [[[_firstPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    NSLog(@"%f", [[[_secondPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
}

-(void)playVideos
{
    [_firstPlayer play];
    [_secondPlayer play];
}

@end
