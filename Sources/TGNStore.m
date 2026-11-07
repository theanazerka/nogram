#import "TGNStore.h"

#import "TL.h"
#import "TGNClient.h"

NSString *TGNPeerKey(NSDictionary *peer)
{
    NSString *name = TLName(peer);
    if ([name isEqualToString:@"peerUser"])
        return [NSString stringWithFormat:@"u%lld", TLLong(peer, @"user_id")];
    if ([name isEqualToString:@"peerChat"])
        return [NSString stringWithFormat:@"c%lld", TLLong(peer, @"chat_id")];
    if ([name isEqualToString:@"peerChannel"])
        return [NSString stringWithFormat:@"h%lld", TLLong(peer, @"channel_id")];
    return nil;
}

NSString *TGNUserPeerKey(int64_t userId)
{
    return [NSString stringWithFormat:@"u%lld", userId];
}

static int64_t TGNPeerKeyId(NSString *peerKey)
{
    return peerKey.length > 1 ? [[peerKey substringFromIndex:1] longLongValue] : 0;
}

@implementation TGNMessage
@end

@interface TGNStore ()
{
    NSMutableDictionary *_users; // NSNumber(id) -> user
    NSMutableDictionary *_chats; // peer key -> chat/channel
}
@end

@implementation TGNStore

+ (TGNStore *)shared
{
    static TGNStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        instance = [[TGNStore alloc] init];
    });
    return instance;
}

+ (NSString *)storagePath
{
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [documents stringByAppendingPathComponent:@"nogram-peers.plist"];
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        _users = [[NSMutableDictionary alloc] init];
        _chats = [[NSMutableDictionary alloc] init];
        NSDictionary *saved = nil;
        @try
        {
            saved = [NSKeyedUnarchiver unarchiveObjectWithFile:[TGNStore storagePath]];
        }
        @catch (__unused NSException *e)
        {
        }
        if ([saved isKindOfClass:[NSDictionary class]])
        {
            [_users addEntriesFromDictionary:saved[@"users"]];
            [_chats addEntriesFromDictionary:saved[@"chats"]];
        }
    }
    return self;
}

- (void)save
{
    NSDictionary *root = @{@"users": [_users copy], @"chats": [_chats copy]};
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^
    {
        [NSKeyedArchiver archiveRootObject:root toFile:[TGNStore storagePath]];
    });
}

- (void)reset
{
    [_users removeAllObjects];
    [_chats removeAllObjects];
    [[NSFileManager defaultManager] removeItemAtPath:[TGNStore storagePath] error:nil];
}

#pragma mark Peers

- (void)addUsers:(NSArray *)users chats:(NSArray *)chats
{
    for (NSDictionary *user in users)
    {
        if (!TLIs(user, @"user"))
            continue;
        NSNumber *key = @(TLLong(user, @"id"));
        NSDictionary *existing = _users[key];
        // "min" users carry no usable access_hash: keep the full copy if we have it.
        if (TLBool(user, @"min") && existing != nil)
            continue;
        _users[key] = user;
    }
    for (NSDictionary *chat in chats)
    {
        NSString *name = TLName(chat);
        NSString *key = nil;
        if ([name isEqualToString:@"chat"] || [name isEqualToString:@"chatForbidden"] || [name isEqualToString:@"chatEmpty"])
            key = [NSString stringWithFormat:@"c%lld", TLLong(chat, @"id")];
        else if ([name isEqualToString:@"channel"] || [name isEqualToString:@"channelForbidden"])
            key = [NSString stringWithFormat:@"h%lld", TLLong(chat, @"id")];
        if (key == nil)
            continue;
        if (TLBool(chat, @"min") && _chats[key] != nil)
            continue;
        _chats[key] = chat;
    }
}

- (NSDictionary *)userWithId:(int64_t)userId
{
    return _users[@(userId)];
}

- (NSDictionary *)chatForPeerKey:(NSString *)peerKey
{
    return _chats[peerKey];
}

