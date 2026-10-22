#import "DYYYWardPanelView.h"
#import "DYYYWardManager.h"
#import "DYYYUtils.h"
#import "DYYYToast.h"
#import "DYYYCustomInputView.h"

// 安全读取未知字段
static NSString *DYYYWardSafeString(id obj, NSString *key) {
    if (!obj || !key) return @"";
    @try {
        id val = [obj valueForKey:key];
        if (val && ![val isKindOfClass:[NSNull class]]) {
            NSString *s = [NSString stringWithFormat:@"%@", val];
            if (s.length > 0 && ![s isEqualToString:@"(null)"]) return s;
        }
    } @catch (NSException *e) {}
    return @"";
}

static NSString *DYYYWardStringForKeys(id obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *s = DYYYWardSafeString(obj, key);
        if (s.length > 0) return s;
    }
    return @"";
}

@interface DYYYWardPanelView ()
@property (nonatomic, strong) AWEAwemeModel *model;
@property (nonatomic, copy) NSString *editingWardID;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nicknameLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UIButton *categoryButton;
@property (nonatomic, strong) UIView *dropdownView;
@property (nonatomic, assign) BOOL dropdownOpen;
@property (nonatomic, copy) NSString *selectedCategory;
@property (nonatomic, strong) UITextView *noteTextView;
@property (nonatomic, copy) NSString *noteText;
// 提取出的作品信息
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *secUid;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *commentID;
@property (nonatomic, copy) NSArray *commentIDs; // 所有候选 cid 值，定位时逐个比对
@property (nonatomic, copy) NSString *createTime;
@property (nonatomic, copy) NSString *shareURL;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *wardType; // 视频 / 主页 / 评论
@end

@implementation DYYYWardPanelView

- (instancetype)initWithAwemeModel:(AWEAwemeModel *)model {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        _model = model;
        _wardType = @"视频";
        _selectedCategory = @"未分类";
        [self extractModel];
        [self buildUI];
    }
    return self;
}

- (instancetype)initWithWardData:(NSDictionary *)data {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        _wardType = [data objectForKey:@"type"] ?: @"视频";
        _nickname = [data objectForKey:@"nickname"] ?: @"未知用户";
        _uid = [data objectForKey:@"uid"] ?: @"";
        _secUid = [data objectForKey:@"secUid"] ?: @"";
        _avatarURL = [data objectForKey:@"avatarURL"] ?: @"";
        _itemID = [data objectForKey:@"awemeID"] ?: @"";
        _commentID = [data objectForKey:@"commentID"] ?: @"";
        id savedIDs = [data objectForKey:@"commentIDs"];
        _commentIDs = [savedIDs isKindOfClass:[NSArray class]] ? savedIDs : nil;
        _createTime = [data objectForKey:@"createTime"] ?: @"";
        _shareURL = [data objectForKey:@"shareURL"] ?: @"";
        _desc = [data objectForKey:@"desc"] ?: @"";
        _selectedCategory = @"未分类";
        _noteText = @"";
        [self buildUI];
    }
    return self;
}

- (instancetype)initWithWard:(NSDictionary *)ward {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        _editingWardID = [ward objectForKey:@"wardID"];
        _wardType = [ward objectForKey:@"type"] ?: @"视频";
        _nickname = [ward objectForKey:@"nickname"] ?: @"未知用户";
        _uid = [ward objectForKey:@"uid"] ?: @"";
        _secUid = [ward objectForKey:@"secUid"] ?: @"";
        _avatarURL = [ward objectForKey:@"avatarURL"] ?: @"";
        _itemID = [ward objectForKey:@"awemeID"] ?: @"";
        _commentID = [ward objectForKey:@"commentID"] ?: @"";
        id savedIDs = [ward objectForKey:@"commentIDs"];
        _commentIDs = [savedIDs isKindOfClass:[NSArray class]] ? savedIDs : nil;
        _createTime = [ward objectForKey:@"createTime"] ?: @"";
        _shareURL = [ward objectForKey:@"shareURL"] ?: @"";
        _desc = [ward objectForKey:@"desc"] ?: @"";
        NSString *cat = [ward objectForKey:@"category"];
        _selectedCategory = cat.length > 0 ? cat : @"未分类";
        _noteText = [ward objectForKey:@"note"] ?: @"";
        [self buildUI];
    }
    return self;
}

