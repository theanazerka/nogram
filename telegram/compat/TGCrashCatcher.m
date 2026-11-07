// On-device launch tracer and crash reporter for iOS 6 builds (no crash logs needed).
//
// - Installed from the first +load in the binary (this file is linked first), so it is
//   active before any other app code runs.
// - Every launch appends stage marks to Library/Caches/launch-trace.txt; uncaught
//   exceptions and fatal signals (with backtraces) go to the same file.
// - When the app has run for 10 s ("stable") the trace is deleted. If the previous
//   launch never got there (crash, watchdog kill, jetsam...), the next launch shows the
//   trace full screen before the app's own launch code and copies it to the pasteboard.
// - Upstream +load methods were renamed to +tg_deferredLoad and are run by
//   compat/TGDeferredLoads.m; a +load that crashed last time is skipped (see there).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <execinfo.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#import "TGCrashCatcher.h"

static char gTracePath[1024];
static NSString *gPendingReport;
static NSMutableSet *gSkippedLoads;

static NSString *TGCachesPath(NSString *name)
{
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:name];
}

void TGTraceMark(const char *mark)
{
    int fd = open(gTracePath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0)
        return;
    write(fd, mark, strlen(mark));
    write(fd, "\n", 1);
    fsync(fd);
    close(fd);
}

void TGTraceMarkf(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    TGTraceMark(text.UTF8String ?: "?");
}

bool TGTraceShouldSkipDeferredLoad(NSString *className)
{
    return [gSkippedLoads containsObject:className];
}

static void TGHandleException(NSException *exception)
{
    NSMutableString *report = [[NSMutableString alloc] init];
    [report appendFormat:@"EXCEPTION %@\nreason: %@\n", exception.name, exception.reason];
    for (NSString *frame in exception.callStackSymbols)
        [report appendFormat:@"  %@\n", frame];
    TGTraceMark(report.UTF8String ?: "EXCEPTION ?");
}

static void TGHandleSignal(int sig)
{
    char line[160];
    int len = snprintf(line, sizeof(line), "SIGNAL %d (slide 0x%lx)\n", sig, (unsigned long)_dyld_get_image_vmaddr_slide(0));
    int fd = open(gTracePath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0)
    {
        write(fd, line, (size_t)len);
        void *frames[64];
        int count = backtrace(frames, 64);
        backtrace_symbols_fd(frames, count, fd);
        close(fd);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - Report screen

static IMP gOriginalDidFinishLaunching;
static UIWindow *gReportWindow;

@interface TGCrashReportController : UIViewController
@property (nonatomic, copy) void (^onContinue)(void);
@end

@implementation TGCrashReportController

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    view.backgroundColor = [UIColor whiteColor];
    CGRect bounds = view.bounds;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, bounds.size.width - 20, 40)];
    title.text = @"Прошлый запуск не удался. Отчёт скопирован в буфер обмена.";
    title.numberOfLines = 2;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:title];

    UITextView *text = [[UITextView alloc] initWithFrame:CGRectMake(10, 55, bounds.size.width - 20, bounds.size.height - 120)];
    text.text = gPendingReport;
    text.editable = NO;
    text.font = [UIFont fontWithName:@"Courier" size:10];
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:text];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.frame = CGRectMake(10, bounds.size.height - 55, bounds.size.width - 20, 44);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [button setTitle:@"Продолжить запуск" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(continuePressed) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];

    self.view = view;
}

- (void)continuePressed
{
    if (self.onContinue)
        self.onContinue();
}

@end

static BOOL TGCallOriginalDidFinishLaunching(id self, SEL cmd, UIApplication *application, NSDictionary *options)
{
    TGTraceMark("didFinishLaunching: begin");
    BOOL result = ((BOOL (*)(id, SEL, UIApplication *, NSDictionary *))gOriginalDidFinishLaunching)(self, cmd, application, options);
    TGTraceMark("didFinishLaunching: end");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        TGTraceMark("stable");
        // A clean run: forget the trace. Skipped +loads stay skipped until the next build.
        unlink(gTracePath);
    });
    return result;
}

