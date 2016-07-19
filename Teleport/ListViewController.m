

#import "ListViewController.h"
#import "Teleport.h"
#import "PreviewViewController.h"
#import "TeleportTableViewCell.h"
#import "CECrossfadeAnimationController.h"
#import "TeleportImages.h"

@interface ListViewController () <UINavigationControllerDelegate>

@property (nonatomic, strong) id animator;
@property (nonatomic) UIButton *cancelButton;

@end

@implementation ListViewController
{
    RLMResults<Teleport *> *teleports;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Teleports";
    
    self.navigationController.delegate = self;
    
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    CGFloat barWidth = floorf((self.view.bounds.size.width*0.07));
    CGFloat barPadding = 10;
    CGFloat buttonSize = 48;
    UIImage *cancelImage = [TeleportImages recordBarImage:buttonSize];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setImage:cancelImage forState:UIControlStateNormal];
    [_cancelButton setFrame:CGRectMake(self.view.bounds.size.width-barWidth-barPadding-buttonSize+5,
                                       self.view.bounds.size.height-barWidth-barPadding-buttonSize+10,
                                       buttonSize,
                                       buttonSize)];
    [_cancelButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];
    
    teleports = [[Teleport allObjects] sortedResultsUsingProperty:@"timestamp" ascending:NO];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (_tableView.indexPathForSelectedRow) {
        [_tableView deselectRowAtIndexPath:_tableView.indexPathForSelectedRow animated:YES];
    } else {
        [_tableView reloadData];
    }
}

-(void)dismiss
{
    [self dismissViewControllerAnimated:NO completion:nil];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    PreviewViewController *vc = [segue destinationViewController];
    NSIndexPath *selectedIndexPath = [_tableView indexPathForSelectedRow];
    Teleport *teleport = [teleports objectAtIndex:selectedIndexPath.row];
    vc.teleport = teleport;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return teleports.count;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"TeleportMenuCell";
    TeleportTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    // Configure the cell...
    if (cell == nil) {
        cell = [[TeleportTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    Teleport *teleport = [teleports objectAtIndex:indexPath.row];
    [cell reload:teleport];
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:@"ShowPreview" sender:self];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation
                                               fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC
{
    self.animator = nil;
    if ([fromVC class] == [PreviewViewController class] ||
        [toVC class] == [PreviewViewController class]) {
        self.animator = [CECrossfadeAnimationController new];
        [self.animator setReverse:(operation == UINavigationControllerOperationPop)];
    }
    return self.animator;
}



@end
