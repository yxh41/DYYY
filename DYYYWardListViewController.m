#import "DYYYWardListViewController.h"
#import <objc/runtime.h>
#import "DYYYWardManager.h"
#import "DYYYWardPanelView.h"
#import "DYYYUtils.h"
#import "DYYYToast.h"

@interface DYYYWardListViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *typeTabBar;
@property (nonatomic, strong) UIScrollView *categoryBar;
@property (nonatomic, strong) UISegmentedControl *sortSegment;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *allWards;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *filteredWards;
@property (nonatomic, copy) NSString *currentType;   // 全部/视频/评论/主页
@property (nonatomic, copy) NSString *currentCategory; // 全部 / 具体分类
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, assign) BOOL sortBySaveTime;
@end

@implementation DYYYWardListViewController

+ (void)present {
    DYYYWardListViewController *vc = [[DYYYWardListViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *top = [DYYYUtils topView];
    if (top) {
        [top presentViewController:nav animated:YES completion:nil];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.currentType = @"全部";
    self.currentCategory = @"全部";
    self.sortBySaveTime = YES;

    BOOL isDark = [DYYYUtils isDarkMode];
    self.view.backgroundColor = isDark ? [UIColor colorWithRed:18/255.0 green:18/255.0 blue:20/255.0 alpha:1.0]
                                       : [UIColor colorWithRed:242/255.0 green:242/255.0 blue:245/255.0 alpha:1.0];

    self.title = @"🌺 我的插眼";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(close)];

    [self setupSearchBar];
    [self setupTypeTabs];
    [self setupCategoryBar];
    [self setupSortSegment];
    [self setupTableView];
    [self reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 布局

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"搜索昵称 / 备注 / 分类";
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];
}

- (void)setupTypeTabs {
    CGFloat y = 44;
    self.typeTabBar = [[UIView alloc] initWithFrame:CGRectMake(0, y, self.view.bounds.size.width, 44)];
    [self.view addSubview:self.typeTabBar];
    NSArray *types = @[@"全部", @"视频", @"评论", @"主页"];
    CGFloat w = self.view.bounds.size.width / types.count;
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(i * w, 0, w, 44);
        [b setTitle:types[i] forState:UIControlStateNormal];
        b.tag = 200 + i;
        [b addTarget:self action:@selector(typeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.typeTabBar addSubview:b];
    }
    [self updateTypeTabAppearance];
}

- (void)setupCategoryBar {
    CGFloat y = 44 + 44;
    self.categoryBar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, self.view.bounds.size.width, 40)];
    self.categoryBar.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:self.categoryBar];
    [self rebuildCategoryChips];
}

- (void)rebuildCategoryChips {
    [self.categoryBar.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSMutableArray *cats = [NSMutableArray arrayWithObject:@"全部"];
    [cats addObjectsFromArray:[DYYYWardManager allCategories]];
    CGFloat x = 8;
    CGFloat h = 28;
    for (NSString *cat in cats) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:cat forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        [b sizeToFit];
        CGFloat w = b.bounds.size.width + 24;
        b.frame = CGRectMake(x, 6, w, h);
        b.layer.cornerRadius = h / 2;
        b.tag = 300 + [cats indexOfObject:cat];
        [b addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.categoryBar addSubview:b];
        x += w + 8;
    }
    self.categoryBar.contentSize = CGSizeMake(x, 40);
    [self updateCategoryAppearance];
}

- (void)setupSortSegment {
    CGFloat y = 44 + 44 + 40;
    self.sortSegment = [[UISegmentedControl alloc] initWithItems:@[@"保存时间", @"视频时间"]];
    self.sortSegment.frame = CGRectMake(self.view.bounds.size.width - 168, y + 6, 156, 30);
    self.sortSegment.selectedSegmentIndex = 0;
    [self.sortSegment addTarget:self action:@selector(sortChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.sortSegment];
}

- (void)setupTableView {
    CGFloat y = 44 + 44 + 40;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, y + 44, self.view.bounds.size.width, self.view.bounds.size.height - y - 44) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"wardCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - 过滤/排序

- (void)reloadData {
    self.allWards = [[[DYYYWardManager sharedManager] allWards] mutableCopy];

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *ward in self.allWards) {
        // 类型过滤
        if (![self.currentType isEqualToString:@"全部"]) {
            if (![[ward objectForKey:@"type"] isEqualToString:self.currentType]) continue;
        }
        // 分类过滤
        if (![self.currentCategory isEqualToString:@"全部"]) {
            if (![[ward objectForKey:@"category"] isEqualToString:self.currentCategory]) continue;
        }
        // 关键字
        if (self.keyword.length > 0) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@",
                            [ward objectForKey:@"nickname"] ?: @"",
                            [ward objectForKey:@"note"] ?: @"",
                            [ward objectForKey:@"category"] ?: @""];
            if ([hay rangeOfString:self.keyword options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        }
        [result addObject:ward];
    }

    // 排序
    NSString *key = self.sortBySaveTime ? @"saveTime" : @"createTime";
    [result sortUsingComparator:^NSComparisonResult(id a, id b) {
        id va = [a objectForKey:key];
        id vb = [b objectForKey:key];
        if ([va isKindOfClass:[NSNumber class]] && [vb isKindOfClass:[NSNumber class]]) {
            return [vb compare:va]; // 倒序
        }
        return NSOrderedAscending;
    }];

    self.filteredWards = result;
    [self refreshTypeCounts];
    [self.tableView reloadData];
}

