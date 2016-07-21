

#import "ListViewController.h"
#import "Teleport.h"
#import "PreviewViewController.h"
#import "TeleportTableViewCell.h"
#import "TeleportImages.h"

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
    
    self.title = @"Teleports";
    
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    teleports = [[Teleport allObjects] sortedResultsUsingProperty:@"timestamp" ascending:YES];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self scrollTableToBottom];
    
    if (_tableView.indexPathForSelectedRow) {
        [_tableView deselectRowAtIndexPath:_tableView.indexPathForSelectedRow animated:YES];
    }
}

- (void)scrollTableToBottom
{
    if (!self.isViewLoaded || teleports.count == 0 || [self tableHeightMinusTableRowsHeight] >= 0)
        return;
    
    CGFloat offsetY = self.tableView.contentSize.height - self.tableView.frame.size.height + self.tableView.contentInset.bottom;
    
    [self.tableView setContentOffset:CGPointMake(0, offsetY) animated:NO];
}

-(void)reload
{
    [_tableView reloadData];
}

-(void)selectFirst
{
    [self scrollTableToBottom];
    [_tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:teleports.count-1 inSection:0]
                            animated:NO
                      scrollPosition:UITableViewScrollPositionBottom];
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
    PreviewViewController *vc = [self.storyboard instantiateViewControllerWithIdentifier:@"preview"];
    NSIndexPath *selectedIndexPath = [_tableView indexPathForSelectedRow];
    Teleport *teleport = [teleports objectAtIndex:selectedIndexPath.row];
    vc.teleport = teleport;
    [self.navigationController pushViewController:vc animated:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectZero];
    headerView.userInteractionEnabled = NO;
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return MAX(0, [self tableHeightMinusTableRowsHeight]);
}

-(CGFloat)tableHeightMinusTableRowsHeight
{
    CGFloat tableHeight = self.tableView.frame.size.height;
    CGFloat tableRowsHeight = teleports.count * 88;
    return tableHeight - tableRowsHeight;
}

@end
