#import "TGNClient.h"

#import <UIKit/UIKit.h>

#import <MTProtoKit/MTContext.h>
#import <MTProtoKit/MTProto.h>
#import <MTProtoKit/MTApiEnvironment.h>
#import <MTProtoKit/MTFileBasedKeychain.h>
#import <MTProtoKit/MTDatacenterAddress.h>
#import <MTProtoKit/MTDatacenterAddressSet.h>
#import <MTProtoKit/MTRequestMessageService.h>
#import <MTProtoKit/MTRequest.h>
#import <MTProtoKit/MTRpcError.h>
#import <MTProtoKit/MTIncomingMessage.h>
#import <MTProtoKit/MTMessageService.h>
#import <MTProtoKit/MTLogging.h>

#import "TL.h"
#import "TGNSerialization.h"
#import "TGNStore.h"

NSString *const TGNUpdatesNotification = @"TGNUpdatesNotification";
NSString *const TGNLoggedOutNotification = @"TGNLoggedOutNotification";

#ifndef TG_API_ID
#define TG_API_ID 0
#endif
#ifndef TG_API_HASH
#define TG_API_HASH ""
#endif

static void TGNLoggingFunction(NSString *format, va_list args)
{
#ifdef DEBUG
    NSLogv(format, args);
#else
    (void)format;
    (void)args;
#endif
}

#pragma mark - Error

@implementation TGNError

- (instancetype)initWithCode:(int32_t)code text:(NSString *)text
{
    self = [super init];
    if (self != nil)
    {
        _code = code;
        _text = text ?: @"UNKNOWN";
    }
    return self;
}

- (bool)hasPrefix:(NSString *)prefix
{
    return [_text hasPrefix:prefix];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%d %@", _code, _text];
}

- (NSString *)localizedText
{
    NSDictionary *known = @{
        @"PHONE_NUMBER_INVALID": @"Неверный номер телефона.",
        @"PHONE_NUMBER_BANNED": @"Этот номер заблокирован в Telegram.",
        @"PHONE_NUMBER_FLOOD": @"Слишком много попыток. Попробуйте позже.",
        @"PHONE_CODE_INVALID": @"Неверный код.",
        @"PHONE_CODE_EMPTY": @"Введите код.",
        @"PHONE_CODE_EXPIRED": @"Код устарел. Запросите новый.",
        @"PASSWORD_HASH_INVALID": @"Неверный пароль.",
        @"FIRSTNAME_INVALID": @"Неверное имя.",
        @"API_ID_INVALID": @"Неверный api_id / api_hash. Проверьте настройки.",
        @"API_ID_PUBLISHED_FLOOD": @"Этот api_id заблокирован. Создайте свой на my.telegram.org.",
        @"UPDATE_APP_TO_LOGIN": @"Сервер считает клиент устаревшим (UPDATE_APP_TO_LOGIN).",
        @"PHONE_PASSWORD_FLOOD": @"Слишком много попыток. Попробуйте позже.",
        @"SESSION_PASSWORD_NEEDED": @"Нужен пароль двухэтапной аутентификации.",
        @"SRP_ID_INVALID": @"Сессия пароля устарела, попробуйте снова.",
        @"NETWORK": @"Нет соединения с сервером.",
    };
    NSString *text = known[_text];
    if (text != nil)
        return text;
    if ([_text hasPrefix:@"FLOOD_WAIT_"])
        return [NSString stringWithFormat:@"Слишком много запросов. Подождите %@ сек.", [_text substringFromIndex:11]];
    return [NSString stringWithFormat:@"Ошибка %d: %@", _code, _text];
}

@end

#pragma mark - Updates service

@interface TGNUpdatesService : NSObject <MTMessageService>
@end

@implementation TGNUpdatesService

- (void)mtProto:(MTProto *)__unused mtProto receivedMessage:(MTIncomingMessage *)message
{
    id body = message.body;
    NSString *name = TLName(body);
    if (name == nil)
        return;
    if ([name hasPrefix:@"update"])
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [[TGNStore shared] applyUpdates:body];
            [[NSNotificationCenter defaultCenter] postNotificationName:TGNUpdatesNotification object:nil userInfo:@{@"updates": body}];
        });
    }
}

@end

#pragma mark - Client

@interface TGNClient () <MTRequestMessageServiceDelegate>
{
    MTContext *_context;
    MTFileBasedKeychain *_keychain;
    MTProto *_mtProto;
    MTRequestMessageService *_requestService;
    TGNUpdatesService *_updatesService;
    bool _started;
}

