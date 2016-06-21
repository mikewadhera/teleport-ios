
#import <UIKit/UIKit.h>
#import "TP3DFlyover.h"

@interface PreviewViewController : UIViewController

@property (nonatomic, copy) NSURL *firstVideoURL;
@property (nonatomic, copy) NSURL *secondVideoURL;
@property (nonatomic, copy) CLLocation *location;
@property (nonatomic) CLLocationDirection direction;
@property (nonatomic) TP3DFlyover *flyover;

@end
