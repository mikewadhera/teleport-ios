
#import <Foundation/Foundation.h>
@import MapKit;

@interface TP3DFlyover : NSObject

@property (nonatomic, copy) CLLocation *location;
@property (nonatomic) CLLocationDirection direction;
@property (nonatomic, strong, readonly) MKMapView *mapView;

-(void)preload;
-(void)start;

@end
