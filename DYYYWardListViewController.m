#import "DYYYWardListViewController.h"
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
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
static NSInteger gDYYYWardGraphStrCount = 0; // 本次定位扫过的字符串数（诊断用：0 表示根本没扫到内容）

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

// 安全取值：优先读同名对象类型 ivar；其次是返回类型为对象的 getter；字典走 objectForKey。
// 只有确认是对象类型才允许 KVC —— valueForKey: 撞上结构体/裸指针/数组/位域属性会直接
// SIGSEGV，@try 抓不住。key 不存在时 valueForKey: 会抛 NSUnknownKeyException，也被挡掉。
static id DYYYWardSafeKVC(id obj, NSString *key);
static BOOL DYYYWardGraphMatch(id node, NSArray *cidList, NSString *probe, NSInteger depth, NSInteger *budget);
static void DYYYWardSweepStep(UITableView *t, NSArray *cidList, NSString *contentHint, NSInteger gen,
                              NSInteger flat, NSInteger total, NSInteger pageTry, NSInteger token);
static void DYYYWardSweepRows(NSArray *cidList, NSString *contentHint, NSInteger gen);
static NSInteger gDYYYWardSweepGen = 0; // 正在按行扫描的 gen（扫描期间跳过渐进滚动，防两者互相打架）
static NSInteger gDYYYWardSweepToken = 0; // 扫描令牌：取消时自增，已在排队的旧步骤一检查就自行退出
static NSInteger gDYYYWardFailCount = 0; // 连续定位失败次数：第 1 次只报人话，第 2 次才附完整诊断

// v2.3-23：旧的「按字段名猜 cid」(DYYYWardCIDOf / DYYYWardCommentIDOfCell) 已删除，
// 改用 DYYYWardGraphMatch 在 cell 对象图里按值搜（见下方），不再依赖任何私有字段名——
// 这是安卓无障碍(AccessibilityService)在 UI 树里按文本找的 iOS 等价做法。

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

// 收集所有「看起来是评论区」且 view 在窗口上的 VC 实例。
// 评论区可能同时存在多个实例（导航栈里的旧页、被覆盖的页面），只取第一个遇到旧实例
// （viewModel 还没赋值）就会彻底放弃调用宿主方法 —— v2.4-1 之前就是这么失效的。
static void DYYYWardCollectCommentVCs(UIViewController *vc, NSInteger depth, NSMutableArray *out) {
    if (!vc || depth > 8 || out.count > 12) return;
    NSString *cls = NSStringFromClass([vc class]);
    BOOL looks = cls.length > 0 && [cls containsString:@"Comment"] &&
                 ![cls containsString:@"Input"] && ![cls containsString:@"Keyboard"] &&
                 ![cls containsString:@"Edit"] && ![cls containsString:@"Panel"] &&
                 ![cls containsString:@"Bar"];
    if (looks && vc.isViewLoaded && vc.view.window && ![out containsObject:vc]) [out addObject:vc];
    for (UIViewController *c in vc.childViewControllers) DYYYWardCollectCommentVCs(c, depth + 1, out);
    if (vc.presentedViewController) DYYYWardCollectCommentVCs(vc.presentedViewController, depth + 1, out);
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *c in [(UINavigationController *)vc viewControllers]) DYYYWardCollectCommentVCs(c, depth + 1, out);
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController *sel = [(UITabBarController *)vc selectedViewController];
        if (sel) DYYYWardCollectCommentVCs(sel, depth + 1, out);
    }
}

static NSArray *DYYYWardAllCommentVCs(void) {
    NSMutableArray *out = [NSMutableArray array];
    UIWindow *w = [DYYYUtils getActiveWindow];
    if (w.rootViewController) DYYYWardCollectCommentVCs(w.rootViewController, 0, out);
    if (out.count == 0) {
        UIViewController *one = DYYYWardFindCommentVC(); // 兜底：沿用旧的单实例查找
        if (one) [out addObject:one];
    }
    return out;
}

// 滚动到 cell 并高亮（P3：左侧 4pt 竖向色条 + 整框细描边，呼吸两次后保留约 3s 再淡出）。
// 密集列表里整框描边不够醒目，左侧色条能一眼扫到；呼吸用 keyframe 做，
// 避免 repeat 动画与最后一次淡出抢同一属性（会出现高亮不消失/瞬间闪掉）。
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
    UIColor *tint = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
    UIView *highlight = [[UIView alloc] initWithFrame:cellView.bounds];
    highlight.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    highlight.backgroundColor = [UIColor clearColor];
    highlight.userInteractionEnabled = NO;
    highlight.tag = 20261022;
    highlight.layer.borderColor = [tint colorWithAlphaComponent:0.85].CGColor;
    highlight.layer.borderWidth = 1.5;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, CGRectGetHeight(cellView.bounds))];
    bar.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    bar.backgroundColor = tint;
    bar.tag = 20261023;
    [highlight addSubview:bar];
    highlight.alpha = 0.0;
    [cellView addSubview:highlight];
    [UIView animateWithDuration:0.18 animations:^{ highlight.alpha = 1.0; }];
    // 两次呼吸（各 0.9s），结束后保持全亮
    [UIView animateKeyframesWithDuration:1.8 delay:0.2 options:UIViewKeyframeAnimationOptionAllowUserInteraction animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.00 relativeDuration:0.25 animations:^{ highlight.alpha = 0.45; }];
        [UIView addKeyframeWithRelativeStartTime:0.25 relativeDuration:0.25 animations:^{ highlight.alpha = 1.00; }];
        [UIView addKeyframeWithRelativeStartTime:0.50 relativeDuration:0.25 animations:^{ highlight.alpha = 0.45; }];
        [UIView addKeyframeWithRelativeStartTime:0.75 relativeDuration:0.25 animations:^{ highlight.alpha = 1.00; }];
    } completion:nil];
    // 约 3.2s 后淡出移除
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            highlight.alpha = 0.0;
        } completion:^(BOOL finished) {
            [highlight removeFromSuperview];
        }];
    });
}

// 评论正文可能含表情短码（如 [看]/[泣不成声]），屏幕上渲染成表情图或不同字符，
// 直接 containsString 必然失败 → 生成 probe 时截掉第一个 '[' / '［' 及其后内容；
// 截完太短再退回原串前 4 字。
static NSString *DYYYWardContentProbe(NSString *content, NSInteger maxLen) {
    if (content.length < 4) return nil;
    NSString *base = content;
    NSUInteger cut = base.length;
    NSRange a = [base rangeOfString:@"["];
    NSRange b = [base rangeOfString:@"［"];
    if (a.location != NSNotFound) cut = MIN(cut, a.location);
    if (b.location != NSNotFound) cut = MIN(cut, b.location);
    if (cut >= 4) base = [base substringToIndex:cut];
    if (base.length > (NSUInteger)maxLen) base = [base substringToIndex:(NSUInteger)maxLen];
    if (base.length < 4) base = [content substringToIndex:MIN((NSUInteger)4, content.length)];
    return base.length >= 4 ? base : nil;
}

// P0：便宜的先查。cell 上真正「能被人看到」的正文只会出现在 UILabel/UITextView 的文本
// 或 accessibilityLabel/Value 里，爬整棵对象图（depth 8 / budget 1500）对一行 cell 是几万次对象访问，
// 148 行逐行这么做要几十秒。先做这一步，命中率已经很高，只在完全没命中时才退化到全图搜。
static BOOL DYYYWardTextContains(NSString *hay, NSString *probe) {
    if (hay.length == 0 || probe.length == 0) return NO;
    if (hay.length >= probe.length) return [hay rangeOfString:probe].location != NSNotFound;
    return NO;
}

