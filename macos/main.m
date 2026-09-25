#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/reveal.h"

typedef struct {
    const char *image;
    const char *positional_output;
    const char *output_option;
    const char *bbox;
    double duration, fps, blank, hold;
    int start_size, threshold;
    CoplandEasing easing;
    uint8_t background[3];
    BOOL has_background;
    CoplandKeyframe *keyframes;
    int keyframe_count;
} Options;

static void print_help(FILE *stream) {
    fputs(
        "usage: copland_video_tool [-h] [-o OUTPUT] [--duration SECONDS] [--fps RATE]\n"
        "                          [--blank SECONDS] [--hold SECONDS]\n"
        "                          [--start-size PIXELS]\n"
        "                          [--easing {linear,geometric,slow-then-fast,fast-then-slow}]\n"
        "                          [--keyframes TIME:SIZE,...] [--bbox BOX]\n"
        "                          [--threshold 0..255] [--background RRGGBB]\n"
        "                          image [output]\n"
        "\n"
        "Render a shrinking, center-sampled pixel grid from a still image.\n"
        "\n"
        "positional arguments:\n"
        "  image                 final PNG/JPEG/etc. image\n"
        "  output                output MP4 path (default: next to image)\n"
        "\n"
        "options:\n"
        "  -h, --help            show this help message and exit\n"
        "  -o, --output PATH     override the output MP4 path\n"
        "  --duration SECONDS    animation seconds (default: 9)\n"
        "  --fps RATE            video frame rate (default: 30)\n"
        "  --blank SECONDS       blank lead-in seconds (default: 0.1)\n"
        "  --hold SECONDS        final-image hold seconds (default: 1)\n"
        "  --start-size PIXELS   initial tile side length (default: box's larger side)\n"
        "  --easing NAME         linear, geometric, slow-then-fast, fast-then-slow\n"
        "                        (default: linear)\n"
        "  --keyframes LIST      time:size pairs, e.g. 0:350,5:100,9:1;\n"
        "                        overrides duration/easing\n"
        "  --bbox BOX            full, auto, or x0,y0,x1,y1 (default: full)\n"
        "  --threshold 0..255    background difference for --bbox auto (default: 20)\n"
        "  --background RRGGBB   blank-area color (default: upper-left pixel)\n",
        stream);
}

static int cli_error(const char *message) {
    print_help(stderr);
    fprintf(stderr, "\nerror: %s\n", message);
    return 2;
}

static BOOL number_value(const char *value, double *result, BOOL positive) {
    char *end = NULL;
    errno = 0;
    double number = strtod(value, &end);
    if (errno || end == value || *end || !isfinite(number) ||
        (positive ? number <= 0 : number < 0)) return NO;
    *result = number;
    return YES;
}

static BOOL integer_value(const char *value, int *result, int minimum, int maximum) {
    char *end = NULL;
    errno = 0;
    long number = strtol(value, &end, 10);
    if (errno || end == value || *end || number < minimum || number > maximum) return NO;
    *result = (int)number;
    return YES;
}

static int hex_digit(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static BOOL color_value(const char *value, uint8_t rgb[3]) {
    if (*value == '#') ++value;
    if (strlen(value) != 6) return NO;
    for (int i = 0; i < 3; ++i) {
        int high = hex_digit(value[i * 2]), low = hex_digit(value[i * 2 + 1]);
        if (high < 0 || low < 0) return NO;
        rgb[i] = (uint8_t)(high * 16 + low);
    }
    return YES;
}

static BOOL parse_keyframes(const char *value, Options *options) {
    NSString *text = [NSString stringWithUTF8String:value];
    if (!text) return NO;
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@","];
    if (parts.count < 2 || parts.count > INT_MAX) return NO;
    CoplandKeyframe *points = calloc(parts.count, sizeof(*points));
    if (!points) return NO;
    BOOL valid = YES;
    for (NSUInteger i = 0; i < parts.count; ++i) {
        NSArray<NSString *> *pair = [parts[i] componentsSeparatedByString:@":"];
        double time, size;
        if (pair.count != 2 || !number_value(pair[0].UTF8String, &time, NO) ||
            !number_value(pair[1].UTF8String, &size, YES) || size < 1 ||
            (i && (time <= points[i - 1].time || size > points[i - 1].size))) {
            valid = NO;
            break;
        }
        points[i] = (CoplandKeyframe){time, size};
    }
    if (valid && (points[0].time != 0 || points[parts.count - 1].size != 1 ||
                  points[0].size > INT_MAX || points[parts.count - 1].time <= 0)) valid = NO;
    if (!valid) {
        free(points);
        return NO;
    }
    free(options->keyframes);
    options->keyframes = points;
    options->keyframe_count = (int)parts.count;
    return YES;
}