- (void)refreshTypeCounts {
    NSArray *types = @[@"全部", @"视频", @"评论", @"主页"];
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *b = [self.typeTabBar viewWithTag:200 + i];
        if (![b isKindOfClass:[UIButton class]]) continue;
        NSString *t = types[i];
        NSInteger count = 0;
        if ([t isEqualToString:@"全部"]) {
            count = self.allWards.count;
        } else {
            for (NSDictionary *w in self.allWards) {
                if ([[w objectForKey:@"type"] isEqualToString:t]) count++;
            }
        }
        [b setTitle:[NSString stringWithFormat:@"%@ %ld", t, (long)count] forState:UIControlStateNormal];
    }
}

#pragma mark - 交互

- (void)typeTapped:(UIButton *)sender {
    NSArray *types = @[@"全部", @"视频", @"评论", @"主页"];
    self.currentType = types[sender.tag - 200];
    [self updateTypeTabAppearance];
    [self reloadData];
}

- (void)updateTypeTabAppearance {
    NSArray *types = @[@"全部", @"视频", @"评论", @"主页"];
    for (NSInteger i = 0; i < types.count; i++) {
        UIButton *b = [self.typeTabBar viewWithTag:200 + i];
        if (![b isKindOfClass:[UIButton class]]) continue;
        if ([types[i] isEqualToString:self.currentType]) {
            [b setTitleColor:[UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        } else {
            [b setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:14];
        }
    }
}

- (void)categoryTapped:(UIButton *)sender {
    NSMutableArray *cats = [NSMutableArray arrayWithObject:@"全部"];
    [cats addObjectsFromArray:[DYYYWardManager allCategories]];
    self.currentCategory = cats[sender.tag - 300];
    [self updateCategoryAppearance];
    [self reloadData];
}

- (void)updateCategoryAppearance {
    NSMutableArray *cats = [NSMutableArray arrayWithObject:@"全部"];
    [cats addObjectsFromArray:[DYYYWardManager allCategories]];
    for (NSInteger i = 0; i < cats.count; i++) {
        UIButton *b = [self.categoryBar viewWithTag:300 + i];
        if (![b isKindOfClass:[UIButton class]]) continue;
        if ([cats[i] isEqualToString:self.currentCategory]) {
            b.backgroundColor = [UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:0.15];
            [b setTitleColor:[UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
            [b setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        }
    }
}

- (void)sortChanged {
    self.sortBySaveTime = self.sortSegment.selectedSegmentIndex == 0;
    [self reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.keyword = searchText;
    [self reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredWards.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 132;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"wardCell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];

    NSDictionary *ward = self.filteredWards[indexPath.row];
    BOOL isDark = [DYYYUtils isDarkMode];
    UIColor *cardBg = isDark ? [UIColor colorWithRed:30/255.0 green:30/255.0 blue:32/255.0 alpha:1.0]
                             : [UIColor whiteColor];
    UIColor *textColor = isDark ? [UIColor colorWithRed:235/255.0 green:235/255.0 blue:240/255.0 alpha:1.0]
                                : [UIColor colorWithRed:40/255.0 green:42/255.0 blue:50/255.0 alpha:1.0];
    UIColor *subColor = isDark ? [UIColor colorWithRed:150/255.0 green:150/255.0 blue:155/255.0 alpha:1.0]
                               : [UIColor colorWithRed:120/255.0 green:122/255.0 blue:130/255.0 alpha:1.0];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, 8, tableView.bounds.size.width - 24, 120)];
    card.backgroundColor = cardBg;
    card.layer.cornerRadius = 14;
    [cell.contentView addSubview:card];

    // 头像
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 40, 40)];
    avatar.layer.cornerRadius = 20;
    avatar.clipsToBounds = YES;
    avatar.backgroundColor = [UIColor lightGrayColor];
    [card addSubview:avatar];
    NSString *avatarURL = [ward objectForKey:@"avatarURL"];
    if (avatarURL.length > 0) [self loadAvatar:avatarURL into:avatar];

    // 昵称
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(60, 12, card.bounds.size.width - 72, 20)];
    name.text = [ward objectForKey:@"nickname"] ?: @"未知用户";
    name.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    name.textColor = textColor;
    [card addSubview:name];

    // 类型 + 分类标签
    NSString *type = [ward objectForKey:@"type"] ?: @"";
    NSString *cat = [ward objectForKey:@"category"] ?: @"";
    UILabel *tag = [[UILabel alloc] initWithFrame:CGRectMake(60, 36, card.bounds.size.width - 72, 18)];
    tag.text = [NSString stringWithFormat:@"%@ · %@", type, cat];
    tag.font = [UIFont systemFontOfSize:12];
    tag.textColor = [UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0];
    [card addSubview:tag];

    // 保存时间
    NSNumber *saveTime = [ward objectForKey:@"saveTime"];
    UILabel *saveLabel = [[UILabel alloc] initWithFrame:CGRectMake(60, 56, card.bounds.size.width - 72, 16)];
    saveLabel.font = [UIFont systemFontOfSize:11];
    saveLabel.textColor = subColor;
    if (saveTime) {
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:[saveTime doubleValue]];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        saveLabel.text = [NSString stringWithFormat:@"保存：%@", [fmt stringFromDate:d] ?: @""];
    }
    [card addSubview:saveLabel];

    // 备注 / 视频时间
    NSString *note = [ward objectForKey:@"note"] ?: @"";
    NSString *createTime = [ward objectForKey:@"createTime"] ?: @"";
    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(12, 80, card.bounds.size.width - 24, 18)];
    detail.font = [UIFont systemFontOfSize:12];
    detail.textColor = subColor;
    detail.lineBreakMode = NSLineBreakByTruncatingTail;
    if (note.length > 0) {
        detail.text = [NSString stringWithFormat:@"备注：%@", note];
    } else if (createTime.length > 0) {
        detail.text = [NSString stringWithFormat:@"视频：%@", createTime];
    }
    [card addSubview:detail];

    // 操作按钮
    NSArray *actions = @[@"查看", @"编辑", @"复制", @"删除"];
    CGFloat btnW = (card.bounds.size.width - 24) / 4;
    for (NSInteger i = 0; i < actions.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(12 + i * btnW, 100, btnW, 20);
        [b setTitle:actions[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        b.tag = 400 + i;
        if (i == 3) {
            [b setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        } else {
            [b setTitleColor:[UIColor colorWithRed:250/255.0 green:60/255.0 blue:90/255.0 alpha:1.0] forState:UIControlStateNormal];
        }
        [b addTarget:self action:@selector(actionTapped:event:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(b, "wardIndex", @(indexPath.row), OBJC_ASSOCIATION_RETAIN);
        [card addSubview:b];
    }

    return cell;
}

- (void)actionTapped:(UIButton *)sender event:(UIEvent *)event {
    NSNumber *idxNum = objc_getAssociatedObject(sender, "wardIndex");
    if (!idxNum) return;
    NSInteger idx = [idxNum integerValue];
    if (idx >= self.filteredWards.count) return;
    NSDictionary *ward = self.filteredWards[idx];
    NSInteger action = sender.tag - 400;

    if (action == 0) { // 查看
        [self openWard:ward];
    } else if (action == 1) { // 编辑
        DYYYWardPanelView *panel = [[DYYYWardPanelView alloc] initWithWard:ward];
        [panel show];
    } else if (action == 2) { // 复制链接
        NSString *url = [ward objectForKey:@"shareURL"] ?: @"";
        if (url.length > 0) {
            [UIPasteboard generalPasteboard].string = url;
            [DYYYUtils showToast:@"已复制链接"];
        } else {
            [DYYYUtils showToast:@"无链接"];
        }
    } else if (action == 3) { // 删除
        [[DYYYWardManager sharedManager] deleteWardWithID:[ward objectForKey:@"wardID"]];
        [DYYYUtils showToast:@"已删除"];
        [self reloadData];
    }
}

- (void)openWard:(NSDictionary *)ward {
    NSString *awemeID = [ward objectForKey:@"awemeID"];
    if (awemeID.length == 0) {
        [DYYYUtils showToast:@"无视频信息，已复制链接"];
        NSString *url = [ward objectForKey:@"shareURL"];
        if (url.length > 0) [UIPasteboard generalPasteboard].string = url;
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"snssdk1233://aweme/detail/?aweme_id=%@", awemeID]];
    BOOL ok = [[UIApplication sharedApplication] openURL:url];
    if (!ok) {
        // 兜底：复制作品链接
        NSString *share = [NSString stringWithFormat:@"https://www.douyin.com/video/%@", awemeID];
        [UIPasteboard generalPasteboard].string = share;
        [DYYYUtils showToast:@"已复制视频链接"];
    }
}

- (void)loadAvatar:(NSString *)urlString into:(UIImageView *)imageView {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data) {
            UIImage *img = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) imageView.image = img;
            });
        }
    });
}

@end