static BOOL DYYYWardCellQuickMatch(id cell, NSString *probe) {
    if (!cell || probe.length == 0) return NO;
    if (![cell isKindOfClass:[UIView class]]) return NO;
    UIView *root = (UIView *)cell;
    // 无障碍标签（等价于安卓无障碍读取，最省）
    if (DYYYWardTextContains(root.accessibilityLabel, probe)) return YES;
    if (DYYYWardTextContains(root.accessibilityValue, probe)) return YES;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < 260) {
        UIView *cur = [stack lastObject];
        [stack removeLastObject];
        visited++;
        if (cur != root) {
            if (DYYYWardTextContains(cur.accessibilityLabel, probe)) return YES;
            if (DYYYWardTextContains(cur.accessibilityValue, probe)) return YES;
        }
        if ([cur isKindOfClass:[UILabel class]]) {
            UILabel *lb = (UILabel *)cur;
            if (DYYYWardTextContains(lb.text, probe)) return YES;
            if (DYYYWardTextContains(lb.attributedText.string, probe)) return YES;
        } else if ([cur isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)cur;
            if (DYYYWardTextContains(tv.text, probe)) return YES;
            if (DYYYWardTextContains(tv.attributedText.string, probe)) return YES;
        }
        [stack addObjectsFromArray:cur.subviews];
    }
    return NO;
}

// 在评论列表可见 cell 里找 cid 匹配的评论；cid 字段名各版本不一致时，
// 再用评论内容前缀兜底匹配 cell 里的 label 文本（前缀逐级缩短，兼容 cell 文本被截断）。
// 滚动过去并闪一下高亮框。列表类型/嵌套不定，逐个候选列表试。
// cidList：插眼时保存的所有候选 cid（含 commentID），逐个比对，避免字段名不一致匹配不上；
// contentHint：评论内容，cid 匹配不上时用其前缀匹配 cell 文本（前缀逐级缩短兼容截断）。
// 列表类型/嵌套不定，逐个候选列表试。
static BOOL DYYYWardHighlightComment(NSArray *cidList, NSString *contentHint) {
    if (cidList.count == 0 && contentHint.length == 0) { gDYYYWardLocateDiag = @"commentID 为空"; return NO; }
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC || !commentVC.view) { gDYYYWardLocateDiag = @"评论区未打开"; return NO; }

    NSArray *lists = DYYYWardCommentListViews(commentVC);
    if (lists.count == 0) {
        gDYYYWardLocateDiag = [NSString stringWithFormat:@"未找到列表(%@)", NSStringFromClass([commentVC class])];
        return NO;
    }

    NSInteger totalVisible = 0;
    NSString *firstCid = nil;
    for (id c in cidList) { if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 0) { firstCid = (NSString *)c; break; } }
    NSString *probe = DYYYWardContentProbe(contentHint, 10); // 自动裁掉 [看] 等表情短码
    gDYYYWardGraphStrCount = 0;
    NSString *firstCellCls = nil;

    for (UIScrollView *scroll in lists) {
        NSArray *cells = nil;
        if ([scroll isKindOfClass:[UITableView class]]) {
            cells = [(UITableView *)scroll visibleCells];
        } else {
            cells = [(UICollectionView *)scroll visibleCells];
        }
        if (cells.count == 0) continue;
        totalVisible += cells.count;
        if (!firstCellCls) { id fc = cells.firstObject; if (fc) firstCellCls = NSStringFromClass([fc class]); }

        // ① 快速路径（P0）：先在 label/无障碍文本上做便宜匹配，再用 cid 复核；
        //    命中即返回，避免对每个 cell 都爬一遍对象图。
        if (probe.length > 0) {
            for (id cell in cells) {
                if (![cell isKindOfClass:[UIView class]]) continue;
                if (!DYYYWardCellQuickMatch(cell, probe)) continue;
                if (cidList.count > 0) {
                    NSInteger budget = 1200;
                    if (!DYYYWardGraphMatch(cell, cidList, nil, 8, &budget)) continue; // 正文撞车，不是这条
                }
                DYYYWardScrollAndHighlight(scroll, cell);
                [DYYYUtils showToast:[NSString stringWithFormat:@"已定位：%@", probe]];
                return YES;
            }
        }

        // ② cid 精确：在 cell 对象图里搜「值等于目标 cid」的字符串（不看私有字段名）
        if (cidList.count > 0) {
            for (id cell in cells) {
                if (![cell isKindOfClass:[UIView class]]) continue;
                NSInteger budget = 1500;
                if (DYYYWardGraphMatch(cell, cidList, nil, 8, &budget)) {
                    DYYYWardScrollAndHighlight(scroll, cell);
                    [DYYYUtils showToast:@"已定位到该评论"];
                    return YES;
                }
            }
        }

        // ③ 评论正文片段兜底：在 cell 对象图里搜「包含正文片段」的字符串（UILabel/富文本/任意 ivar 字符串）
        if (probe.length > 0) {
            for (id cell in cells) {
                if (![cell isKindOfClass:[UIView class]]) continue;
                NSInteger budget = 1500;
                if (DYYYWardGraphMatch(cell, @[], probe, 8, &budget)) {
                    DYYYWardScrollAndHighlight(scroll, cell);
                    [DYYYUtils showToast:@"已定位到该评论"];
                    return YES;
                }
            }
        }
    }

    NSString *cidTail = firstCid ? [firstCid substringToIndex:MIN(10, firstCid.length)] : @"(空)";
    gDYYYWardLocateDiag = [NSString stringWithFormat:@"%ld列表可见%ld条无匹配 cid:%@ 内容:%@ 扫描%ld串 首cell:%@",
                           (long)lists.count, (long)totalVisible, cidTail, probe ?: @"(空)",
                           (long)gDYYYWardGraphStrCount, firstCellCls ?: @"(无)"];
    return NO;
}

// MARK: - 数据源定位
// 只匹配「可见 cell」的致命短板：目标评论在第几百条时根本不在首屏，滚动几屏也覆盖不到。
// 改从列表 dataSource 的模型数组里直接算出目标评论的下标，再滚到对应 indexPath，
// 滚完后取该 indexPath 的 cell 复核（算错也不会误高亮）。
static NSInteger gDYYYWardLocateGen = 0;
static NSInteger gDYYYWardLocateDone = 0;
static NSInteger gDYYYWardLocatePending = 0; // 数据源已精确滚到目标下标，勿再滚动列表（否则把定位到的评论滚走）
static NSString *gDYYYWardDataSourceDiag = nil;

// ⚠️ 本段一律禁用裸 valueForKey:。在陌生宿主对象上做 KVC，遇到结构体/裸指针/数组/位域
// 类型的属性会直接 SIGSEGV/SIGBUS，@try/@catch 抓不住信号（v2.3-19 就是这样闪退的）。
// ⚠️ 同理，对反射取出的 id 也不能直接发消息（isKindOfClass: 等）：type encoding 标 '@'
// 但实际存的是 C++ 指针/数据时，第一次 msgSend 就会跳进垃圾地址 —— 崩溃报告表现为
// "called through a pointer whose authentication code was invalid"（v2.3-20 的 SIGBUS）。
// 所有反射取出的值必须先过 DYYYWardLooksLikeObject（只读 isa + 查类表，不执行任何代码）。

// 伪对象探测：读 isa 并确认它在 ObjC 运行时注册过。全程只有内存读取与查表，
// 不发送消息、不执行未知代码，因此不会触发 PAC/SIGBUS。
//
// ⚠️ v2.4-0 崩溃根因（真机 SIGBUS / KERN_PROTECTION_FAILURE @0x3300003630393938）：
//   tagged pointer 判据写成了 `bits >> 60`，等于「最高 4 位非 0 就当 tagged pointer 放行」。
//   Swift 的内联字符串/小结构体把内容直接塞在 8 字节里，位模式形如 0x3300003630393938
//   （字节恰好是 ASCII 数字），最高 4 位是 0x3 → 被误判为合法对象放行 → 调用方 isKindOfClass:
//   对它发消息 → 运行时按普通对象去解引用 isa → 该地址未映射 → SIGBUS，崩溃地址就是这个位模式。
// 正确判据只有 bit63（arm64 tagged pointer 约定）。另外加了「用户态地址窗口」粗筛 +
// mach_vm_read_overwrite 安全读 isa（绝不直接解引用候选指针）+ 已注册类表比对，三层兜住。
static BOOL DYYYWardLooksLikeObject(id v);

// 运行时已注册类（含元类）集合：isa 只能命中真正存在的类，否则一律判为伪对象。
// 用裸指针开放寻址哈希表，避免把候选指针当对象（CF/NSValue 包装都可能产生需要解引用的操作）。
static uintptr_t *gDYYYWardClassSet = NULL;
static size_t gDYYYWardClassSetCap = 0;

