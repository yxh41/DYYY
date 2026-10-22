#import "DYYYWardListViewController.h"
#import <objc/runtime.h>
#import "DYYYWardManager.h"
#import "DYYYWardPanelView.h"
#import "DYYYUtils.h"
#import "DYYYToast.h"

@interface DYYYWardListViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIGestureRecognizerDelegate>
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

#pragma mark - 评论插眼定位：跳作品 → 开评论区 → 找到该评论并高亮

static UIViewController *DYYYWardTopViewController(void) {
    UIWindow *window = [DYYYUtils getActiveWindow];
    UIViewController *vc = window.rootViewController;
    for (NSInteger i = 0; vc && i < 10; i++) {
        UIViewController *next = nil;
        if (vc.presentedViewController) {
            next = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            next = [(UINavigationController *)vc topViewController];
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            next = [(UITabBarController *)vc selectedViewController];
        }
        if (!next || next == vc) break;
        vc = next;
    }
    return vc;
}

static void DYYYWardFindVCHelper(UIViewController *vc, Class cls, NSInteger depth, UIViewController **found) {
    if (!vc || !cls || depth > 6 || *found) return;
    if ([vc isKindOfClass:cls]) {
        *found = vc;
        return;
    }
    for (UIViewController *child in vc.childViewControllers) {
        DYYYWardFindVCHelper(child, cls, depth + 1, found);
        if (*found) return;
    }
    if (vc.presentedViewController) DYYYWardFindVCHelper(vc.presentedViewController, cls, depth + 1, found);
}

static UIViewController *DYYYWardFindVC(Class cls) {
    UIViewController *found = nil;
    DYYYWardFindVCHelper(DYYYWardTopViewController(), cls, 0, &found);
    return found;
}

static UIViewController *DYYYWardFindCommentVC(void);

// 评论区没打开时，借作品页交互控制器主动打开
static void DYYYWardOpenCommentPanelIfNeeded(void) {
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (commentVC) return;
    UIViewController *interaction = DYYYWardFindVC(NSClassFromString(@"AWEPlayInteractionViewController"));
    if (interaction && [interaction respondsToSelector:@selector(performCommentAction)]) {
        [interaction performSelector:@selector(performCommentAction)];
    }
}

static NSString *gDYYYWardLocateDiag = nil; // 最近一次定位失败原因，供 toast 诊断

// 递归收集视图树里所有 UITableView / UICollectionView（评论区列表类型/嵌套不定，
// 曾出现「找错列表只看到 2 条无关 cell」的情况，故收集全部候选逐个试）
static void DYYYWardCollectListCandidates(UIView *view, NSInteger depth, NSMutableArray *out) {
    if (!view || depth > 10 || out.count > 24) return;
    if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) {
        [out addObject:view];
    }
    for (UIView *sub in view.subviews) {
        DYYYWardCollectListCandidates(sub, depth + 1, out);
    }
}

// 评论列表候选：容器 VC 自身 + 子 VC 的视图树；UITableView 优先，其余按面积降序
static NSArray *DYYYWardCommentListViews(UIViewController *commentVC) {
    NSMutableArray *all = [NSMutableArray array];
    DYYYWardCollectListCandidates(commentVC.view, 0, all);
    for (UIViewController *child in commentVC.childViewControllers) {
        if (child.isViewLoaded) DYYYWardCollectListCandidates(child.view, 0, all);
    }
    NSMutableArray *tables = [NSMutableArray array];
    NSMutableArray *collections = [NSMutableArray array];
    for (UIScrollView *s in all) {
        if ([s isKindOfClass:[UITableView class]]) [tables addObject:s];
        else [collections addObject:s];
    }
    [collections sortUsingComparator:^NSComparisonResult(UIScrollView *a, UIScrollView *b) {
        CGFloat areaA = CGRectGetWidth(a.bounds) * CGRectGetHeight(a.bounds);
        CGFloat areaB = CGRectGetWidth(b.bounds) * CGRectGetHeight(b.bounds);
        return areaA < areaB ? NSOrderedDescending : (areaA > areaB ? NSOrderedAscending : NSOrderedSame);
    }];
    NSMutableArray *result = [NSMutableArray arrayWithArray:tables];
    [result addObjectsFromArray:collections];
    return result;
}

