#import "TGNAuthControllers.h"

#import "TL.h"
#import "TGNClient.h"
#import "TGNSRP.h"
#import "TGNAppDelegate.h"

static NSString *TGNDigitsOnly(NSString *text)
{
    NSMutableString *result = [[NSMutableString alloc] init];
    for (NSUInteger i = 0; i < text.length; i++)
    {
        unichar c = [text characterAtIndex:i];
        if (c >= '0' && c <= '9')
            [result appendFormat:@"%C", c];
    }
    return result;
}

static void TGNFinishLogin(id authorization)
{
    [[TGNClient shared] completeAuthorizationWithResult:authorization];
    [[TGNAppDelegate shared] showRootInterface];
}

void TGNHandleAuthorizationResult(UIViewController *from, id result, NSString *phone, NSString *phoneCodeHash)
{
    if (TLIs(result, @"auth.authorization"))
    {
        TGNFinishLogin(result);
    }
    else if (TLIs(result, @"auth.authorizationSignUpRequired"))
    {
        [from.navigationController pushViewController:[[TGNSignUpController alloc] initWithPhone:phone phoneCodeHash:phoneCodeHash] animated:YES];
    }
    else
    {
        TGNShowAlert(@"Ошибка", [NSString stringWithFormat:@"Неожиданный ответ сервера: %@", TLName(result)]);
    }
}

static void TGNRequestPasswordStep(TGNFormController *from)
{
    [from setBusy:true];
    __weak TGNFormController *weakFrom = from;
    [[TGNClient shared] invoke:@{@"_": @"account.getPassword"} completion:^(id result, TGNError *error)
    {
        TGNFormController *strongFrom = weakFrom;
        [strongFrom setBusy:false];
        if (error != nil)
        {
            TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        [strongFrom.navigationController pushViewController:[[TGNPasswordController alloc] initWithPassword:result] animated:YES];
    }];
}

#pragma mark - API setup

@interface TGNApiSetupController ()
{
    UITextField *_apiIdField;
    UITextField *_apiHashField;
}
@end

@implementation TGNApiSetupController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"api_id";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Готово" style:UIBarButtonItemStyleDone target:self action:@selector(done)];

    [self addFormView:TGNMakeLabel(@"nogram", 26.0f, true) height:34.0f];
    [self addFormView:TGNMakeLabel(@"Для работы клиента нужен собственный api_id и api_hash. Получите их на my.telegram.org → API development tools и введите ниже.", 15.0f, false) height:0.0f];
    _apiIdField = TGNMakeField(@"api_id", UIKeyboardTypeNumberPad);
    [self addFormView:_apiIdField height:44.0f];
    _apiHashField = TGNMakeField(@"api_hash", UIKeyboardTypeASCIICapable);
    [self addFormView:_apiHashField height:44.0f];
    [self addFormView:TGNMakeButton(@"Сохранить", self, @selector(done)) height:44.0f];
}

- (void)done
{
    int32_t apiId = (int32_t)[TGNDigitsOnly(_apiIdField.text) longLongValue];
    NSString *apiHash = [_apiHashField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (apiId <= 0 || apiHash.length != 32)
    {
        TGNShowAlert(@"Проверьте данные", @"api_id — число, api_hash — 32 символа.");
        return;
    }
    [TGNClient setApiId:apiId apiHash:apiHash];
    [[TGNClient shared] start];
    [[TGNAppDelegate shared] showRootInterface];
}

@end

#pragma mark - Phone

@interface TGNPhoneController () <UITextFieldDelegate>
{
    UITextField *_codeField;
    UITextField *_phoneField;
}
@end

@implementation TGNPhoneController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Телефон";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Далее" style:UIBarButtonItemStyleDone target:self action:@selector(next)];

    [self addFormView:TGNMakeLabel(@"Вход в Telegram", 24.0f, true) height:32.0f];
    [self addFormView:TGNMakeLabel(@"Укажите код страны и номер телефона.", 15.0f, false) height:0.0f];

    _codeField = TGNMakeField(@"Код страны", UIKeyboardTypePhonePad);
    NSString *country = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    NSDictionary *codes = @{@"RU": @"+7", @"KZ": @"+7", @"UA": @"+380", @"BY": @"+375", @"US": @"+1", @"DE": @"+49", @"GB": @"+44", @"UZ": @"+998", @"AM": @"+374", @"GE": @"+995", @"AZ": @"+994", @"KG": @"+996", @"TJ": @"+992", @"MD": @"+373", @"LV": @"+371", @"LT": @"+370", @"EE": @"+372", @"PL": @"+48", @"IL": @"+972", @"TR": @"+90"};
    _codeField.text = codes[country] ?: @"+";
    [self addFormView:_codeField height:44.0f];

    _phoneField = TGNMakeField(@"Номер телефона", UIKeyboardTypePhonePad);
    [self addFormView:_phoneField height:44.0f];

    [self addFormView:TGNMakeButton(@"Получить код", self, @selector(next)) height:44.0f];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_phoneField becomeFirstResponder];
}

