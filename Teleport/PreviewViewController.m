
@import AVFoundation;
@import CoreLocation;
@import CoreMedia;

#import "PreviewViewController.h"
#import "MaterialDesignSymbol.h"
#import "TeleportImages.h"

@interface PreviewViewController ()

@property (nonatomic) UIView *playerView;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) AVPlayer *secondPlayer;
@property (nonatomic) AVPlayerLayer *secondPlayerLayer;
@property (nonatomic) UIView *menuView;
@property (nonatomic) UIButton *advanceButton;
@property (nonatomic) UIButton *cancelButton;
@property (nonatomic) UIButton *replayButton;
@property (nonatomic) UIView *topEyeLensView;
@property (nonatomic) UIView *bottomEyeLensView;

@end

@implementation PreviewViewController
{
    CMClockRef syncClock;
    CGRect topViewportRect;
    CGRect bottomViewportRect;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    NSNumber *fileSizeValue = nil;
    [[NSURL fileURLWithPath:[_teleport pathForVideo1]] getResourceValue:&fileSizeValue
                       forKey:NSURLFileSizeKey
                        error:nil];
    if (fileSizeValue) {
        NSLog(@"value for %@ is %f", [_teleport pathForVideo1], [fileSizeValue floatValue]/1024.0f/1024.0f);
    }
    NSNumber *fileSizeValue2 = nil;
    [[NSURL fileURLWithPath:[_teleport pathForVideo2]] getResourceValue:&fileSizeValue2
                              forKey:NSURLFileSizeKey
                               error:nil];
    if (fileSizeValue2) {
        NSLog(@"value for %@ is %f", [_teleport pathForVideo2], [fileSizeValue2 floatValue]/1024.0f/1024.0f);
    }
    
    // Calculate Viewports
    int topViewW = self.view.frame.size.width;
    int topViewH = ceil(self.view.frame.size.height / 2.0);
    int topViewX = 0;
    int topViewY = 0;
    topViewportRect = CGRectMake(topViewX, topViewY, topViewW, topViewH);
    
    int bottomViewW = self.view.frame.size.width;
    int bottomViewH = ceil(self.view.frame.size.height / 2.0);
    int bottomViewX = 0;
    int bottomViewY = floor(self.view.frame.size.height / 2.0);
    bottomViewportRect = CGRectMake(bottomViewX, bottomViewY, bottomViewW, bottomViewH);
    
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
    
    _topEyeLensView = [[UIView alloc] initWithFrame:topViewportRect];
    _topEyeLensView.backgroundColor = [UIColor blackColor];
    
    _bottomEyeLensView = [[UIView alloc] initWithFrame:bottomViewportRect];
    _bottomEyeLensView.backgroundColor = [UIColor blackColor];
    
    [self.view addSubview:_playerView];
    [self.view addSubview:_topEyeLensView];
    [self.view addSubview:_bottomEyeLensView];
    
    // Menu
    _menuView = [[UIView alloc] initWithFrame:self.view.bounds];
    _menuView.alpha = 0.0;
    
    // Buttons
    NSInteger buttonSize = 70;
    NSInteger barWidth = 20;
    NSInteger barPadding = 10;
    
    
    MaterialDesignSymbol *replaySymbol = [MaterialDesignSymbol iconWithCode:MaterialDesignIconCode.refresh48px fontSize:buttonSize];
    [replaySymbol addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor]];
    
    MaterialDesignSymbol *advanceSymbol = [MaterialDesignSymbol iconWithCode:MaterialDesignIconCode.doneAll48px fontSize:buttonSize];
    [advanceSymbol addAttribute:NSForegroundColorAttributeName value:[UIColor greenColor]];
    
    UIImage *replayImage = [replaySymbol image];
    UIImage *advanceImage = [advanceSymbol image];
    UIImage *cancelImage = [TeleportImages recordBarImage:buttonSize-10];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(barWidth+barPadding,
                                       _menuView.frame.size.height-barWidth-barPadding-buttonSize+1,
                                       buttonSize,
                                       buttonSize)];
    [_cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [_menuView addSubview:_cancelButton];
    
    _replayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_replayButton setImage:replayImage forState:UIControlStateNormal];
    [_replayButton setFrame:CGRectMake((_menuView.frame.size.width/2.0)-(buttonSize/2.0),
                                       _menuView.frame.size.height-barWidth-barPadding-buttonSize,
                                       buttonSize,
                                       buttonSize)];
    [_replayButton addTarget:self action:@selector(replay) forControlEvents:UIControlEventTouchUpInside];
    [_menuView addSubview:_replayButton];
    
    _advanceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_advanceButton setFrame:CGRectMake(_menuView.frame.size.width-barWidth-barPadding-buttonSize,
                                        _menuView.frame.size.height-barWidth-barPadding-buttonSize,
                                        buttonSize,
                                        buttonSize)];
    [_advanceButton setImage:advanceImage forState:UIControlStateNormal];
    [_advanceButton addTarget:self action:@selector(advance) forControlEvents:UIControlEventTouchUpInside];
    [_menuView addSubview:_advanceButton];
    
    [self.view addSubview:_menuView];
    
    [self setup];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerWillForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerWillBackground) name:UIApplicationWillResignActiveNotification object:nil];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self playVideos];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}

