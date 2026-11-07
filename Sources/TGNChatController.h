#import <UIKit/UIKit.h>

@interface TGNChatController : UIViewController

@property (nonatomic, strong, readonly) NSString *peerKey;

- (instancetype)initWithPeerKey:(NSString *)peerKey;

@end
