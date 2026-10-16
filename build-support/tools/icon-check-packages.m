#import <Foundation/Foundation.h>

static void require(BOOL valid, NSString *message) {
    if (!valid) { fprintf(stderr, "Icon check packages: %s\n", message.UTF8String); exit(1); }
}
static NSData *readData(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    require(data != nil, [@"Cannot read " stringByAppendingString:path]);
    return data;
}
static void writeData(NSData *data, NSString *path) {
    NSError *error = nil;
    require(data && [data writeToFile:path options:0 error:&error],
        [NSString stringWithFormat:@"Cannot write %@: %@", path, error ?: @"encoding failed"]);
}
static void writeText(NSString *text, NSString *path) { writeData([text dataUsingEncoding:NSUTF8StringEncoding], path); }
static NSData *jsonData(id value) {
    return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
}
static NSString *releaseAt(NSString *root) {
    NSString *release = [[[NSString alloc] initWithData:readData([root stringByAppendingPathComponent:@"release.txt"]) encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    require(release.length == 36 && [[NSUUID alloc] initWithUUIDString:release], @"Invalid reference release");
    return release;
}
static void check(NSString *checker, NSString *root) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:checker]; task.arguments = @[root];
    NSError *error = nil;
    require([task launchAndReturnError:&error], [NSString stringWithFormat:@"Cannot launch package checker: %@", error]);
    [task waitUntilExit];
    require(task.terminationStatus == 0, [@"Package validation failed: " stringByAppendingString:root]);
}
static NSString *makePackage(NSString *source, NSString *output, NSString *oldRelease, NSArray *inventory,
    NSString *kind, NSString *name, NSDictionary *appleIcons, NSString *checker) {
    NSString *release = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *folder = [NSString stringWithFormat:@"cvt-icon-%@-%@", kind, release];
    NSString *root = [output stringByAppendingPathComponent:folder];
    NSString *oldPrefix = [NSString stringWithFormat:@"releases/%@/", oldRelease];
    NSString *prefix = [NSString stringWithFormat:@"releases/%@/", release];
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray *paths = [NSMutableArray new];
    for (NSDictionary *item in inventory) {
        NSString *path = item[@"path"];
        NSString *next = [path hasPrefix:oldPrefix] ? [prefix stringByAppendingString:[path substringFromIndex:oldPrefix.length]] : path;
        NSString *target = [root stringByAppendingPathComponent:next];
        NSError *error = nil;
        require([files createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error],
            [NSString stringWithFormat:@"Cannot create test directory: %@", error]);
        require([files copyItemAtPath:[source stringByAppendingPathComponent:path] toPath:target error:&error],
            [NSString stringWithFormat:@"Cannot copy %@: %@", path, error]);
        [paths addObject:next];
    }
    NSString *htmlPath = [root stringByAppendingPathComponent:@"index.html"];
    NSString *html = [[NSString alloc] initWithData:readData(htmlPath) encoding:NSUTF8StringEncoding];
    html = [html stringByReplacingOccurrencesOfString:oldRelease withString:release];
    html = [html stringByReplacingOccurrencesOfString:@"<title>Copland Video Tool</title>" withString:[NSString stringWithFormat:@"<title>%@</title>", name]];
    html = [html stringByReplacingOccurrencesOfString:@"<h1>Copland Video Tool</h1>" withString:[NSString stringWithFormat:@"<h1>%@</h1>", name]];
    writeText(html, htmlPath);
    NSString *worker = [[NSString alloc] initWithData:readData([source stringByAppendingPathComponent:@"service-worker.js"]) encoding:NSUTF8StringEncoding];
    writeText([worker stringByReplacingOccurrencesOfString:oldRelease withString:release], [root stringByAppendingPathComponent:@"service-worker.js"]);
    writeText([release stringByAppendingString:@"\n"], [root stringByAppendingPathComponent:@"release.txt"]);
    NSString *manifestPath = [root stringByAppendingPathComponent:@"manifest.webmanifest"];
    NSMutableDictionary *manifest = [[NSJSONSerialization JSONObjectWithData:readData(manifestPath) options:0 error:nil] mutableCopy];
    manifest[@"name"] = name; manifest[@"short_name"] = name;
    // Default identity to this test folder's start_url. The production id,
    // "./", would resolve at the origin root and collide with production.
    [manifest removeObjectForKey:@"id"];
    writeData(jsonData(manifest), manifestPath);
    for (NSString *icon in appleIcons) writeData(appleIcons[icon], [root stringByAppendingPathComponent:icon]);
    // Measure after replacing Apple images and editing HTML/manifest. Each
    // diagnostic package is a complete, independent offline installation.
    NSMutableArray *nextInventory = [NSMutableArray new];
    for (NSString *path in paths) {
        NSDictionary *info = [files attributesOfItemAtPath:[root stringByAppendingPathComponent:path] error:nil];
        require(info != nil, [@"Missing test resource: " stringByAppendingString:path]);
        [nextInventory addObject:@{@"path": path, @"size": @(info.fileSize)}];
    }
    writeData(jsonData(nextInventory), [root stringByAppendingPathComponent:@"offline-resources.json"]);
    check(checker, root);
    return folder;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 5) { fprintf(stderr, "Usage: icon-check-packages COPLAND_WEB MANDELBROT_WEB OUTPUT PACKAGE_CHECKER\n"); return 2; }
        NSString *source = [NSURL fileURLWithPath:@(argv[1])].path;
        NSString *reference = [NSURL fileURLWithPath:@(argv[2])].path;
        NSString *output = [NSURL fileURLWithPath:@(argv[3])].path;
        NSString *checker = [NSURL fileURLWithPath:@(argv[4])].path;
        check(checker, source);
        NSString *release = releaseAt(source), *referenceRelease = releaseAt(reference);
        NSString *referenceIcons = reference;
        for (NSString *name in @[@"apple-touch-icon-152.png", @"apple-touch-icon-167.png", @"apple-touch-icon.png"])
            if (![NSFileManager.defaultManager fileExistsAtPath:[reference stringByAppendingPathComponent:name]]) {
                referenceIcons = [reference stringByAppendingPathComponent:[NSString stringWithFormat:@"releases/%@", referenceRelease]];
                break;
            }
        NSMutableDictionary *appleIcons = [NSMutableDictionary new];
        for (NSString *name in @[@"apple-touch-icon-152.png", @"apple-touch-icon-167.png", @"apple-touch-icon.png"]) {
            NSData *data = readData([referenceIcons stringByAppendingPathComponent:name]);
            require(![data isEqual:readData([source stringByAppendingPathComponent:name])], @"Reference and production Apple icons must differ");
            appleIcons[name] = data;
        }
        NSArray *inventory = [NSJSONSerialization JSONObjectWithData:readData([source stringByAppendingPathComponent:@"offline-resources.json"]) options:0 error:nil];
        NSString *probe = makePackage(source, output, release, inventory, @"probe", @"CVT Icon Probe", appleIcons, checker);
        NSString *control = makePackage(source, output, release, inventory, @"control", @"CVT Icon Control", @{}, checker);
        writeData(jsonData(@{@"probe": probe, @"control": control}), [output stringByAppendingPathComponent:@"latest.json"]);
        NSString *instructions = [NSString stringWithFormat:
            @"iPhone icon selection and appearance check\n\n"
             "Upload these two complete folders as siblings of /cvt/, outside its service-worker scope:\n"
             "  /%@/\n  /%@/\n\n"
             "Neither package is uploaded automatically. Production files are untouched.\n"
             "Each folder has a fresh release, a separate installation identity and a verified offline inventory.\n\n"
             "1. Open the Probe folder in Safari, wait for Offline ready, then add it to the Home Screen.\n"
             "   All three Apple Touch icons contain Mandelbrot. All manifest icons contain Copland.\n"
             "   Record the icon in the installation preview AND on the Home Screen.\n"
             "   Mandelbrot proves the Apple Touch group was selected; Copland points to a different icon source.\n"
             "2. Install the Control folder the same way. All its icons contain Copland.\n"
             "3. On both iOS 27.0.1 devices, set Home Screen customization to Dark > Automatic.\n"
             "   Switch the system between Light and Dark and compare both installations.\n"
             "   Record appearance, selected motif, device and iOS version. Do not change any icon background.\n"
             "4. In Safari's inspector, confirm each installation is controlled by its own worker and works offline.\n"
             "5. Remove both test installations and only these two server folders after the comparison.\n\n"
             "Do not replace files after packaging: the offline inventory would become invalid.\n"
             "Run make icon-check again for a fresh pair of test folders.\n",
             probe, control];
        writeText(instructions, [output stringByAppendingPathComponent:@"README.txt"]);
        printf("Probe: %s\nControl: %s\nInstructions: %s\n", [output stringByAppendingPathComponent:probe].UTF8String,
            [output stringByAppendingPathComponent:control].UTF8String, [output stringByAppendingPathComponent:@"README.txt"].UTF8String);
    }
    return 0;
}
