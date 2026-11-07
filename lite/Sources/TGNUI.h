#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

void TGNShowAlert(NSString *title, NSString *message);
NSString *TGNFormatDate(int32_t unixtime, bool short_);
UIColor *TGNColor(uint32_t rgb);
// Plain grouped-style form helpers used by the login screens.
UITextField *TGNMakeField(NSString *placeholder, UIKeyboardType keyboard);
UILabel *TGNMakeLabel(NSString *text, CGFloat fontSize, bool bold);
UIButton *TGNMakeButton(NSString *title, id target, SEL action);

#ifdef __cplusplus
}
#endif

// Base class for the login steps: a scrollable column of views with a spinner.
@interface TGNFormController : UIViewController
@property (nonatomic, strong, readonly) UIScrollView *scrollView;
- (void)addFormView:(UIView *)view height:(CGFloat)height;
- (void)setBusy:(bool)busy;
@property (nonatomic, readonly) bool busy;
@end
