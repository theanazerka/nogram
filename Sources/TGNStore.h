#import <Foundation/Foundation.h>

// Peer keys: @"u<id>" user, @"c<id>" basic group, @"h<id>" channel / supergroup.
NSString *TGNPeerKey(NSDictionary *peer);
NSString *TGNUserPeerKey(int64_t userId);

@interface TGNMessage : NSObject
@property (nonatomic) int32_t mid;
@property (nonatomic, strong) NSString *peerKey;
@property (nonatomic) int64_t fromId;       // 0 for channel posts
@property (nonatomic) bool outgoing;
@property (nonatomic) int32_t date;
@property (nonatomic, strong) NSString *text;
@property (nonatomic) bool isService;
@end

@interface TGNStore : NSObject

+ (TGNStore *)shared;

- (void)addUsers:(NSArray *)users chats:(NSArray *)chats;
- (NSDictionary *)userWithId:(int64_t)userId;
- (NSDictionary *)chatForPeerKey:(NSString *)peerKey;

- (NSString *)titleForPeerKey:(NSString *)peerKey;
- (NSString *)nameForUserId:(int64_t)userId;
- (NSString *)statusForPeerKey:(NSString *)peerKey;
- (bool)isBroadcastChannel:(NSString *)peerKey;
- (NSDictionary *)inputPeerForKey:(NSString *)peerKey;   // nil if no access hash known
- (NSDictionary *)inputChannelForKey:(NSString *)peerKey;

// Extracts users/chats from any Updates object.
- (void)applyUpdates:(NSDictionary *)updates;
// Extracts new/edited messages from any Updates object.
- (NSArray *)messagesFromUpdates:(NSDictionary *)updates;

- (TGNMessage *)messageFromTL:(NSDictionary *)message;

- (void)save;
- (void)reset;

@end
