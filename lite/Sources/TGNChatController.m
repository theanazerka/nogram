#import "TGNChatController.h"

#import <QuartzCore/QuartzCore.h>

#import "TL.h"
#import "TGNClient.h"
#import "TGNStore.h"
#import "TGNUI.h"

static const CGFloat TGNBubbleFontSize = 16.0f;
static const CGFloat TGNInputHeight = 44.0f;

static UIFont *TGNBubbleFont(void)
{
    static UIFont *font = nil;
    if (font == nil)
        font = [UIFont systemFontOfSize:TGNBubbleFontSize];
    return font;
}

static UIColor *TGNAuthorColor(int64_t userId)
{
    static uint32_t colors[] = { 0xCE4A4A, 0x3E9E3E, 0x2E7BBF, 0xA65FBF, 0xD07A1F, 0x2A9E9E, 0xC24B85 };
    return TGNColor(colors[(uint64_t)userId % 7]);
}

@interface TGNMessageCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *textBodyLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@end

@implementation TGNMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self != nil)
    {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _bubble = [[UIView alloc] init];
        _bubble.layer.cornerRadius = 10.0f;
        _bubble.layer.borderWidth = 0.5f;
        [self.contentView addSubview:_bubble];

        _authorLabel = [[UILabel alloc] init];
        _authorLabel.font = [UIFont boldSystemFontOfSize:13.0f];
        _authorLabel.backgroundColor = [UIColor clearColor];
        [_bubble addSubview:_authorLabel];

        _textBodyLabel = [[UILabel alloc] init];
        _textBodyLabel.font = TGNBubbleFont();
        _textBodyLabel.numberOfLines = 0;
        _textBodyLabel.backgroundColor = [UIColor clearColor];
        [_bubble addSubview:_textBodyLabel];

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11.0f];
        _timeLabel.textColor = TGNColor(0x7D8A99);
        _timeLabel.backgroundColor = [UIColor clearColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_bubble addSubview:_timeLabel];
    }
    return self;
}

@end

@interface TGNChatController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
{
    UITableView *_tableView;
    UIView *_inputBar;
    UITextField *_inputField;
    UIButton *_sendButton;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;

    NSMutableArray *_messages;  // TGNMessage, ascending by mid
    NSMutableSet *_messageIds;
    NSMutableDictionary *_heights;
    bool _loading;
    bool _reachedStart;
    CGFloat _keyboardHeight;
}
@end

@implementation TGNChatController

- (instancetype)initWithPeerKey:(NSString *)peerKey
{
    self = [super init];
    if (self != nil)
    {
        _peerKey = peerKey;
        _messages = [[NSMutableArray alloc] init];
        _messageIds = [[NSMutableSet alloc] init];
        _heights = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (bool)showsAuthors
{
    return ![_peerKey hasPrefix:@"u"] && ![[TGNStore shared] isBroadcastChannel:_peerKey];
}

- (bool)canWrite
{
    if ([[TGNStore shared] isBroadcastChannel:_peerKey])
    {
        NSDictionary *channel = [[TGNStore shared] chatForPeerKey:_peerKey];
        return TLBool(channel, @"creator") || TLDict(channel, @"admin_rights") != nil;
    }
    return true;
}

- (void)loadView
{
    [super loadView];
    self.view.backgroundColor = TGNColor(0xDCE5EE);

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.backgroundView = nil;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];

    _inputBar = [[UIView alloc] init];
    _inputBar.backgroundColor = TGNColor(0xF4F4F4);
    _inputBar.layer.borderColor = TGNColor(0xC8C8CC).CGColor;
    _inputBar.layer.borderWidth = 0.5f;
    [self.view addSubview:_inputBar];

    _inputField = [[UITextField alloc] init];
    _inputField.borderStyle = UITextBorderStyleRoundedRect;
    _inputField.placeholder = @"Сообщение";
    _inputField.font = [UIFont systemFontOfSize:16.0f];
    _inputField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.delegate = self;
    [_inputBar addSubview:_inputField];

    _sendButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_sendButton setTitle:@"Отпр." forState:UIControlStateNormal];
    _sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
    [_sendButton addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventTouchUpInside];
    [_inputBar addSubview:_sendButton];

    _inputBar.hidden = ![self canWrite];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 200.0f, 40.0f)];
    titleView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 2.0f, 200.0f, 20.0f)];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
    _titleLabel.shadowOffset = CGSizeMake(0.0f, -1.0f);
    [titleView addSubview:_titleLabel];
    _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 22.0f, 200.0f, 16.0f)];
    _subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _subtitleLabel.font = [UIFont systemFontOfSize:12.0f];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.backgroundColor = [UIColor clearColor];
    _subtitleLabel.textColor = [UIColor colorWithWhite:0.92f alpha:1.0f];
    [titleView addSubview:_subtitleLabel];
    self.navigationItem.titleView = titleView;
    [self updateTitle];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatesReceived:) name:TGNUpdatesNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];

    [self loadHistoryOlder:false];
}