static BOOL TGDidFinishLaunching(id self, SEL cmd, UIApplication *application, NSDictionary *options)
{
    if (gPendingReport == nil)
        return TGCallOriginalDidFinishLaunching(self, cmd, application, options);

    [UIPasteboard generalPasteboard].string = gPendingReport;
    gReportWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    TGCrashReportController *controller = [[TGCrashReportController alloc] init];
    __weak id weakSelf = self;
    controller.onContinue = ^
    {
        gPendingReport = nil;
        gReportWindow.hidden = YES;
        gReportWindow = nil;
        TGCallOriginalDidFinishLaunching(weakSelf, cmd, application, options);
        [[UIApplication sharedApplication].delegate.window makeKeyAndVisible];
    };
    gReportWindow.rootViewController = controller;
    [gReportWindow makeKeyAndVisible];
    TGTraceMark("report shown");
    return YES;
}

static void (*gOriginalSetDelegate)(id, SEL, id);

static void TGSetDelegate(id self, SEL cmd, id delegate)
{
    static bool hooked = false;
    if (!hooked && delegate != nil)
    {
        hooked = true;
        TGTraceMarkf(@"app delegate: %@", NSStringFromClass([delegate class]));
        Method method = class_getInstanceMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:));
        if (method != NULL)
            gOriginalDidFinishLaunching = method_setImplementation(method, (IMP)TGDidFinishLaunching);
    }
    gOriginalSetDelegate(self, cmd, delegate);
}

#pragma mark - Install

@interface TGCrashCatcher : NSObject
@end

@implementation TGCrashCatcher

+ (void)load
{
    @autoreleasepool
    {
        NSString *tracePath = TGCachesPath(@"launch-trace.txt");
        strncpy(gTracePath, [tracePath fileSystemRepresentation], sizeof(gTracePath) - 1);

        NSString *skippedPath = TGCachesPath(@"skipped-loads.txt");
        NSString *build = [NSString stringWithFormat:@"build %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?"];
        NSString *skipped = [NSString stringWithContentsOfFile:skippedPath encoding:NSUTF8StringEncoding error:NULL] ?: @"";
        NSArray *skippedLines = [skipped componentsSeparatedByString:@"\n"];
        gSkippedLoads = [[NSMutableSet alloc] init];
        // The list belongs to one build: a new build gets every +load another chance.
        if (skippedLines.count != 0 && [skippedLines[0] isEqualToString:build])
        {
            for (NSString *line in [skippedLines subarrayWithRange:NSMakeRange(1, skippedLines.count - 1)])
                if (line.length != 0)
                    [gSkippedLoads addObject:line];
        }

        // The previous launch never reached "stable": report it.
        NSString *previous = [NSString stringWithContentsOfFile:tracePath encoding:NSUTF8StringEncoding error:NULL];
        if (previous.length != 0)
        {
            // If it died inside a deferred +load, skip that one from now on.
            NSString *lastBegin = nil;
            for (NSString *line in [previous componentsSeparatedByString:@"\n"])
            {
                if ([line hasPrefix:@"+load begin "])
                    lastBegin = [line substringFromIndex:12];
                else if ([line hasPrefix:@"+load end "] && [[line substringFromIndex:10] isEqualToString:lastBegin ?: @""])
                    lastBegin = nil;
            }
            if (lastBegin.length != 0 && ![gSkippedLoads containsObject:lastBegin])
            {
                [gSkippedLoads addObject:lastBegin];
                NSString *all = [build stringByAppendingFormat:@"\n%@", [[gSkippedLoads allObjects] componentsJoinedByString:@"\n"]];
                [all writeToFile:skippedPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }

            NSMutableString *report = [[NSMutableString alloc] init];
            [report appendFormat:@"%@ %@ / iOS %@ %@\n", [[NSBundle mainBundle] bundleIdentifier],
                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?",
                [[UIDevice currentDevice] systemVersion], [[UIDevice currentDevice] model]];
            if (gSkippedLoads.count != 0)
                [report appendFormat:@"skipping +load of: %@\n", [[gSkippedLoads allObjects] componentsJoinedByString:@", "]];
            [report appendString:@"--- previous launch trace ---\n"];
            [report appendString:previous.length > 12000 ? [previous substringFromIndex:previous.length - 12000] : previous];
            gPendingReport = report;
            unlink(gTracePath);
        }

        TGTraceMarkf(@"launch %@ (slide 0x%lx)", [NSDate date], (unsigned long)_dyld_get_image_vmaddr_slide(0));

        NSSetUncaughtExceptionHandler(&TGHandleException);
        int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP };
        for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
            signal(signals[i], TGHandleSignal);

        Method setDelegate = class_getInstanceMethod([UIApplication class], @selector(setDelegate:));
        gOriginalSetDelegate = (void (*)(id, SEL, id))method_setImplementation(setDelegate, (IMP)TGSetDelegate);
    }
}

@end