- (void)next
{
    if (self.busy)
        return;
    NSString *phone = [TGNDigitsOnly(_codeField.text) stringByAppendingString:TGNDigitsOnly(_phoneField.text)];
    if (phone.length < 7)
    {
        TGNShowAlert(@"Номер", @"Введите номер полностью.");
        return;
    }
    [self setBusy:true];
    __weak TGNPhoneController *weakSelf = self;
    NSDictionary *request = @{
        @"_": @"auth.sendCode",
        @"phone_number": phone,
        @"api_id": @([TGNClient apiId]),
        @"api_hash": [TGNClient apiHash],
        @"settings": @{@"_": @"codeSettings"},
    };
    [[TGNClient shared] invoke:request completion:^(id result, TGNError *error)
    {
        TGNPhoneController *strongSelf = weakSelf;
        [strongSelf setBusy:false];
        if (error != nil)
        {
            TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        if (TLIs(result, @"auth.sentCodeSuccess"))
        {
            TGNFinishLogin(TLDict(result, @"authorization"));
            return;
        }
        if (TLIs(result, @"auth.sentCodePaymentRequired"))
        {
            TGNShowAlert(@"Вход недоступен", @"Telegram требует оплату для входа с этого номера. Войдите через официальное приложение.");
            return;
        }
        NSDictionary *type = TLDict(result, @"type");
        if (TLIs(type, @"auth.sentCodeTypeSetUpEmailRequired"))
        {
            [strongSelf.navigationController pushViewController:[[TGNEmailSetupController alloc] initWithPhone:phone phoneCodeHash:TLString(result, @"phone_code_hash")] animated:YES];
            return;
        }
        [strongSelf.navigationController pushViewController:[[TGNCodeController alloc] initWithPhone:phone sentCode:result] animated:YES];
    }];
}

@end

#pragma mark - Code

@interface TGNCodeController ()
{
    NSString *_phone;
    NSDictionary *_sentCode;
    UILabel *_infoLabel;
    UITextField *_codeField;
    UIButton *_resendButton;
}
@end

@implementation TGNCodeController

- (instancetype)initWithPhone:(NSString *)phone sentCode:(NSDictionary *)sentCode
{
    self = [super init];
    if (self != nil)
    {
        _phone = phone;
        _sentCode = sentCode;
    }
    return self;
}

- (NSString *)phoneCodeHash
{
    return TLString(_sentCode, @"phone_code_hash") ?: @"";
}

- (bool)isEmailCode
{
    return TLIs(TLDict(_sentCode, @"type"), @"auth.sentCodeTypeEmailCode");
}

- (NSString *)describeSentCode
{
    NSDictionary *type = TLDict(_sentCode, @"type");
    NSString *name = TLName(type);
    if ([name isEqualToString:@"auth.sentCodeTypeApp"])
        return @"Код отправлен в Telegram на другом вашем устройстве (чат «Telegram»).";
    if ([name isEqualToString:@"auth.sentCodeTypeSms"] || [name isEqualToString:@"auth.sentCodeTypeSmsWord"] || [name isEqualToString:@"auth.sentCodeTypeSmsPhrase"])
        return [NSString stringWithFormat:@"Код отправлен по SMS на +%@.", _phone];
    if ([name isEqualToString:@"auth.sentCodeTypeCall"])
        return @"Вам позвонят и продиктуют код.";
    if ([name isEqualToString:@"auth.sentCodeTypeFlashCall"] || [name isEqualToString:@"auth.sentCodeTypeMissedCall"])
        return [NSString stringWithFormat:@"Вам поступит звонок. Введите последние цифры номера%@.", TLString(type, @"prefix") ? [NSString stringWithFormat:@" (начинается с %@)", TLString(type, @"prefix")] : @""];
    if ([name isEqualToString:@"auth.sentCodeTypeEmailCode"])
        return [NSString stringWithFormat:@"Код отправлен на почту %@.", TLString(type, @"email_pattern") ?: @""];
    if ([name isEqualToString:@"auth.sentCodeTypeFragmentSms"])
        return [NSString stringWithFormat:@"Код отправлен через Fragment: %@", TLString(type, @"url") ?: @""];
    if ([name isEqualToString:@"auth.sentCodeTypeFirebaseSms"])
        return @"Код отправлен по SMS.";
    return @"Введите полученный код.";
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"+%@", _phone];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Далее" style:UIBarButtonItemStyleDone target:self action:@selector(next)];

    _infoLabel = TGNMakeLabel([self describeSentCode], 15.0f, false);
    [self addFormView:_infoLabel height:0.0f];

    _codeField = TGNMakeField(@"Код", [self isEmailCode] ? UIKeyboardTypeASCIICapable : UIKeyboardTypeNumberPad);
    _codeField.textAlignment = NSTextAlignmentCenter;
    _codeField.font = [UIFont boldSystemFontOfSize:24.0f];
    [self addFormView:_codeField height:50.0f];

    [self addFormView:TGNMakeButton(@"Войти", self, @selector(next)) height:44.0f];

    _resendButton = TGNMakeButton(@"Отправить код другим способом", self, @selector(resend));
    _resendButton.hidden = _sentCode[@"next_type"] == nil;
    [self addFormView:_resendButton height:44.0f];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_codeField becomeFirstResponder];
}