- (NSString *)nameForUserId:(int64_t)userId
{
    if (userId == [TGNClient shared].selfUserId && userId != 0)
    {
        NSDictionary *me = [self userWithId:userId];
        NSString *first = TLString(me, @"first_name");
        return first.length != 0 ? first : @"Вы";
    }
    NSDictionary *user = [self userWithId:userId];
    if (user == nil)
        return [NSString stringWithFormat:@"id%lld", userId];
    if (TLBool(user, @"deleted"))
        return @"Удалённый аккаунт";
    NSString *first = TLString(user, @"first_name") ?: @"";
    NSString *last = TLString(user, @"last_name") ?: @"";
    NSString *full = [[NSString stringWithFormat:@"%@ %@", first, last] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (full.length == 0)
        full = TLString(user, @"username") ?: TLString(user, @"phone") ?: @"Без имени";
    return full;
}

- (NSString *)titleForPeerKey:(NSString *)peerKey
{
    if ([peerKey hasPrefix:@"u"])
    {
        int64_t userId = TGNPeerKeyId(peerKey);
        if (userId == [TGNClient shared].selfUserId)
            return @"Избранное";
        return [self nameForUserId:userId];
    }
    NSString *title = TLString(_chats[peerKey], @"title");
    return title.length != 0 ? title : @"Чат";
}

- (NSString *)statusForPeerKey:(NSString *)peerKey
{
    if ([peerKey hasPrefix:@"u"])
    {
        NSDictionary *user = [self userWithId:TGNPeerKeyId(peerKey)];
        if (TLBool(user, @"bot"))
            return @"бот";
        NSDictionary *status = TLDict(user, @"status");
        NSString *name = TLName(status);
        if ([name isEqualToString:@"userStatusOnline"])
            return @"в сети";
        if ([name isEqualToString:@"userStatusOffline"])
        {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:TLInt(status, @"was_online")];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateStyle = NSDateFormatterShortStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
            return [NSString stringWithFormat:@"был(а) %@", [formatter stringFromDate:date]];
        }
        if ([name isEqualToString:@"userStatusRecently"])
            return @"был(а) недавно";
        if ([name isEqualToString:@"userStatusLastWeek"])
            return @"был(а) на этой неделе";
        if ([name isEqualToString:@"userStatusLastMonth"])
            return @"был(а) в этом месяце";
        return @"";
    }
    NSDictionary *chat = _chats[peerKey];
    int32_t count = TLInt(chat, @"participants_count");
    if ([self isBroadcastChannel:peerKey])
        return count > 0 ? [NSString stringWithFormat:@"канал, %d подписчиков", count] : @"канал";
    return count > 0 ? [NSString stringWithFormat:@"группа, %d участников", count] : @"группа";
}

- (bool)isBroadcastChannel:(NSString *)peerKey
{
    NSDictionary *chat = _chats[peerKey];
    return [peerKey hasPrefix:@"h"] && TLBool(chat, @"broadcast");
}

- (NSDictionary *)inputPeerForKey:(NSString *)peerKey
{
    int64_t peerId = TGNPeerKeyId(peerKey);
    if ([peerKey hasPrefix:@"u"])
    {
        if (peerId == [TGNClient shared].selfUserId)
            return @{@"_": @"inputPeerSelf"};
        NSDictionary *user = [self userWithId:peerId];
        if (user[@"access_hash"] == nil)
            return nil;
        return @{@"_": @"inputPeerUser", @"user_id": @(peerId), @"access_hash": user[@"access_hash"]};
    }
    if ([peerKey hasPrefix:@"c"])
        return @{@"_": @"inputPeerChat", @"chat_id": @(peerId)};
    if ([peerKey hasPrefix:@"h"])
    {
        NSDictionary *channel = _chats[peerKey];
        if (channel[@"access_hash"] == nil)
            return nil;
        return @{@"_": @"inputPeerChannel", @"channel_id": @(peerId), @"access_hash": channel[@"access_hash"]};
    }
    return nil;
}

- (NSDictionary *)inputChannelForKey:(NSString *)peerKey
{
    if (![peerKey hasPrefix:@"h"])
        return nil;
    NSDictionary *channel = _chats[peerKey];
    if (channel[@"access_hash"] == nil)
        return nil;
    return @{@"_": @"inputChannel", @"channel_id": @(TGNPeerKeyId(peerKey)), @"access_hash": channel[@"access_hash"]};
}

#pragma mark Updates

- (void)applyUpdates:(NSDictionary *)updates
{
    if (TLIs(updates, @"updates") || TLIs(updates, @"updatesCombined"))
        [self addUsers:TLArray(updates, @"users") chats:TLArray(updates, @"chats")];
}