static NSString *DYYYWardCIDOf(id obj) {
    if (!obj) return nil;
    // 与插眼保存侧（DYYYCommentStrForKeys）保持同一套 cid 键
    NSArray *cidKeys = @[ @"cid", @"commentID", @"commentId", @"comment_id", @"id" ];
    for (NSString *k in cidKeys) {
        @try {
            id v = [obj valueForKey:k];
            if (v && ![v isKindOfClass:[NSNull class]]) {
                NSString *s = [NSString stringWithFormat:@"%@", v];
                if (s.length > 0 && ![s isEqualToString:@"(null)"]) return s;
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

// cell → 评论模型 → cid；模型可能嵌在 viewModel 里，最多探两层
static NSString *DYYYWardCommentIDOfCell(id cell) {
    if (!cell) return nil;
    NSArray *modelKeys = @[ @"comment", @"commentModel", @"awemeComment", @"model", @"cellViewModel", @"itemModel" ];
    for (NSString *k in modelKeys) {
        @try {
            id m = [cell valueForKey:k];
            if (!m || [m isKindOfClass:[NSNull class]]) continue;
            NSString *cid = DYYYWardCIDOf(m);
            if (cid) return cid;
            for (NSString *k2 in @[ @"model", @"comment", @"awemeComment" ]) {
                @try {
                    id m2 = [m valueForKey:k2];
                    if (m2 && ![m2 isKindOfClass:[NSNull class]]) {
                        NSString *cid2 = DYYYWardCIDOf(m2);
                        if (cid2) return cid2;
                    }
                } @catch (NSException *e) {}
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

// 评论区 VC：先认已知类名，找不到就沿 VC 链找类名含 Comment 的（各版本容器类名不一致）；
// 排除评论输入框/键盘类（它们常驻且类名也含 Comment，会误命中）
static UIViewController *DYYYWardFindCommentVC(void) {
    UIViewController *vc = DYYYWardFindVC(NSClassFromString(@"AWECommentContainerViewController"));
    if (vc) return vc;
    UIViewController *top = DYYYWardTopViewController();
    for (NSInteger i = 0; top && i < 10; i++) {
        NSString *cls = NSStringFromClass([top class]);
        BOOL looksLikeContainer = [cls containsString:@"Comment"] &&
                                  ![cls containsString:@"Input"] && ![cls containsString:@"Keyboard"] &&
                                  ![cls containsString:@"Edit"] && ![cls containsString:@"Panel"] &&
                                  ![cls containsString:@"Bar"];
        if (looksLikeContainer && top.isViewLoaded && top.view.window) return top;
        UIViewController *next = top.presentedViewController;
        if (!next && [top isKindOfClass:[UINavigationController class]]) next = [(UINavigationController *)top topViewController];
        if (!next && [top isKindOfClass:[UITabBarController class]]) next = [(UITabBarController *)top selectedViewController];
        if (!next || next == top) break;
        top = next;
    }
    return nil;
}

// 滚动到 cell 并闪高亮框（清复用残留，避免叠框）
static void DYYYWardScrollAndHighlight(UIScrollView *scroll, id cell) {
    if (!scroll || !cell) return;
    UIView *cellView = (UIView *)cell;
    for (UIView *sub in [cellView.subviews copy]) {
        if (sub.tag == 20261022) [sub removeFromSuperview];
    }
    if ([scroll isKindOfClass:[UITableView class]]) {
        NSIndexPath *ip = [(UITableView *)scroll indexPathForCell:(UITableViewCell *)cell];
        if (ip) {
            [(UITableView *)scroll scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        }
    } else {
        NSIndexPath *ip = [(UICollectionView *)scroll indexPathForCell:(UICollectionViewCell *)cell];
        if (ip) {
            [(UICollectionView *)scroll scrollToItemAtIndexPath:ip
                   atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                           animated:YES];
        }
    }
    UIView *highlight = [[UIView alloc] initWithFrame:cellView.bounds];
    highlight.layer.borderColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0].CGColor;
    highlight.layer.borderWidth = 2.0;
    highlight.userInteractionEnabled = NO;
    highlight.tag = 20261022;
    [cellView addSubview:highlight];
    [UIView animateWithDuration:0.6 delay:1.2 options:0 animations:^{ highlight.alpha = 0.0; } completion:^(BOOL f) { [highlight removeFromSuperview]; }];
}

// 递归收集 cell 里的 UILabel（评论内容兜底匹配用）
static void DYYYWardCollectCellLabels(UIView *view, NSInteger depth, NSMutableArray *out) {
    if (!view || depth > 6 || out.count > 120) return;
    if ([view isKindOfClass:[UILabel class]]) [out addObject:view];
    for (UIView *sub in view.subviews) {
        DYYYWardCollectCellLabels(sub, depth + 1, out);
    }
}

// 在评论列表可见 cell 里找 cid 匹配的评论；cid 字段名各版本不一致时，
// 再用评论内容前缀兜底匹配 cell 里的 label 文本（前缀逐级缩短，兼容 cell 文本被截断）。
// 滚动过去并闪一下高亮框。列表类型/嵌套不定，逐个候选列表试。
static BOOL DYYYWardHighlightComment(NSString *commentID, NSString *contentHint) {
    if (commentID.length == 0 && contentHint.length == 0) { gDYYYWardLocateDiag = @"commentID 为空"; return NO; }
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC || !commentVC.view) { gDYYYWardLocateDiag = @"评论区未打开"; return NO; }

    NSArray *lists = DYYYWardCommentListViews(commentVC);
    if (lists.count == 0) {
        gDYYYWardLocateDiag = [NSString stringWithFormat:@"未找到列表(%@)", NSStringFromClass([commentVC class])];
        return NO;
    }

    NSInteger totalVisible = 0;
    for (UIScrollView *scroll in lists) {
        NSArray *cells = nil;
        if ([scroll isKindOfClass:[UITableView class]]) {
            cells = [(UITableView *)scroll visibleCells];
        } else {
            cells = [(UICollectionView *)scroll visibleCells];
        }
        if (cells.count == 0) continue;
        totalVisible += cells.count;

        // ① cid 匹配
        if (commentID.length > 0) {
            for (id cell in cells) {
                if (![cell isKindOfClass:[UIView class]]) continue;
                NSString *cid = DYYYWardCommentIDOfCell(cell);
                if (cid.length == 0 || ![cid isEqualToString:commentID]) continue;
                DYYYWardScrollAndHighlight(scroll, cell);
                return YES;
            }
        }

        // ② 评论内容前缀兜底匹配：cell 文本常被截断，前缀从长到短逐级试
        if (contentHint.length >= 4) {
            NSArray *probeLens = contentHint.length > 12 ? @[ @12, @10, @8, @6 ] :
                                 (contentHint.length > 6 ? @[ @8, @6 ] : @[ @4 ]);
            for (NSNumber *lenNum in probeLens) {
                NSInteger len = [lenNum integerValue];
                if (len > contentHint.length) continue;
                NSString *probe = [contentHint substringToIndex:len];
                for (id cell in cells) {
                    if (![cell isKindOfClass:[UIView class]]) continue;
                    NSMutableArray *labels = [NSMutableArray array];
                    DYYYWardCollectCellLabels((UIView *)cell, 0, labels);
                    for (UILabel *l in labels) {
                        if (l.text.length > 0 && [l.text containsString:probe]) {
                            DYYYWardScrollAndHighlight(scroll, cell);
                            return YES;
                        }
                    }
                }
            }
        }
    }

    gDYYYWardLocateDiag = [NSString stringWithFormat:@"%ld 个列表可见 %ld 条无匹配", (long)lists.count, (long)totalVisible];
    return NO;
}

static NSInteger gDYYYWardLocateGen = 0;
static NSInteger gDYYYWardLocateDone = 0;

// 宿主内部定位：抖音自己支持「跳到指定评论」（安卓侧已验证该能力存在），
// 盲调白名单方法名；调用前用 NSMethodSignature 校验单对象参，防签名不匹配崩
// 在单个 target 上盲调白名单方法；调用前用 NSMethodSignature 校验单对象参，防签名不匹配崩
static BOOL DYYYWardTrySelectorsOnTarget(id target, NSArray *selNames, NSString *commentID) {
    if (!target) return NO;
    for (NSString *s in selNames) {
        SEL sel = NSSelectorFromString(s);
        if (![target respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [target methodSignatureForSelector:sel];
        if (!sig || sig.numberOfArguments != 3) continue; // 单对象参方法（self/_cmd/arg）
        const char *t = [sig getArgumentTypeAtIndex:2];
        if (!t || t[0] != '@') continue;
        @try {
            [target performSelector:sel withObject:commentID];
            return YES;
        } @catch (NSException *e) {}
    }
    return NO;
}

// 宿主内部定位：抖音自己支持「跳到指定评论」（安卓侧已验证），盲调白名单方法名
static void DYYYWardTryHostLocateComment(NSString *commentID) {
    if (commentID.length == 0) return;
    NSArray *clsNames = @[ @"AWECommentContainerViewController" ];
    NSArray *selNames = @[ @"scrollToCommentWithID:", @"scrollToCommentWithCommentID:", @"scrollToComment:",
                           @"locateComment:", @"focusComment:", @"highlightComment:", @"scrollToCommentWithCID:",
                           @"locateCommentWithCommentID:", @"scrollToCommentWithCommentID:animated:" ];
    for (NSString *clsName in clsNames) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;
        id target = DYYYWardFindVC(cls);
        if (!target) continue;
        if (DYYYWardTrySelectorsOnTarget(target, selNames, commentID)) {
            gDYYYWardLocateDone = gDYYYWardLocateGen;
            return;
        }
        // 定位能力也可能挂在 viewModel 上
        id vm = nil;
        @try { vm = [target valueForKey:@"viewModel"]; } @catch (NSException *e) { vm = nil; }
        if (vm && DYYYWardTrySelectorsOnTarget(vm, selNames, commentID)) {
            gDYYYWardLocateDone = gDYYYWardLocateGen;
            return;
        }
    }
}

// 把所有候选列表都滚一屏（评论列表是 6 个候选里的哪个不定，只滚第一个会滚错对象；
// up=NO 向下触发分页加载，YES 向上回头找漏掉的）
static void DYYYWardScrollCommentList(BOOL up) {
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC) return;
    for (UIScrollView *scroll in DYYYWardCommentListViews(commentVC)) {
        CGFloat h = CGRectGetHeight(scroll.bounds);
        if (h <= 0) continue;
        CGFloat maxOffset = scroll.contentSize.height - h;
        if (maxOffset < 0) maxOffset = 0;
        CGFloat y;
        if (up) {
            y = MAX(0, scroll.contentOffset.y - h * 0.8);
        } else {
            y = MIN(scroll.contentOffset.y + h * 0.8, maxOffset);
        }
        [scroll setContentOffset:CGPointMake(scroll.contentOffset.x, y) animated:YES];
    }
}

static void DYYYWardLocateComment(NSString *awemeID, NSString *commentID, NSString *contentHint) {
    (void)awemeID;
    gDYYYWardLocateGen++;
    NSInteger gen = gDYYYWardLocateGen;

    // 详情页起来后，如果评论区没自动开，就主动打开
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            DYYYWardOpenCommentPanelIfNeeded();
        } @catch (NSException *e) {}
    });

    // 滚动搜索：评论列表分页加载，目标评论常不在首屏可见区（cid 与内容匹配都只看 visibleCells）。
    // 每 1s 一步：先试宿主内部定位方法（抖音自身支持跳指定评论），
    // 再 cid/内容匹配当前可见 cell，失败就滚动一屏继续（前 8 步向下、后 4 步回头向上），
    // 滚动同时触发宿主加载更多评论。第 4 步起若仍失败先 toast 首因（不用等 12 秒），
    // 12 步全失败静默结束。
    for (NSInteger i = 0; i < 12; i++) {
        NSTimeInterval delay = 2.8 + i * 1.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen) return;
            @try {
                if (i == 0) {
                    DYYYWardTryHostLocateComment(commentID);
                    if (gDYYYWardLocateDone == gen) return;
                }
                if (DYYYWardHighlightComment(commentID, contentHint)) {
                    gDYYYWardLocateDone = gen;
                    return;
                }
                if (i == 3) {
                    [DYYYUtils showToast:[NSString stringWithFormat:@"评论定位失败：%@", gDYYYWardLocateDiag ?: @"未知原因"]];
                }
                if (i == 11) return;
                DYYYWardScrollCommentList(i >= 8); // 前 8 步向下，后 4 步向上回头
            } @catch (NSException *e) {}
        });
    }
}

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
    [self relayoutViews];
    [self reloadData];
}

