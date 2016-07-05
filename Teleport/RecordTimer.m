
@import QuartzCore;

#import "RecordTimer.h"

@interface RecordTimer ()

@property (nonatomic) dispatch_block_t dispatchBlock;
@property (nonatomic) CFTimeInterval dispatchTime;
@property (nonatomic) CADisplayLink *displayLink;

@end

@implementation RecordTimer
{
    BOOL shouldInvalidate;
}

+(instancetype)scheduleTimerWithTimeInterval:(CFTimeInterval)interval block:(dispatch_block_t)block
{
    CFTimeInterval fireTime = CACurrentMediaTime() + interval;
    RecordTimer *timer = [[RecordTimer alloc] initWithFireDate:fireTime block:block];
    [timer startTicking];
    return timer;
}

-(instancetype)initWithFireDate:(CFTimeInterval)fireTime block:(dispatch_block_t)block
{
    self = [super init];
    if (self) {
        _dispatchTime = fireTime;
        _dispatchBlock = block;
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    }
    return self;
}

-(void)startTicking
{
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

-(void)invalidate
{
    [_displayLink invalidate];
    shouldInvalidate = NO;
}

-(void)tick:(CADisplayLink*)link
{
    if (shouldInvalidate) {
        [self invalidate];
        return;
    }
    if ([link timestamp] >= _dispatchTime) {
        _dispatchBlock();
        shouldInvalidate = YES; // Queue invalidation
    }
}

@end
