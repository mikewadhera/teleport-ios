//
//  TeleportImages.m
//  Teleport
//
//  Created by Mike Wadhera on 7/14/16.
//  Copyright © 2016 SportsFeed, LLC. All rights reserved.
//

#import "TeleportImages.h"

@implementation TeleportImages

+(UIImage*)recordBarImage:(NSInteger)height
{
    CGFloat width = ceil(height/(16.0/9.0));
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, width, height)];
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.path = path.CGPath;
    layer.frame = CGRectMake(0, 0, width, height);
    [layer setStrokeColor:[UIColor colorWithRed:1.0 green:0.13 blue:0.13 alpha:0.5].CGColor];
    [layer setLineWidth:ceil(0.25*width)];
    [layer setFillColor:[UIColor clearColor].CGColor];
    
    UIGraphicsBeginImageContextWithOptions(layer.frame.size, NO, 0);
    
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return outputImage;
}

@end
