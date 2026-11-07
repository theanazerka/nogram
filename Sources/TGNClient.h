#import <Foundation/Foundation.h>

// Posted on the main thread for every Updates object pushed by the server
// and for Updates returned from methods (sendMessage etc). userInfo[@"updates"].
extern NSString *const TGNUpdatesNotification;
// Posted on the main thread when the session was revoked (AUTH_KEY_UNREGISTERED etc).
extern NSString *const TGNLoggedOutNotification;

@interface TGNError : NSObject
@property (nonatomic, readonly) int32_t code;
@property (nonatomic, strong, readonly) NSString *text;
- (instancetype)initWithCode:(int32_t)code text:(NSString *)text;
- (bool)hasPrefix:(NSString *)prefix;
// Human readable message in Russian for common auth errors.
- (NSString *)localizedText;
@end

typedef void (^TGNCompletion)(id result, TGNError *error);

@interface TGNClient : NSObject

+ (TGNClient *)shared;

// api_id / api_hash: compiled in (TG_API_ID / TG_API_HASH) or entered by the user.
+ (bool)hasApiCredentials;
+ (void)setApiId:(int32_t)apiId apiHash:(NSString *)apiHash;
+ (int32_t)apiId;
+ (NSString *)apiHash;

@property (nonatomic, readonly) bool isAuthorized;
@property (nonatomic, readonly) int64_t selfUserId;
@property (nonatomic, readonly) NSInteger datacenterId;

- (void)start;

// Sends a TL method (dictionary with @"_" = method name). Completion runs on the main thread.
// *_MIGRATE_X errors are handled transparently.
- (void)invoke:(NSDictionary *)method completion:(TGNCompletion)completion;

// Called after auth.signIn / auth.signUp / auth.checkPassword succeeded.
- (void)completeAuthorizationWithResult:(NSDictionary *)authorization;
// Logs out on the server (best effort) and wipes local state.
- (void)logout;

@end
