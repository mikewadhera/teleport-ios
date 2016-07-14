

#import "ListViewController.h"
#import "Teleport.h"
#import "PreviewViewController.h"
#import "TeleportTableViewCell.h"

@interface ListViewController ()

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
    
    teleports = [[Teleport allObjects] sortedResultsUsingProperty:@"timestamp" ascending:NO];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    [self.tableView setLayoutMargins:UIEdgeInsetsZero];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    PreviewViewController *vc = [segue destinationViewController];
    NSIndexPath *selectedIndexPath = [_tableView indexPathForSelectedRow];
    [_tableView deselectRowAtIndexPath:selectedIndexPath animated:YES];
    Teleport *teleport = [teleports objectAtIndex:selectedIndexPath.row];
    vc.teleport = teleport;
    
    [_tableView deselectRowAtIndexPath:selectedIndexPath animated:YES];
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
    cell.userLabel.text = @"Me";
    cell.statusLabel.text = [teleport status];
    [cell.userLabel sizeToFit];
    [cell.statusLabel sizeToFit];
    return cell;
}



@end
