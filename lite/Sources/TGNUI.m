#import "TGNUI.h"

void TGNShowAlert(NSString *title, NSString *message)
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}

NSString *TGNFormatDate(int32_t unixtime, bool short_)
{
    static NSDateFormatter *timeFormatter = nil;
    static NSDateFormatter *dateFormatter = nil;
    static NSDateFormatter *fullFormatter = nil;
    if (timeFormatter == nil)
    {
        timeFormatter = [[NSDateFormatter alloc] init];
        timeFormatter.dateFormat = @"HH:mm";
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"dd.MM.yy";
        fullFormatter = [[NSDateFormatter alloc] init];
        fullFormatter.dateFormat = @"dd.MM.yy HH:mm";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixtime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *now = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    NSDateComponents *then = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:date];
    bool today = now.year == then.year && now.month == then.month && now.day == then.day;
    if (short_)
        return today ? [timeFormatter stringFromDate:date] : [dateFormatter stringFromDate:date];
    return today ? [timeFormatter stringFromDate:date] : [fullFormatter stringFromDate:date];
}

UIColor *TGNColor(uint32_t rgb)
{
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f green:((rgb >> 8) & 0xff) / 255.0f blue:(rgb & 0xff) / 255.0f alpha:1.0f];
}

UITextField *TGNMakeField(NSString *placeholder, UIKeyboardType keyboard)
{
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.placeholder = placeholder;
    field.keyboardType = keyboard;
    field.font = [UIFont systemFontOfSize:18.0f];
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    return field;
}

UILabel *TGNMakeLabel(NSString *text, CGFloat fontSize, bool bold)
{
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.text = text;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = bold ? [UIFont boldSystemFontOfSize:fontSize] : [UIFont systemFontOfSize:fontSize];
    label.textColor = bold ? [UIColor blackColor] : TGNColor(0x555555);
    return label;
}

UIButton *TGNMakeButton(NSString *title, id target, SEL action)
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17.0f];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@interface TGNFormController ()
{
    NSMutableArray *_formViews;
    NSMutableArray *_formHeights;
    UIActivityIndicatorView *_spinner;
}
@end

@implementation TGNFormController

- (void)loadView
{
    [super loadView];
    self.view.backgroundColor = TGNColor(0xEFEFF4);
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];

    _formViews = [[NSMutableArray alloc] init];
    _formHeights = [[NSMutableArray alloc] init];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)addFormView:(UIView *)view height:(CGFloat)height
{
    [_formViews addObject:view];
    [_formHeights addObject:@(height)];
    [_scrollView addSubview:view];
    [self.view setNeedsLayout];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat margin = 20.0f;
    CGFloat contentWidth = MIN(width - margin * 2.0f, 440.0f);
    CGFloat x = (CGFloat)floor((width - contentWidth) / 2.0f);
    CGFloat y = 20.0f;
    for (NSUInteger i = 0; i < _formViews.count; i++)
    {
        UIView *view = _formViews[i];
        CGFloat height = [_formHeights[i] floatValue];
        if ([view isKindOfClass:[UILabel class]] && height <= 0.0f)
        {
            CGSize size = [((UILabel *)view).text sizeWithFont:((UILabel *)view).font constrainedToSize:CGSizeMake(contentWidth, 1000.0f) lineBreakMode:NSLineBreakByWordWrapping];
            height = (CGFloat)ceil(size.height);
        }
        view.frame = CGRectMake(x, y, contentWidth, height);
        y += height + 14.0f;
    }
    _scrollView.contentSize = CGSizeMake(width, y);
}

- (void)setBusy:(bool)busy
{
    _busy = busy;
    if (busy)
    {
        [_spinner startAnimating];
        self.navigationItem.rightBarButtonItem.enabled = NO;
        self.navigationItem.titleView = _spinner;
    }
    else
    {
        [_spinner stopAnimating];
        self.navigationItem.rightBarButtonItem.enabled = YES;
        self.navigationItem.titleView = nil;
    }
}

- (void)keyboardWillChange:(NSNotification *)notification
{
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0.0f, self.view.bounds.size.height - frame.origin.y);
    _scrollView.contentInset = UIEdgeInsetsMake(0.0f, 0.0f, overlap, 0.0f);
    _scrollView.scrollIndicatorInsets = _scrollView.contentInset;
}

- (void)keyboardWillHide:(NSNotification *)__unused notification
{
    _scrollView.contentInset = UIEdgeInsetsZero;
    _scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
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
