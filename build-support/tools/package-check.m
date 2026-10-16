#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

static void require(BOOL valid, NSString *message) {
    if (!valid) { fprintf(stderr, "Package check: %s\n", message.UTF8String); exit(1); }
}
static NSData *readFile(NSString *root, NSString *name) {
    NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:name]];
    require(data != nil, [@"Missing " stringByAppendingString:name]);
    return data;
}
static BOOL imageValid(NSData *data, size_t size, BOOL maskable) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source && !CFEqual(CGImageSourceGetType(source), CFSTR("public.png"))) { CFRelease(source); return NO; }
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (source) CFRelease(source);
    if (!image) return NO;
    if (CGImageGetWidth(image) != size || CGImageGetHeight(image) != size) { CGImageRelease(image); return NO; }
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, size * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(image); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, size, size), image);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    BOOL transparent = NO, artwork = NO, valid = YES;
    for (size_t y = 0; y < size && valid; ++y) for (size_t x = 0; x < size; ++x) {
        const uint8_t *p = pixels + (y * size + x) * 4;
        transparent |= p[3] == 0;
        artwork |= p[3] > 32 && (p[0] < 240 || p[1] < 240 || p[2] < 240);
        if (maskable && (p[3] != 255 ||
            (hypot(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0) > 0.4 * size &&
             (p[0] != 255 || p[1] != 255 || p[2] != 255)))) { valid = NO; break; }
    }
    CGContextRelease(context); CGImageRelease(image);
    return valid && artwork && (maskable || transparent);
}
static uint32_t littleEndian(const uint8_t *bytes, unsigned count) {
    uint32_t value = 0;
    for (unsigned i = 0; i < count; ++i) value |= (uint32_t)bytes[i] << (i * 8);
    return value;
}
static BOOL icoValid(NSData *data, NSData *png32) {
    if (data.length < 54) return NO;
    const uint8_t *bytes = data.bytes;
    if (littleEndian(bytes, 2) != 0 || littleEndian(bytes + 2, 2) != 1 || littleEndian(bytes + 4, 2) != 3) return NO;
    const size_t sizes[] = {16, 32, 256};
    NSUInteger expected = 54;
    for (unsigned i = 0; i < 3; ++i) {
        const uint8_t *entry = bytes + 6 + i * 16;
        NSUInteger length = littleEndian(entry + 8, 4), offset = littleEndian(entry + 12, 4);
        size_t width = entry[0] ?: 256, height = entry[1] ?: 256;
        if (width != sizes[i] || height != sizes[i] ||
            offset != expected || !length || offset > data.length || length > data.length - offset) return NO;
        NSData *frame = [data subdataWithRange:NSMakeRange(offset, length)];
        if (!imageValid(frame, sizes[i], NO) || (sizes[i] == 32 && ![frame isEqual:png32])) return NO;
        expected += length;
    }
    return expected == data.length;
}
static NSDictionary *attributes(NSString *tag) {
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"([a-zA-Z][a-zA-Z0-9:-]*)\\s*=\\s*([\"'])(.*?)\\2" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (NSTextCheckingResult *match in [pattern matchesInString:tag options:0 range:NSMakeRange(0, tag.length)])
        values[[[tag substringWithRange:[match rangeAtIndex:1]] lowercaseString]] = [tag substringWithRange:[match rangeAtIndex:3]];
    return values;
}
static void checkHTML(NSString *html) {
    NSDictionary *touch = @{@"152x152": @"./apple-touch-icon-152.png", @"167x167": @"./apple-touch-icon-167.png", @"180x180": @"./apple-touch-icon.png"};
    NSMutableSet *seenTouch = [NSMutableSet new], *seenFavicon = [NSMutableSet new];
    unsigned manifests = 0, brands = 0;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"<(link|img)\\b[^>]*>"
        options:NSRegularExpressionCaseInsensitive error:nil];
    for (NSTextCheckingResult *match in [pattern matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSDictionary *a = attributes([html substringWithRange:match.range]);
        NSArray *rel = [[a[@"rel"] lowercaseString] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([rel containsObject:@"apple-touch-icon"]) {
            NSString *size = a[@"sizes"];
            require(size && [a[@"href"] isEqual:touch[size]] && ![seenTouch containsObject:size], @"Invalid or duplicate Apple Touch link");
            [seenTouch addObject:size];
        }
        if ([rel containsObject:@"icon"]) {
            NSString *href = a[@"href"];
            BOOL png = [href isEqual:@"./icon-32.png"] && [a[@"sizes"] isEqual:@"32x32"] && [a[@"type"] isEqual:@"image/png"];
            BOOL ico = [href isEqual:@"./favicon.ico"] && [a[@"sizes"] isEqual:@"16x16 32x32 256x256"] && [a[@"type"] isEqual:@"image/x-icon"];
            require((png || ico) && ![seenFavicon containsObject:href], @"Invalid or duplicate favicon link");
            [seenFavicon addObject:href];
        }
        if ([rel containsObject:@"manifest"]) {
            require([a[@"href"] isEqual:@"./manifest.webmanifest"], @"Manifest link must use the project root");
            ++manifests;
        }
        if ([[a[@"class"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] containsObject:@"brand-icon"]) {
            require([a[@"src"] isEqual:@"./icon-32.png"] && [a[@"srcset"] isEqual:@"./icon-64.png 2x"], @"Header icons must use the project root");
            ++brands;
        }
    }
    require(seenTouch.count == 3 && seenFavicon.count == 2 && manifests == 1 && brands == 1, @"Incomplete HTML icon references");
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *root = [NSURL fileURLWithPath:@(argv[1])].path.stringByStandardizingPath;
        NSString *release = [[[NSString alloc] initWithData:readFile(root, @"release.txt") encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        require(release.length == 36 && [[NSUUID alloc] initWithUUIDString:release], @"Invalid release ID");
        NSString *prefix = [NSString stringWithFormat:@"releases/%@/", release];
        NSArray *resources = [NSJSONSerialization JSONObjectWithData:readFile(root, @"offline-resources.json") options:0 error:nil];
        require([resources isKindOfClass:NSArray.class] && resources.count, @"Invalid offline inventory");
        NSMutableSet *paths = [NSMutableSet new];
        for (id item in resources) {
            require([item isKindOfClass:NSDictionary.class] && [item[@"path"] isKindOfClass:NSString.class] &&
                [item[@"size"] isKindOfClass:NSNumber.class], @"Invalid offline resource");
            NSString *name = item[@"path"];
            require(name.length && !name.isAbsolutePath && ![name.pathComponents containsObject:@".."] &&
                ![name.pathComponents containsObject:@"."] && ![paths containsObject:name], @"Invalid or duplicate offline path");
            require(![name hasPrefix:@"releases/"] || [name hasPrefix:prefix], @"Mixed offline releases");
            [paths addObject:name];
            NSDictionary *info = [[NSFileManager defaultManager] attributesOfItemAtPath:[root stringByAppendingPathComponent:name] error:nil];
            require([info[NSFileType] isEqual:NSFileTypeRegular] && info.fileSize == [item[@"size"] unsignedLongLongValue],
                [@"Offline size mismatch: " stringByAppendingString:name]);
        }
        NSArray *specs = @[
            @[@"apple-touch-icon-152.png", @152], @[@"apple-touch-icon-167.png", @167], @[@"apple-touch-icon.png", @180],
            @[@"icon-32.png", @32], @[@"icon-64.png", @64], @[@"icon-192.png", @192],
            @[@"icon-512.png", @512], @[@"icon-1024.png", @1024],
            @[@"icon-maskable-512.png", @512], @[@"icon-maskable-1024.png", @1024]
        ];
        NSMutableSet *icons = [NSMutableSet setWithObject:@"favicon.ico"];
        for (NSArray *spec in specs) {
            NSString *name = spec[0]; [icons addObject:name];
            require([paths containsObject:name], [@"Icon missing from inventory: " stringByAppendingString:name]);
            require(imageValid(readFile(root, name), [spec[1] unsignedIntegerValue], [name containsString:@"maskable"]),
                [@"Invalid icon dimensions, alpha or safe circle: " stringByAppendingString:name]);
        }
        require([paths containsObject:@"favicon.ico"] && icoValid(readFile(root, @"favicon.ico"), readFile(root, @"icon-32.png")), @"Invalid ICO");
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil])
            if ([name hasPrefix:@"icon-"] || [name hasPrefix:@"apple-touch-icon"] || [name isEqual:@"favicon.ico"])
                require([icons containsObject:name], [@"Obsolete root icon: " stringByAppendingString:name]);
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:prefix] error:nil])
            require(![@[@"png", @"ico"] containsObject:name.pathExtension.lowercaseString], @"Current release must not contain icon copies");
        for (NSString *name in @[@"index.html", @"manifest.webmanifest", [prefix stringByAppendingString:@"app.js"]])
            require([paths containsObject:name], [@"Missing required offline resource: " stringByAppendingString:name]);
        NSString *html = [[NSString alloc] initWithData:readFile(root, @"index.html") encoding:NSUTF8StringEncoding];
        require([html containsString:[NSString stringWithFormat:@"./%@app.js", prefix]] && ![html containsString:@"__RELEASE__"], @"HTML release mismatch");
        checkHTML(html);
        NSString *worker = [[NSString alloc] initWithData:readFile(root, @"service-worker.js") encoding:NSUTF8StringEncoding];
        require([worker hasPrefix:[NSString stringWithFormat:@"const RELEASE = '%@';", release]] && ![worker containsString:@"__RELEASE__"], @"Service worker release mismatch");
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:readFile(root, @"manifest.webmanifest") options:0 error:nil];
        require([manifest isKindOfClass:NSDictionary.class] && [manifest[@"icons"] isKindOfClass:NSArray.class] && [manifest[@"icons"] count] == 5, @"Invalid manifest icons");
        NSMutableSet *expected = [NSMutableSet new];
        for (NSNumber *size in @[@192, @512, @1024]) [expected addObject:[NSString stringWithFormat:@"./icon-%@.png|%@x%@|any", size, size, size]];
        for (NSNumber *size in @[@512, @1024]) [expected addObject:[NSString stringWithFormat:@"./icon-maskable-%@.png|%@x%@|maskable", size, size, size]];
        for (id icon in manifest[@"icons"]) {
            require([icon isKindOfClass:NSDictionary.class] && [icon[@"type"] isEqual:@"image/png"], @"Invalid manifest icon");
            NSString *key = [NSString stringWithFormat:@"%@|%@|%@", icon[@"src"], icon[@"sizes"], icon[@"purpose"]];
            require([expected containsObject:key], @"Manifest icon must use its canonical root path, size and purpose");
            [expected removeObject:key];
        }
        require(!expected.count, @"Incomplete manifest icons");
    }
    return 0;
}