static size_t DYYYWardClassHash(uintptr_t v) {
    return (size_t)(((v >> 4) ^ (v >> 20)) * 2654435761u);
}

static void DYYYWardBuildClassSet(void) {
    if (gDYYYWardClassSet) return;
    int n = objc_getClassList(NULL, 0);
    if (n <= 0) return;
    Class *buf = (Class *)malloc(sizeof(Class) * (size_t)n);
    if (!buf) return;
    n = objc_getClassList(buf, n);
    size_t cap = 16;
    while (cap < (size_t)n * 4) cap <<= 1;
    uintptr_t *set = (uintptr_t *)calloc(cap, sizeof(uintptr_t));
    if (!set) { free(buf); return; }
    for (int i = 0; i < n; i++) {
        uintptr_t vals[2] = { (uintptr_t)buf[i], (uintptr_t)object_getClass(buf[i]) };
        for (int k = 0; k < 2; k++) {
            uintptr_t cv = vals[k];
            if (!cv) continue;
            size_t h = DYYYWardClassHash(cv) & (cap - 1);
            for (size_t p = 0; p < cap; p++) {
                size_t idx = (h + p) & (cap - 1);
                if (set[idx] == 0) { set[idx] = cv; break; }
                if (set[idx] == cv) break;
            }
        }
    }
    free(buf);
    gDYYYWardClassSetCap = cap;
    gDYYYWardClassSet = set;
}

static BOOL DYYYWardIsRegisteredClass(uintptr_t isa) {
    if (!gDYYYWardClassSet) return NO;
    size_t cap = gDYYYWardClassSetCap;
    size_t h = DYYYWardClassHash(isa) & (cap - 1);
    for (size_t p = 0; p < 64; p++) {
        uintptr_t cur = gDYYYWardClassSet[(h + p) & (cap - 1)];
        if (cur == 0) return NO;    // 开放寻址：遇到空槽就是不存在
        if (cur == isa) return YES;
    }
    return NO;
}

// 安全读 8 字节：用内核拷出，地址非法时返回 KERN_INVALID_ADDRESS 而不是让本进程崩
static BOOL DYYYWardSafeReadPtr(uintptr_t addr, uintptr_t *out) {
    if (!out) return NO;
    mach_vm_size_t got = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr,
                                              sizeof(uintptr_t), (mach_vm_address_t)(uintptr_t)out, &got);
    return (kr == KERN_SUCCESS && got == sizeof(uintptr_t));
}

static BOOL DYYYWardLooksLikeObject(id v) {
    if (!v) return NO;
    uintptr_t bits = (uintptr_t)v;
    // tagged pointer：arm64 约定只看 bit63（短 NSString/NSNumber）。绝不能用 bits>>60：
    // 0x3 开头的伪指针会被当成 tagged 放行，随后 msgSend 直接崩（v2.4-0 的真机崩溃）。
    if (bits & 0x8000000000000000ULL) return YES;
    if (bits < 0x100000000ULL) return NO;          // 低于 4GB 不可能是堆/缓存对象
    if (bits > 0x0000FFFFFFFFFFFFULL) return NO;   // 超出用户态窗口 = 内联字符串/结构体位模式
    if (bits & 0x7) return NO;                     // 必须 8 字节对齐
    DYYYWardBuildClassSet();
    uintptr_t isa = 0;
    if (!DYYYWardSafeReadPtr(bits, &isa)) return NO; // 地址不可读 → 伪对象
    if (!isa) return NO;
    return DYYYWardIsRegisteredClass(isa);           // isa 必须是运行时注册过的类
}

// type encoding 首字符为 '@' 即对象槽，允许裸 '@'（generic id）——**Swift 存储属性几乎都是裸 '@'**，
// 之前只认 '@"ClassName"' 导致 Swift 的模型/数组 ivar 全被跳过（v2.3-24 仍「数据源0数组」的真因）。
// 裸 '@' 槽可能存 C++ 指针/裸数据，但**所有读取点**都会先过 DYYYWardLooksLikeObject 做零代码执行
// 合法性探测（读 isa + 查类表）再发消息，所以放宽安全——v2.3-21 的崩溃是「没探测就 isKindOfClass」，不是读本身。
static BOOL DYYYWardIvarTypeIsDeclaredObject(const char *t) {
    return t && t[0] == '@';
}

// 按名字取对象 ivar（含 `_` 前缀，沿继承链向上最多 4 层）
// 结果按「类 + 键」缓存：扫 ivar 列表不便宜，上千条评论逐个探测时会明显卡主线程
static NSMutableDictionary *gDYYYWardIvarCache = nil;

static id DYYYWardIvarNamed(id obj, NSString *name) {
    if (!obj || name.length == 0) return nil;
    Class startCls = object_getClass(obj);
    if (!gDYYYWardIvarCache) gDYYYWardIvarCache = [NSMutableDictionary dictionary];
    NSString *cacheKey = [NSString stringWithFormat:@"%p|%@", (void *)startCls, name];
    id cached = [gDYYYWardIvarCache objectForKey:cacheKey];
    if (cached) {
        if ([cached isKindOfClass:[NSNull class]]) return nil;
        Ivar cv = (Ivar)[(NSValue *)cached pointerValue];
        id v = object_getIvar(obj, cv);
        return DYYYWardLooksLikeObject(v) ? v : nil;
    }
    NSString *want = name;
    NSString *wantUnderscore = [@"_" stringByAppendingString:name];
    Class cls = startCls;
    for (NSInteger depth = 0; cls && depth < 4; depth++) {
        unsigned int ic = 0;
        Ivar *ivars = class_copyIvarList(cls, &ic);
        Ivar hit = NULL;
        id found = nil;
        for (unsigned int i = 0; i < ic && !hit; i++) {
            const char *n = ivar_getName(ivars[i]);
            const char *t = ivar_getTypeEncoding(ivars[i]);
            if (!DYYYWardIvarTypeIsDeclaredObject(t)) continue;
            if (!n) continue;
            NSString *cn = [NSString stringWithUTF8String:n];
            if (!cn) continue;
            if (![cn isEqualToString:want] && ![cn isEqualToString:wantUnderscore]) continue;
            // 关键：名字命中即认定「找到了这个 ivar」，哪怕此刻值还是 nil。
            // 之前把「值为 nil」也当成「没这个 ivar」并缓存 NSNull，于是第一次调用（评论面板刚起、
            // viewModel 还没赋值）就把该类永久标记成「没有 viewModel」，后面再也不会去找——
            // 表现就是诊断里 VM:/vm方法: 整段消失、宿主定位方法一次都不调用（v2.4-1 修）。
            hit = ivars[i];
            id v = object_getIvar(obj, ivars[i]);
            if (DYYYWardLooksLikeObject(v)) found = v;
        }
        if (ivars) free(ivars);
        if (hit) {
            [gDYYYWardIvarCache setObject:[NSValue valueWithPointer:(void *)hit] forKey:cacheKey];
            return found;
        }
        cls = class_getSuperclass(cls);
    }
    [gDYYYWardIvarCache setObject:[NSNull null] forKey:cacheKey];
    return nil;
}

// 见上方声明：确认是对象类型才允许 KVC
static id DYYYWardSafeKVC(id obj, NSString *key) {
    if (!obj || key.length == 0) return nil;
    if ([obj isKindOfClass:[NSDictionary class]]) return [(NSDictionary *)obj objectForKey:key];
    id v = DYYYWardIvarNamed(obj, key);
    if (v) return v;
    SEL sel = NSSelectorFromString(key);
    Method m = class_getInstanceMethod(object_getClass(obj), sel);
    if (!m) return nil;
    char rt[64];
    method_getReturnType(m, rt, sizeof(rt));
    if (rt[0] != '@') return nil; // 非对象返回值：KVC 可能按标量/结构体处理，直接放弃
    @try {
        id r = [obj valueForKey:key];
        return DYYYWardLooksLikeObject(r) ? r : nil;
    } @catch (NSException *e) { return nil; }
}

