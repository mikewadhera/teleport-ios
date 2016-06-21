
@import AVFoundation;
@import MapKit;

#import "PreviewViewController.h"
#import "TP3DFlyover.h"

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
    
    _playerView = [[UIView alloc] initWithFrame:self.view.bounds];
    [_playerView.layer addSublayer:_firstPlayerLayer];
    [_playerView.layer addSublayer:_secondPlayerLayer];
    
    [_flyover.mapView removeFromSuperview];
    [_flyover.mapView setFrame:self.view.bounds];
    [self.view addSubview:_flyover.mapView];
    _flyover.mapView.alpha = 1;
    [_flyover start];
    
    [self performSelector:@selector(playVideo) withObject:nil afterDelay:TPFlyoverInterval];
}

-(void)playVideo
{
    [_firstPlayer play];
    [_secondPlayer play];
    [UIView transitionFromView:_flyover.mapView
                        toView:_playerView
                      duration:TPFlyoverCutFadeInterval
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    completion:^(BOOL finished) {
                        [_flyover.mapView removeFromSuperview];
                    }];
}

@end
