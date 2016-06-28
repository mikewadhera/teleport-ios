
@import AVFoundation;
@import CoreLocation;
@import CoreMedia;

#import "PreviewViewController.h"

static const NSTimeInterval TPPlaybackInterval = 5.5;
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
    [_advanceButton setFrame:CGRectMake(self.view.bounds.size.width/2-68/2+55, self.view.bounds.size.height, 68, 68)];
    [_advanceButton setImage:[UIImage imageNamed:@"green.png"] forState:UIControlStateNormal];
    [_advanceButton addTarget:self action:@selector(springOut:) forControlEvents:UIControlEventTouchDown];
    [_advanceButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchUpInside];
    [_advanceButton addTarget:self action:@selector(advance) forControlEvents:UIControlEventTouchUpInside];
    [_advanceButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchDragExit];
    [_playerView addSubview:_advanceButton];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *cancelImage = [UIImage imageNamed:@"red.png"];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(self.view.bounds.size.width/2-68/2-55, self.view.bounds.size.height, 68, 68)];
    [_cancelButton addTarget:self action:@selector(springOut:) forControlEvents:UIControlEventTouchDown];
    [_cancelButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchUpInside];
    [_cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [_cancelButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchDragExit];
    [_playerView addSubview:_cancelButton];
    
    [self addVideosToPlayers];
    [self playVideos];
    
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [_advanceButton setFrame:CGRectMake(self.view.bounds.size.width/2-68/2+55, self.view.bounds.size.height-68-26, 68, 68)];
        [_cancelButton setFrame:CGRectMake(self.view.bounds.size.width/2-68/2-55, self.view.bounds.size.height-68-26, 68, 68)];
    } completion:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playVideos) name:UIApplicationWillEnterForegroundNotification object:nil];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

-(void)cancel
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:NO];
    });
}

-(void)advance
{
    
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

-(void)springOut:(UIButton*)sender
{
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.layer.transform = CATransform3DMakeScale(1.3, 1.3, 1.0);
    } completion:nil];
}

-(void)restore:(UIButton*)sender
{
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.layer.transform = CATransform3DMakeScale(1.0, 1.0, 1.0);
    } completion:nil];
}

@end
