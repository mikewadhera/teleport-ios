

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
    self.tableView.backgroundColor = [UIColor blackColor];
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 10;
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
    NSString *labelText = @"Mike Wadhera\n📍Marina District 🕒 1:56 PM ";
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:labelText];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    [paragraphStyle setLineSpacing:13.5];
    [attributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, [labelText length])];
    cell.textLabel.attributedText = attributedString;
    
    return cell;
}



@end