- (void)resend
{
    if (self.busy)
        return;
    [self setBusy:true];
    __weak TGNCodeController *weakSelf = self;
    [[TGNClient shared] invoke:@{@"_": @"auth.resendCode", @"phone_number": _phone, @"phone_code_hash": [self phoneCodeHash]} completion:^(id result, TGNError *error)
    {
        TGNCodeController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        [strongSelf setBusy:false];
        if (error != nil)
        {
            TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        if (TLIs(result, @"auth.sentCode"))
        {
            strongSelf->_sentCode = result;
            strongSelf->_infoLabel.text = [strongSelf describeSentCode];
            strongSelf->_resendButton.hidden = result[@"next_type"] == nil;
            [strongSelf.view setNeedsLayout];
        }
    }];
}

- (void)next
{
    if (self.busy)
        return;
    NSString *code = [_codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (code.length == 0)
        return;

    NSMutableDictionary *request = [@{@"_": @"auth.signIn", @"phone_number": _phone, @"phone_code_hash": [self phoneCodeHash]} mutableCopy];
    if ([self isEmailCode])
        request[@"email_verification"] = @{@"_": @"emailVerificationCode", @"code": code};
    else
        request[@"phone_code"] = code;

    [self setBusy:true];
    __weak TGNCodeController *weakSelf = self;
    NSString *phone = _phone;
    NSString *hash = [self phoneCodeHash];
    [[TGNClient shared] invoke:request completion:^(id result, TGNError *error)
    {
        TGNCodeController *strongSelf = weakSelf;
        [strongSelf setBusy:false];
        if (error != nil)
        {
            if ([error.text isEqualToString:@"SESSION_PASSWORD_NEEDED"])
                TGNRequestPasswordStep(strongSelf);
            else
                TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        TGNHandleAuthorizationResult(strongSelf, result, phone, hash);
    }];
}

@end

#pragma mark - Email setup (auth.sentCodeTypeSetUpEmailRequired)

@interface TGNEmailSetupController ()
{
    NSString *_phone;
    NSString *_phoneCodeHash;
    UITextField *_emailField;
    UITextField *_codeField;
    UILabel *_infoLabel;
    bool _codeSent;
}
@end

@implementation TGNEmailSetupController

- (instancetype)initWithPhone:(NSString *)phone phoneCodeHash:(NSString *)phoneCodeHash
{
    self = [super init];
    if (self != nil)
    {
        _phone = phone;
        _phoneCodeHash = phoneCodeHash ?: @"";
    }
    return self;
}

- (NSDictionary *)purpose
{
    return @{@"_": @"emailVerifyPurposeLoginSetup", @"phone_number": _phone, @"phone_code_hash": _phoneCodeHash};
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Почта";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Далее" style:UIBarButtonItemStyleDone target:self action:@selector(next)];

    _infoLabel = TGNMakeLabel(@"Telegram требует привязать почту для входа. Введите адрес — на него придёт код.", 15.0f, false);
    [self addFormView:_infoLabel height:0.0f];
    _emailField = TGNMakeField(@"E-mail", UIKeyboardTypeEmailAddress);
    [self addFormView:_emailField height:44.0f];
    _codeField = TGNMakeField(@"Код из письма", UIKeyboardTypeNumberPad);
    _codeField.hidden = YES;
    [self addFormView:_codeField height:44.0f];
    [self addFormView:TGNMakeButton(@"Далее", self, @selector(next)) height:44.0f];
}

- (void)next
{
    if (self.busy)
        return;
    __weak TGNEmailSetupController *weakSelf = self;
    if (!_codeSent)
    {
        NSString *email = [_emailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([email rangeOfString:@"@"].location == NSNotFound)
            return;
        [self setBusy:true];
        [[TGNClient shared] invoke:@{@"_": @"account.sendVerifyEmailCode", @"purpose": [self purpose], @"email": email} completion:^(id result, TGNError *error)
        {
            TGNEmailSetupController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            [strongSelf setBusy:false];
            if (error != nil)
            {
                TGNShowAlert(@"Ошибка", error.localizedText);
                return;
            }
            strongSelf->_codeSent = true;
            strongSelf->_codeField.hidden = NO;
            strongSelf->_emailField.enabled = NO;
            strongSelf->_infoLabel.text = [NSString stringWithFormat:@"Код отправлен на %@.", TLString(result, @"email_pattern") ?: email];
            [strongSelf.view setNeedsLayout];
            [strongSelf->_codeField becomeFirstResponder];
        }];
        return;
    }

    NSString *code = [_codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (code.length == 0)
        return;
    [self setBusy:true];
    NSString *phone = _phone;
    [[TGNClient shared] invoke:@{@"_": @"account.verifyEmail", @"purpose": [self purpose], @"verification": @{@"_": @"emailVerificationCode", @"code": code}} completion:^(id result, TGNError *error)
    {
        TGNEmailSetupController *strongSelf = weakSelf;
        [strongSelf setBusy:false];
        if (error != nil)
        {
            TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        NSDictionary *sentCode = TLDict(result, @"sent_code");
        if (TLIs(sentCode, @"auth.sentCodeSuccess"))
        {
            TGNFinishLogin(TLDict(sentCode, @"authorization"));
            return;
        }
        if (sentCode != nil)
            [strongSelf.navigationController pushViewController:[[TGNCodeController alloc] initWithPhone:phone sentCode:sentCode] animated:YES];
    }];
}

@end

#pragma mark - Password

@interface TGNPasswordController ()
{
    NSDictionary *_accountPassword;
    UITextField *_passwordField;
}
@end

@implementation TGNPasswordController

- (instancetype)initWithPassword:(NSDictionary *)accountPassword
{
    self = [super init];
    if (self != nil)
        _accountPassword = accountPassword;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Пароль";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Войти" style:UIBarButtonItemStyleDone target:self action:@selector(next)];

    NSString *hint = TLString(_accountPassword, @"hint");
    NSString *info = @"Включена двухэтапная аутентификация. Введите облачный пароль.";
    if (hint.length != 0)
        info = [info stringByAppendingFormat:@"\nПодсказка: %@", hint];
    [self addFormView:TGNMakeLabel(info, 15.0f, false) height:0.0f];
    _passwordField = TGNMakeField(@"Пароль", UIKeyboardTypeDefault);
    _passwordField.secureTextEntry = YES;
    [self addFormView:_passwordField height:44.0f];
    [self addFormView:TGNMakeButton(@"Войти", self, @selector(next)) height:44.0f];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_passwordField becomeFirstResponder];
}

- (void)next
{
    if (self.busy)
        return;
    NSString *password = _passwordField.text ?: @"";
    if (password.length == 0)
        return;
    [self setBusy:true];
    __weak TGNPasswordController *weakSelf = self;
    NSDictionary *accountPassword = _accountPassword;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        NSDictionary *check = TGNComputePasswordCheck(accountPassword, password);
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGNPasswordController *strongSelf = weakSelf;
            if (check == nil)
            {
                [strongSelf setBusy:false];
                TGNShowAlert(@"Ошибка", @"Не удалось вычислить проверку пароля (неподдерживаемый алгоритм).");
                return;
            }
            [[TGNClient shared] invoke:@{@"_": @"auth.checkPassword", @"password": check} completion:^(id result, TGNError *error)
            {
                TGNPasswordController *innerSelf = weakSelf;
                [innerSelf setBusy:false];
                if (error != nil)
                {
                    if ([error.text isEqualToString:@"SRP_ID_INVALID"])
                    {
                        // Parameters expired: refetch and let the user retry.
                        [[TGNClient shared] invoke:@{@"_": @"account.getPassword"} completion:^(id fresh, __unused TGNError *e)
                        {
                            TGNPasswordController *s = weakSelf;
                            if (s != nil && fresh != nil)
                                s->_accountPassword = fresh;
                        }];
                    }
                    TGNShowAlert(@"Ошибка", error.localizedText);
                    return;
                }
                TGNHandleAuthorizationResult(innerSelf, result, nil, nil);
            }];
        });
    });
}