// v2.3-23：不再猜私有字段名，直接在「对象图」里按值搜——这是安卓无障碍(AccessibilityService)
// 在 UI 树里按文本找的 iOS 等价做法：iOS 无无障碍，但 tweak 有运行时权限，可从 cell 出发递归扫
// ivar + 子视图 + UILabel.text + 富文本，命中「值等于目标 cid」或「包含评论正文片段」即定位。
// 不碰任何私有字段名，因此与极速版字段布局无关；所有取值都过 DYYYWardLooksLikeObject 防伪对象。
static NSMutableDictionary *gDYYYWardGraphIvarsCache = nil;

static NSArray *DYYYWardObjectIvars(Class cls) {
    if (!cls) return nil;
    if (!gDYYYWardGraphIvarsCache) gDYYYWardGraphIvarsCache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromClass(cls);
    NSArray *cached = [gDYYYWardGraphIvarsCache objectForKey:key];
    if (cached) return cached;
    NSMutableArray *out = [NSMutableArray array];
    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic); // ivar* 指向类元数据，长期有效；数组不 free
    for (unsigned int i = 0; i < ic; i++) {
        const char *t = ivar_getTypeEncoding(ivars[i]);
        // 允许裸 '@'（Swift 存储属性）——读值后由 DYYYWardLooksLikeObject 统一验真，安全
        if (t && t[0] == '@') [out addObject:[NSValue valueWithPointer:(void *)ivars[i]]];
    }
    [gDYYYWardGraphIvarsCache setObject:out forKey:key];
    return out;
}

// 跳过的 ivar：避免爬出 cell 进入 App 全局图（responder/delegate/VC）或陷入 layer 环
static BOOL DYYYWardSkipIvar(NSString *name) {
    if (!name) return YES;
    static NSSet *skip = nil;
    if (!skip) skip = [NSSet setWithObjects:@"nextResponder", @"responder", @"delegate", @"target",
                          @"dataSource", @"gestureRecognizers", @"superview", @"layer",
                          @"_nextResponder", @"_responder", @"_delegate", @"_target", @"_dataSource",
                          @"_gestureRecognizers", @"_superview", @"_layer", @"window", @"_window", nil];
    return [skip containsObject:name];
}

static BOOL DYYYWardGraphMatch(id node, NSArray *cidList, NSString *probe, NSInteger depth, NSInteger *budget) {
    if (!node || depth < 0 || *budget <= 0) return NO;
    (*budget)--;
    if ([node isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)node;
        gDYYYWardGraphStrCount++;
        if (s.length == 0 || s.length > 4000) return NO;
        if (cidList.count > 0) {
            for (id c in cidList) {
                if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 4 && [s isEqualToString:(NSString *)c]) return YES;
            }
        }
        if (probe.length > 0 && [s containsString:probe]) return YES;
        return NO;
    }
    if ([node isKindOfClass:[NSNumber class]]) {
        if (cidList.count > 0) {
            NSString *s = [node stringValue];
            if (s.length >= 10) { // 只比对长数字（cid 多为 19 位），避免时间戳/计数误中
                for (id c in cidList) {
                    if ([c isKindOfClass:[NSString class]] && [s isEqualToString:(NSString *)c]) return YES;
                }
            }
        }
        return NO;
    }
    if ([node isKindOfClass:[NSAttributedString class]]) {
        NSString *s = [(NSAttributedString *)node string];
        gDYYYWardGraphStrCount++;
        if (s.length > 0 && s.length <= 4000) {
            for (id c in cidList) {
                if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 4 && [s isEqualToString:(NSString *)c]) return YES;
            }
            if (probe.length > 0 && [s containsString:probe]) return YES;
        }
        return NO;
    }
    if ([node isKindOfClass:[UILabel class]]) {
        NSString *s = [(UILabel *)node text];
        gDYYYWardGraphStrCount++;
        if (s.length > 0 && s.length <= 4000) {
            for (id c in cidList) {
                if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 4 && [s isEqualToString:(NSString *)c]) return YES;
            }
            if (probe.length > 0 && [s containsString:probe]) return YES;
        }
        return NO; // UILabel 内容即 text，无需再走 ivar
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)node;
        if (d.count > 200) return NO;
        for (id v in d.allValues) { if (DYYYWardGraphMatch(v, cidList, probe, depth - 1, budget)) return YES; }
        return NO;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        NSArray *a = (NSArray *)node;
        if (a.count > 300) return NO;
        for (id v in a) { if (DYYYWardGraphMatch(v, cidList, probe, depth - 1, budget)) return YES; }
        return NO;
    }
    if ([node isKindOfClass:[NSSet class]] || [node isKindOfClass:[NSOrderedSet class]]) {
        NSArray *a = [(NSSet *)node allObjects];
        if (a.count > 300) return NO;
        for (id v in a) { if (DYYYWardGraphMatch(v, cidList, probe, depth - 1, budget)) return YES; }
        return NO;
    }
    if ([node isKindOfClass:[UIView class]]) {
        UIView *uv = (UIView *)node;
        // ① 直接读常见文本属性：覆盖 UILabel 之外的 YYLabel/UITextView/自定义标签；
        //    accessibilityLabel 正是安卓 AccessibilityService 在 UI 树里读的东西——最贴近「按内容找」
        for (NSString *k in @[ @"text", @"attributedText", @"accessibilityLabel", @"accessibilityValue" ]) {
            id tv = DYYYWardSafeKVC(uv, k); // 已按返回类型 '@' 过滤，非对象 getter 不会调用
            if (tv && DYYYWardLooksLikeObject(tv) && DYYYWardGraphMatch(tv, cidList, probe, depth, budget)) return YES;
        }
        // ② 子视图
        for (UIView *sub in uv.subviews) {
            if (DYYYWardGraphMatch(sub, cidList, probe, depth - 1, budget)) return YES;
        }
        // ③ 继续走 ivar（拿 cell 上挂的模型对象）
    }
    // 普通对象：扫对象类型 ivar（skip 列表里的不碰，避免爬向 App 全局图 / layer 环）
    Class cls = object_getClass(node);
    NSArray *ivars = DYYYWardObjectIvars(cls);
    for (NSValue *iv in ivars) {
        NSString *nm = [NSString stringWithUTF8String:ivar_getName((Ivar)[iv pointerValue])];
        if (DYYYWardSkipIvar(nm)) continue;
        Ivar v = (Ivar)[iv pointerValue];
        id val = object_getIvar(node, v);
        if (DYYYWardLooksLikeObject(val) && DYYYWardGraphMatch(val, cidList, probe, depth - 1, budget)) return YES;
    }
    return NO;
}

// 取对象的评论文本（各版本字段名不一致）
static NSString *DYYYWardTextOfModel(id obj) {
    if (!obj) return nil;
    for (NSString *k in @[ @"content", @"text", @"commentContent", @"contentText", @"commentText", @"desc", @"description" ]) {
        id v = DYYYWardIvarNamed(obj, k);
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return (NSString *)v;
    }
    return nil;
}

// 取对象的 cid（可能是 NSString 或 NSNumber）
static NSString *DYYYWardCIDOfModel(id obj) {
    if (!obj) return nil;
    for (NSString *k in @[ @"cid", @"commentID", @"commentId", @"comment_id", @"id" ]) {
        id v = DYYYWardIvarNamed(obj, k);
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return (NSString *)v;
        if ([v isKindOfClass:[NSNumber class]]) {
            NSString *s = [(NSNumber *)v stringValue];
            if (s.length > 0) return s;
        }
    }
    return nil;
}

