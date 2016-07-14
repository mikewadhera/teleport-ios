
#import <UIKit/UIKit.h>
#import "Teleport.h"

@interface TeleportTableViewCell : UITableViewCell

@property (nonatomic) IBOutlet UILabel *userLabel;
@property (nonatomic) IBOutlet UILabel *statusLabel;
@property (nonatomic) IBOutlet UILabel *dateLabel;

-(void)reload:(Teleport*)model;

@end
