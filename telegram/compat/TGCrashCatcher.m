// Minimal on-device crash reporter for builds that run on iOS 6.
//
// Uncaught Objective-C exceptions and fatal signals are written to
// Library/Caches/last-crash.txt. On the next launch, before the app's own
// launch code runs, the report is shown full-screen and copied to the
// pasteboard, so it can be pasted into a chat without access to device logs.
// "Продолжить" then runs the normal application:didFinishLaunchingWithOptions:.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <execinfo.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

static char gCrashPath[1024];
static volatile sig_atomic_t gExceptionWritten = 0;

static NSString *TGCrashFilePath(void)
{
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:@"last-crash.txt"];
}

static void TGHandleException(NSException *exception)
{
    NSMutableString *report = [[NSMutableString alloc] init];
    [report appendFormat:@"app %@ %@\niOS %@ %@\nslide 0x%lx\n",
        [[NSBundle mainBundle] bundleIdentifier],
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?",
        [[UIDevice currentDevice] systemVersion], [[UIDevice currentDevice] model],
        (unsigned long)_dyld_get_image_vmaddr_slide(0)];
    [report appendFormat:@"exception %@\nreason %@\n", exception.name, exception.reason];
    for (NSString *frame in exception.callStackSymbols)
        [report appendFormat:@"%@\n", frame];
    [report writeToFile:TGCrashFilePath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    gExceptionWritten = 1;
}

static void TGHandleSignal(int sig)
{
    if (!(sig == SIGABRT && gExceptionWritten))
    {
        int fd = open(gCrashPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0)
        {
            char line[160];
            int len = snprintf(line, sizeof(line), "signal %d\nslide 0x%lx\n", sig, (unsigned long)_dyld_get_image_vmaddr_slide(0));
            write(fd, line, (size_t)len);
            void *frames[64];
            int count = backtrace(frames, 64);
            backtrace_symbols_fd(frames, count, fd);
            close(fd);
        }
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - Report screen

static NSString *gPendingReport;
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
    title.text = @"Прошлый запуск упал. Отчёт скопирован в буфер обмена.";
    title.numberOfLines = 2;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:title];

    UITextView *text = [[UITextView alloc] initWithFrame:CGRectMake(10, 55, bounds.size.width - 20, bounds.size.height - 120)];
    text.text = gPendingReport;
    text.editable = NO;
    text.font = [UIFont fontWithName:@"Courier" size:11];
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

static BOOL TGDidFinishLaunchingWithReport(id self, SEL _cmd, UIApplication *application, NSDictionary *options)
{
    if (gPendingReport == nil)
        return ((BOOL (*)(id, SEL, UIApplication *, NSDictionary *))gOriginalDidFinishLaunching)(self, _cmd, application, options);

    gReportWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    TGCrashReportController *controller = [[TGCrashReportController alloc] init];
    __weak id weakSelf = self;
    controller.onContinue = ^
    {
        gPendingReport = nil;
        gReportWindow.hidden = YES;
        gReportWindow = nil;
        ((BOOL (*)(id, SEL, UIApplication *, NSDictionary *))gOriginalDidFinishLaunching)(weakSelf, _cmd, application, options);
        [[UIApplication sharedApplication].delegate.window makeKeyAndVisible];
    };
    gReportWindow.rootViewController = controller;
    [gReportWindow makeKeyAndVisible];
    return YES;
}

static void (*gOriginalSetDelegate)(id, SEL, id);

static void TGSetDelegate(id self, SEL _cmd, id delegate)
{
    static bool hooked = false;
    if (!hooked && delegate != nil && gPendingReport != nil)
    {
        hooked = true;
        SEL sel = @selector(application:didFinishLaunchingWithOptions:);
        Method method = class_getInstanceMethod([delegate class], sel);
        if (method != NULL)
            gOriginalDidFinishLaunching = method_setImplementation(method, (IMP)TGDidFinishLaunchingWithReport);
    }
    gOriginalSetDelegate(self, _cmd, delegate);
}

__attribute__((constructor)) static void TGCrashCatcherInstall(void)
{
    @autoreleasepool
    {
        NSString *path = TGCrashFilePath();
        strncpy(gCrashPath, [path fileSystemRepresentation], sizeof(gCrashPath) - 1);

        NSString *report = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (report.length != 0)
        {
            gPendingReport = report;
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            Method setDelegate = class_getInstanceMethod([UIApplication class], @selector(setDelegate:));
            gOriginalSetDelegate = (void (*)(id, SEL, id))method_setImplementation(setDelegate, (IMP)TGSetDelegate);
        }

        NSSetUncaughtExceptionHandler(&TGHandleException);
        int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP };
        for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
            signal(signals[i], TGHandleSignal);
    }
}

// Pasteboard is set once UIKit is up (it is not available in a constructor).
@interface TGCrashCatcherPasteboard : NSObject
@end

@implementation TGCrashCatcherPasteboard

+ (void)load
{
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note)
    {
        if (gPendingReport != nil)
            [UIPasteboard generalPasteboard].string = gPendingReport;
    }];
}

@end
