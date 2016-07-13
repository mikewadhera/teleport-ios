

#import "ListViewController.h"
#import "Teleport.h"
#import "PreviewViewController.h"

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
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    // Configure the cell...
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.textLabel.font = [UIFont systemFontOfSize:13.5];
        cell.backgroundColor = [UIColor colorWithRed:0.15 green:0.17 blue:0.18 alpha:1.0];
        cell.contentView.backgroundColor = cell.backgroundColor;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.numberOfLines = 0;
    }
    Teleport *teleport = [teleports objectAtIndex:indexPath.row];
    NSString *labelText = [NSString stringWithFormat:@"%@", teleport];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:labelText];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    [paragraphStyle setLineSpacing:13.5];
    [attributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, [labelText length])];
    cell.textLabel.attributedText = attributedString;
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self performSegueWithIdentifier:@"Teleport" sender:self];
}



@end