// 导航栏下方起始，避免与标题/关闭按钮交叠
- (void)relayoutViews {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = CGRectGetMaxY(self.navigationController.navigationBar.frame);
    if (top < 20) top = 64; // nav bar 未布局时兜底（状态栏20+导航44）
    self.searchBar.frame = CGRectMake(0, top, w, 44);
    self.typeTabBar.frame = CGRectMake(0, top + 44, w, 44);
    self.categoryBar.frame = CGRectMake(0, top + 88, w, 40);
    self.sortSegment.frame = CGRectMake(w - 168, top + 134, 156, 30);
    self.tableView.frame = CGRectMake(0, top + 172, w, h - top - 172);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self relayoutViews];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// 从视频返回后，宿主 App（标准版/极速版）可能把导航栏隐藏了，这里强制恢复导航栏与关闭按钮
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    if (!self.navigationItem.rightBarButtonItem) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                                style:UIBarButtonItemStyleDone
                                                                               target:self
                                                                              action:@selector(close)];
    }
}

#pragma mark - 布局

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"搜索分类、备注、昵称、内容";
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

    // 点击列表空白处收回键盘（不拦截卡片点击/按钮）
    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resignSearchKeyboard)];
    bgTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:bgTap];
}

- (void)resignSearchKeyboard {
    if ([self.searchBar isFirstResponder]) {
        [self.searchBar resignFirstResponder];
    }
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
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@",
                            [ward objectForKey:@"nickname"] ?: @"",
                            [ward objectForKey:@"note"] ?: @"",
                            [ward objectForKey:@"category"] ?: @"",
                            [ward objectForKey:@"desc"] ?: @""];
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
            return [vb compare:va]; // saveTime 为时间戳(NSNumber)，倒序：最新在前
        }
        if ([va isKindOfClass:[NSString class]] && [vb isKindOfClass:[NSString class]]) {
            // createTime 为 yyyy-MM-dd HH:mm:ss 字符串，字典序即时间序；倒序，空串自然下沉
            return [vb compare:va];
        }
        return NSOrderedSame;
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

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.keyword = searchText;
    [self reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredWards.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 190;
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

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, 8, tableView.bounds.size.width - 24, 178)];
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

    // 视频文案 / 备注（两行）
    NSString *desc = [ward objectForKey:@"desc"] ?: @"";
    NSString *note = [ward objectForKey:@"note"] ?: @"";
    NSString *createTime = [ward objectForKey:@"createTime"] ?: @"";
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 78, card.bounds.size.width - 24, 34)];
    descLabel.font = [UIFont systemFontOfSize:12];
    descLabel.textColor = textColor;
    descLabel.numberOfLines = 2;
    descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    if (desc.length > 0) {
        descLabel.text = desc;
    } else if (note.length > 0) {
        descLabel.text = note;
    }
    [card addSubview:descLabel];

    // 视频时间（始终显示，不再被备注覆盖）
    UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 116, card.bounds.size.width - 24, 14)];
    timeLabel.font = [UIFont systemFontOfSize:11];
    timeLabel.textColor = subColor;
    timeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    if (createTime.length > 0) {
        timeLabel.text = [NSString stringWithFormat:@"视频：%@", createTime];
    }
    [card addSubview:timeLabel];

    // 备注（仅当文案与备注同时存在时另起一行，避免与文案重复）
    if (desc.length > 0 && note.length > 0) {
        UILabel *noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 132, card.bounds.size.width - 24, 14)];
        noteLabel.font = [UIFont systemFontOfSize:11];
        noteLabel.textColor = subColor;
        noteLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        noteLabel.text = [NSString stringWithFormat:@"备注：%@", note];
        [card addSubview:noteLabel];
    }

    // 操作按钮
    NSArray *actions = @[@"查看", @"编辑", @"复制", @"删除"];
    CGFloat btnW = (card.bounds.size.width - 24) / 4;
    for (NSInteger i = 0; i < actions.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(12 + i * btnW, 150, btnW, 20);
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

    // 点击卡片本体（非按钮区）直接跳转到插眼视频
    objc_setAssociatedObject(card, "wardIndex", @(indexPath.row), OBJC_ASSOCIATION_RETAIN);
    card.userInteractionEnabled = YES;
    UITapGestureRecognizer *cardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    cardTap.delegate = self;
    [card addGestureRecognizer:cardTap];

    return cell;
}