- (void)updateTitle
{
    _titleLabel.text = [[TGNStore shared] titleForPeerKey:_peerKey];
    _subtitleLabel.text = [[TGNStore shared] statusForPeerKey:_peerKey];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat inputHeight = _inputBar.hidden ? 0.0f : TGNInputHeight;
    _inputBar.frame = CGRectMake(-1.0f, size.height - _keyboardHeight - inputHeight, size.width + 2.0f, inputHeight + 1.0f);
    _inputField.frame = CGRectMake(7.0f, 6.0f, size.width - 7.0f - 72.0f, 32.0f);
    _sendButton.frame = CGRectMake(size.width - 62.0f, 6.0f, 58.0f, 32.0f);
    CGRect tableFrame = CGRectMake(0.0f, 0.0f, size.width, size.height - _keyboardHeight - inputHeight);
    if (!CGRectEqualToRect(_tableView.frame, tableFrame))
    {
        _tableView.frame = tableFrame;
        [_heights removeAllObjects];
        [_tableView reloadData];
    }
}

- (void)keyboardWillChange:(NSNotification *)notification
{
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:frame fromView:nil];
    CGFloat height = [notification.name isEqualToString:UIKeyboardWillHideNotification] ? 0.0f : MAX(0.0f, self.view.bounds.size.height - frame.origin.y);
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _keyboardHeight = height;
    [UIView animateWithDuration:duration animations:^
    {
        [self viewWillLayoutSubviews];
    } completion:^(__unused BOOL finished)
    {
        [self scrollToBottomAnimated:true];
    }];
}

#pragma mark Data

- (void)loadHistoryOlder:(bool)older
{
    if (_loading || (older && _reachedStart))
        return;
    NSDictionary *inputPeer = [[TGNStore shared] inputPeerForKey:_peerKey];
    if (inputPeer == nil)
        return;
    _loading = true;

    int32_t offsetId = 0;
    if (older && _messages.count != 0)
        offsetId = ((TGNMessage *)_messages[0]).mid;

    NSDictionary *request = @{
        @"_": @"messages.getHistory",
        @"peer": inputPeer,
        @"offset_id": @(offsetId),
        @"offset_date": @0,
        @"add_offset": @0,
        @"limit": @40,
        @"max_id": @0,
        @"min_id": @0,
        @"hash": @0,
    };
    __weak TGNChatController *weakSelf = self;
    [[TGNClient shared] invoke:request completion:^(id result, TGNError *error)
    {
        TGNChatController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        strongSelf->_loading = false;
        if (error != nil)
        {
            TGNShowAlert(@"Не удалось загрузить историю", error.localizedText);
            return;
        }
        [strongSelf applyHistory:result older:older];
    }];
}

- (void)applyHistory:(NSDictionary *)result older:(bool)older
{
    TGNStore *store = [TGNStore shared];
    [store addUsers:TLArray(result, @"users") chats:TLArray(result, @"chats")];

    NSArray *list = TLArray(result, @"messages");
    if (list.count == 0)
        _reachedStart = true;

    CGFloat oldContentHeight = _tableView.contentSize.height;
    CGFloat oldOffset = _tableView.contentOffset.y;

    for (NSDictionary *tl in list)
    {
        TGNMessage *message = [store messageFromTL:tl];
        if (message != nil)
            [self insertMessage:message];
    }
    [self updateTitle];
    [_tableView reloadData];

    if (older)
    {
        [_tableView layoutIfNeeded];
        CGFloat delta = _tableView.contentSize.height - oldContentHeight;
        _tableView.contentOffset = CGPointMake(0.0f, oldOffset + delta);
    }
    else
    {
        [self scrollToBottomAnimated:false];
        [self markRead];
    }
}