- (void)extractModel {
    if (!_model) return;
    id author = [_model valueForKey:@"author"];
    _nickname = DYYYWardSafeString(author, @"nickname");
    if (_nickname.length == 0) _nickname = @"未知用户";
    _uid = DYYYWardStringForKeys(author, @[@"uid", @"userID", @"userId"]);
    _secUid = DYYYWardStringForKeys(author, @[@"secUid", @"secUID", @"sec_uid"]);
    _itemID = DYYYWardSafeString(_model, @"itemID");

    id avatar = [author valueForKey:@"avatarMedium"];
    if ([avatar respondsToSelector:@selector(originURLList)]) {
        NSArray *list = [avatar originURLList];
        if (list.count > 0) _avatarURL = list.firstObject;
    }

    NSNumber *ct = [NSNumber numberWithDouble:[DYYYWardSafeString(_model, @"createTime") doubleValue]];
    if (ct && [ct doubleValue] > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[ct doubleValue]];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        _createTime = [fmt stringFromDate:date] ?: @"";
    }

    if (_itemID.length > 0) {
        _shareURL = [NSString stringWithFormat:@"https://www.douyin.com/video/%@", _itemID];
    }

    // 视频文案：优先头文件声明的 descriptionString，兜底 KVC desc
    if ([_model respondsToSelector:@selector(descriptionString)]) {
        _desc = _model.descriptionString ?: @"";
    }
    if (_desc.length == 0) {
        _desc = DYYYWardSafeString(_model, @"desc");
    }
}

#pragma mark - UI

