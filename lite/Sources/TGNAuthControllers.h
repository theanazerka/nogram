#import "TGNUI.h"

// Asks for api_id / api_hash from my.telegram.org when none were compiled in.
@interface TGNApiSetupController : TGNFormController
@end

@interface TGNPhoneController : TGNFormController
@end

@interface TGNCodeController : TGNFormController
- (instancetype)initWithPhone:(NSString *)phone sentCode:(NSDictionary *)sentCode;
@end

@interface TGNEmailSetupController : TGNFormController
- (instancetype)initWithPhone:(NSString *)phone phoneCodeHash:(NSString *)phoneCodeHash;
@end

@interface TGNPasswordController : TGNFormController
- (instancetype)initWithPassword:(NSDictionary *)accountPassword;
@end

@interface TGNSignUpController : TGNFormController
- (instancetype)initWithPhone:(NSString *)phone phoneCodeHash:(NSString *)phoneCodeHash;
@end

// Handles any auth.Authorization result (or SESSION_PASSWORD_NEEDED) from a login step.
void TGNHandleAuthorizationResult(UIViewController *from, id result, NSString *phone, NSString *phoneCodeHash);
