
#import "TeleportTableViewCell.h"

@implementation TeleportTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    UIView *bgColorView = [[UIView alloc] init];
    bgColorView.backgroundColor = [UIColor darkGrayColor];
    bgColorView.layer.masksToBounds = YES;
    [self setSelectedBackgroundView:bgColorView];
}

-(void)reload:(Teleport*)model
{
    self.userLabel.text = @"Me";
    self.statusLabel.text = [model status];
    self.dateLabel.text = [model date];
    [self.userLabel sizeToFit];
    [self.statusLabel sizeToFit];
}

@end
