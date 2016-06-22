
#import "TP3DFlyover.h"

static const int TPFlyoverSpinStartOffset = 111;
static const int TPFlyoverSpinStep = 20;
static const NSTimeInterval TPSFlyoverSpinStepInterval = 0.2;
static const int TPFlyoverSpinLat = 100;
static const int TPFlyoverSpinLong = 100;
static const CGFloat TPFlyoverPitch = 60.0;

@interface RotatingCamera : NSObject

@property (nonatomic, weak) MKMapView *mapView;
@property (nonatomic) BOOL rotating;
@property (nonatomic) double headingStep;

-(instancetype)initWithMapView:(MKMapView*)mapView;
-(void)startRotatingWithCoordinate:(CLLocationCoordinate2D)coordinate heading:(CLLocationDirection)heading pitch:(CGFloat)pitch altitude:(CLLocationDistance)altitude headingStep:(double)headingStep;
-(void)stopRotating;
-(BOOL)isStopped;
-(void)continueRotating;

@end

@interface TP3DFlyover () <MKMapViewDelegate>

@property (nonatomic, strong) RotatingCamera *rotatingCamera;

@end


@implementation TP3DFlyover

-(instancetype)init
{
    self = [super init];
    if (self) {
        _mapView = [[MKMapView alloc] init];
        [_mapView setDelegate:self];
        _mapView.mapType = MKMapTypeSatelliteFlyover;
        _mapView.userInteractionEnabled = NO;
        _mapView.showsCompass = NO;
        _mapView.showsScale = NO;
        _mapView.showsTraffic = NO;
        _mapView.showsUserLocation = NO;
        _mapView.showsPointsOfInterest = NO;
        _rotatingCamera = [[RotatingCamera alloc] initWithMapView:_mapView];
    }
    return self;
}

-(void)preload
{
    [self start];
}

-(void)start
{
    if (_location && _direction) {
        [_rotatingCamera stopRotating];
        [_mapView setRegion:MKCoordinateRegionMakeWithDistance(_location.coordinate, TPFlyoverSpinLat, TPFlyoverSpinLong) animated:NO];
        [_rotatingCamera startRotatingWithCoordinate:_location.coordinate
                                             heading:fmod(_direction-TPFlyoverSpinStartOffset, 360)
                                               pitch:TPFlyoverPitch
                                            altitude:_location.altitude
                                         headingStep:TPFlyoverSpinStep];
    }
}

#pragma mark - MKMapViewDelegate methods

- (void)mapViewDidFinishRenderingMap:(MKMapView *)mapView
                       fullyRendered:(BOOL)fullyRendered
{
    NSLog(@"~~~~~~~~~~~ LOADED %@", fullyRendered ? @"" : @"(PARTIAL)");
}

// Move behavior to above method?
-(void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    if ([_rotatingCamera rotating]) {
        [_rotatingCamera continueRotating];
    }
}

@end

@implementation RotatingCamera

-(instancetype)initWithMapView:(MKMapView*)mapView
{
    self = [super init];
    if (self) {
        _mapView = mapView;
        _rotating = NO;
        _headingStep = 0;
    }
    return self;
}

-(void)stopRotating
{
    _rotating = NO;
}

-(BOOL)isStopped
{
    return _rotating;
}

-(void)startRotatingWithCoordinate:(CLLocationCoordinate2D)coordinate heading:(CLLocationDirection)heading pitch:(CGFloat)pitch altitude:(CLLocationDistance)altitude headingStep:(double)headingStep
{
    MKMapCamera *newCamera = [MKMapCamera camera];
    [newCamera setCenterCoordinate:coordinate];
    [newCamera setPitch:pitch];
    [newCamera setHeading:heading];
    [newCamera setAltitude:altitude];
    [_mapView setCamera:newCamera animated:YES];
    _rotating = YES;
    _headingStep = headingStep;
}

-(void)continueRotating
{
    MKMapCamera *newCamera = [_mapView.camera copy];
    newCamera.heading = fmod(newCamera.heading+_headingStep, 360);
    [UIView animateWithDuration:TPSFlyoverSpinStepInterval delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        [_mapView setCamera:newCamera];
    } completion:nil];
}

@end