- (NSArray *)messagesFromUpdates:(NSDictionary *)updates
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSString *name = TLName(updates);
    int64_t selfId = [TGNClient shared].selfUserId;

    if ([name isEqualToString:@"updateShortMessage"])
    {
        TGNMessage *message = [[TGNMessage alloc] init];
        message.mid = TLInt(updates, @"id");
        message.peerKey = TGNUserPeerKey(TLLong(updates, @"user_id"));
        message.outgoing = TLBool(updates, @"out");
        message.fromId = message.outgoing ? selfId : TLLong(updates, @"user_id");
        message.date = TLInt(updates, @"date");
        message.text = TLString(updates, @"message") ?: @"";
        [result addObject:message];
    }
    else if ([name isEqualToString:@"updateShortChatMessage"])
    {
        TGNMessage *message = [[TGNMessage alloc] init];
        message.mid = TLInt(updates, @"id");
        message.peerKey = [NSString stringWithFormat:@"c%lld", TLLong(updates, @"chat_id")];
        message.outgoing = TLBool(updates, @"out");
        message.fromId = TLLong(updates, @"from_id");
        message.date = TLInt(updates, @"date");
        message.text = TLString(updates, @"message") ?: @"";
        [result addObject:message];
    }
    else
    {
        NSArray *list = nil;
        if ([name isEqualToString:@"updateShort"])
            list = @[updates[@"update"] ?: [NSNull null]];
        else if ([name isEqualToString:@"updates"] || [name isEqualToString:@"updatesCombined"])
            list = TLArray(updates, @"updates");
        for (NSDictionary *update in list)
        {
            NSString *updateName = TLName(update);
            if ([updateName isEqualToString:@"updateNewMessage"] || [updateName isEqualToString:@"updateNewChannelMessage"] || [updateName isEqualToString:@"updateEditMessage"] || [updateName isEqualToString:@"updateEditChannelMessage"])
            {
                TGNMessage *message = [self messageFromTL:TLDict(update, @"message")];
                if (message != nil)
                    [result addObject:message];
            }
        }
    }
    return result;
}

#pragma mark Messages

static NSString *TGNDocumentDescription(NSDictionary *document)
{
    NSString *fileName = nil;
    for (NSDictionary *attribute in TLArray(document, @"attributes"))
    {
        NSString *name = TLName(attribute);
        if ([name isEqualToString:@"documentAttributeSticker"])
        {
            NSString *alt = TLString(attribute, @"alt");
            return alt.length != 0 ? [NSString stringWithFormat:@"[Стикер %@]", alt] : @"[Стикер]";
        }
        if ([name isEqualToString:@"documentAttributeAnimated"])
            return @"[GIF]";
        if ([name isEqualToString:@"documentAttributeAudio"])
        {
            if (TLBool(attribute, @"voice"))
                return [NSString stringWithFormat:@"[Голосовое, %d сек]", TLInt(attribute, @"duration")];
            NSString *title = TLString(attribute, @"title");
            NSString *performer = TLString(attribute, @"performer");
            if (title.length != 0)
                return [NSString stringWithFormat:@"[Музыка] %@%@", performer.length != 0 ? [performer stringByAppendingString:@" — "] : @"", title];
            return @"[Аудио]";
        }
        if ([name isEqualToString:@"documentAttributeVideo"])
            return TLBool(attribute, @"round_message") ? @"[Видеосообщение]" : @"[Видео]";
        if ([name isEqualToString:@"documentAttributeFilename"])
            fileName = TLString(attribute, @"file_name");
    }
    return fileName.length != 0 ? [NSString stringWithFormat:@"[Файл] %@", fileName] : @"[Файл]";
}

static NSString *TGNMediaDescription(NSDictionary *media)
{
    NSString *name = TLName(media);
    if (name == nil || [name isEqualToString:@"messageMediaEmpty"] || [name isEqualToString:@"messageMediaWebPage"])
        return nil;
    if ([name isEqualToString:@"messageMediaPhoto"])
        return @"[Фото]";
    if ([name isEqualToString:@"messageMediaDocument"])
        return TGNDocumentDescription(TLDict(media, @"document"));
    if ([name isEqualToString:@"messageMediaGeo"] || [name isEqualToString:@"messageMediaGeoLive"])
        return @"[Геопозиция]";
    if ([name isEqualToString:@"messageMediaVenue"])
        return [NSString stringWithFormat:@"[Место] %@", TLString(media, @"title") ?: @""];
    if ([name isEqualToString:@"messageMediaContact"])
        return [NSString stringWithFormat:@"[Контакт] %@ %@", TLString(media, @"first_name") ?: @"", TLString(media, @"phone_number") ?: @""];
    if ([name isEqualToString:@"messageMediaPoll"])
    {
        NSDictionary *question = TLDict(TLDict(media, @"poll"), @"question");
        return [NSString stringWithFormat:@"[Опрос] %@", TLString(question, @"text") ?: @""];
    }
    if ([name isEqualToString:@"messageMediaDice"])
        return [NSString stringWithFormat:@"%@ %d", TLString(media, @"emoticon") ?: @"🎲", TLInt(media, @"value")];
    if ([name isEqualToString:@"messageMediaGame"])
        return @"[Игра]";
    if ([name isEqualToString:@"messageMediaInvoice"])
        return @"[Счёт]";
    if ([name isEqualToString:@"messageMediaStory"])
        return @"[История]";
    if ([name isEqualToString:@"messageMediaGiveaway"] || [name isEqualToString:@"messageMediaGiveawayResults"])
        return @"[Розыгрыш]";
    if ([name isEqualToString:@"messageMediaPaidMedia"])
        return @"[Платный контент]";
    if ([name isEqualToString:@"messageMediaUnsupported"])
        return @"[Не поддерживается]";
    return @"[Медиа]";
}

