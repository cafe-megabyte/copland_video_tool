#import <Foundation/Foundation.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSString *root=[NSURL fileURLWithPath:@(argv[1])].path.stringByStandardizingPath;
        NSData *inventory=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"offline-resources.json"]];
        NSArray *resources=inventory?[NSJSONSerialization JSONObjectWithData:inventory options:0 error:nil]:nil;
        if(![resources isKindOfClass:[NSArray class]] || !resources.count)return 1;
        for(id item in resources){
            if(![item isKindOfClass:[NSDictionary class]] || ![item[@"path"] isKindOfClass:[NSString class]] || ![item[@"size"] isKindOfClass:[NSNumber class]])return 1;
            NSString *path=[[root stringByAppendingPathComponent:item[@"path"]] stringByStandardizingPath];
            if(![path hasPrefix:[root stringByAppendingString:@"/"]])return 1;
            NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            if(!attributes || [attributes fileSize]!=[item[@"size"] unsignedLongLongValue])return 1;
        }
    }return 0;
}