/* Returns 0 on success, 1 for help, 2 for a bad command line. */
static int parse_arguments(int argc, char **argv, Options *options) {
    *options = (Options){.bbox = "full", .duration = 9, .fps = 30,
                         .blank = 0.1, .hold = 1, .threshold = 20,
                         .easing = COPLAND_LINEAR};
    BOOL positional_only = NO;
    for (int i = 1; i < argc; ++i) {
        const char *argument = argv[i];
        if (!positional_only && (!strcmp(argument, "-h") || !strcmp(argument, "--help"))) {
            print_help(stdout);
            return 1;
        }
        if (!positional_only && !strcmp(argument, "--")) {
            positional_only = YES;
            continue;
        }
        const char *name = argument, *value = NULL;
        char name_buffer[64];
        if (!positional_only && argument[0] == '-') {
            const char *equals = strchr(argument, '=');
            if (equals) {
                size_t length = (size_t)(equals - argument);
                if (length >= sizeof(name_buffer)) return cli_error("unknown option");
                memcpy(name_buffer, argument, length);
                name_buffer[length] = 0;
                name = name_buffer;
                value = equals + 1;
            } else if (!strncmp(argument, "-o", 2) && argument[2]) {
                name = "-o";
                value = argument + 2;
            }
            BOOL known = !strcmp(name, "-o") || !strcmp(name, "--output") ||
                         !strcmp(name, "--duration") || !strcmp(name, "--fps") ||
                         !strcmp(name, "--blank") || !strcmp(name, "--hold") ||
                         !strcmp(name, "--start-size") || !strcmp(name, "--easing") ||
                         !strcmp(name, "--keyframes") || !strcmp(name, "--bbox") ||
                         !strcmp(name, "--threshold") || !strcmp(name, "--background");
            if (!known) return cli_error("unknown option");
            if (!value && ++i < argc) value = argv[i];
            if (!value || !*value) return cli_error("option requires a value");
            if (!strcmp(name, "-o") || !strcmp(name, "--output")) options->output_option = value;
            else if (!strcmp(name, "--duration")) {
                if (!number_value(value, &options->duration, YES)) return cli_error("--duration must be positive and finite");
            } else if (!strcmp(name, "--fps")) {
                if (!number_value(value, &options->fps, YES)) return cli_error("--fps must be positive and finite");
            } else if (!strcmp(name, "--blank")) {
                if (!number_value(value, &options->blank, NO)) return cli_error("--blank must be nonnegative and finite");
            } else if (!strcmp(name, "--hold")) {
                if (!number_value(value, &options->hold, NO)) return cli_error("--hold must be nonnegative and finite");
            } else if (!strcmp(name, "--start-size")) {
                if (!integer_value(value, &options->start_size, 1, INT_MAX)) return cli_error("--start-size must be a positive integer");
            } else if (!strcmp(name, "--easing")) {
                if (!strcmp(value, "linear")) options->easing = COPLAND_LINEAR;
                else if (!strcmp(value, "geometric")) options->easing = COPLAND_GEOMETRIC;
                else if (!strcmp(value, "slow-then-fast")) options->easing = COPLAND_SLOW_THEN_FAST;
                else if (!strcmp(value, "fast-then-slow")) options->easing = COPLAND_FAST_THEN_SLOW;
                else return cli_error("--easing must be geometric, linear, slow-then-fast, or fast-then-slow");
            } else if (!strcmp(name, "--keyframes")) {
                if (!parse_keyframes(value, options)) return cli_error("invalid --keyframes: use increasing time:size pairs ending at size 1");
            } else if (!strcmp(name, "--bbox")) options->bbox = value;
            else if (!strcmp(name, "--threshold")) {
                if (!integer_value(value, &options->threshold, 0, 255)) return cli_error("--threshold must be an integer from 0 to 255");
            } else if (!strcmp(name, "--background")) {
                if (!color_value(value, options->background)) return cli_error("--background must be RRGGBB");
                options->has_background = YES;
            }
        } else if (!options->image) options->image = argument;
        else if (!options->positional_output) options->positional_output = argument;
        else return cli_error("too many positional arguments");
    }
    if (!options->image) return cli_error("image is required");
    if (options->positional_output && options->output_option)
        return cli_error("use either positional output or --output, not both");
    return 0;
}