// Returns true if the message was new.
- (bool)insertMessage:(TGNMessage *)message
{
    NSNumber *key = @(message.mid);
    if ([_messageIds containsObject:key])
    {
        NSUInteger index = [_messages indexOfObjectPassingTest:^BOOL(TGNMessage *m, __unused NSUInteger idx, __unused BOOL *stop)
        {
            return m.mid == message.mid;
        }];
        if (index != NSNotFound)
        {
            _messages[index] = message; // edit
            [_heights removeObjectForKey:key];
        }
        return false;
    }
    [_messageIds addObject:key];
    NSUInteger index = _messages.count;
    while (index > 0 && ((TGNMessage *)_messages[index - 1]).mid > message.mid)
        index--;
    [_messages insertObject:message atIndex:index];
    return true;
}

- (void)updatesReceived:(NSNotification *)notification
{
    NSArray *messages = [[TGNStore shared] messagesFromUpdates:notification.userInfo[@"updates"]];
    bool changed = false;
    bool incoming = false;
    for (TGNMessage *message in messages)
    {
        if (![message.peerKey isEqualToString:_peerKey])
            continue;
        if ([self insertMessage:message] && !message.outgoing)
            incoming = true;
        changed = true;
    }
    if (changed)
    {
        bool atBottom = _tableView.contentOffset.y + _tableView.bounds.size.height >= _tableView.contentSize.height - 80.0f;
        [_tableView reloadData];
        if (atBottom)
            [self scrollToBottomAnimated:true];
        if (incoming)
            [self markRead];
    }
}

- (void)markRead
{
    if (_messages.count == 0)
        return;
    int32_t maxId = ((TGNMessage *)[_messages lastObject]).mid;
    NSDictionary *request = nil;
    if ([_peerKey hasPrefix:@"h"])
    {
        NSDictionary *channel = [[TGNStore shared] inputChannelForKey:_peerKey];
        if (channel != nil)
            request = @{@"_": @"channels.readHistory", @"channel": channel, @"max_id": @(maxId)};
    }
    else
    {
        NSDictionary *peer = [[TGNStore shared] inputPeerForKey:_peerKey];
        if (peer != nil)
            request = @{@"_": @"messages.readHistory", @"peer": peer, @"max_id": @(maxId)};
    }
    if (request != nil)
        [[TGNClient shared] invoke:request completion:nil];
}

