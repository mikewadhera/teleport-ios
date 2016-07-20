

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
    
    teleports = [[Teleport allObjects] sortedResultsUsingProperty:@"timestamp" ascending:NO];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (_tableView.indexPathForSelectedRow) {
        [_tableView deselectRowAtIndexPath:_tableView.indexPathForSelectedRow animated:YES];
    }
}

-(void)reload
{
    [_tableView reloadData];
}

-(void)selectFirst
{
    [_tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                            animated:NO
                      scrollPosition:UITableViewScrollPositionTop];
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

@end
