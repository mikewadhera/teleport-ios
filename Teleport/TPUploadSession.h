
#import <Foundation/Foundation.h>

typedef NS_ENUM( NSInteger, TPUpload ) {
    TPUploadFirst,
    TPUploadSecond
};

@interface TPUploadSession : NSObject

@property (nonatomic, copy) NSURL *firstVideoURL;
@property (nonatomic, copy) NSURL *secondVideoURL;
@property (nonatomic, weak) id delegate;

-(void)enqueue:(TPUpload)firstOrSecond fileUrl:(NSURL*)fileURL;
-(BOOL)isCompleted;
-(double)currentProgress;

@end

@protocol TPUploadSessionDelegate <NSObject>

@optional
-(void)progressDidUpdate:(TPUploadSession*)uploadSession;

@end