// 取出对象里「名字像模型数组缓存」的 NSArray ivar（沿继承链向上最多 3 层）。
// 只读名字命中白名单的 ivar：对任意 '@' ivar 取值再发消息是 v2.3-20 的闪退来源，
// 名字不像数组缓存的一律不碰，风险面收敛到几乎为零。
static NSArray *DYYYWardModelArraysIn(id obj) {
    NSMutableArray *out = [NSMutableArray array];
    if (!obj) return out;
    NSArray *nameWhitelist = @[ @"dataArray", @"dataArr", @"comments", @"commentArray", @"commentList",
                                @"commentModels", @"commentDataArray", @"models", @"cellModels",
                                @"viewModels", @"items", @"itemModels", @"listData", @"elements",
                                @"sectionModels", @"commentData", @"visibleCommentModels",
                                @"listModels", @"dataSource", @"sections", @"contentModels",
                                @"commentSectionModels", @"dataModels", @"modelList" ];
    // 名字启发式：含这些片段的 ivar 多半是集合缓存。只收集真正的 NSArray，
    // 伪对象已被 DYYYWardLooksLikeObject 挡掉，扩名不会引入崩溃风险
    // ⚠️ 名字提示必须小写比较：ObjC ivar 几乎都是小写（_data/_items/_list/_models），
    // 之前用大写子串("Data"/"List"/"Items")匹配，极速版这些数组一个都没命中 → 「数据源0数组」
    NSArray *nameHint = @[ @"array", @"arr", @"list", @"models", @"model", @"data", @"items",
                           @"item", @"sections", @"section", @"elements", @"element", @"comments",
                           @"comment", @"datalist", @"datasource", @"cellmodels", @"viewmodels" ];
    Class cls = object_getClass(obj);
    for (NSInteger depth = 0; cls && depth < 3 && out.count < 12; depth++) {
        unsigned int ic = 0;
        Ivar *ivars = class_copyIvarList(cls, &ic);
        for (unsigned int i = 0; i < ic && out.count < 12; i++) {
            const char *n = ivar_getName(ivars[i]);
            const char *t = ivar_getTypeEncoding(ivars[i]);
            if (!DYYYWardIvarTypeIsDeclaredObject(t)) continue;
            NSString *cn = [NSString stringWithUTF8String:n];
            NSString *bare = cn;
            if ([bare hasPrefix:@"_"]) bare = [bare substringFromIndex:1];
            NSString *lower = [bare lowercaseString];
            BOOL nameOK = NO;
            for (NSString *w in nameWhitelist) {
                if ([bare isEqualToString:w] || [lower isEqualToString:[w lowercaseString]]) { nameOK = YES; break; }
            }
            if (!nameOK) {
                for (NSString *h in nameHint) {
                    if ([lower containsString:h]) { nameOK = YES; break; }
                }
            }
            if (!nameOK) continue;
            id v = object_getIvar(obj, ivars[i]);
            if (!DYYYWardLooksLikeObject(v)) continue;
            if (![v isKindOfClass:[NSArray class]]) continue;
            NSUInteger c = [(NSArray *)v count];
            if (c == 0 || c > 10000) continue;
            BOOL dup = NO;
            for (NSArray *exist in out) { if (exist == (NSArray *)v) { dup = YES; break; } }
            if (!dup) [out addObject:v];
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
    return out;
}

// 在模型数组里找目标评论下标：cid 命中优先，其次评论内容前缀命中
static NSInteger DYYYWardIndexInArray(NSArray *arr, NSArray *cidList, NSString *contentHint) {
    if (![arr isKindOfClass:[NSArray class]] || arr.count == 0) return NSNotFound;
    NSUInteger n = arr.count;
    if (n > 1500) n = 1500;
    NSString *probe = DYYYWardContentProbe(contentHint, 10); // 自动裁掉 [看] 等表情短码
    NSArray *wrapKeys = @[ @"model", @"comment", @"awemeComment", @"commentModel", @"originComment" ];
    for (NSUInteger i = 0; i < n; i++) {
        @autoreleasepool {
            id item = [arr objectAtIndex:i];
            if (!item || [item isKindOfClass:[NSNull class]]) continue;
            // 值搜优先：不依赖模型字段名，直接在模型图里按 cid/正文找（与可见 cell 同一套判定）
            if (cidList.count > 0) { NSInteger bg = 150; if (DYYYWardGraphMatch(item, cidList, nil, 3, &bg)) return (NSInteger)i; }
            if (probe.length > 0) { NSInteger bg = 150; if (DYYYWardGraphMatch(item, @[], probe, 3, &bg)) return (NSInteger)i; }
            NSString *cid = DYYYWardCIDOfModel(item);
            if (cid.length == 0) {
                for (NSString *k in wrapKeys) {
                    id m = DYYYWardIvarNamed(item, k);
                    if (!m || [m isKindOfClass:[NSNull class]]) continue;
                    cid = DYYYWardCIDOfModel(m);
                    if (cid.length > 0) break;
                }
            }
            if (cid.length > 0) {
                for (id t in cidList) {
                    if ([t isKindOfClass:[NSString class]] && [cid isEqualToString:(NSString *)t]) return (NSInteger)i;
                }
            }
            if (probe) {
                NSString *txt = DYYYWardTextOfModel(item);
                if (txt.length > 0 && [txt containsString:probe]) return (NSInteger)i;
                for (NSString *k in wrapKeys) {
                    id m = DYYYWardIvarNamed(item, k);
                    NSString *t2 = DYYYWardTextOfModel(m);
                    if (t2.length > 0 && [t2 containsString:probe]) return (NSInteger)i;
                }
            }
        }
    }
    return NSNotFound;
}

// 把数组下标换算成 indexPath 并滚动过去；滚完取 cell 复核，命中才高亮
static BOOL DYYYWardScrollListToIndex(UIScrollView *scroll, NSInteger idx, NSArray *cidList, NSString *contentHint) {
    if (!scroll || idx < 0) return NO;
    NSIndexPath *ip = nil;
    if ([scroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)scroll;
        // 只用 UITableView 公开 API 问行数（不调 dataSource 的回调方法，副作用/崩溃风险都更小）
        NSInteger sections = tv.numberOfSections;
        if (sections < 1) sections = 1;
        if (sections > 8) sections = 8;
        NSInteger remain = idx;
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = 0;
            if (s < tv.numberOfSections) rows = [tv numberOfRowsInSection:s];
            if (rows > 0 && remain < rows) { ip = [NSIndexPath indexPathForRow:remain inSection:s]; break; }
            remain -= rows;
        }
        if (!ip) return NO;
        @try { [tv scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES]; } @catch (NSException *e) { return NO; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
                if (!cell) return;
                // 下标照模型数组算，cell 取到即位置对；用对象图按值复核（cid 或正文片段），
                // 不因此否定，否则等于又把「按字段名猜 cid」那套不可靠判定搬回来
                BOOL hit = NO;
                NSInteger budget = 400;
                if (cidList.count > 0) hit = DYYYWardGraphMatch(cell, cidList, nil, 4, &budget);
                if (!hit) {
                    NSString *p = DYYYWardContentProbe(contentHint, 10);
                    if (p.length > 0) { NSInteger b2 = 1500; hit = DYYYWardGraphMatch(cell, @[], p, 8, &b2); }
                }
                if (!hit) return;
                DYYYWardScrollAndHighlight(tv, cell);
                [DYYYUtils showToast:@"已定位到该评论"];
                gDYYYWardLocateDone = gDYYYWardLocateGen;
            } @catch (NSException *e) {}
        });
        return YES;
    }
    if ([scroll isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)scroll;
        NSInteger sections = cv.numberOfSections;
        if (sections < 1) sections = 1;
        if (sections > 8) sections = 8;
        NSInteger remain = idx;
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger items = 0;
            if (s < cv.numberOfSections) items = [cv numberOfItemsInSection:s];
            if (items > 0 && remain < items) { ip = [NSIndexPath indexPathForItem:remain inSection:s]; break; }
            remain -= items;
        }
        if (!ip) return NO;
        @try { [cv scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES]; } @catch (NSException *e) { return NO; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
                if (cell) { DYYYWardScrollAndHighlight(cv, cell); [DYYYUtils showToast:@"已定位到该评论"]; }
            } @catch (NSException *e) {}
        });
        return YES;
    }
    return NO;
}

