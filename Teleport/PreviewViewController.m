
@import AVFoundation;
@import CoreLocation;
@import CoreMedia;

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
{
    CMClockRef syncClock;
}

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
    CMAudioClockCreate(kCFAllocatorDefault, &syncClock);
    
    _firstPlayer = [AVPlayer new];
    _firstPlayer.masterClock = syncClock;
    _firstPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_firstPlayer];
    _firstPlayerLayer.frame = topViewportRect;
    _firstPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    _firstPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _firstPlayer.muted = YES; // Always muted
    
    _secondPlayer = [AVPlayer new];
    _secondPlayer.masterClock = syncClock;
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
    NSString *title = [NSString stringWithFormat:@"Share 📍%@, %@  🕒 %@ ", [mark subLocality], [mark subAdministrativeArea], [dateFormatter stringFromDate:date]];
    NSMutableAttributedString *mutAttrTextViewString = [[NSMutableAttributedString alloc] initWithString:title];
    [mutAttrTextViewString setAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:12.0],
                                            NSForegroundColorAttributeName : [UIColor whiteColor]
                                           } range:NSMakeRange(0, title.length)];
    [mutAttrTextViewString setAttributes:@{ NSFontAttributeName : [UIFont boldSystemFontOfSize:12.0],
                                            NSForegroundColorAttributeName : [UIColor whiteColor]
                                            } range:[title rangeOfString:@"Share "]];
    [_advanceButton setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.35]];
    _advanceButton.layer.borderWidth = 2.0f;
    _advanceButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:1] CGColor];
    [_advanceButton setAttributedTitle:mutAttrTextViewString forState:UIControlStateNormal];
    _advanceButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [_advanceButton setFrame:CGRectMake(10, self.view.bounds.size.height-44-10, self.view.bounds.size.width-20, 44)];
    _advanceButton.alpha = 0.0f;
    [_playerView addSubview:_advanceButton];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _cancelButton.alpha = 0;
    UIImage *cancelImage = [UIImage imageNamed:@"x.png"];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(25, 24, 44, 44)];
    [_playerView addSubview:_cancelButton];
    
    [self addVideosToPlayers];
    [self playVideos];
    
    [UIView animateWithDuration:1.0 delay:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _advanceButton.alpha = 1.0;
        _cancelButton.alpha = 1.0;
    } completion:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playVideos) name:UIApplicationWillEnterForegroundNotification object:nil];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
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
    
    AVPlayerItem *firstItem = [AVPlayerItem playerItemWithAsset:firstComposition];
    AVPlayerItem *secondItem = [AVPlayerItem playerItemWithAsset:secondComposition];
    
    [_firstPlayer replaceCurrentItemWithPlayerItem:firstItem];
    [_secondPlayer replaceCurrentItemWithPlayerItem:secondItem];
    
    NSLog(@"%f", [[[_firstPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    NSLog(@"%f", [[[_secondPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
}

-(void)playVideos
{
    [self playAt:kCMTimeZero player:_firstPlayer];
    [self playAt:kCMTimeZero player:_secondPlayer];
}

-(void)playAt:(CMTime)time player:(AVPlayer*)player {
    if(player.status == AVPlayerStatusReadyToPlay && player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        [player setRate:1.0 time:time atHostTime:CMClockGetTime(syncClock)];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self playAt:time player:player];
        });
    }
}

@end