- (void)buildUI {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped)]];

    BOOL isDark = [DYYYUtils isDarkMode];
    UIColor *cardBg = isDark ? [UIColor colorWithRed:30/255.0 green:30/255.0 blue:32/255.0 alpha:1.0]
                             : [UIColor colorWithRed:248/255.0 green:248/255.0 blue:250/255.0 alpha:1.0];
    UIColor *textColor = isDark ? [UIColor colorWithRed:235/255.0 green:235/255.0 blue:240/255.0 alpha:1.0]
                                : [UIColor colorWithRed:40/255.0 green:42/255.0 blue:50/255.0 alpha:1.0];
    UIColor *subColor = isDark ? [UIColor colorWithRed:150/255.0 green:150/255.0 blue:155/255.0 alpha:1.0]
                               : [UIColor colorWithRed:120/255.0 green:122/255.0 blue:130/255.0 alpha:1.0];

    CGFloat cardW = MIN(self.bounds.size.width - 36, 340);
    CGFloat cardH = MIN(self.bounds.size.height - 80, 560);
    CGFloat cardX = (self.bounds.size.width - cardW) / 2;
    CGFloat cardY = (self.bounds.size.height - cardH) / 2;
    self.cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardH)];
    self.cardView.backgroundColor = cardBg;
    self.cardView.layer.cornerRadius = 18;
    self.cardView.clipsToBounds = YES;
    self.cardView.alpha = 0;
    self.cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [self addSubview:self.cardView];

    CGFloat margin = 16;

    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(margin, 16, cardW - margin*2, 24)];
    title.text = _editingWardID ? @"🌺 编辑插眼" : @"🌺 视频插眼";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    title.textColor = textColor;
    title.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:title];

    // 用户卡片
    UIView *userCard = [[UIView alloc] initWithFrame:CGRectMake(margin, 50, cardW - margin*2, 60)];
    userCard.backgroundColor = isDark ? [UIColor colorWithRed:42/255.0 green:42/255.0 blue:46/255.0 alpha:1.0]
                                      : [UIColor whiteColor];
    userCard.layer.cornerRadius = 12;
    [self.cardView addSubview:userCard];

    self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 40, 40)];
    self.avatarView.layer.cornerRadius = 20;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.backgroundColor = [UIColor lightGrayColor];
    [userCard addSubview:self.avatarView];
    if (_avatarURL.length > 0) {
        [self loadAvatar:_avatarURL];
    }

    self.nicknameLabel = [[UILabel alloc] initWithFrame:CGRectMake(58, 10, cardW - margin*2 - 68, 22)];
    self.nicknameLabel.text = _nickname;
    self.nicknameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.nicknameLabel.textColor = textColor;
    [userCard addSubview:self.nicknameLabel];

    self.subLabel = [[UILabel alloc] initWithFrame:CGRectMake(58, 34, cardW - margin*2 - 68, 18)];
    self.subLabel.font = [UIFont systemFontOfSize:12];
    self.subLabel.textColor = subColor;
    [userCard addSubview:self.subLabel];
    [self refreshSubLabel];

    // 分类选择
    UILabel *catTitle = [[UILabel alloc] initWithFrame:CGRectMake(margin, 124, cardW - margin*2, 20)];
    catTitle.text = @"分类";
    catTitle.font = [UIFont systemFontOfSize:13];
    catTitle.textColor = subColor;
    [self.cardView addSubview:catTitle];

    self.categoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.categoryButton.frame = CGRectMake(margin, 148, cardW - margin*2, 40);
    self.categoryButton.backgroundColor = isDark ? [UIColor colorWithRed:42/255.0 green:42/255.0 blue:46/255.0 alpha:1.0]
                                                 : [UIColor whiteColor];
    self.categoryButton.layer.cornerRadius = 10;
    self.categoryButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.categoryButton.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
    [self.categoryButton setTitleColor:textColor forState:UIControlStateNormal];
    [self.categoryButton setTitle:[NSString stringWithFormat:@"%@  ▾", _selectedCategory] forState:UIControlStateNormal];
    [self.categoryButton addTarget:self action:@selector(toggleDropdown) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.categoryButton];

    // 备注
    UILabel *noteTitle = [[UILabel alloc] initWithFrame:CGRectMake(margin, 200, cardW - margin*2, 20)];
    noteTitle.text = @"备注";
    noteTitle.font = [UIFont systemFontOfSize:13];
    noteTitle.textColor = subColor;
    [self.cardView addSubview:noteTitle];

    self.noteTextView = [[UITextView alloc] initWithFrame:CGRectMake(margin, 224, cardW - margin*2, 160)];
    self.noteTextView.backgroundColor = isDark ? [UIColor colorWithRed:42/255.0 green:42/255.0 blue:46/255.0 alpha:1.0]
                                               : [UIColor whiteColor];
    self.noteTextView.layer.cornerRadius = 10;
    self.noteTextView.textColor = textColor;
    self.noteTextView.font = [UIFont systemFontOfSize:14];
    self.noteTextView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    if (_noteText.length > 0) {
        self.noteTextView.text = _noteText;
    }
    [self.cardView addSubview:self.noteTextView];

    // 底部按钮
    CGFloat btnY = cardH - 56;
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, btnY, cardW, 0.5)];
    sep.backgroundColor = isDark ? [UIColor colorWithRed:60/255.0 green:60/255.0 blue:64/255.0 alpha:1.0]
                                 : [UIColor colorWithRed:230/255.0 green:230/255.0 blue:232/255.0 alpha:1.0];
    [self.cardView addSubview:sep];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(0, btnY + 0.5, cardW/2 - 0.25, 55.5);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:subColor forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [cancelBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:cancelBtn];

    UIView *btnSep = [[UIView alloc] initWithFrame:CGRectMake(cardW/2 - 0.25, btnY + 0.5, 0.5, 55.5)];
    btnSep.backgroundColor = isDark ? [UIColor colorWithRed:60/255.0 green:60/255.0 blue:64/255.0 alpha:1.0]
                                    : [UIColor colorWithRed:230/255.0 green:230/255.0 blue:232/255.0 alpha:1.0];
    [self.cardView addSubview:btnSep];

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(cardW/2 + 0.25, btnY + 0.5, cardW/2 - 0.25, 55.5);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0] forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [saveBtn addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:saveBtn];
}