- (void)scrollToBottomAnimated:(bool)animated
{
    if (_messages.count == 0)
        return;
    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)_messages.count - 1 inSection:0];
    [_tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark Sending

- (BOOL)textFieldShouldReturn:(UITextField *)__unused textField
{
    [self sendPressed];
    return NO;
}

- (void)sendPressed
{
    NSString *text = [_inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0)
        return;
    NSDictionary *inputPeer = [[TGNStore shared] inputPeerForKey:_peerKey];
    if (inputPeer == nil)
        return;
    _inputField.text = @"";

    int64_t randomId = 0;
    arc4random_buf(&randomId, sizeof(randomId));
    NSDictionary *request = @{@"_": @"messages.sendMessage", @"peer": inputPeer, @"message": text, @"random_id": @(randomId)};

    __weak TGNChatController *weakSelf = self;
    [[TGNClient shared] invoke:request completion:^(id result, TGNError *error)
    {
        TGNChatController *strongSelf = weakSelf;
        if (error != nil)
        {
            TGNShowAlert(@"Сообщение не отправлено", error.localizedText);
            if (strongSelf != nil && strongSelf->_inputField.text.length == 0)
                strongSelf->_inputField.text = text;
            return;
        }
        if (strongSelf == nil)
            return;
        if (TLIs(result, @"updateShortSentMessage"))
        {
            TGNMessage *message = [[TGNMessage alloc] init];
            message.mid = TLInt(result, @"id");
            message.peerKey = strongSelf->_peerKey;
            message.outgoing = true;
            message.fromId = [TGNClient shared].selfUserId;
            message.date = TLInt(result, @"date");
            message.text = text;
            [strongSelf insertMessage:message];
            [strongSelf->_tableView reloadData];
            [strongSelf scrollToBottomAnimated:true];
        }
        // Other Updates shapes are delivered through TGNUpdatesNotification.
    }];
}

#pragma mark Table

- (CGSize)bubbleTextSizeFor:(TGNMessage *)message
{
    CGFloat maxWidth = (CGFloat)floor(_tableView.bounds.size.width * 0.75f) - 20.0f;
    if (message.isService)
        maxWidth = _tableView.bounds.size.width - 60.0f;
    CGSize size = [message.text sizeWithFont:(message.isService ? [UIFont systemFontOfSize:13.0f] : TGNBubbleFont()) constrainedToSize:CGSizeMake(maxWidth, 10000.0f) lineBreakMode:NSLineBreakByWordWrapping];
    return CGSizeMake((CGFloat)ceil(size.width), (CGFloat)ceil(size.height));
}

- (bool)showsAuthorFor:(TGNMessage *)message
{
    return [self showsAuthors] && !message.outgoing && !message.isService;
}

- (NSInteger)tableView:(UITableView *)__unused tableView numberOfRowsInSection:(NSInteger)__unused section
{
    return (NSInteger)_messages.count;
}

- (CGFloat)tableView:(UITableView *)__unused tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TGNMessage *message = _messages[(NSUInteger)indexPath.row];
    NSNumber *cached = _heights[@(message.mid)];
    if (cached != nil)
        return [cached floatValue];
    CGSize size = [self bubbleTextSizeFor:message];
    CGFloat height = size.height + (message.isService ? 16.0f : 34.0f);
    if ([self showsAuthorFor:message])
        height += 17.0f;
    _heights[@(message.mid)] = @(height);
    return height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TGNMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message"];
    if (cell == nil)
        cell = [[TGNMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"message"];

    TGNMessage *message = _messages[(NSUInteger)indexPath.row];
    CGSize textSize = [self bubbleTextSizeFor:message];
    CGFloat width = tableView.bounds.size.width;

    if (message.isService)
    {
        cell.authorLabel.hidden = YES;
        cell.timeLabel.hidden = YES;
        cell.textBodyLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.textBodyLabel.textColor = [UIColor whiteColor];
        cell.textBodyLabel.textAlignment = NSTextAlignmentCenter;
        cell.textBodyLabel.text = message.text;
        cell.bubble.backgroundColor = [UIColor colorWithRed:0.35f green:0.45f blue:0.55f alpha:0.6f];
        cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
        CGFloat bubbleWidth = textSize.width + 20.0f;
        cell.bubble.frame = CGRectMake((CGFloat)floor((width - bubbleWidth) / 2.0f), 4.0f, bubbleWidth, textSize.height + 8.0f);
        cell.textBodyLabel.frame = CGRectMake(10.0f, 4.0f, textSize.width, textSize.height);
        return cell;
    }

    bool showAuthor = [self showsAuthorFor:message];
    cell.authorLabel.hidden = !showAuthor;
    cell.timeLabel.hidden = NO;
    cell.textBodyLabel.font = TGNBubbleFont();
    cell.textBodyLabel.textColor = [UIColor blackColor];
    cell.textBodyLabel.textAlignment = NSTextAlignmentLeft;
    cell.textBodyLabel.text = message.text;
    cell.timeLabel.text = TGNFormatDate(message.date, false);

    CGFloat authorHeight = 0.0f;
    CGFloat contentWidth = textSize.width;
    if (showAuthor)
    {
        cell.authorLabel.text = [[TGNStore shared] nameForUserId:message.fromId];
        cell.authorLabel.textColor = TGNAuthorColor(message.fromId);
        CGSize authorSize = [cell.authorLabel.text sizeWithFont:cell.authorLabel.font];
        contentWidth = MAX(contentWidth, MIN(authorSize.width, width * 0.75f - 20.0f));
        authorHeight = 17.0f;
    }
    CGSize timeSize = [cell.timeLabel.text sizeWithFont:cell.timeLabel.font];
    contentWidth = MAX(contentWidth, timeSize.width);

    CGFloat bubbleWidth = contentWidth + 20.0f;
    CGFloat bubbleHeight = authorHeight + textSize.height + 26.0f;
    CGFloat x = message.outgoing ? width - bubbleWidth - 8.0f : 8.0f;
    cell.bubble.frame = CGRectMake(x, 4.0f, bubbleWidth, bubbleHeight);
    cell.bubble.backgroundColor = message.outgoing ? TGNColor(0xE1FFC7) : [UIColor whiteColor];
    cell.bubble.layer.borderColor = (message.outgoing ? TGNColor(0xA8D38A) : TGNColor(0xC3CDD6)).CGColor;
    cell.authorLabel.frame = CGRectMake(10.0f, 5.0f, contentWidth, 16.0f);
    cell.textBodyLabel.frame = CGRectMake(10.0f, 5.0f + authorHeight, textSize.width, textSize.height);
    cell.timeLabel.frame = CGRectMake(10.0f, bubbleHeight - 18.0f, contentWidth, 14.0f);
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView.contentOffset.y < 100.0f && _messages.count != 0 && !_loading && !_reachedStart)
        [self loadHistoryOlder:true];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)__unused scrollView
{
    [_inputField resignFirstResponder];
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
