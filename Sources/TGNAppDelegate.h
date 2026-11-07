#import <UIKit/UIKit.h>

@interface TGNAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

+ (TGNAppDelegate *)shared;
- (void)showRootInterface;

@end