- (void)refreshSubLabel {
    if (_secUid.length > 0) {
        NSArray *existing = [[DYYYWardManager sharedManager] wardsForUserWithSecUid:_secUid];
        if (existing.count == 0) {
            _subLabel.text = @"首次插眼此用户";
        } else {
            _subLabel.text = [NSString stringWithFormat:@"已插眼 %lu 次", (unsigned long)existing.count];
        }
    } else {
        _subLabel.text = @"";
    }
}

- (void)loadAvatar:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data) {
            UIImage *img = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) self.avatarView.image = img;
            });
        }
    });
}

#pragma mark - 下拉分类

- (void)toggleDropdown {
    if (_dropdownOpen) {
        [self closeDropdown];
    } else {
        [self openDropdown];
    }
}

- (void)openDropdown {
    CGFloat cardW = self.cardView.bounds.size.width;
    CGFloat margin = 16;
    CGFloat baseY = 192;
    CGFloat maxH = 220;

    self.dropdownView = [[UIView alloc] initWithFrame:CGRectMake(margin, baseY, cardW - margin*2, 0)];
    self.dropdownView.backgroundColor = self.cardView.backgroundColor;
    self.dropdownView.layer.cornerRadius = 10;
    self.dropdownView.layer.borderWidth = 0.5;
    self.dropdownView.layer.borderColor = [UIColor colorWithWhite:0.7 alpha:0.4].CGColor;
    self.dropdownView.clipsToBounds = YES;
    [self.cardView addSubview:self.dropdownView];

    NSArray *cats = [DYYYWardManager allCategories];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 36, cardW - margin*2, maxH - 36)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.dropdownView addSubview:scroll];

    CGFloat y = 0;
    CGFloat rowH = 40;
    for (NSString *cat in cats) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(0, y, cardW - margin*2, rowH);
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 0);
        [b setTitle:cat forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithRed:40/255.0 green:42/255.0 blue:50/255.0 alpha:1.0] forState:UIControlStateNormal];
        b.tag = 1000 + [cats indexOfObject:cat];
        [b addTarget:self action:@selector(selectCategory:) forControlEvents:UIControlEventTouchUpInside];
        // 自定义分类支持长按删除
        if (![[DYYYWardManager defaultCategories] containsObject:cat]) {
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressCategory:)];
            lp.minimumPressDuration = 0.6;
            [b addGestureRecognizer:lp];
        }
        [scroll addSubview:b];
        y += rowH;
    }
    scroll.contentSize = CGSizeMake(cardW - margin*2, y);

    // 管理行
    UIButton *manage = [UIButton buttonWithType:UIButtonTypeSystem];
    manage.frame = CGRectMake(0, 0, cardW - margin*2, 36);
    [manage setTitle:@"➕ 管理分类" forState:UIControlStateNormal];
    [manage setTitleColor:[UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0] forState:UIControlStateNormal];
    [manage addTarget:self action:@selector(manageCategory) forControlEvents:UIControlEventTouchUpInside];
    [self.dropdownView addSubview:manage];

    [UIView animateWithDuration:0.2 animations:^{
        self.dropdownView.frame = CGRectMake(margin, baseY, cardW - margin*2, maxH);
    }];
    _dropdownOpen = YES;
}

- (void)closeDropdown {
    if (!self.dropdownView) { _dropdownOpen = NO; return; }
    [UIView animateWithDuration:0.15 animations:^{
        self.dropdownView.alpha = 0;
    } completion:^(BOOL finished) {
        [self.dropdownView removeFromSuperview];
        self.dropdownView = nil;
    }];
    _dropdownOpen = NO;
}

