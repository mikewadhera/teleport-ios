
#import "Teleport.h"

@implementation Teleport

+ (NSString *)primaryKey {
    return @"id";
}

+(NSDateFormatter*)dateFormatter
{
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setDateFormat:@"h:mm a"];
    return dateFormatter;
}

+(NSString*)baseVideoPath
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                   inDomains:NSUserDomainMask] lastObject].path;
}

+(void)cacheVideo1:(Teleport *)teleport URL:(NSURL *)url
{
    [self copyURL:url toPath:[teleport pathForVideo1]];
}

+(void)cacheVideo2:(Teleport *)teleport URL:(NSURL *)url
{
    [self copyURL:url toPath:[teleport pathForVideo2]];
}

+(void)copyURL:(NSURL*)url toPath:(NSString*)path
{
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSError *e;
    [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:path] error:&e];
    if (e) {
        NSLog(@" !!!! COPY VIDEO ERROR !!!!");
    }
}

+(void)cleanupCaches:(Teleport*)teleport
{
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSError *e;
    if ([self existsPath:[teleport pathForVideo1]]) [fm removeItemAtPath:[teleport pathForVideo1] error:&e];
    if ([self existsPath:[teleport pathForVideo2]]) [fm removeItemAtPath:[teleport pathForVideo2] error:&e];
    if (e) {
        NSLog(@" !!!! REMOVE VIDEO ERROR !!!!");
    }
}

+(BOOL)existsPath:(NSString*)path
{
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"Me\n📍%@ 🕒 %@ ",
            self.location,
            [[[self class] dateFormatter] stringFromDate:self.timestamp]];
}

-(NSString*)pathForVideo1
{
    NSString *basename = [NSString stringWithFormat:@"%@-1.mp4", self.id];
    return [[[self class] baseVideoPath] stringByAppendingPathComponent:basename];
}

-(NSString*)pathForVideo2
{
    NSString *basename = [NSString stringWithFormat:@"%@-2.mp4", self.id];
    return [[[self class] baseVideoPath] stringByAppendingPathComponent:basename];
}

@end
