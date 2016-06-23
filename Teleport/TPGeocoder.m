
#import "TPGeocoder.h"

@implementation TPGeocoder

-(void)reverseGeocode:(CLLocation *)location completionHandler:(CLGeocodeCompletionHandler)handler
{
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:location completionHandler:handler];
}

@end
