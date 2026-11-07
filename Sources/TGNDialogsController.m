#import "TGNDialogsController.h"

#import <QuartzCore/QuartzCore.h>

#import "TL.h"
#import "TGNClient.h"
#import "TGNStore.h"
#import "TGNUI.h"
#import "TGNChatController.h"

@interface TGNDialog : NSObject
@property (nonatomic, strong) NSString *peerKey;
@property (nonatomic, strong) TGNMessage *topMessage;
@property (nonatomic) int32_t unreadCount;
@property (nonatomic) bool pinned;
@end

@implementation TGNDialog
@end

@interface TGNDialogCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation TGNDialogCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self != nil)
    {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

        _previewLabel = [[UILabel alloc] init];
        _previewLabel.font = [UIFont systemFontOfSize:14.0f];
        _previewLabel.textColor = TGNColor(0x8E8E93);
        _previewLabel.numberOfLines = 2;
        _previewLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_previewLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [UIFont systemFontOfSize:13.0f];
        _dateLabel.textColor = TGNColor(0x8E8E93);
        _dateLabel.textAlignment = NSTextAlignmentRight;
        _dateLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_dateLabel];

        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.font = [UIFont boldSystemFontOfSize:13.0f];
        _badgeLabel.textColor = [UIColor whiteColor];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.backgroundColor = TGNColor(0x2481CC);
        _badgeLabel.layer.cornerRadius = 10.0f;
        _badgeLabel.clipsToBounds = YES;
        [self.contentView addSubview:_badgeLabel];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat dateWidth = 70.0f;
    _titleLabel.frame = CGRectMake(12.0f, 8.0f, width - 24.0f - dateWidth, 20.0f);
    _dateLabel.frame = CGRectMake(width - 10.0f - dateWidth, 9.0f, dateWidth, 18.0f);

    CGFloat badgeWidth = 0.0f;
    if (!_badgeLabel.hidden)
    {
        CGSize size = [_badgeLabel.text sizeWithFont:_badgeLabel.font];
        badgeWidth = MAX(20.0f, size.width + 12.0f);
        _badgeLabel.frame = CGRectMake(width - 10.0f - badgeWidth, 36.0f, badgeWidth, 20.0f);
    }
    _previewLabel.frame = CGRectMake(12.0f, 29.0f, width - 24.0f - (badgeWidth > 0.0f ? badgeWidth + 8.0f : 0.0f), 36.0f);
}

@end

@interface TGNDialogsController () <UIActionSheetDelegate>
{
    NSMutableArray *_dialogs;
    bool _loading;
    bool _reachedEnd;
    bool _reloadScheduled;
    __weak TGNChatController *_openChat;
}
@end

@implementation TGNDialogsController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self != nil)
    {
        _dialogs = [[NSMutableArray alloc] init];
        self.title = @"Чаты";
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = 72.0f;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Выход" style:UIBarButtonItemStyleBordered target:self action:@selector(logoutPressed)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatesReceived:) name:TGNUpdatesNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused notification
{
    [self reload];
}

#pragma mark Loading

- (void)reload
{
    _reachedEnd = false;
    [self loadDialogsAppending:false];
}

- (void)loadDialogsAppending:(bool)appending
{
    if (_loading)
        return;
    _loading = true;

    NSMutableDictionary *request = [@{
        @"_": @"messages.getDialogs",
        @"offset_date": @0,
        @"offset_id": @0,
        @"offset_peer": @{@"_": @"inputPeerEmpty"},
        @"limit": @50,
        @"hash": @0,
    } mutableCopy];

    if (appending)
    {
        TGNDialog *last = nil;
        for (TGNDialog *dialog in [_dialogs reverseObjectEnumerator])
        {
            if (!dialog.pinned && dialog.topMessage != nil)
            {
                last = dialog;
                break;
            }
        }
        NSDictionary *inputPeer = last != nil ? [[TGNStore shared] inputPeerForKey:last.peerKey] : nil;
        if (inputPeer == nil)
        {
            _loading = false;
            _reachedEnd = true;
            return;
        }
        request[@"offset_date"] = @(last.topMessage.date);
        request[@"offset_id"] = @(last.topMessage.mid);
        request[@"offset_peer"] = inputPeer;
        request[@"exclude_pinned"] = @YES;
    }

    __weak TGNDialogsController *weakSelf = self;
    [[TGNClient shared] invoke:request completion:^(id result, TGNError *error)
    {
        TGNDialogsController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        strongSelf->_loading = false;
        [strongSelf.refreshControl endRefreshing];
        if (error != nil)
        {
            if (!appending)
                TGNShowAlert(@"Не удалось загрузить чаты", error.localizedText);
            return;
        }
        [strongSelf applyDialogsResult:result appending:appending];
    }];
}

- (void)applyDialogsResult:(NSDictionary *)result appending:(bool)appending
{
    TGNStore *store = [TGNStore shared];
    [store addUsers:TLArray(result, @"users") chats:TLArray(result, @"chats")];

    NSMutableDictionary *messages = [[NSMutableDictionary alloc] init];
    for (NSDictionary *tl in TLArray(result, @"messages"))
    {
        TGNMessage *message = [store messageFromTL:tl];
        if (message.peerKey != nil)
            messages[[NSString stringWithFormat:@"%@:%d", message.peerKey, message.mid]] = message;
    }

    NSMutableArray *loaded = [[NSMutableArray alloc] init];
    for (NSDictionary *tl in TLArray(result, @"dialogs"))
    {
        if (!TLIs(tl, @"dialog"))
            continue;
        TGNDialog *dialog = [[TGNDialog alloc] init];
        dialog.peerKey = TGNPeerKey(TLDict(tl, @"peer"));
        if (dialog.peerKey == nil)
            continue;
        dialog.unreadCount = TLInt(tl, @"unread_count");
        dialog.pinned = TLBool(tl, @"pinned");
        dialog.topMessage = messages[[NSString stringWithFormat:@"%@:%d", dialog.peerKey, TLInt(tl, @"top_message")]];
        [loaded addObject:dialog];
    }

    if (!appending)
        [_dialogs removeAllObjects];
    NSMutableSet *known = [[NSMutableSet alloc] init];
    for (TGNDialog *dialog in _dialogs)
        [known addObject:dialog.peerKey];
    for (TGNDialog *dialog in loaded)
    {
        if (![known containsObject:dialog.peerKey])
            [_dialogs addObject:dialog];
    }

    if (loaded.count == 0 || TLIs(result, @"messages.dialogs"))
        _reachedEnd = true;

    [self.tableView reloadData];
    [store save];
}

- (void)scheduleReload
{
    if (_reloadScheduled)
        return;
    _reloadScheduled = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        _reloadScheduled = false;
        [self reload];
    });
}

