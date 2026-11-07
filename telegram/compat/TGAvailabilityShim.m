// Runtime support for @available(...) checks.
// Newer clang lowers @available to __isOSVersionAtLeast(), which normally lives in
// compiler-rt (libclang_rt.ios.a); provide it here so the app links for iOS 6.

#import <UIKit/UIKit.h>

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor);

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor)
{
    static int32_t current[3] = {0, 0, 0};
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        NSArray *parts = [[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."];
        for (NSUInteger i = 0; i < 3 && i < parts.count; i++)
            current[i] = (int32_t)[parts[i] intValue];
    });
    if (current[0] != major)
        return current[0] > major;
    if (current[1] != minor)
        return current[1] > minor;
    return current[2] >= subminor;
}