static uint8_t unpremultiply(uint8_t channel, uint8_t alpha) {
    if (alpha == 0) return 0;
    return (uint8_t)fmin(255.0, floor((double)channel * 255.0 / alpha + 0.5));
}

static BOOL choose_box(const uint8_t *rgba, int width, int height,
                       const Options *options, BOOL has_alpha, CoplandBox *box) {
    if (!strcmp(options->bbox, "full")) {
        *box = (CoplandBox){0, 0, width, height};
        return YES;
    }
    if (!strcmp(options->bbox, "auto")) {
        int x0 = width, y0 = height, x1 = 0, y1 = 0;
        int corner[3] = {unpremultiply(rgba[0], rgba[3]),
                         unpremultiply(rgba[1], rgba[3]),
                         unpremultiply(rgba[2], rgba[3])};
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const uint8_t *pixel = rgba + ((size_t)y * width + x) * 4;
                BOOL visible;
                if (has_alpha) visible = pixel[3] > 0;
                else {
                    int dr = abs((int)pixel[0] - corner[0]);
                    int dg = abs((int)pixel[1] - corner[1]);
                    int db = abs((int)pixel[2] - corner[2]);
                    int gray = (19595 * dr + 38470 * dg + 7471 * db + 32768) >> 16;
                    visible = gray > options->threshold;
                }
                if (visible) {
                    if (x < x0) x0 = x;
                    if (y < y0) y0 = y;
                    if (x + 1 > x1) x1 = x + 1;
                    if (y + 1 > y1) y1 = y + 1;
                }
            }
        }
        if (x1 == 0) return NO;
        *box = (CoplandBox){x0, y0, x1, y1};
        return YES;
    }
    int x0, y0, x1, y1;
    char extra;
    if (sscanf(options->bbox, "%d,%d,%d,%d%c", &x0, &y0, &x1, &y1, &extra) != 4 ||
        x0 < 0 || y0 < 0 || x0 >= x1 || y0 >= y1 || x1 > width || y1 > height) return NO;
    *box = (CoplandBox){x0, y0, x1, y1};
    return YES;
}

