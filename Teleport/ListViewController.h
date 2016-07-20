

#import <UIKit/UIKit.h>

@interface ListViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic) dispatch_block_t onDismissHandler;

@end