- (void)cardTapped:(UITapGestureRecognizer *)gesture {
    NSNumber *idxNum = objc_getAssociatedObject(gesture.view, "wardIndex");
    if (!idxNum) return;
    NSInteger idx = [idxNum integerValue];
    if (idx >= self.filteredWards.count) return;
    [self resignSearchKeyboard];
    [self openWard:self.filteredWards[idx]];
}

// 按钮区域不触发卡片跳转，避免与 编辑/复制/删除 重复响应
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UIButton class]]) return NO;
    return YES;
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

// 宿主 App 自己的 snssdk scheme：标准版 snssdk1128 / 极速版 snssdk2329 / TikTok snssdk1233
- (NSString *)hostSnssdkScheme {
    static NSString *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 按 bundle id 确定性映射
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSDictionary *map = @{@"com.ss.iphone.ugc.Aweme" : @"snssdk1128",
                              @"com.ss.iphone.ugc.aweme.lite" : @"snssdk2329"};
        cached = map[bid];
        // 兜底：读宿主 CFBundleURLTypes 第一个 snssdk 前缀 scheme
        if (cached.length == 0) {
            NSArray *urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
            for (NSDictionary *t in urlTypes) {
                if (![t isKindOfClass:[NSDictionary class]]) continue;
                NSArray *schemes = t[@"CFBundleURLSchemes"];
                if (![schemes isKindOfClass:[NSArray class]]) continue;
                for (NSString *s in schemes) {
                    if ([s isKindOfClass:[NSString class]] && [s hasPrefix:@"snssdk"]) {
                        cached = s;
                        break;
                    }
                }
                if (cached) break;
            }
        }
        if (cached.length == 0) cached = @"snssdk1128"; // 最终兜底：抖音标准版
    });
    return cached;
}

