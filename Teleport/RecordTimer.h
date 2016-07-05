
#import <Foundation/Foundation.h>

@interface RecordTimer : NSObject

+(instancetype)scheduleTimerWithTimeInterval:(CFTimeInterval)interval block:(dispatch_block_t)block;
-(instancetype)initWithFireDate:(CFTimeInterval)fireTime block:(dispatch_block_t)block;
-(void)invalidate;

@end