-(void)controllerWillBackground
{
    [self stopAnimation:nil];
}

-(void)controllerWillForeground
{
    [self playVideos];
}

-(void)playVideos
{
    if (_menuEnabled) {
        if (_menuView.alpha > 0) return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self playAt:kCMTimeZero player:_firstPlayer];
        [self playAt:kCMTimeZero player:_secondPlayer];
        [self startAnimation];
    });
}

-(void)didFinishPlaying:(NSNotification *) notification
{
    [self stopAnimation:^{
        if (_menuEnabled) {
            [UIView animateWithDuration:0.2f animations:^{
                _menuView.alpha = 1.0;
            }];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }];
}


-(void)cancel
{
    [self.navigationController popViewControllerAnimated:NO];
    [Teleport cleanupCaches:_teleport];
    _teleport = nil;
}

-(void)replay
{
    // We need to re-create the state of when -viewDidLoad is called
    [_topEyeLensView setFrame:_firstPlayerLayer.frame];
    [_bottomEyeLensView setFrame:_secondPlayerLayer.frame];
    _playerView.alpha = 1.0;
    [UIView animateWithDuration:0.2f animations:^{
        _menuView.alpha = 0.0f;
    } completion:^(BOOL finished) {
        [self playVideos];
    }];
}

-(void)advance
{
    // Save to DB
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    [realm addObject:_teleport];
    [realm commitWriteTransaction];
    if (self.onAdvanceHandler) self.onAdvanceHandler();    
    [self.navigationController popViewControllerAnimated:YES];
}

-(void)startAnimation
{
    double animationDuation = 0.3;
    
    [UIView animateWithDuration:animationDuation delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [_topEyeLensView setFrame:CGRectMake(_topEyeLensView.frame.origin.x, -_topEyeLensView.frame.size.height, _topEyeLensView.frame.size.width, _topEyeLensView.frame.size.height)];
        
        [_bottomEyeLensView setFrame:CGRectMake(_bottomEyeLensView.frame.origin.x, _bottomEyeLensView.frame.origin.y+_bottomEyeLensView.frame.size.height, _bottomEyeLensView.frame.size.width, _bottomEyeLensView.frame.size.height)];
    } completion:nil];
}

-(void)stopAnimation:(dispatch_block_t)completion
{
    NSTimeInterval duration = 0.3f;
    [UIView animateWithDuration:duration
                          delay:0.0f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         [_topEyeLensView setFrame:topViewportRect];
                         [_bottomEyeLensView setFrame:bottomViewportRect];
                     } completion:^(BOOL finished) {
                         if (completion) completion();
                     }];
}

-(void)setup
{
    AVAsset *firstAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[_teleport pathForVideo1]] options:nil];
    AVAsset *secondAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[_teleport pathForVideo2]] options:nil];
    NSLog(@"1: %f", CMTimeGetSeconds(firstAsset.duration));
    NSLog(@"2: %f", CMTimeGetSeconds(secondAsset.duration));
    
    // Create a composition
    AVMutableComposition *firstComposition = [AVMutableComposition composition];
    AVMutableComposition *secondComposition = [AVMutableComposition composition];
    
    // NOTE: We clip the to length of shorter duration
    AVAsset *shorterAsset = CMTimeGetSeconds(firstAsset.duration) > CMTimeGetSeconds(secondAsset.duration) ? secondAsset : firstAsset;
    CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, shorterAsset.duration);
    [firstComposition insertTimeRange:timeRange ofAsset:firstAsset atTime:firstComposition.duration error:nil];
    [secondComposition insertTimeRange:timeRange ofAsset:secondAsset atTime:secondComposition.duration error:nil];
    
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:shorterAsset==firstAsset?firstItem:secondItem];
    
    [_firstPlayer replaceCurrentItemWithPlayerItem:firstItem];
    [_secondPlayer replaceCurrentItemWithPlayerItem:secondItem];
    
    NSLog(@"%f", [[[_firstPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
    NSLog(@"%f", [[[_secondPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject] estimatedDataRate]);
}

-(void)playAt:(CMTime)time player:(AVPlayer*)player {
    if(player.status == AVPlayerStatusReadyToPlay && player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        [player setRate:1.0 time:time atHostTime:CMClockGetTime(syncClock)];
    } else {
        NSLog(@"NOT READY!!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self playAt:time player:player];
        });
    }
}

@end