- (void)updatesReceived:(NSNotification *)notification
{
    NSDictionary *updates = notification.userInfo[@"updates"];
    if (TLIs(updates, @"updatesTooLong"))
    {
        [self scheduleReload];
        return;
    }
    NSArray *messages = [[TGNStore shared] messagesFromUpdates:updates];
    bool changed = false;
    for (TGNMessage *message in messages)
    {
        if (message.peerKey == nil)
            continue;
        NSUInteger index = [_dialogs indexOfObjectPassingTest:^BOOL(TGNDialog *dialog, __unused NSUInteger idx, __unused BOOL *stop)
        {
            return [dialog.peerKey isEqualToString:message.peerKey];
        }];
        TGNDialog *dialog = nil;
        if (index == NSNotFound)
        {
            dialog = [[TGNDialog alloc] init];
            dialog.peerKey = message.peerKey;
        }
        else
        {
            dialog = _dialogs[index];
            [_dialogs removeObjectAtIndex:index];
        }
        if (dialog.topMessage == nil || message.mid >= dialog.topMessage.mid)
        {
            bool isNew = dialog.topMessage == nil || message.mid > dialog.topMessage.mid;
            dialog.topMessage = message;
            bool chatOpen = _openChat != nil && [_openChat.peerKey isEqualToString:message.peerKey];
            if (isNew && !message.outgoing && !chatOpen)
                dialog.unreadCount += 1;
        }
        // Keep pinned dialogs on top: insert after the last pinned one.
        NSUInteger insertAt = 0;
        if (!dialog.pinned)
        {
            while (insertAt < _dialogs.count && ((TGNDialog *)_dialogs[insertAt]).pinned)
                insertAt++;
        }
        [_dialogs insertObject:dialog atIndex:insertAt];
        changed = true;
    }
    if (changed)
        [self.tableView reloadData];
}

#pragma mark Logout

- (void)logoutPressed
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Выйти из аккаунта?" delegate:self cancelButtonTitle:@"Отмена" destructiveButtonTitle:@"Выйти" otherButtonTitles:nil];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.destructiveButtonIndex)
        [[TGNClient shared] logout];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)__unused tableView numberOfRowsInSection:(NSInteger)__unused section
{
    return (NSInteger)_dialogs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TGNDialogCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dialog"];
    if (cell == nil)
        cell = [[TGNDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dialog"];

    TGNDialog *dialog = _dialogs[(NSUInteger)indexPath.row];
    TGNStore *store = [TGNStore shared];
    NSString *title = [store titleForPeerKey:dialog.peerKey];
    cell.titleLabel.text = dialog.pinned ? [@"📌 " stringByAppendingString:title] : title;

    TGNMessage *top = dialog.topMessage;
    NSString *preview = top.text ?: @"";
    if (top != nil && !top.isService && ![dialog.peerKey hasPrefix:@"u"] && ![store isBroadcastChannel:dialog.peerKey])
    {
        NSString *author = top.outgoing ? @"Вы" : [store nameForUserId:top.fromId];
        preview = [NSString stringWithFormat:@"%@: %@", author, preview];
    }
    else if (top.outgoing && !top.isService)
        preview = [@"Вы: " stringByAppendingString:preview];
    cell.previewLabel.text = [preview stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    cell.dateLabel.text = top != nil ? TGNFormatDate(top.date, true) : @"";
    cell.badgeLabel.hidden = dialog.unreadCount <= 0;
    cell.badgeLabel.text = dialog.unreadCount > 999 ? @"999+" : [NSString stringWithFormat:@"%d", dialog.unreadCount];
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)__unused cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_reachedEnd && !_loading && indexPath.row >= (NSInteger)_dialogs.count - 5)
        [self loadDialogsAppending:true];
    (void)tableView;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TGNDialog *dialog = _dialogs[(NSUInteger)indexPath.row];
    if ([[TGNStore shared] inputPeerForKey:dialog.peerKey] == nil)
    {
        TGNShowAlert(@"Чат недоступен", @"Нет данных для доступа к этому чату. Обновите список.");
        return;
    }
    dialog.unreadCount = 0;
    TGNChatController *chat = [[TGNChatController alloc] initWithPeerKey:dialog.peerKey];
    _openChat = chat;
    [self.navigationController pushViewController:chat animated:YES];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
{
    return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

@end
