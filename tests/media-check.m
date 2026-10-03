#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
static BOOL baseline_fixture(void) {
    NSString *path=@"build/internal/tests/baseline.mp4";
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    AVAssetWriter *writer=[AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path] fileType:AVFileTypeMPEG4 error:nil];
    NSDictionary *settings=@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@66,AVVideoHeightKey:@50,
        AVVideoCompressionPropertiesKey:@{AVVideoProfileLevelKey:AVVideoProfileLevelH264BaselineAutoLevel,AVVideoAllowFrameReorderingKey:@NO}};
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(NSString *)kCVPixelBufferWidthKey:@66,(NSString *)kCVPixelBufferHeightKey:@50}];
    [writer addInput:input]; if(![writer startWriting]) return NO;[writer startSessionAtSourceTime:kCMTimeZero];
    for(int i=0;i<10;i++) {
        while(!input.readyForMoreMediaData) {if(writer.status==AVAssetWriterStatusFailed)return NO;[NSThread sleepForTimeInterval:.001];}
        CVPixelBufferRef buffer=NULL; if(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&buffer)) return NO;
        CVPixelBufferLockBaseAddress(buffer,0);uint8_t *p=CVPixelBufferGetBaseAddress(buffer);size_t stride=CVPixelBufferGetBytesPerRow(buffer);
        for(int y=0;y<50;y++)for(int x=0;x<66;x++){uint8_t *pixel=p+stride*y+4*x;pixel[0]=x*3;pixel[1]=y*4;pixel[2]=i*24;pixel[3]=255;}
        CVPixelBufferUnlockBaseAddress(buffer,0);BOOL ok=[adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i,10)];CVPixelBufferRelease(buffer);if(!ok)return NO;
    }
    [input markAsFinished];dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(done);}];dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
    return writer.status==AVAssetWriterStatusCompleted;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        if (!strcmp(argv[1],"fixture")) {
            const int w=65,h=49; uint8_t *p=calloc(w*h,4);
            for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
                size_t i=(y*w+x)*4; p[i]=x*3;p[i+1]=y*4;p[i+2]=((x/8+y/8)%2)*200;p[i+3]=255;
            }
            CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef c=CGBitmapContextCreate(p,w,h,8,w*4,cs,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGImageRef image=CGBitmapContextCreateImage(c);
            CGImageDestinationRef d=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[2])],CFSTR("public.png"),1,NULL);
            CGImageDestinationAddImage(d,image,NULL); BOOL ok=CGImageDestinationFinalize(d);
            CFRelease(d);CGImageRelease(image);CGContextRelease(c);CGColorSpaceRelease(cs);free(p);return ok && baseline_fixture()?0:1;
        }
        AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:@(argv[2])] options:nil];
        AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        if(!track) {fprintf(stderr,"No video track\n");return 1;}
        NSError *error=nil; AVAssetReader *reader=[AVAssetReader assetReaderWithAsset:asset error:&error];
        BOOL chunks = !strcmp(argv[1], "chunks");
        AVAssetReaderTrackOutput *output=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:chunks ? nil : @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
        NSMutableArray *encoded = [NSMutableArray new];
        NSArray *configuration = nil;
        [reader addOutput:output]; if(![reader startReading]) return 1;
        int count=0; double last=-1; NSMutableArray *pixels=[NSMutableArray new];
        CMSampleBufferRef sample;
        while((sample=[output copyNextSampleBuffer])) {
            double time=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
            if(!chunks && time<=last) {fprintf(stderr,"Non-increasing sample timestamp: %g after %g\n",time,last);CFRelease(sample);return 1;} last=time;
            if (chunks) {
                CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sample);
                NSDictionary *extensions = (__bridge NSDictionary *)CMFormatDescriptionGetExtensions(description);
                NSData *avc = extensions[(NSString *)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms][@"avcC"];
                if (!avc) {
                    const uint8_t *sps=NULL, *pps=NULL; size_t spsSize=0, ppsSize=0, sets=0; int nal=0;
                    if (!CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,0,&sps,&spsSize,&sets,&nal) &&
                        !CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,1,&pps,&ppsSize,NULL,NULL) && spsSize>=4 && spsSize<65536 && ppsSize<65536) {
                        uint8_t header[]={1,sps[1],sps[2],sps[3],(uint8_t)(0xfc|(nal-1)),0xe1,(uint8_t)(spsSize>>8),(uint8_t)spsSize};
                        NSMutableData *record=[NSMutableData dataWithBytes:header length:sizeof(header)];
                        [record appendBytes:sps length:spsSize];uint8_t tail[]={1,(uint8_t)(ppsSize>>8),(uint8_t)ppsSize};
                        [record appendBytes:tail length:3];[record appendBytes:pps length:ppsSize];avc=record;
                    }
                }
                if (avc && !configuration) {
                    NSMutableArray *values = [NSMutableArray new]; const uint8_t *p=avc.bytes;
                    for(NSUInteger i=0;i<avc.length;i++) [values addObject:@(p[i])]; configuration=values;
                }
                CMBlockBufferRef block=CMSampleBufferGetDataBuffer(sample); size_t length=CMBlockBufferGetDataLength(block);
                if (!length) { CFRelease(sample); continue; } /* Reader control buffers carry no video sample. */
                NSMutableData *bytes=[NSMutableData dataWithLength:length]; CMBlockBufferCopyDataBytes(block,0,length,bytes.mutableBytes);
                NSMutableArray *values=[NSMutableArray new];const uint8_t *p=bytes.bytes;
                for(NSUInteger i=0;i<length;i++) [values addObject:@(p[i])];
                NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,false);
                BOOL key=!attachments.count || ![attachments[0][(NSString *)kCMSampleAttachmentKey_NotSync] boolValue];
                [encoded addObject:@{@"data":values,@"key":@(key)}];CFRelease(sample);count++;continue;
            }
            CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(sample); CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
            uint8_t *p=CVPixelBufferGetBaseAddress(buffer);size_t stride=CVPixelBufferGetBytesPerRow(buffer);
            uint8_t *center=p+stride*(CVPixelBufferGetHeight(buffer)/2)+4*(CVPixelBufferGetWidth(buffer)/2);
            [pixels addObject:@[@(center[2]),@(center[1]),@(center[0])]];
            CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly); CFRelease(sample); count++;
        }
        double duration=CMTimeGetSeconds(asset.duration); CGSize size=track.naturalSize;
        if(reader.status!=AVAssetReaderStatusCompleted || !count || !isfinite(duration)) {fprintf(stderr,"Reader status=%ld count=%d error=%s\n",(long)reader.status,count,reader.error.description.UTF8String);return 1;}
        if(argc>=6 && (count!=atoi(argv[3]) || size.width!=atoi(argv[4]) || size.height!=atoi(argv[5]))) return 1;
        if (chunks) {
            if(!configuration || !encoded.count) {fprintf(stderr,"No AVC configuration, %lu samples\n",(unsigned long)encoded.count);return 1;}
            NSDictionary *fixture=@{@"configuration":configuration,@"samples":encoded};
            NSData *json=[NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil];
            return [json writeToFile:@"build/internal/tests/avc-samples.json" atomically:NO]?0:1;
        }
        NSDictionary *report=@{@"frames":@(count),@"width":@(size.width),@"height":@(size.height),@"duration":@(duration),@"lastTimestamp":@(last),@"centerPixels":pixels};
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    } return 0;
}