static BOOL append_frame(AVAssetWriter *writer, AVAssetWriterInput *input,
                         AVAssetWriterInputPixelBufferAdaptor *adaptor,
                         const uint8_t *rgb, int width, int height,
                         int encoded_width, int encoded_height,
                         const uint8_t background[3], long index, double fps,
                         NSString **failure) {
    while (!input.readyForMoreMediaData) {
        if (writer.status == AVAssetWriterStatusFailed) {
            *failure = writer.error.localizedDescription;
            return NO;
        }
        [NSThread sleepForTimeInterval:0.002];
    }
    CVPixelBufferRef pixel_buffer = NULL;
    CVReturn result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                         adaptor.pixelBufferPool, &pixel_buffer);
    if (result != kCVReturnSuccess || !pixel_buffer) {
        *failure = @"could not allocate a video frame";
        return NO;
    }
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    uint8_t *bytes = CVPixelBufferGetBaseAddress(pixel_buffer);
    size_t row_bytes = CVPixelBufferGetBytesPerRow(pixel_buffer);
    for (int y = 0; y < encoded_height; ++y) {
        uint8_t *row = bytes + (size_t)y * row_bytes;
        for (int x = 0; x < encoded_width; ++x) {
            const uint8_t *color = y < height && x < width
                ? rgb + ((size_t)y * width + x) * 3 : background;
            row[4 * x] = color[2];
            row[4 * x + 1] = color[1];
            row[4 * x + 2] = color[0];
            row[4 * x + 3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    CMTime timestamp = CMTimeMakeWithSeconds((double)index / fps, 1000000000);
    BOOL success = [adaptor appendPixelBuffer:pixel_buffer withPresentationTime:timestamp];
    CVPixelBufferRelease(pixel_buffer);
    if (!success) *failure = writer.error.localizedDescription ?: @"video encoder rejected a frame";
    return success;
}

static int run(const Options *options) {
    NSString *image_path = [NSString stringWithUTF8String:options->image];
    if (!image_path) return cli_error("image path is not UTF-8");
    NSString *output_path;
    if (options->output_option || options->positional_output)
        output_path = [NSString stringWithUTF8String:options->output_option ?: options->positional_output];
    else output_path = [[image_path stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
    if (!output_path || !output_path.length) return cli_error("invalid output path");
    NSString *input_absolute = [[[NSURL fileURLWithPath:image_path] path] stringByStandardizingPath];
    NSString *output_absolute = [[[NSURL fileURLWithPath:output_path] path] stringByStandardizingPath];
    if ([input_absolute isEqualToString:output_absolute]) return cli_error("input and output must be different files");

    NSURL *image_url = [NSURL fileURLWithPath:image_path];
    CGImageSourceRef image_source = CGImageSourceCreateWithURL((__bridge CFURLRef)image_url, NULL);
    if (!image_source) return cli_error("cannot read image");
    CGImageRef image = CGImageSourceCreateImageAtIndex(image_source, 0, NULL);
    CFRelease(image_source);
    if (!image) return cli_error("cannot decode image");
    size_t image_width = CGImageGetWidth(image), image_height = CGImageGetHeight(image);
    if (!image_width || !image_height || image_width >= INT_MAX || image_height >= INT_MAX ||
        image_width > SIZE_MAX / image_height / 4) {
        CGImageRelease(image);
        fprintf(stderr, "error: invalid or too-large image dimensions\n");
        return 1;
    }
    int width = (int)image_width, height = (int)image_height;
    uint8_t *rgba = calloc(image_width * image_height, 4);
    uint8_t *source = malloc(image_width * image_height * 3);
    uint8_t *base = malloc(image_width * image_height * 3);
    uint8_t *frame = malloc(image_width * image_height * 3);
    if (!rgba || !source || !base || !frame) {
        fprintf(stderr, "error: out of memory\n");
        CGImageRelease(image);
        free(rgba); free(source); free(base); free(frame);
        return 1;
    }
    CGColorSpaceRef color_space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(rgba, image_width, image_height, 8,
        image_width * 4, color_space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color_space);
    if (!context) {
        fprintf(stderr, "error: cannot create image bitmap\n");
        CGImageRelease(image);
        free(rgba); free(source); free(base); free(frame);
        return 1;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    BOOL has_alpha = NO;
    for (size_t i = 0; i < image_width * image_height; ++i) {
        if (rgba[i * 4 + 3] < 255) { has_alpha = YES; break; }
    }
    uint8_t background[3];
    if (options->has_background) memcpy(background, options->background, 3);
    else if (has_alpha && rgba[3] == 0) memset(background, 255, 3);
    else for (int channel = 0; channel < 3; ++channel)
        background[channel] = unpremultiply(rgba[channel], rgba[3]);

    CoplandBox box;
    if (!choose_box(rgba, width, height, options, has_alpha, &box)) {
        free(rgba); free(source); free(base); free(frame);
        return cli_error("invalid --bbox or auto box found no visible content");
    }
    for (size_t i = 0; i < image_width * image_height; ++i) {
        uint8_t alpha = rgba[i * 4 + 3];
        for (int channel = 0; channel < 3; ++channel) {
            int premultiplied = rgba[i * 4 + channel];
            int mixed = premultiplied + (background[channel] * (255 - alpha) + 127) / 255;
            source[i * 3 + channel] = (uint8_t)(mixed > 255 ? 255 : mixed);
        }
    }
    copland_make_base(source, base, width, height, box, background);

    int start_size = options->start_size ?: (box.x1 - box.x0 > box.y1 - box.y0
                                               ? box.x1 - box.x0 : box.y1 - box.y0);
    double duration = options->keyframe_count
        ? options->keyframes[options->keyframe_count - 1].time : options->duration;
    double blank_count = nearbyint(options->blank * options->fps);
    double animation_count = ceil(duration * options->fps) + 1;
    double hold_count = nearbyint(options->hold * options->fps);
    if (!isfinite(blank_count + animation_count + hold_count) ||
        blank_count + animation_count + hold_count > 10000000 ||
        animation_count < 0) {
        free(rgba); free(source); free(base); free(frame);
        return cli_error("duration and fps would create too many frames");
    }
    long blank_frames = (long)blank_count;
    long animation_frames = (long)fmax(2, animation_count);
    long hold_frames = (long)hold_count;
    long total_frames = blank_frames + animation_frames + hold_frames;
    int encoded_width = width + (width & 1), encoded_height = height + (height & 1);

    NSError *error = nil;
    NSString *directory = [output_path stringByDeletingLastPathComponent];
    if (directory.length && ![[NSFileManager defaultManager] createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:&error]) {
        fprintf(stderr, "error: %s\n", error.localizedDescription.UTF8String);
        free(rgba); free(source); free(base); free(frame);
        return 1;
    }
    NSString *temporary_path = [output_path stringByAppendingFormat:@".%@.tmp.mp4", NSUUID.UUID.UUIDString];
    NSURL *temporary_url = [NSURL fileURLWithPath:temporary_path];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:temporary_url
                                                     fileType:AVFileTypeMPEG4 error:&error];
    if (!writer) {
        fprintf(stderr, "error: %s\n", error.localizedDescription.UTF8String);
        free(rgba); free(source); free(base); free(frame);
        return 1;
    }
    double bitrate = fmin(100000000, fmax(4000000,
        (double)encoded_width * encoded_height * options->fps * 0.8));
    NSDictionary *settings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(encoded_width),
        AVVideoHeightKey: @(encoded_height),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @((long)bitrate)}
    };
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                   outputSettings:settings];
    input.expectsMediaDataInRealTime = NO;
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey: @(encoded_width),
        (NSString *)kCVPixelBufferHeightKey: @(encoded_height),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                                                sourcePixelBufferAttributes:attributes];
    if (![writer canAddInput:input]) {
        fprintf(stderr, "error: video encoder does not accept these settings\n");
        free(rgba); free(source); free(base); free(frame);
        return 1;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
        fprintf(stderr, "error: %s\n", writer.error.localizedDescription.UTF8String);
        free(rgba); free(source); free(base); free(frame);
        [[NSFileManager defaultManager] removeItemAtPath:temporary_path error:nil];
        return 1;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    BOOL success = YES;
    NSString *failure = nil;
    int previous_size = -1;
    for (long index = 0; index < total_frames; ++index) {
        const uint8_t *pixels = base;
        if (index >= blank_frames && index < blank_frames + animation_frames) {
            long animation_index = index - blank_frames;
            double time = fmin((double)animation_index / options->fps, duration);
            if (animation_index == animation_frames - 1) time = duration;
            double exact_size = copland_continuous_size_at_time(time, duration, start_size,
                options->easing, options->keyframes, options->keyframe_count);
            if (!options->keyframe_count && exact_size <= 16.0) {
                copland_render_smooth_frame(source, base, frame, rgba, width, height, box, exact_size);
                previous_size = -1;
            } else {
                int size = copland_size_at_time(time, duration, start_size, options->easing,
                                                options->keyframes, options->keyframe_count);
                if (size != previous_size) {
                    copland_render_frame(source, base, frame, width, height, box, size);
                    previous_size = size;
                }
            }
            pixels = frame;
        } else if (index >= blank_frames + animation_frames) pixels = source;
        if (!append_frame(writer, input, adaptor, pixels, width, height,
                          encoded_width, encoded_height, background, index,
                          options->fps, &failure)) { success = NO; break; }
    }
    free(rgba); free(source); free(base); free(frame);
    if (!success) {
        [writer cancelWriting];
        [[NSFileManager defaultManager] removeItemAtPath:temporary_path error:nil];
        fprintf(stderr, "error: %s\n", (failure ?: @"video encoding failed").UTF8String);
        return 1;
    }
    [input markAsFinished];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(semaphore); }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) {
        [[NSFileManager defaultManager] removeItemAtPath:temporary_path error:nil];
        fprintf(stderr, "error: %s\n", writer.error.localizedDescription.UTF8String);
        return 1;
    }
    if (rename(temporary_url.fileSystemRepresentation,
               [NSURL fileURLWithPath:output_path].fileSystemRepresentation) != 0) {
        fprintf(stderr, "error: cannot move video to output: %s\n", strerror(errno));
        [[NSFileManager defaultManager] removeItemAtPath:temporary_path error:nil];
        return 1;
    }
    printf("Wrote %s (%dx%d, %ld frames)\n", output_path.UTF8String,
           encoded_width, encoded_height, total_frames);
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        Options options;
        int status = parse_arguments(argc, argv, &options);
        if (status) { free(options.keyframes); return status == 1 ? 0 : status; }
        status = run(&options);
        free(options.keyframes);
        return status;
    }
}