@end

@implementation TGNClient

+ (TGNClient *)shared
{
    static TGNClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        instance = [[TGNClient alloc] init];
    });
    return instance;
}

+ (bool)hasApiCredentials
{
    return [self apiId] != 0 && [self apiHash].length != 0;
}

+ (void)setApiId:(int32_t)apiId apiHash:(NSString *)apiHash
{
    [[NSUserDefaults standardUserDefaults] setInteger:apiId forKey:@"nogram_api_id"];
    [[NSUserDefaults standardUserDefaults] setObject:apiHash forKey:@"nogram_api_hash"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (int32_t)apiId
{
    int32_t stored = (int32_t)[[NSUserDefaults standardUserDefaults] integerForKey:@"nogram_api_id"];
    return stored != 0 ? stored : (int32_t)TG_API_ID;
}

+ (NSString *)apiHash
{
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:@"nogram_api_hash"];
    return stored.length != 0 ? stored : @TG_API_HASH;
}

+ (NSString *)documentsPath
{
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}

- (int64_t)selfUserId
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:@"nogram_self_id"] longLongValue];
}

- (bool)isAuthorized
{
    return self.selfUserId != 0;
}

- (NSInteger)datacenterId
{
    NSNumber *dc = [_keychain objectForKey:@"defaultDatacenterId" group:@"persistent"];
    return dc != nil ? [dc integerValue] : 2;
}

- (void)start
{
    if (_started)
        return;
    _started = true;

    MTLogSetLoggingFunction(&TGNLoggingFunction);

    _keychain = [MTFileBasedKeychain unencryptedKeychainWithName:@"nogram" documentsPath:[TGNClient documentsPath]];

    MTApiEnvironment *apiEnvironment = [[MTApiEnvironment alloc] init];
    apiEnvironment.apiId = [TGNClient apiId];
    apiEnvironment.layer = @([TLSchema shared].layer);
    apiEnvironment.langPack = @"";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    apiEnvironment.appVersion = [NSString stringWithFormat:@"nogram %@", version ?: @"1.0"];
    NSArray *languages = [NSLocale preferredLanguages];
    NSString *language = languages.count != 0 ? languages[0] : @"en";
    if ([language rangeOfString:@"-"].location != NSNotFound)
        language = [language substringToIndex:[language rangeOfString:@"-"].location];
    apiEnvironment = [apiEnvironment withUpdatedLangPackCode:language];

    _context = [[MTContext alloc] initWithSerialization:[[TGNSerialization alloc] init] apiEnvironment:apiEnvironment isTestingEnvironment:false useTempAuthKeys:false];

    NSDictionary *seeds = @{
        @1: @"149.154.175.50",
        @2: @"149.154.167.51",
        @3: @"149.154.175.100",
        @4: @"149.154.167.91",
        @5: @"91.108.56.130",
    };
    [_context performBatchUpdates:^
    {
        for (NSNumber *dcId in seeds)
        {
            MTDatacenterAddress *address = [[MTDatacenterAddress alloc] initWithIp:seeds[dcId] port:443 preferForMedia:false restrictToTcp:false cdn:false preferForProxy:false secret:nil];
            [_context setSeedAddressSetForDatacenterWithId:[dcId integerValue] seedAddressSet:[[MTDatacenterAddressSet alloc] initWithAddressList:@[address]]];
        }
    }];
    _context.keychain = _keychain;

    [self moveToDatacenter:self.datacenterId];

    if (self.isAuthorized)
        [self subscribeToUpdates];
}

- (void)moveToDatacenter:(NSInteger)datacenterId
{
    if (_requestService != nil)
    {
        _requestService.delegate = nil;
        [_mtProto removeMessageService:_requestService];
        _requestService = nil;
    }
    if (_updatesService != nil)
    {
        [_mtProto removeMessageService:_updatesService];
        _updatesService = nil;
    }
    if (_mtProto != nil)
        [_mtProto stop];

    [_keychain setObject:@(datacenterId) forKey:@"defaultDatacenterId" group:@"persistent"];

    _mtProto = [[MTProto alloc] initWithContext:_context datacenterId:datacenterId usageCalculationInfo:nil];
    _mtProto.useTempAuthKeys = false;
    _mtProto.shouldStayConnected = true;

    _requestService = [[MTRequestMessageService alloc] initWithContext:_context];
    _requestService.delegate = self;
    [_mtProto addMessageService:_requestService];

    _updatesService = [[TGNUpdatesService alloc] init];
    [_mtProto addMessageService:_updatesService];

    [_context authInfoForDatacenterWithIdRequired:datacenterId isCdn:false];
}

