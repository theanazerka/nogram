#import "TGNAppDelegate.h"

#import "TGNClient.h"
#import "TGNStore.h"
#import "TGNUI.h"
#import "TGNAuthControllers.h"
#import "TGNDialogsController.h"

@implementation TGNAppDelegate

+ (TGNAppDelegate *)shared
{
    return (TGNAppDelegate *)[UIApplication sharedApplication].delegate;
}

- (BOOL)application:(UIApplication *)__unused application didFinishLaunchingWithOptions:(NSDictionary *)__unused launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loggedOut:) name:TGNLoggedOutNotification object:nil];

    if ([TGNClient hasApiCredentials])
        [[TGNClient shared] start];

    [self showRootInterface];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showRootInterface
{
    UIViewController *root = nil;
    if (![TGNClient hasApiCredentials])
        root = [[TGNApiSetupController alloc] init];
    else if (![TGNClient shared].isAuthorized)
        root = [[TGNPhoneController alloc] init];
    else
        root = [[TGNDialogsController alloc] init];

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = navigation;
}

- (void)loggedOut:(NSNotification *)__unused notification
{
    [self showRootInterface];
}

- (void)applicationDidEnterBackground:(UIApplication *)__unused application
{
    [[TGNStore shared] save];
}

- (void)applicationWillTerminate:(UIApplication *)__unused application
{
    [[TGNStore shared] save];
}

@end
