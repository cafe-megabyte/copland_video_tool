#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include "../core/timeline.h"
#include <math.h>

static NSData *read_audio(NSString *path, BOOL pcm, double *start, double *end, long *frames) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track) return nil;
    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    NSDictionary *settings = pcm ? @{AVFormatIDKey:@(kAudioFormatLinearPCM), AVLinearPCMIsFloatKey:@YES,
        AVLinearPCMBitDepthKey:@32, AVLinearPCMIsNonInterleaved:@NO} : nil;
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    [reader addOutput:output]; if (![reader startReading]) return nil;
    NSMutableData *data = [NSMutableData new]; *start = NAN; *end = NAN; *frames = 0;
    CMSampleBufferRef sample;
    while ((sample = [output copyNextSampleBuffer])) {
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
        if (length) {
            if (isnan(*start)) *start = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
            *end = CMTimeGetSeconds(CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample), CMSampleBufferGetDuration(sample)));
            NSUInteger offset = data.length; [data increaseLengthBy:length];
            CMBlockBufferCopyDataBytes(block, 0, length, (uint8_t *)data.mutableBytes + offset);
            *frames += CMSampleBufferGetNumSamples(sample);
        }
        CFRelease(sample);
    }
    if (reader.status != AVAssetReaderStatusCompleted) { fprintf(stderr,"Audio read: %s\n",reader.error.localizedDescription.UTF8String); return nil; }
    return data;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        NSString *source = @(argv[1]), *candidate = @(argv[2]);
        double start1, start2, end1, end2; long frames1, frames2;
        NSData *a = read_audio(source, NO, &start1, &end1, &frames1), *b = read_audio(candidate, NO, &start2, &end2, &frames2);
        if (!a || ![a isEqualToData:b]) { fprintf(stderr,"AAC packets changed (%lu / %lu bytes)\n", (unsigned long)a.length, (unsigned long)b.length); return 1; }
        a = read_audio(source, YES, &start1, &end1, &frames1); b = read_audio(candidate, YES, &start2, &end2, &frames2);
        printf("%s: decoded %ld / %ld frames, start %.9f / %.9f, PCM bytes %lu / %lu\n",argv[2],frames1,frames2,start1,start2,(unsigned long)a.length,(unsigned long)b.length);
        if (!a || ![a isEqualToData:b] || frames1 != COPLAND_SOUND_FRAMES || frames2 != frames1 || fabs(start2) > 1e-8) {
            fprintf(stderr,"Decoded sound differs or priming/remainder is incorrect\n"); return 1;
        }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:candidate] options:nil];
        double duration = CMTimeGetSeconds(asset.duration);
        double expected_duration = COPLAND_SOUND_DURATION;
        if (argc >= 7) expected_duration = fmax(expected_duration, nearbyint(COPLAND_SOUND_REVEAL_END * atof(argv[3])) / atof(argv[3]) + atof(argv[6]));
        printf("Duration %.9f (expected %.9f)\n",duration,expected_duration);
        if (fabs(duration - expected_duration) > 1.0 / COPLAND_SOUND_RATE) return 1;
        if ([asset tracksWithMediaType:AVMediaTypeAudio].count != 1 || [asset tracksWithMediaType:AVMediaTypeVideo].count != 1) return 1;
        /* AVFoundation's track timeRange can include an extra priming correction.
           Check the actual decoded presentation interval rather than that estimate. */
        printf("Audible interval %.9f / %.9f (source / output end)\n",end1,end2);
        if (!isfinite(end2) || fabs(end1-end2) > 1.0 / COPLAND_SOUND_RATE || fabs(end2-COPLAND_SOUND_DURATION) > 1.0 / COPLAND_SOUND_RATE) {
            fprintf(stderr,"Audible audio interval was extended or shortened with the video\n"); return 1;
        }
        if (argc >= 4) {
            double fps = atof(argv[3]); int count = 0, cue = (int)nearbyint(COPLAND_SOUND_REVEAL_END * fps);
            int blank = (int)nearbyint((argc >= 6 && strcmp(argv[5],"default") ? atof(argv[5]) : COPLAND_SOUND_REVEAL_START) * fps);
            AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                outputSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
            [reader addOutput:output]; if (![reader startReading]) return 1;
            CMSampleBufferRef sample;
            while ((sample = [output copyNextSampleBuffer])) {
                double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
                if (fabs(time - count / fps) > 1e-6) { CFRelease(sample); return 1; }
                if (argc >= 5 && !strcmp(argv[4],"reveal") && (count < blank || count >= cue)) {
                    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
                    CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
                    uint8_t *p = CVPixelBufferGetBaseAddress(pixel);
                    p += CVPixelBufferGetBytesPerRow(pixel) * 25 + 4 * 33;
                    BOOL expected = count < blank ? p[0] <= 12 && p[1] <= 12 && p[2] <= 12 :
                        abs(p[2]-99) <= 18 && abs(p[1]-100) <= 18 && abs(p[0]-200) <= 18;
                    CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
                    if (!expected) { fprintf(stderr,"Incorrect lead-in or final image at frame %d\n",count); CFRelease(sample); return 1; }
                }
                count++; CFRelease(sample);
            }
            if (reader.status != AVAssetReaderStatusCompleted || count != (int)ceil(expected_duration * fps)) return 1;
            printf("%d video frames, timestamps, piano lead-in and final image passed at %g fps.\n",count,fps);
        }
        puts("AAC packets, decoded PCM, priming, remainder, track count and duration passed.");
        return 0;
    }
}