// 遍历候选列表 → dataSource（含其 viewModel）的模型数组 → 算出下标 → 滚动复核
static BOOL DYYYWardLocateViaDataSource(NSArray *cidList, NSString *contentHint) {
    if (cidList.count == 0 && contentHint.length == 0) return NO;
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC || !commentVC.view) { gDYYYWardDataSourceDiag = @"评论区未打开"; return NO; }
    NSArray *lists = DYYYWardCommentListViews(commentVC);
    NSInteger arrCount = 0;
    NSInteger foundIdx = NSNotFound;
    for (UIScrollView *scroll in lists) {
        id ds = nil;
        if ([scroll isKindOfClass:[UITableView class]]) ds = [(UITableView *)scroll dataSource];
        else if ([scroll isKindOfClass:[UICollectionView class]]) ds = [(UICollectionView *)scroll dataSource];
        if (!ds) continue;
        NSMutableArray *owners = [NSMutableArray array];
        [owners addObject:ds];
        if (commentVC && commentVC != ds) [owners addObject:commentVC]; // 极速版可能由评论 VC 直接持有模型数组
        id vm = DYYYWardIvarNamed(ds, @"viewModel");
        if (!vm) vm = DYYYWardIvarNamed(ds, @"model");
        if (vm && ![vm isKindOfClass:[NSNull class]] && vm != ds) [owners addObject:vm];
        for (id owner in owners) {
            for (NSArray *arr in DYYYWardModelArraysIn(owner)) {
                arrCount++;
                @try {
                    NSInteger idx = DYYYWardIndexInArray(arr, cidList, contentHint);
                    if (idx == NSNotFound) continue;
                    foundIdx = idx;
                    if (DYYYWardScrollListToIndex(scroll, idx, cidList, contentHint)) {
                        gDYYYWardDataSourceDiag = [NSString stringWithFormat:@"数据源命中 idx%ld", (long)idx];
                        gDYYYWardLocatePending = gDYYYWardLocateGen;
                        return YES;
                    }
                } @catch (NSException *e) {}
            }
            if (arrCount > 14) break;
        }
        if (arrCount > 14) break;
    }
    gDYYYWardDataSourceDiag = [NSString stringWithFormat:@"数据源%ld数组%@无命中", (long)arrCount,
                               foundIdx == NSNotFound ? @"(未算到下标)" : [NSString stringWithFormat:@"idx%ld滚不到", (long)foundIdx]];
    return NO;
}

// 运行时发现宿主「定位评论」方法：白名单猜不中时，扫 target 类所有实例方法，
// 名字同时含 comment 与 scroll/locate/highlight/focus/jump 的即为候选（通常只有几个）。
// 命中的方法名记到 gDYYYWardHostLocateMethods，失败 toast 里带上，便于下一版精确调用。
static NSString *gDYYYWardHostLocateMethods = nil;

static NSArray *DYYYWardDiscoverLocateSelectors(id target) {
    NSMutableArray *found = [NSMutableArray array];
    if (!target) return found;
    unsigned int mc = 0;
    Method *ml = class_copyMethodList(object_getClass(target), &mc);
    for (unsigned int i = 0; i < mc; i++) {
        SEL sel = method_getName(ml[i]);
        const char *n = sel_getName(sel);
        if (!n) continue;
        NSString *name = [NSString stringWithUTF8String:n];
        if (name.length == 0) continue;
        BOOL hasComment = [name containsString:@"omment"]; // Comment/comment
        BOOL hasAction = [name containsString:@"scroll"] || [name containsString:@"Scroll"] ||
                         [name containsString:@"locate"] || [name containsString:@"Locate"] ||
                         [name containsString:@"highlight"] || [name containsString:@"Highlight"] ||
                         [name containsString:@"focus"] || [name containsString:@"Focus"] ||
                         [name containsString:@"jump"] || [name containsString:@"Jump"] ||
                         [name containsString:@"seek"] || [name containsString:@"Seek"];
        if (hasComment && hasAction) [found addObject:name];
    }
    if (ml) free(ml);
    return found;
}