@end

#pragma mark - Sign up

@interface TGNSignUpController ()
{
    NSString *_phone;
    NSString *_phoneCodeHash;
    UITextField *_firstNameField;
    UITextField *_lastNameField;
}
@end

@implementation TGNSignUpController

- (instancetype)initWithPhone:(NSString *)phone phoneCodeHash:(NSString *)phoneCodeHash
{
    self = [super init];
    if (self != nil)
    {
        _phone = phone;
        _phoneCodeHash = phoneCodeHash;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Регистрация";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Готово" style:UIBarButtonItemStyleDone target:self action:@selector(next)];
    [self addFormView:TGNMakeLabel(@"Этот номер ещё не зарегистрирован. Укажите имя.", 15.0f, false) height:0.0f];
    _firstNameField = TGNMakeField(@"Имя", UIKeyboardTypeDefault);
    _firstNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    [self addFormView:_firstNameField height:44.0f];
    _lastNameField = TGNMakeField(@"Фамилия (необязательно)", UIKeyboardTypeDefault);
    _lastNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    [self addFormView:_lastNameField height:44.0f];
    [self addFormView:TGNMakeButton(@"Зарегистрироваться", self, @selector(next)) height:44.0f];
}

- (void)next
{
    if (self.busy || _phone == nil || _phoneCodeHash == nil)
        return;
    NSString *first = [_firstNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (first.length == 0)
        return;
    NSString *last = [_lastNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [self setBusy:true];
    __weak TGNSignUpController *weakSelf = self;
    [[TGNClient shared] invoke:@{@"_": @"auth.signUp", @"phone_number": _phone, @"phone_code_hash": _phoneCodeHash, @"first_name": first, @"last_name": last} completion:^(id result, TGNError *error)
    {
        TGNSignUpController *strongSelf = weakSelf;
        [strongSelf setBusy:false];
        if (error != nil)
        {
            TGNShowAlert(@"Ошибка", error.localizedText);
            return;
        }
        TGNHandleAuthorizationResult(strongSelf, result, nil, nil);
    }];
}

@end
