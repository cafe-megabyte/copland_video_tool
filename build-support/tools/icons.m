#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

// The canonical SVG deliberately uses only solid rects. Foundation parses it
// and CoreGraphics rasterizes it, so the build needs no external SVG renderer.
@interface IconSource : NSObject <NSXMLParserDelegate>
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *rectangles;
@property(nonatomic) BOOL validRoot;
@property(nonatomic, copy) NSString *failure;
@end
@implementation IconSource
- (instancetype)init { if ((self = [super init])) _rectangles = [NSMutableArray new]; return self; }
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    (void)uri; (void)name;
    if ([element isEqualToString:@"svg"]) {
        if (self.validRoot || ![attributes[@"viewBox"] isEqualToString:@"0 0 512 512"] ||
            ![attributes[@"width"] isEqualToString:@"512"] || ![attributes[@"height"] isEqualToString:@"512"]) self.failure = @"Expected one 512px SVG with viewBox 0 0 512 512.";
        else self.validRoot = YES;
        for (NSString *key in attributes) if (![@[@"xmlns", @"width", @"height", @"viewBox"] containsObject:key]) self.failure = @"Unsupported SVG root attribute.";
    } else if ([element isEqualToString:@"rect"]) {
        NSMutableDictionary *rect = [NSMutableDictionary new];
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            NSScanner *scanner = [NSScanner scannerWithString:attributes[key] ?: @""]; double value;
            if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < 0 || value > 512 ||
                (([key isEqualToString:@"width"] || [key isEqualToString:@"height"]) && value == 0)) self.failure = @"Invalid rectangle coordinates.";
            else rect[key] = @(value);
        }
        NSString *fill = attributes[@"fill"]; unsigned colour = 0;
        NSScanner *scanner = [NSScanner scannerWithString:fill.length == 7 ? [fill substringFromIndex:1] : @""];
        if (fill.length != 7 || ![fill hasPrefix:@"#"] || ![scanner scanHexInt:&colour] || !scanner.isAtEnd) self.failure = @"Rectangles need an explicit #RRGGBB fill.";
        else rect[@"colour"] = @(colour);
        if ([rect[@"x"] doubleValue] + [rect[@"width"] doubleValue] > 512 || [rect[@"y"] doubleValue] + [rect[@"height"] doubleValue] > 512) self.failure = @"Rectangle exceeds the icon canvas.";
        if (!self.failure) [self.rectangles addObject:rect];
        for (NSString *key in attributes) if (![@[@"x", @"y", @"width", @"height", @"fill"] containsObject:key]) self.failure = @"Unsupported rectangle attribute.";
    } else if (![@[@"title", @"desc"] containsObject:element]) self.failure = @"Icon SVG supports only svg, rect, title and desc elements.";
    if (self.failure) [parser abortParsing];
}
@end
static void littleEndian(NSMutableData *data, uint32_t value, int bytes) {
    for (int i = 0; i < bytes; ++i) { uint8_t b = (uint8_t)(value >> (i * 8)); [data appendBytes:&b length:1]; }
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSData *svg = [NSData dataWithContentsOfFile:@(argv[2])];
        if (!svg) return 1;
        IconSource *source = [IconSource new]; NSXMLParser *parser = [[NSXMLParser alloc] initWithData:svg];
        parser.delegate = source; parser.shouldResolveExternalEntities = NO;
        if (![parser parse] || !source.validRoot || !source.rectangles.count || source.failure) {
            fprintf(stderr, "%s\n", (source.failure ?: @"Invalid icon SVG.").UTF8String); return 1;
        }
        const int sizes[] = {16, 32, 64, 180, 192, 256, 512};
        NSMutableDictionary *pngs = [NSMutableDictionary new];
        for (NSUInteger i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
            int n = sizes[i]; CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef c = CGBitmapContextCreate(NULL, n, n, 8, n * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(cs); if (!c) return 1;
            CGContextClearRect(c, CGRectMake(0, 0, n, n));
            CGContextTranslateCTM(c, 0, n); CGContextScaleCTM(c, n / 512.0, -n / 512.0);
            for (NSDictionary *rect in source.rectangles) {
                unsigned colour = [rect[@"colour"] unsignedIntValue];
                CGContextSetRGBFillColor(c, ((colour >> 16) & 255) / 255.0, ((colour >> 8) & 255) / 255.0, (colour & 255) / 255.0, 1);
                CGContextFillRect(c, CGRectMake([rect[@"x"] doubleValue], [rect[@"y"] doubleValue], [rect[@"width"] doubleValue], [rect[@"height"] doubleValue]));
            }
            CGImageRef image = CGBitmapContextCreateImage(c); CGContextRelease(c);
            NSString *path = [@(argv[1]) stringByAppendingPathComponent:[NSString stringWithFormat:@"icon-%d.png", n]];
            NSMutableData *png = [NSMutableData new];
            CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
            if (!dest) { CGImageRelease(image); return 1; }
            CGImageDestinationAddImage(dest, image, NULL); BOOL ok = CGImageDestinationFinalize(dest);
            CFRelease(dest); CGImageRelease(image);
            if (!ok || ![png writeToFile:path atomically:NO]) return 1;
            pngs[@(n)] = png;
        }
        // ICO stores the generated PNGs without a second image encoder.
        const int icoSizes[] = {16, 32, 256};
        NSMutableData *ico = [NSMutableData new];
        littleEndian(ico, 0, 2); littleEndian(ico, 1, 2); littleEndian(ico, 3, 2);
        uint32_t offset = 6 + 3 * 16;
        for (int i = 0; i < 3; ++i) {
            int n = icoSizes[i]; NSData *png = pngs[@(n)];
            littleEndian(ico, n == 256 ? 0 : n, 1); littleEndian(ico, n == 256 ? 0 : n, 1);
            littleEndian(ico, 0, 2); littleEndian(ico, 1, 2); littleEndian(ico, 32, 2);
            littleEndian(ico, (uint32_t)png.length, 4); littleEndian(ico, offset, 4); offset += png.length;
        }
        for (int i = 0; i < 3; ++i) [ico appendData:pngs[@(icoSizes[i])]];
        if (![ico writeToFile:[@(argv[1]) stringByAppendingPathComponent:@"favicon.ico"] atomically:NO]) return 1;
    } return 0;
}