// 宿主内部定位：抖音自己支持「跳到指定评论」（安卓侧已验证该能力存在）。
// ⚠️ v2.3-21 起只「发现 + 记录」，不再盲调：对宿主私有方法盲调是 SIGBUS 崩溃源
// （方法内部对参数/状态有别的预期时，objc_msgSend 传错参就会跳进垃圾地址）。
// 本版只把候选方法名带回给用户，下一版按回报的方法名做精确（校验签名后）调用。
static BOOL DYYYWardTrySelectorsOnTarget(id target, NSArray *selNames, NSString *commentID) {
    (void)commentID;
    if (!target) return NO;
    for (NSString *s in selNames) {
        SEL sel = NSSelectorFromString(s);
        if (![target respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [target methodSignatureForSelector:sel];
        if (!sig || sig.numberOfArguments != 3) continue; // 单对象参方法（self/_cmd/arg）
        const char *t = [sig getArgumentTypeAtIndex:2];
        if (!t || t[0] != '@') continue;
        return YES; // 只确认「存在且可调」，不实际执行（防盲调崩溃）
    }
    return NO;
}

// v2.3-22：白名单命中后「精确调用」（已先验签名：单对象参），不再只记录。
// 命中方法名写入 gDYYYWardHostLocateMethods，失败诊断可直接看到；调用本身包 @try。
// 仅对「名字即定位评论」的 whitelist 方法调用，参数传评论 cid 字符串（合法对象，
// 不像 v2.3-20 那样盲传参到签名未知的方法），宿主内部自行滚到该评论。
static NSString *DYYYWardInvokeHostLocate(id target, NSArray *selNames, NSString *commentID) {
    if (!target || commentID.length == 0) return nil;
    for (NSString *s in selNames) {
        SEL sel = NSSelectorFromString(s);
        if (![target respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [target methodSignatureForSelector:sel];
        if (!sig) continue;
        if (sig.numberOfArguments != 3) continue; // 仅允许 单对象参（self/_cmd/arg）
        const char *t = [sig getArgumentTypeAtIndex:2];
        if (!t || t[0] != '@') continue;
        @try {
            [target performSelector:sel withObject:commentID];
            return s; // 调用成功：返回方法名（宿主内部会自行滚动/高亮到该评论）
        } @catch (NSException *e) {
            return [@"调用异常:" stringByAppendingString:s];
        }
    }
    return nil;
}

// v2.3-28：扫描到的候选方法只跑「名字里带 id」的那些（scrollToCommentWithID:/...WithCID: 这类）。
// 像 locateComment:/focusComment: 可能收的是模型对象，把 cid 字符串塞进去会把 NSString
// 当 AWECommentModel 用（非对象参数/直访 ivar 时是硬崩溃，@try 拦不住），所以一律不盲调。
static NSArray *DYYYWardIDOnlySelectors(NSArray *names) {
    if (names.count == 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        if (![n isKindOfClass:[NSString class]]) continue;
        if ([[n lowercaseString] containsString:@"id"]) [out addObject:n];
    }
    return out;
}

// 本版对宿主定位方法：先验签名后「精确调用」（v2.3-21 只记录不调用，本版落地调用）。
// 调用后由后续可见 cell/数据源复核去确认；若宿主方法本身就把评论滚到屏内，用户直接可见。
// v2.4-1：不再只认「第一个评论 VC + 名为 viewModel 的 ivar」。
// 实测同一时刻可能存在多个评论 VC 实例（导航栈里的旧页），也可能 ivar 叫 commentViewModel/vm；
// 而且早期调用时 viewModel 还没赋值（cache 会把「值为 nil」误记成「没这个 ivar」，见 DYYYWardIvarNamed），
// 于是宿主方法永远调不到。现在遍历所有候选 VC × 所有候选 ivar 名，找到一个能用的就调。
static void DYYYWardTryHostLocateComment(NSString *commentID) {
    if (commentID.length == 0) return;
    NSArray *selNames = @[ @"scrollToCommentWithID:", @"scrollToCommentWithCommentID:", @"scrollToComment:",
                           @"locateComment:", @"focusComment:", @"highlightComment:", @"scrollToCommentWithCID:",
                           @"locateCommentWithCommentID:", @"scrollToCommentWithCommentID:animated:" ];
    NSArray *vcs = DYYYWardAllCommentVCs();
    if (vcs.count == 0) {
        gDYYYWardHostLocateMethods = @"未找到评论VC";
        return;
    }
    NSArray *vmNames = @[ @"viewModel", @"commentViewModel", @"vm", @"listViewModel", @"dataViewModel", @"viewModelObject" ];
    NSInteger vcCount = 0, vmCount = 0;
    NSString *invoked = nil;
    NSMutableString *detail = [NSMutableString string];
    for (UIViewController *vc in vcs) {
        vcCount++;
        if (invoked.length == 0) {
            NSString *d = DYYYWardInvokeHostLocate(vc, selNames, commentID);
            if (d.length > 0) { invoked = d; [detail appendFormat:@" VC白名单已调用(%@)", d]; }
            else if (DYYYWardTrySelectorsOnTarget(vc, selNames, commentID)) {
                [detail appendString:@" VC白名单签名不符"];
            }
        }
        NSArray *discovered = DYYYWardDiscoverLocateSelectors(vc);
        if (discovered.count > 0) {
            [detail appendFormat:@" VC方法:%@", [discovered componentsJoinedByString:@";"]];
        }
        // 逐个候选 ivar 名找 viewModel；找到第一个非空的就够（其余候选名通常指向同一对象）
        for (NSString *vn in vmNames) {
            id vm = DYYYWardIvarNamed(vc, vn); // 不用 KVC，避免属性类型非对象时崩溃
            if (!vm) continue;
            vmCount++;
            if (detail.length < 160) [detail appendFormat:@" %@:%@", vn, NSStringFromClass([vm class])];
            if (invoked.length == 0) {
                NSString *v = DYYYWardInvokeHostLocate(vm, selNames, commentID);
                if (v.length > 0) { invoked = v; [detail appendFormat:@" vm白名单已调用(%@)", v]; }
            }
            NSArray *vmDisc = DYYYWardDiscoverLocateSelectors(vm);
            if (vmDisc.count > 0 && detail.length < 220) {
                [detail appendFormat:@" vm方法:%@", [vmDisc componentsJoinedByString:@";"]];
            }
            if (invoked.length == 0 && vmDisc.count > 0) {
                NSString *v2 = DYYYWardInvokeHostLocate(vm, DYYYWardIDOnlySelectors(vmDisc), commentID);
                if (v2.length > 0) { invoked = v2; [detail appendFormat:@" vm扫描调用(%@)", v2]; }
            }
            break;
        }
        if (invoked.length > 0) break; // 宿主方法已经接受调用，不必再试其它实例
    }
    // 精简诊断：VC 实例数 / 命中 vm 的实例数 + 细节（避免 toast 被撑爆）
    gDYYYWardHostLocateMethods = [NSString stringWithFormat:@"VCs:%ld vm:%ld%@",
                                   (long)vcCount, (long)vmCount, detail];
}

// 统一的定位失败 toast。P3：诊断信息不再直接糊在 toast 上——
// 第 1 次失败只给人话（用户真正想知道的：是没找到，还是还在加载），
// 连点两次仍失败才附完整诊断（cid/内容/扫描串数/首 cell/宿主方法/数据源/行数/偏移），
// 这样平时不打扰，出问题时又能一次拿到全部线索。
static void DYYYWardShowLocateFailure(void) {
    gDYYYWardFailCount++;
    if (gDYYYWardFailCount == 1) {
        [DYYYUtils showToast:@"没找到这条评论（可能还在加载），再点一次「查看」可重试"];
        return;
    }
    gDYYYWardFailCount = 0; // 完整诊断只报一次，之后重新从人话开始
    NSString *reason = gDYYYWardLocateDiag ?: @"未匹配到可见评论";
    NSString *hostMsg = @"";
    if (gDYYYWardHostLocateMethods.length > 0) {
        hostMsg = [NSString stringWithFormat:@" 方法:%@", gDYYYWardHostLocateMethods];
    }
    NSString *dsMsg = @"";
    if (gDYYYWardDataSourceDiag.length > 0) {
        dsMsg = [NSString stringWithFormat:@" %@", gDYYYWardDataSourceDiag];
    }
    NSInteger maxRows = 0; CGFloat off = 0;
    UIViewController *cvc = DYYYWardFindCommentVC();
    if (cvc) {
        for (UIScrollView *sv in DYYYWardCommentListViews(cvc)) {
            NSInteger cnt = 0;
            if ([sv isKindOfClass:[UITableView class]]) {
                UITableView *t = (UITableView *)sv;
                for (NSInteger s = 0; s < t.numberOfSections; s++) cnt += [t numberOfRowsInSection:s];
            } else if ([sv isKindOfClass:[UICollectionView class]]) {
                UICollectionView *cv2 = (UICollectionView *)sv;
                for (NSInteger s = 0; s < cv2.numberOfSections; s++) cnt += [cv2 numberOfItemsInSection:s];
            }
            if (cnt > maxRows) { maxRows = cnt; off = sv.contentOffset.y; }
        }
    }
    BOOL hostInvoked = [gDYYYWardHostLocateMethods containsString:@"已调用"];
    NSString *prefix = hostInvoked ? @"已请求宿主定位" : @"评论定位失败";
    [DYYYUtils showToast:[NSString stringWithFormat:@"%@：%@%@%@ 行:%ld 偏移:%.0f",
                          prefix, reason, hostMsg, dsMsg, (long)maxRows, off]];
}

// P0：按屏批量扫描（替代 v2.3 的逐行 0.15s）。
// 逐行为什么慢：每一行都要 scrollToRow + 等 0.15s，148 行 ≈ 22s，而一屏本来能同时看到 6~7 行。
// 现在一次把「领头行」滚到顶部，等 0.14s（够宿主把整屏 cell 配好）后用 indexPathsForVisibleRows
// 一次性取整屏 cell 全查，下一轮从本屏最大行 +1 继续 → 步数降到约 1/6，148 行约 3~4s。
// 只在完全没命中时才退化到全图搜（DYYYWardGraphMatch），常见情况只做便宜的 label 文本比对。
static void DYYYWardSweepStep(UITableView *t, NSArray *cidList, NSString *contentHint, NSInteger gen,
                              NSInteger flat, NSInteger total, NSInteger pageTry, NSInteger token) {
    if (!t || gDYYYWardLocateDone == gen || total <= 0) return;
    if (token != gDYYYWardSweepToken) return; // 已被取消（宿主接管/重新起扫），旧链自行退出
    if (flat >= total) {
        // 已扫到「当前已加载」的末尾：滚到真正的最后一行触发分页加载，重新读行数，若变多就接着扫
        // （148 条评论只加载 60 行的场景）。光设 contentOffset 有些宿主不会 load-more，
        // 必须 scrollToRow 到最后一行让 willDisplay 真的跑一遍；两种都做，互为保险。
        NSIndexPath *lastIP = nil;
        for (NSInteger s = t.numberOfSections - 1; s >= 0; s--) {
            NSInteger rows = [t numberOfRowsInSection:s];
            if (rows > 0) { lastIP = [NSIndexPath indexPathForRow:rows - 1 inSection:s]; break; }
        }
        if (lastIP) {
            @try { [t scrollToRowAtIndexPath:lastIP atScrollPosition:UITableViewScrollPositionBottom animated:NO]; } @catch (NSException *e) {}
        }
        @try { [t setContentOffset:CGPointMake(0, MAX(0, t.contentSize.height - t.bounds.size.height)) animated:NO]; } @catch (NSException *e) {}
        // 网络分页不是瞬时的（实测 0.7s 常不够），所以同一次到底最多重试 3 次（每次 0.9s）再判失败，
        // 避免「其实还能翻页、只是还没回来」被误报成定位失败。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen || token != gDYYYWardSweepToken) return;
            NSInteger nowTotal = 0;
            for (NSInteger s = 0; s < t.numberOfSections; s++) nowTotal += [t numberOfRowsInSection:s];
            if (nowTotal > total) {
                DYYYWardSweepStep(t, cidList, contentHint, gen, total, nowTotal, 0, token); // 已翻出更多，接着扫
            } else if (pageTry < 2) {
                DYYYWardSweepStep(t, cidList, contentHint, gen, total, total, pageTry + 1, token); // 还没回来，再等等
            } else {
                DYYYWardShowLocateFailure(); // 重试 3 次仍无新行，真到底了
            }
        });
        return;
    }
    // 用户自己正在滑（拖拽/惯性），别跟他抢滚动条，等他松手再继续
    if (t.isDragging || t.isDecelerating) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYWardSweepStep(t, cidList, contentHint, gen, flat, total, pageTry, token);
        });
        return;
    }
    NSIndexPath *ip = nil;
    NSInteger remain = flat;
    for (NSInteger s = 0; s < t.numberOfSections; s++) {
        NSInteger rows = [t numberOfRowsInSection:s];
        if (rows > 0 && remain < rows) { ip = [NSIndexPath indexPathForRow:remain inSection:s]; break; }
        remain -= rows;
    }
    if (!ip) return;
    // 领头行顶到列表顶部（不是 Middle），这样一屏能覆盖 flat 之后的 6~7 个新行
    @try { [t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:NO]; } @catch (NSException *e) { return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.14 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDYYYWardLocateDone == gen || token != gDYYYWardSweepToken) return;
        NSString *probe = DYYYWardContentProbe(contentHint, 10);
        NSInteger sectionCount = t.numberOfSections;
        NSArray *visible = [t indexPathsForVisibleRows];
        NSInteger maxFlat = -1;
        UITableViewCell *hitCell = nil;
        for (NSIndexPath *vip in visible) {
            if (vip.section >= sectionCount) continue;
            NSInteger rowsInSection = [t numberOfRowsInSection:vip.section];
            if (vip.row >= rowsInSection) continue;
            NSInteger fi = vip.row;
            for (NSInteger s = 0; s < vip.section; s++) fi += [t numberOfRowsInSection:s];
            if (fi < flat) continue;                 // 上一屏已经查过
            if (fi > maxFlat) maxFlat = fi;
            if (hitCell) continue;
            UITableViewCell *cell = [t cellForRowAtIndexPath:vip];
            if (!cell) continue;
            BOOL quick = (probe.length > 0) && DYYYWardCellQuickMatch(cell, probe);
            BOOL exact = NO;
            // 有正文时走便宜路径；只有正文太短/缺失（probe 为空）才不得不做昂贵的全图 cid 搜索
            if (quick) {
                if (cidList.count == 0) exact = YES;
                else { NSInteger b = 1200; exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b); }
            } else if (probe.length == 0 && cidList.count > 0) {
                NSInteger b = 1500;
                exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b);
            }
            if (quick || exact) { hitCell = cell; }
        }
        if (hitCell) {
            DYYYWardScrollAndHighlight(t, hitCell);
            [DYYYUtils showToast:[NSString stringWithFormat:@"已定位：%@", probe.length > 0 ? probe : @"该评论"]];
            gDYYYWardLocateDone = gen;
            return;
        }
        NSInteger next = (maxFlat >= flat) ? (maxFlat + 1) : (flat + 1); // 本屏最大行之后继续；无可见行就前挪一行
        DYYYWardSweepStep(t, cidList, contentHint, gen, next, total, pageTry, token);
    });
}