- (void)selectCategory:(UIButton *)sender {
    NSString *cat = [sender titleForState:UIControlStateNormal];
    _selectedCategory = cat;
    [self.categoryButton setTitle:[NSString stringWithFormat:@"%@  ▾", cat] forState:UIControlStateNormal];
    [self closeDropdown];
}

- (void)longPressCategory:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIButton *b = (UIButton *)gesture.view;
    NSString *cat = [b titleForState:UIControlStateNormal];
    if ([[DYYYWardManager defaultCategories] containsObject:cat]) return;
    [DYYYWardManager removeCustomCategory:cat];
    [self closeDropdown];
    [self openDropdown];
    [DYYYUtils showToast:[NSString stringWithFormat:@"已删除分类：%@", cat]];
}

- (void)manageCategory {
    DYYYCustomInputView *input = [[DYYYCustomInputView alloc] initWithTitle:@"新增分类" defaultText:nil placeholder:@"输入分类名称"];
    input.onConfirm = ^(NSString *text) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [DYYYWardManager addCustomCategory:trimmed];
            [self closeDropdown];
            [self openDropdown];
        }
    };
    [input show];
}

#pragma mark - 操作

- (void)backgroundTapped {
    // 先记录点击时键盘是否弹出：弹出时本次点击只收键盘（resign 后 isFirstResponder 立即变 NO，
    // 若不提前记录会同帧把面板一起关掉），下次再点才关闭面板
    BOOL wasEditing = self.noteTextView.isFirstResponder;
    if (wasEditing) [self.noteTextView resignFirstResponder];
    if (_dropdownOpen) {
        [self closeDropdown];
        return;
    }
    if (!wasEditing) {
        [self dismiss];
    }
}

- (void)saveTapped {
    NSMutableDictionary *ward = [NSMutableDictionary dictionary];
    [ward setObject:(_wardType ?: @"视频") forKey:@"type"];
    [ward setObject:(_uid ?: @"") forKey:@"uid"];
    [ward setObject:(_secUid ?: @"") forKey:@"secUid"];
    [ward setObject:_nickname forKey:@"nickname"];
    [ward setObject:(_avatarURL ?: @"") forKey:@"avatarURL"];
    [ward setObject:(_itemID ?: @"") forKey:@"awemeID"];
    [ward setObject:(_commentID ?: @"") forKey:@"commentID"];
    if (_commentIDs.count > 0) [ward setObject:_commentIDs forKey:@"commentIDs"];
    [ward setObject:(_createTime ?: @"") forKey:@"createTime"];
    [ward setObject:_selectedCategory forKey:@"category"];
    [ward setObject:(_noteTextView.text ?: @"") forKey:@"note"];
    [ward setObject:(_shareURL ?: @"") forKey:@"shareURL"];
    [ward setObject:(_desc ?: @"") forKey:@"desc"];

    NSString *wardID = nil;
    if (_editingWardID.length > 0) {
        [[DYYYWardManager sharedManager] updateWardWithID:_editingWardID fields:ward];
        wardID = _editingWardID;
        [DYYYUtils showToast:@"🌺 已更新插眼"];
    } else {
        wardID = [[DYYYWardManager sharedManager] addWard:ward];
        if (wardID.length > 0) {
            [DYYYUtils showToast:@"🌺 插眼成功"];
        } else {
            [DYYYUtils showToast:@"插眼失败"];
        }
    }
    [self dismiss];
}

#pragma mark - 显示/隐藏

- (void)show {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;
    // 先清掉残留实例，避免多个面板叠加把交互全挡住
    for (UIView *sub in [window.subviews copy]) {
        if ([sub isKindOfClass:[DYYYWardPanelView class]] && sub != self) {
            [sub removeFromSuperview];
        }
    }
    self.frame = window.bounds;
    [window addSubview:self];
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.alpha = 1;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.cardView.alpha = 0;
        self.cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end