- (void)openWard:(NSDictionary *)ward {
    NSString *type = [ward objectForKey:@"type"];
    if (![type isKindOfClass:[NSString class]]) type = @"视频";
    NSString *awemeID = [ward objectForKey:@"awemeID"];
    if (![awemeID isKindOfClass:[NSString class]]) awemeID = @"";

    // 主页插眼：直接跳该用户主页
    if ([type isEqualToString:@"主页"]) {
        NSString *secUid = [ward objectForKey:@"secUid"];
        if (![secUid isKindOfClass:[NSString class]]) secUid = @"";
        NSString *uid = [ward objectForKey:@"uid"];
        if (![uid isKindOfClass:[NSString class]]) uid = @"";
        NSString *idValue = secUid.length > 0 ? secUid : uid;
        if (idValue.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://user/profile/%@", [self hostSnssdkScheme], idValue]];
            if (url && [[UIApplication sharedApplication] openURL:url]) return;
        }
        NSString *share = [ward objectForKey:@"shareURL"];
        if (![share isKindOfClass:[NSString class]] || share.length == 0) {
            if (secUid.length > 0) {
                share = [NSString stringWithFormat:@"https://www.douyin.com/user/%@", secUid];
            } else if (uid.length > 0) {
                // secUid 缺失时用 share/user 兜底（浏览器/宿主 webview 可打开）
                share = [NSString stringWithFormat:@"https://www.douyin.com/share/user/%@", uid];
            } else {
                share = @"";
            }
        }
        if (share.length > 0) {
            [UIPasteboard generalPasteboard].string = share;
            [DYYYUtils showToast:@"已复制主页链接"];
        } else {
            [DYYYUtils showToast:@"无主页信息"];
        }
        return;
    }

    // 评论插眼：跳到作品并直接开评论区，再尽量定位到这条评论
    if ([type isEqualToString:@"评论"]) {
        NSString *commentID = [ward objectForKey:@"commentID"];
        if (![commentID isKindOfClass:[NSString class]]) commentID = @"";
        NSString *contentHint = [ward objectForKey:@"desc"];
        if (![contentHint isKindOfClass:[NSString class]]) contentHint = @"";
        if (awemeID.length == 0) {
            [DYYYUtils showToast:@"无视频信息，已复制链接"];
            NSString *url = [ward objectForKey:@"shareURL"];
            if ([url isKindOfClass:[NSString class]] && url.length > 0) [UIPasteboard generalPasteboard].string = url;
            return;
        }
        // 优先带 comment_id：宿主自身支持「跳到指定评论」（安卓侧已验证），
        // 只传 comment=1 只能展开评论区、不能定位到具体某条
        NSString *base = [NSString stringWithFormat:@"%@://aweme/detail/%@?refer=web&gd_label=click_wap",
                          [self hostSnssdkScheme], awemeID];
        BOOL ok = NO;
        if (commentID.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@&comment_id=%@", base, commentID]];
            ok = url && [[UIApplication sharedApplication] openURL:url];
        }
        if (!ok) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@&comment=1", base]];
            ok = url && [[UIApplication sharedApplication] openURL:url];
        }
        if (!ok) {
            NSURL *url = [NSURL URLWithString:base];
            ok = url && [[UIApplication sharedApplication] openURL:url];
        }
        if (!ok) {
            NSString *share = [NSString stringWithFormat:@"https://www.douyin.com/video/%@", awemeID];
            [UIPasteboard generalPasteboard].string = share;
            [DYYYUtils showToast:@"已复制视频链接"];
            return;
        }
        DYYYWardLocateComment(awemeID, commentID, contentHint);
        return;
    }

    if (awemeID.length == 0) {
        [DYYYUtils showToast:@"无视频信息，已复制链接"];
        NSString *url = [ward objectForKey:@"shareURL"];
        if ([url isKindOfClass:[NSString class]] && url.length > 0) [UIPasteboard generalPasteboard].string = url;
        return;
    }

    // 路由必须用 path 形态：极速版仅注册 aweme/detail/<id>，
    // 查询串形态（?aweme_id=）匹配不到路由会落"外部链接"兜底弹风险提示
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://aweme/detail/%@?refer=web&gd_label=click_wap", [self hostSnssdkScheme], awemeID]];
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
