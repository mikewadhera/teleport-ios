
#import "TeleportTableViewCell.h"

@implementation TeleportTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    UIView *bgColorView = [[UIView alloc] init];
    bgColorView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:1.0];
    bgColorView.layer.masksToBounds = YES;
    [self setSelectedBackgroundView:bgColorView];
}

@end
