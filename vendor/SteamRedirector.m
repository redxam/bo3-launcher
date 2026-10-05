#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        // Look for BO3 Launcher.app in known locations
        NSArray *searchPaths = @[
            @"/Applications/BO3 Launcher.app",
            [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/BO3 Launcher.app"],
            // Also check next to the game itself (in the BO3MacFix folder)
            [[[NSString stringWithUTF8String:argv[0]]
                stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:@"../../../BO3MacFix/BO3 Launcher.app"],
        ];

        for (NSString *path in searchPaths) {
            NSString *resolved = [path stringByStandardizingPath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:resolved]) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:resolved]];
                return 0;
            }
        }

        // Fallback: try to find it via Launch Services
        NSArray *urls = [[NSWorkspace sharedWorkspace]
            URLsForApplicationsWithBundleIdentifier:@"com.redxam.bo3launcher"];
        if (urls.count > 0) {
            [[NSWorkspace sharedWorkspace] openURL:urls[0]];
            return 0;
        }

        // Last resort: show error
        NSLog(@"BO3 Launcher.app not found. Install it to /Applications.");
        return 1;
    }
}