static void DYYYWardSweepRows(NSArray *cidList, NSString *contentHint, NSInteger gen) {
    if (gDYYYWardSweepGen == gen) return;      // 本代已经在扫，别叠加第二条扫描链（两条会互相抢滚动）
    // 多实例：把每个候选评论 VC 里的 table 都算进来，选行数最多的那个（可能是窗口上正在用的那个）
    UITableView *best = nil; NSInteger total = 0;
    NSArray *vcs = DYYYWardAllCommentVCs();
    if (vcs.count == 0) {
        UIViewController *one = DYYYWardFindCommentVC();
        if (one) vcs = @[ one ];
    }
    for (UIViewController *vc in vcs) {
        for (UIScrollView *sv in DYYYWardCommentListViews(vc)) {
            if (![sv isKindOfClass:[UITableView class]]) continue;
            UITableView *t = (UITableView *)sv;
            NSInteger c = 0;
            for (NSInteger s = 0; s < t.numberOfSections; s++) c += [t numberOfRowsInSection:s];
            if (c > total) { total = c; best = t; }
        }
    }
    if (!best || total <= 0) return;
    gDYYYWardSweepGen = gen;                  // 告知主循环：已在按行扫描，跳过渐进滚动（防互相打架）
    gDYYYWardSweepToken++;                    // 新令牌：让上一代还在排队的步骤失效
    NSInteger token = gDYYYWardSweepToken;
    // 起点不一定是 0：宿主定位方法常已经把列表带到目标附近（二级回复尤其），
    // 这时从当前可见处往上留一屏重叠再往下扫，比每次从第 0 行重扫既快又更容易命中。
    NSInteger start = 0;
    NSIndexPath *firstVisible = [best indexPathsForVisibleRows].firstObject;
    if (firstVisible) {
        NSInteger fi = firstVisible.row;
        for (NSInteger s = 0; s < firstVisible.section; s++) fi += [best numberOfRowsInSection:s];
        start = MAX(0, fi - 6);
    }
    DYYYWardSweepStep(best, cidList, contentHint, gen, start, total, 0, token);
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

static void DYYYWardLocateComment(NSString *awemeID, NSArray *cidList, NSString *contentHint) {
    (void)awemeID;
    // 上一次已经定位成功 → 失败计数归零（「连点两次才给诊断」只在连续失败时生效）
    if (gDYYYWardLocateGen > 0 && gDYYYWardLocateDone == gDYYYWardLocateGen) gDYYYWardFailCount = 0;
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
    for (NSInteger i = 0; i < 18; i++) {
        NSTimeInterval delay = 2.6 + i * 0.9;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen) return;
            @try {
                // 宿主内部定位：第 1/7/13 步各试一次（评论 VC 起来后才可靠，避免过多盲调副作用）
                if (i == 0 || i == 6 || i == 12) {
                    for (NSString *cid in cidList) {
                        DYYYWardTryHostLocateComment(cid);
                        if (gDYYYWardLocateDone == gen) return;
                    }
                    // 宿主方法真的被调用了 → 它很可能已经把列表带到目标附近。
                    // 这时必须让正在跑的按行扫描停下（否则扫描下一步就把列表拽回自己那一行，
                    // 等于把宿主的定位结果抹掉），0.8s 后从新位置重新起扫。
                    if ([gDYYYWardHostLocateMethods containsString:@"已调用"]) {
                        gDYYYWardSweepGen = 0;
                        gDYYYWardSweepToken++;   // 真正叫停在排队/paging 的旧步骤
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            if (gDYYYWardLocateDone == gen) return;
                            DYYYWardSweepRows(cidList, contentHint, gen);
                        });
                    }
                }
                if (DYYYWardHighlightComment(cidList, contentHint)) {
                    gDYYYWardLocateDone = gen;
                    return;
                }
                // 按行扫描：用公开行数逐行 scrollToRow 复核，覆盖整列（渐进滚动覆盖不到中间/后半段）
                if (i == 2) {
                    DYYYWardSweepRows(cidList, contentHint, gen);
                }
                // 数据源定位：直接按模型数组算下标再滚过去（第 1/5/9 步各试一次，
                // 扫数组较贵，不必每步都做）。命中后由 0.7s 后的复核去置 done。
                // 注意：按行扫描一旦接管（gDYYYWardSweepGen==gen），就绝不能再让数据源定位去 scrollToRow，
                // 否则两边抢滚动位置——实测表现为「扫描到一半被拽回顶部附近」，扫描永远走不完（v2.3-26 偏移停在 991 的真因）。
                if ((i == 1 || i == 5 || i == 9) && gDYYYWardSweepGen != gen) {
                    DYYYWardLocateViaDataSource(cidList, contentHint);
                    if (gDYYYWardLocateDone == gen) return;
                }
                if (i == 3) {
                    // 中途提示「仍在查找」，避免被误认为失败；真正的失败在第 12 步报
                    [DYYYUtils showToast:@"评论查找中…"];
                }
                if (i == 17) {
                    // 若按行扫描正在进行/已接管，失败 toast 由扫描自身在「真到底」时报；
                    // 否则（无 table 可扫）这里兜底报一次。
                    if (gDYYYWardSweepGen != gen) DYYYWardShowLocateFailure();
                    return;
                }
                if (gDYYYWardLocateDone == gen || gDYYYWardLocatePending == gen || gDYYYWardSweepGen == gen) return; // 已定位/正在定位/正在按行扫描，勿再渐进滚动（防互相打架）
                DYYYWardScrollCommentList(i >= 10); // 前 10 步向下，后 4 步向上回头
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
        // 候选 cid 列表（插眼时保存的所有 id 字段值），定位时逐个试
        NSMutableArray *cidList = [NSMutableArray array];
        id saved = [ward objectForKey:@"commentIDs"];
        if ([saved isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)saved) {
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                    if (![cidList containsObject:(NSString *)v]) [cidList addObject:(NSString *)v];
                }
            }
        }
        if (commentID.length > 0 && ![cidList containsObject:commentID]) [cidList addObject:commentID];
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
        DYYYWardLocateComment(awemeID, cidList, contentHint);
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
