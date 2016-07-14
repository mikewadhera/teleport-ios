
#import <Realm/Realm.h>
@import CoreLocation;

@interface Teleport : RLMObject

@property NSString *id;
@property NSString *userId;
@property NSDate *timestamp;
@property CLLocationDegrees latitude;
@property CLLocationDegrees longitude;
@property NSString *location;
@property NSString *video1Url;
@property NSString *video2Url;
@property double video1Length;
@property double video2length;

+(void)cacheVideo1:(Teleport*)teleport URL:(NSURL*)url;
+(void)cacheVideo2:(Teleport*)teleport URL:(NSURL*)url;
+(void)cleanupCaches:(Teleport*)teleport;
-(NSString*)pathForVideo1;
-(NSString*)pathForVideo2;
-(NSString*)status;

@end
