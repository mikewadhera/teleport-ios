
#import <UIKit/UIKit.h>

@interface PreviewViewController : UIViewController

@property (nonatomic, copy) NSURL *firstVideoURL;
@property (nonatomic, copy) NSURL *secondVideoURL;
@property (nonatomic, strong) UIImage *firstVideoImage;
@property (nonatomic, strong) UIImage *secondVideoImage;
@property (nonatomic, copy) CLLocation *location;
@property (nonatomic) NSArray *placemarks;

@end
