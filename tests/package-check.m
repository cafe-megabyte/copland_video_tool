#import <Foundation/Foundation.h>

static NSFileManager *files;
static NSString *product, *checker, *parent;
static unsigned checks;
static void require(BOOL valid, NSString *message) {
    if (!valid) { fprintf(stderr, "Package regression: %s\n", message.UTF8String); exit(1); }
}
static NSData *readFixture(NSString *root, NSString *path) { return [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:path]]; }
static void writeFixture(NSString *root, NSString *path, NSData *data) {
    require([data writeToFile:[root stringByAppendingPathComponent:path] options:0 error:nil], [@"Cannot write " stringByAppendingString:path]);
}
static void writeJSON(NSString *root, NSString *path, id value) {
    writeFixture(root, path, [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil]);
}
static void refreshInventory(NSString *root) {
    NSArray *inventory = [NSJSONSerialization JSONObjectWithData:readFixture(root, @"offline-resources.json") options:0 error:nil];
    NSMutableArray *next = [NSMutableArray new];
    for (NSDictionary *item in inventory) [next addObject:@{@"path": item[@"path"], @"size": @(readFixture(root, item[@"path"]).length)}];
    writeJSON(root, @"offline-resources.json", next);
}
static NSString *releaseDirectory(NSString *root) {
    NSString *release = [[[NSString alloc] initWithData:readFixture(root, @"release.txt") encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [root stringByAppendingPathComponent:[NSString stringWithFormat:@"releases/%@", release]];
}
static void run(NSString *name, NSString *expectedError, void (^mutate)(NSString *root)) {
    NSString *root = [parent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    require([files copyItemAtPath:product toPath:root error:nil], @"Cannot create package fixture");
    mutate(root);
    NSTask *task = [NSTask new]; NSPipe *pipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:checker]; task.arguments = @[root];
    task.standardError = pipe; task.standardOutput = pipe;
    require([task launchAndReturnError:nil], @"Cannot run package checker");
    NSData *output = [pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    NSString *message = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    BOOL valid = expectedError ? task.terminationStatus == 1 && [message containsString:expectedError] : task.terminationStatus == 0;
    require([files removeItemAtPath:root error:nil], @"Cannot remove package fixture");
    require(valid, [NSString stringWithFormat:@"%@: unexpected result %@ (%d)", name, message, task.terminationStatus]);
    ++checks;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        files = NSFileManager.defaultManager;
        product = [NSURL fileURLWithPath:@(argv[1])].path; checker = [NSURL fileURLWithPath:@(argv[2])].path;
        parent = [files.currentDirectoryPath stringByAppendingPathComponent:@"build/internal/tests/package-check-fixtures"];
        require([files createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create fixtures directory");
        run(@"Valid package", nil, ^(NSString *root) { (void)root; });
        run(@"Historical releases remain valid", nil, ^(NSString *root) {
            NSString *legacy = [root stringByAppendingPathComponent:@"releases/00000000-0000-0000-0000-000000000000"];
            require([files createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create historical release");
            writeFixture(legacy, @"icon-180.png", readFixture(root, @"apple-touch-icon.png"));
        });
        run(@"Changed icon without rebuilt inventory", @"Offline size mismatch", ^(NSString *root) {
            writeFixture(root, @"apple-touch-icon.png", readFixture(root, @"icon-32.png"));
        });
        run(@"Wrong PNG dimensions with correct inventory", @"Invalid icon dimensions", ^(NSString *root) {
            writeFixture(root, @"apple-touch-icon.png", readFixture(root, @"icon-32.png")); refreshInventory(root);
        });
        run(@"Lost transparency", @"Invalid icon dimensions, alpha", ^(NSString *root) {
            writeFixture(root, @"icon-512.png", readFixture(root, @"icon-maskable-512.png")); refreshInventory(root);
        });
        run(@"Apple Touch link into a release", @"Invalid or duplicate Apple Touch link", ^(NSString *root) {
            NSString *html = [[NSString alloc] initWithData:readFixture(root, @"index.html") encoding:NSUTF8StringEncoding];
            html = [html stringByReplacingOccurrencesOfString:@"href=\"./apple-touch-icon.png\"" withString:@"href=\"./releases/old/apple-touch-icon.png\""];
            writeFixture(root, @"index.html", [html dataUsingEncoding:NSUTF8StringEncoding]); refreshInventory(root);
        });
        run(@"Manifest link into a release", @"Manifest icon must use", ^(NSString *root) {
            NSMutableDictionary *manifest = [[NSJSONSerialization JSONObjectWithData:readFixture(root, @"manifest.webmanifest") options:0 error:nil] mutableCopy];
            NSMutableArray *icons = [manifest[@"icons"] mutableCopy]; NSMutableDictionary *icon = [icons[0] mutableCopy];
            icon[@"src"] = @"./releases/old/icon-192.png"; icons[0] = icon; manifest[@"icons"] = icons;
            writeJSON(root, @"manifest.webmanifest", manifest); refreshInventory(root);
        });
        run(@"Duplicate offline resource", @"Invalid or duplicate offline path", ^(NSString *root) {
            NSMutableArray *inventory = [[NSJSONSerialization JSONObjectWithData:readFixture(root, @"offline-resources.json") options:0 error:nil] mutableCopy];
            [inventory addObject:inventory[0]]; writeJSON(root, @"offline-resources.json", inventory);
        });
        run(@"Icon omitted from inventory", @"Icon missing from inventory", ^(NSString *root) {
            NSMutableArray *inventory = [[NSJSONSerialization JSONObjectWithData:readFixture(root, @"offline-resources.json") options:0 error:nil] mutableCopy];
            NSIndexSet *indices = [inventory indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
                (void)index; (void)stop; return [item[@"path"] isEqual:@"icon-64.png"];
            }];
            [inventory removeObjectsAtIndexes:indices]; writeJSON(root, @"offline-resources.json", inventory);
        });
        run(@"Obsolete root alias", @"Obsolete root icon", ^(NSString *root) {
            writeFixture(root, @"icon-180.png", readFixture(root, @"apple-touch-icon.png"));
        });
        run(@"Icon copied into current release", @"Current release must not contain icon copies", ^(NSString *root) {
            writeFixture(releaseDirectory(root), @"apple-touch-icon.png", readFixture(root, @"apple-touch-icon.png"));
        });
        run(@"Service worker from another release", @"Service worker release mismatch", ^(NSString *root) {
            writeFixture(root, @"service-worker.js", [@"const RELEASE = '00000000-0000-0000-0000-000000000000';" dataUsingEncoding:NSUTF8StringEncoding]);
        });
        run(@"Invalid embedded ICO frame", @"Invalid ICO", ^(NSString *root) {
            NSMutableData *data = [readFixture(root, @"favicon.ico") mutableCopy];
            ((uint8_t *)data.mutableBytes)[6] = 15;
            writeFixture(root, @"favicon.ico", data); refreshInventory(root);
        });
        require([files removeItemAtPath:parent error:nil], @"Cannot remove fixtures directory");
        printf("Icon package: %u valid, compatibility and rejection scenarios passed.\n", checks);
    }
    return 0;
}