- (void)invoke:(NSDictionary *)method completion:(TGNCompletion)completion
{
    [self invoke:method attempt:0 completion:completion];
}

- (void)invoke:(NSDictionary *)method attempt:(int)attempt completion:(TGNCompletion)completion
{
    NSError *serializeError = nil;
    NSData *payload = TLSerializeSafe(method, &serializeError);
    if (payload == nil)
    {
        if (completion)
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [[TGNError alloc] initWithCode:-1 text:serializeError.localizedDescription]); });
        return;
    }

    NSString *name = method[@"_"];
    NSString *returnType = TLReturnType(name);

    MTRequest *request = [[MTRequest alloc] init];
    [request setPayload:payload metadata:name shortMetadata:name responseParser:^id(NSData *data)
    {
        return TLParse(data, returnType, NULL);
    }];

    __weak TGNClient *weakSelf = self;
    [request setCompleted:^(id result, __unused NSTimeInterval timestamp, MTRpcError *rpcError)
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGNClient *strongSelf = weakSelf;
            if (rpcError != nil)
            {
                TGNError *error = [[TGNError alloc] initWithCode:rpcError.errorCode text:rpcError.errorDescription];
                if (error.code == 303 && attempt < 3)
                {
                    NSRange range = [error.text rangeOfString:@"_MIGRATE_"];
                    if (range.location != NSNotFound && ![error hasPrefix:@"FILE_"] && ![error hasPrefix:@"STATS_"])
                    {
                        NSInteger dc = [[error.text substringFromIndex:range.location + range.length] integerValue];
                        if (dc > 0)
                        {
                            [strongSelf moveToDatacenter:dc];
                            [strongSelf invoke:method attempt:attempt + 1 completion:completion];
                            return;
                        }
                    }
                }
                if (error.code == 401 && strongSelf.isAuthorized && ([error hasPrefix:@"AUTH_KEY_UNREGISTERED"] || [error hasPrefix:@"SESSION_REVOKED"] || [error hasPrefix:@"USER_DEACTIVATED"] || [error hasPrefix:@"AUTH_KEY_INVALID"]))
                {
                    [strongSelf resetLocalState];
                }
                if (completion)
                    completion(nil, error);
                return;
            }

            NSString *resultName = TLName(result);
            if ([resultName hasPrefix:@"update"])
            {
                [[TGNStore shared] applyUpdates:result];
                [[NSNotificationCenter defaultCenter] postNotificationName:TGNUpdatesNotification object:nil userInfo:@{@"updates": result}];
            }
            if (completion)
                completion(result, nil);
        });
    }];

    [_requestService addRequest:request];
}

- (void)completeAuthorizationWithResult:(NSDictionary *)authorization
{
    NSDictionary *user = TLDict(authorization, @"user");
    if (user == nil)
        return;
    [[TGNStore shared] addUsers:@[user] chats:nil];
    [[NSUserDefaults standardUserDefaults] setObject:@(TLLong(user, @"id")) forKey:@"nogram_self_id"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self subscribeToUpdates];
}

- (void)subscribeToUpdates
{
    // The server starts pushing updates to a session after it calls updates.getState.
    [self invoke:@{@"_": @"updates.getState"} completion:nil];
}

- (void)logout
{
    __weak TGNClient *weakSelf = self;
    [self invoke:@{@"_": @"auth.logOut"} completion:^(__unused id result, __unused TGNError *error)
    {
        [weakSelf resetLocalState];
    }];
    // Do not wait for the network: wipe after a short grace period anyway.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [weakSelf resetLocalState];
    });
}

- (void)resetLocalState
{
    if (!self.isAuthorized)
        return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"nogram_self_id"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[TGNStore shared] reset];

    for (NSNumber *dcId in [_context knownDatacenterIds])
        [_context updateAuthInfoForDatacenterWithId:[dcId integerValue] authInfo:nil];
    [_context removeAllAuthTokens];
    [self moveToDatacenter:2];

    [[NSNotificationCenter defaultCenter] postNotificationName:TGNLoggedOutNotification object:nil];
}

#pragma mark MTRequestMessageServiceDelegate

- (void)requestMessageServiceAuthorizationRequired:(MTRequestMessageService *)__unused requestMessageService
{
}

@end