- (NSString *)serviceDescription:(NSDictionary *)action fromId:(int64_t)fromId
{
    NSString *name = TLName(action);
    NSString *actor = fromId != 0 ? [self nameForUserId:fromId] : @"Канал";
    if ([name isEqualToString:@"messageActionChatCreate"] || [name isEqualToString:@"messageActionChannelCreate"])
        return [NSString stringWithFormat:@"%@ создал(а) «%@»", actor, TLString(action, @"title") ?: @""];
    if ([name isEqualToString:@"messageActionChatEditTitle"])
        return [NSString stringWithFormat:@"%@ сменил(а) название на «%@»", actor, TLString(action, @"title") ?: @""];
    if ([name isEqualToString:@"messageActionChatEditPhoto"])
        return [NSString stringWithFormat:@"%@ сменил(а) фото", actor];
    if ([name isEqualToString:@"messageActionChatDeletePhoto"])
        return [NSString stringWithFormat:@"%@ удалил(а) фото", actor];
    if ([name isEqualToString:@"messageActionChatAddUser"])
    {
        NSMutableArray *names = [[NSMutableArray alloc] init];
        for (NSNumber *userId in TLArray(action, @"users"))
            [names addObject:[self nameForUserId:[userId longLongValue]]];
        NSArray *added = TLArray(action, @"users");
        if (added.count == 1 && [added[0] longLongValue] == fromId)
            return [NSString stringWithFormat:@"%@ вступил(а) в группу", actor];
        return [NSString stringWithFormat:@"%@ добавил(а) %@", actor, [names componentsJoinedByString:@", "]];
    }
    if ([name isEqualToString:@"messageActionChatDeleteUser"])
    {
        int64_t userId = TLLong(action, @"user_id");
        if (userId == fromId)
            return [NSString stringWithFormat:@"%@ покинул(а) группу", actor];
        return [NSString stringWithFormat:@"%@ удалил(а) %@", actor, [self nameForUserId:userId]];
    }
    if ([name isEqualToString:@"messageActionChatJoinedByLink"] || [name isEqualToString:@"messageActionChatJoinedByRequest"])
        return [NSString stringWithFormat:@"%@ вступил(а) по ссылке", actor];
    if ([name isEqualToString:@"messageActionPinMessage"])
        return [NSString stringWithFormat:@"%@ закрепил(а) сообщение", actor];
    if ([name isEqualToString:@"messageActionPhoneCall"])
        return @"Звонок";
    if ([name isEqualToString:@"messageActionScreenshotTaken"])
        return [NSString stringWithFormat:@"%@ сделал(а) скриншот", actor];
    if ([name isEqualToString:@"messageActionContactSignUp"])
        return [NSString stringWithFormat:@"%@ теперь в Telegram", actor];
    if ([name isEqualToString:@"messageActionChatMigrateTo"] || [name isEqualToString:@"messageActionChannelMigrateFrom"])
        return @"Группа преобразована в супергруппу";
    if ([name isEqualToString:@"messageActionHistoryClear"])
        return @"История очищена";
    if ([name isEqualToString:@"messageActionGroupCall"])
        return @"Видеочат";
    return @"Служебное сообщение";
}

- (TGNMessage *)messageFromTL:(NSDictionary *)tl
{
    NSString *name = TLName(tl);
    if (![name isEqualToString:@"message"] && ![name isEqualToString:@"messageService"])
        return nil;

    TGNMessage *message = [[TGNMessage alloc] init];
    message.mid = TLInt(tl, @"id");
    message.peerKey = TGNPeerKey(TLDict(tl, @"peer_id"));
    message.outgoing = TLBool(tl, @"out");
    message.date = TLInt(tl, @"date");

    NSDictionary *from = TLDict(tl, @"from_id");
    if (TLIs(from, @"peerUser"))
        message.fromId = TLLong(from, @"user_id");
    else if (message.outgoing)
        message.fromId = [TGNClient shared].selfUserId;
    else if ([message.peerKey hasPrefix:@"u"])
        message.fromId = TGNPeerKeyId(message.peerKey);

    if ([name isEqualToString:@"messageService"])
    {
        message.isService = true;
        message.text = [self serviceDescription:TLDict(tl, @"action") fromId:message.fromId];
        return message;
    }

    NSString *text = TLString(tl, @"message") ?: @"";
    NSString *media = TGNMediaDescription(TLDict(tl, @"media"));
    if (media != nil)
        text = text.length != 0 ? [NSString stringWithFormat:@"%@\n%@", media, text] : media;
    message.text = text;
    return message;
}

@end
