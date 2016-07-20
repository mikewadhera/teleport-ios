
#import <UIKit/UIKit.h>
#import "Teleport.h"

@interface PreviewViewController : UIViewController

@property (nonatomic, strong) Teleport *teleport;
@property (nonatomic) BOOL menuEnabled;
@property (nonatomic) dispatch_block_t onAdvanceHandler;

@end
