
#import "TPUploadSession.h"

#import <AWSS3/AWSS3.h>

NSString *const TPUploadBucket = @"teleport-beta";
NSString *const TPVideoContentType = @"video/quicktime";
NSString *const TPUploadKeyFormat = @"videos/%@/%ld";

@interface TPUploadSession ()

@property (nonatomic, copy) NSString *teleportId;
@property (nonatomic, strong) AWSS3TransferUtility *transferUtility;
@property (nonatomic) NSProgress *firstProgress;
@property (nonatomic) NSProgress *secondProgress;

@end

@implementation TPUploadSession

-(instancetype)initWithId:(NSString*)teleportId
{
    self = [super init];
    if (self) {
        _teleportId = teleportId;
        _transferUtility = [AWSS3TransferUtility defaultS3TransferUtility];
    }
    return self;
}

-(double)currentProgress
{
    return (_firstProgress.fractionCompleted+_secondProgress.fractionCompleted)/2.0;
}

-(BOOL)isCompleted
{
    return _firstVideoURL && _secondVideoURL;
}

-(void)enqueue:(TPUpload)firstOrSecond fileUrl:(NSURL*)fileURL
{
    NSString *key = [NSString stringWithFormat:TPUploadKeyFormat, _teleportId, (long)firstOrSecond];
    
    AWSS3TransferUtilityUploadExpression *expression = [AWSS3TransferUtilityUploadExpression new];
    expression.progressBlock = ^(AWSS3TransferUtilityTask *task, NSProgress *progress) {
        switch (firstOrSecond) {
            case TPUploadFirst:
                _firstProgress = progress;
                break;
            case TPUploadSecond:
                _secondProgress = progress;
                break;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_delegate respondsToSelector:@selector(progressDidUpdate:)]) {
                [_delegate progressDidUpdate:self];
            }
        });
    };
    
    [_transferUtility uploadFile:fileURL
                          bucket:TPUploadBucket
                             key:key
                     contentType:TPVideoContentType
                      expression:expression
                completionHander:^(AWSS3TransferUtilityUploadTask *task, NSError *error) {
                    switch (firstOrSecond) {
                        case TPUploadFirst:
                            _firstVideoURL = task.response.URL;
                            break;
                        case TPUploadSecond:
                            _secondVideoURL = task.response.URL;
                            break;
                    }
                }];
}

@end
