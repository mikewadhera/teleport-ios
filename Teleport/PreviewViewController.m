
@import AVFoundation;
@import CoreLocation;
@import CoreMedia;

#import "PreviewViewController.h"
#import "MaterialDesignSymbol.h"

@interface PreviewViewController ()

@property (nonatomic) UIView *playerView;
@property (nonatomic) AVPlayer *firstPlayer;
@property (nonatomic) AVPlayerLayer *firstPlayerLayer;
@property (nonatomic) AVPlayer *secondPlayer;
@property (nonatomic) AVPlayerLayer *secondPlayerLayer;
@property (nonatomic) UIVisualEffectView *menuView;
@property (nonatomic) UIButton *advanceButton;
@property (nonatomic) UIButton *cancelButton;
@property (nonatomic) UIButton *replayButton;

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
    
    self.view.backgroundColor = [UIColor whiteColor];
    
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
    _playerView.alpha = 0.0f;
    
    [self.view addSubview:_playerView];
    
    // Menu
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _menuView = [[UIVisualEffectView alloc] initWithEffect:effect];
    _menuView.frame = self.view.bounds;
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
    UIImage *cancelImage = [self recordBarImage:buttonSize-10];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(barWidth+barPadding,
                                       _menuView.frame.size.height-barWidth-barPadding-buttonSize+1,
                                       buttonSize,
                                       buttonSize)];
    [_cancelButton addTarget:self action:@selector(springOut:) forControlEvents:UIControlEventTouchDown];
    [_cancelButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchUpInside];
    [_cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [_cancelButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchDragExit];
    [_menuView addSubview:_cancelButton];
    
    _replayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_replayButton setImage:replayImage forState:UIControlStateNormal];
    [_replayButton setFrame:CGRectMake((_menuView.frame.size.width/2.0)-(buttonSize/2.0),
                                       _menuView.frame.size.height-barWidth-barPadding-buttonSize,
                                       buttonSize,
                                       buttonSize)];
    [_replayButton addTarget:self action:@selector(springOut:) forControlEvents:UIControlEventTouchDown];
    [_replayButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchUpInside];
    [_replayButton addTarget:self action:@selector(replay) forControlEvents:UIControlEventTouchUpInside];
    [_replayButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchDragExit];
    [_menuView addSubview:_replayButton];
    
    _advanceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_advanceButton setFrame:CGRectMake(_menuView.frame.size.width-barWidth-barPadding-buttonSize,
                                        _menuView.frame.size.height-barWidth-barPadding-buttonSize,
                                        buttonSize,
                                        buttonSize)];
    [_advanceButton setImage:advanceImage forState:UIControlStateNormal];
    [_advanceButton addTarget:self action:@selector(springOut:) forControlEvents:UIControlEventTouchDown];
    [_advanceButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchUpInside];
    [_advanceButton addTarget:self action:@selector(advance) forControlEvents:UIControlEventTouchUpInside];
    [_advanceButton addTarget:self action:@selector(restore:) forControlEvents:UIControlEventTouchDragExit];
    [_menuView addSubview:_advanceButton];
    
    [self.view addSubview:_menuView];
    
    [self addVideosToPlayers];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playVideos) name:UIApplicationWillEnterForegroundNotification object:nil];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}

-(void)cancel
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:NO];
        [Teleport cleanupCaches:_teleport];
        _teleport = nil;
    });
}

-(void)replay
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // We need to re-create the state of when -viewDidLoad is called
        UIView *whiteView = [[UIView alloc] initWithFrame:self.view.bounds];
        whiteView.backgroundColor = [UIColor whiteColor];
        whiteView.alpha = 0.0;
        [self.view addSubview:whiteView];
        [UIView animateWithDuration:0.2f animations:^{
            whiteView.alpha = 1.0;
        } completion:^(BOOL finished) {
            [_firstPlayer seekToTime:kCMTimeZero];
            [_secondPlayer seekToTime:kCMTimeZero];
            _menuView.alpha = 0.0;
            _playerView.alpha = 0.0;
            [whiteView removeFromSuperview];
            [self playVideos];
        }];
    });
}

-(void)advance
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Save to DB
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm beginWriteTransaction];
        [realm addObject:_teleport];
        [realm commitWriteTransaction];
        [self.navigationController popViewControllerAnimated:NO];
    });
}

-(void)addVideosToPlayers
{
    // Create a composition to ensure smooth looping
    AVMutableComposition *firstComposition = [AVMutableComposition composition];
    AVMutableComposition *secondComposition = [AVMutableComposition composition];
    AVAsset *firstAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[_teleport pathForVideo1]] options:nil];
    AVAsset *secondAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[_teleport pathForVideo2]] options:nil];
    NSLog(@"1: %f", CMTimeGetSeconds(firstAsset.duration));
    NSLog(@"2: %f", CMTimeGetSeconds(secondAsset.duration));
    
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

-(void)playVideos
{
    if (_menuEnabled) {
        if (_menuView.alpha > 0) return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self playAt:kCMTimeZero player:_firstPlayer];
        [self playAt:kCMTimeZero player:_secondPlayer];
        NSTimeInterval duration = 0.3f;
        [UIView animateWithDuration:duration
                              delay:0.3f
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
                             _playerView.alpha = 1.0;
                         } completion:nil];
    });
}

-(void)didFinishPlaying:(NSNotification *) notification
{
    if (_menuEnabled) {
        [UIView animateWithDuration:0.2f animations:^{
            _menuView.alpha = 1.0;
        }];
    } else {
        NSTimeInterval duration = 0.3f;
        [UIView animateWithDuration:duration
                              delay:0.0f
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
                             _playerView.alpha = 0.0;
                         } completion:^(BOOL finished) {
                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                 [self dismissViewControllerAnimated:NO completion:nil];
                             });
                         }];
    }
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

-(UIImage*)recordBarImage:(NSInteger)height
{
    CGFloat width = ceil(height/(16.0/9.0));
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, width, height)];
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.path = path.CGPath;
    layer.frame = CGRectMake(0, 0, width, height);
    [layer setStrokeColor:[UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:1].CGColor];
    [layer setLineWidth:ceil(0.20*width)];
    [layer setFillColor:[UIColor clearColor].CGColor];
    
    UIGraphicsBeginImageContextWithOptions(layer.frame.size, NO, 0);
    
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return outputImage;
}

@end
