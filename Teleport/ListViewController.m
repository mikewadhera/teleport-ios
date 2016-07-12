

#import "ListViewController.h"

@interface ListViewController ()

@end

@implementation ListViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
}

@end
