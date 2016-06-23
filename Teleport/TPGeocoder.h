
#import <Foundation/Foundation.h>
@import CoreLocation;

@interface TPGeocoder : NSObject

-(void)reverseGeocode:(CLLocation *)location completionHandler:(CLGeocodeCompletionHandler)handler;

@end
