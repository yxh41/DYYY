#import "DYYYWardListViewController.h"
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <dlfcn.h>
#import <sys/mman.h> // v2.4-8 引入；v2.4-11 起 mincore 不再用于可读性判定（只报驻留不报权限，见 PageMapped 注释）
#import <unistd.h>   // v2.4-8：sysconf(_SC_PAGESIZE)
// v2.4-11：vm_region_64——查区域保护位（PROT_NONE 保留区必须拒）。
// 用 __has_include 守卫：万一某 SDK 缺此头文件，退化成「宁拒不放」（v2.4-6 行为，不崩）。
#if __has_include(<mach/vm_region.h>)
#import <mach/vm_region.h>
#import <mach/mach.h>
#define DYYY_HAVE_VM_REGION 1
#endif
// v2.4-13：安全读改走 Mach vm_read_overwrite（见 DYYYWardProbeRead8 上方长注释）。
// 旧 vm_* 家族的 vm_read_overwrite 在 <mach/vm_map.h> 里，iOS SDK 可用；不可用
// 的是 <mach/mach_vm.h> 那套 mach_vm_*（该头文件直接是 #error），别混。
#if __has_include(<mach/vm_map.h>)
#import <mach/vm_map.h>
#define DYYY_HAVE_VM_MAP 1
#endif
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

// v2.4-10 前向声明：宿主调用总闸要用（定义在文件后部）
static NSArray *DYYYWardListLayerRoots(UIViewController *commentVC);
static BOOL DYYYWardListLayerFindModel(NSArray *roots, NSArray *cidList, id *outModel);

// v2.4-10：宿主调用总闸——先跑列表层图搜（纯只读：ivar 扫描 + 值匹配，零宿主代码
// 执行）确认目标 cid 的模型已在已加载数组里，才允许调宿主定位方法。
// 背景：v2.4-8 校验链复活后深枚举第一次真调宿主方法，真机秒退（Swift runtime
// trapped / SIGTRAP，@try 拦不住）。v2.4-9 收了白名单（只留 ID 类选择器）和类名闸
// 仍崩——剩下唯一触发面：宿主 VM 未就绪或 cid 不在其数据时，scrollToCommentWithID:
// 内部对找不到的 cid 强转/fatalError。模型在已加载数组里 ⇒ 宿主自己的数据源也有它
// ⇒ 调用才安全。未加载则跳过（由渐进扫描继续加载，下轮再试）。
static BOOL DYYYWardCIDModelLoaded(NSString *cid) {
    if (cid.length == 0) return NO;
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC) return NO;
    NSArray *roots = DYYYWardListLayerRoots(commentVC);
    if (roots.count == 0) return NO;
    id model = nil;
    return DYYYWardListLayerFindModel(roots, @[cid], &model);
}

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
static BOOL DYYYWardAuthorGateOK(id cell); // v2.4-20：作者双条件闸（定义在 CellAuthorMatch 之后）
static CGRect DYYYWardContentColumnRect(UIView *cellView); // v2.4-22：精准框取框矩形（定义在 DYYYWardViewText 之后）
static void DYYYWardSweepStep(UITableView *t, NSArray *cidList, NSString *contentHint, NSInteger gen,
                              NSInteger flat, NSInteger total, NSInteger pageTry, NSInteger token);
static void DYYYWardSweepStepCV(UICollectionView *cv, NSArray *cidList, NSString *contentHint, NSInteger gen,
                                NSInteger flat, NSInteger total, NSInteger pageTry, NSInteger token); // v2.4-3：collection view 版
static void DYYYWardParentSweepHit(id cell, UIScrollView *list, NSInteger gen); // v2.4-4：父扫描命中后的统一动作
static void DYYYWardSweepParentThenExpand(NSArray *parentIDs, NSArray *childCidList, NSString *childContentHint, NSArray *parentTexts, NSInteger gen); // v2.4-4 / v2.4-5 加 parentTexts
static BOOL DYYYWardListLayerJump(NSArray *cidList, NSString *contentHint, NSInteger gen, NSInteger urlGen); // v2.4-7：列表层直达（一级评论用）
static NSInteger DYYYWardListRowCount(UIScrollView *sv); // v2.4-3：table/collection 通吃行数
static void DYYYWardSweepRows(NSArray *cidList, NSString *contentHint, NSInteger gen);
static NSInteger gDYYYWardSweepGen = 0; // 正在按行扫描的 gen（扫描期间跳过渐进滚动，防两者互相打架）
static NSInteger gDYYYWardSweepToken = 0; // 扫描令牌：取消时自增，已在排队的旧步骤一检查就自行退出
static NSInteger gDYYYWardFailCount = 0; // 连续定位失败次数：第 1 次只报人话，第 2 次才附完整诊断
// v2.4-2：URL 直达复核/兜底扫描的代号。只有最新一次「查看」发起的这一代才有效；
// 上一代还在排队的 dispatch_after 步骤一看到不等就自行作废，防止旧链把新评论拽走。
static NSInteger gDYYYWardURLGen = 0;
static BOOL gDYYYWardURLDirectOK = NO; // comment_id 深链复核通过（宿主已把目标评论滚到位）
static NSString *gDYYYWardURLDiag = nil; // 深链复核结果（直达到位/未到位），失败 toast 里带出来
// v2.4-18：本次「查看」的插眼人身份（secUid 优先，缺失退 uid 数字串）。
// 仅作「短探针双条件确认」的辅助信号——同作者可能有多条评论，绝不单独宣告命中。
// openWard: 评论分支置入，下一次查看覆盖；老插眼记录没存 secUid 则为空（双条件自动退化为旧行为）。
static NSString *gDYYYWardAuthorPat = @"";
// v2.4-20：作者闸过/拒计数，进失败诊断 toast——真机复测时看闸是否真的在拦
// （过=作者确认过目标，拒=挡掉的疑似乱找：回复引用目标 cid、抄原文等）。
static NSInteger gDYYYWardGatePass = 0;
static NSInteger gDYYYWardGateReject = 0;

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

// 滚动到 cell 并高亮（P3：左侧 4pt 竖向色条 + 细描边，呼吸两次后保留约 3s 再淡出）。
// 密集列表里整框描边不够醒目，左侧色条能一眼扫到；呼吸用 keyframe 做，
// 避免 repeat 动画与最后一次淡出抢同一属性（会出现高亮不消失/瞬间闪掉）。
// v2.4-22：改「精准框」——框 cell 内容列（DYYYWardContentColumnRect）而不是整个 cell：
// 旧实现框 cellView.bounds，头像/留白/底部操作行全包进去，用户观感「一大块红框」。
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
    CGRect frame = DYYYWardContentColumnRect(cellView); // v2.4-22：内容列精准框（取不到退整框）
    UIView *highlight = [[UIView alloc] initWithFrame:frame];
    highlight.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    highlight.backgroundColor = [tint colorWithAlphaComponent:0.07]; // v2.4-22：极淡红填充，框位醒目不糊字
    highlight.userInteractionEnabled = NO;
    highlight.tag = 20261022;
    highlight.layer.borderColor = [tint colorWithAlphaComponent:0.85].CGColor;
    highlight.layer.borderWidth = 1.5;
    highlight.layer.cornerRadius = 6.0;  // v2.4-22：圆角细框，不再是「一大块方砖」
    highlight.layer.masksToBounds = YES; // 把左竖条一起裁进圆角
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, CGRectGetHeight(frame))];
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
    // v2.4-17：probe 至少 16 字（调用方多传 10），太短的子串极易在别的评论里撞车 → 乱找；
    // 拉长探针能压住假阳性，且对真实评论（含自身正文）匹配几乎无影响。
    NSUInteger cap = MAX((NSUInteger)maxLen, (NSUInteger)16);
    if (base.length > cap) base = [base substringToIndex:cap];
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
    // v2.4-3：正文命中但 cell 对象图搜不到 cid 的第一格（Swift 新 cell 很常见 cid 不在图里）。
    // 全列表扫完仍无 cid 命中就认它 —— 正文前缀撞车概率远小于「明明在屏上却报无匹配」。
    id probeOnlyCell = nil;
    UIScrollView *probeOnlyList = nil;

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
                    if (!DYYYWardGraphMatch(cell, cidList, nil, 8, &budget)) {
                        // v2.4-3：不再是「正文撞车，不是这条」直接 continue —— 先记下来兜底
                        if (!probeOnlyCell) { probeOnlyCell = cell; probeOnlyList = scroll; }
                        continue;
                    }
                }
                // v2.4-20：probe+cid 双命中仍可能是乱找——回复评论抄目标原文且把目标 cid 当
                // 父评论引用，两个条件都能过。作者双条件闸挡掉「同文同 cid 不同人」。
                if (!DYYYWardAuthorGateOK(cell)) continue;
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
                    // v2.4-20：cid 只比对的最大乱找源——回复评论的对象图里就有目标 cid
                    // （父评论引用）。过作者闸：不是插眼人发的就拒，继续扫下一格。
                    if (!DYYYWardAuthorGateOK(cell)) continue;
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
                    // v2.4-20：正文片段兜底同样过作者闸（回复抄原文是主要假阳性源）
                    if (!DYYYWardAuthorGateOK(cell)) continue;
                    DYYYWardScrollAndHighlight(scroll, cell);
                    [DYYYUtils showToast:@"已定位到该评论"];
                    return YES;
                }
            }
        }
    }

    // v2.4-3：cid 全都没命中，但有一格正文前缀命中 → 认它（最后兜底，好过直接报失败）
    // v2.4-20：该兜底也要过作者闸——「正文撞车但 cid 对不上」的格子若不是插眼人发的，
    // 认它就是把乱找当成功。过不了闸就老实报失败（乱找比找不到更误导）。
    if (probeOnlyCell && probeOnlyList && DYYYWardAuthorGateOK(probeOnlyCell)) {
        DYYYWardScrollAndHighlight(probeOnlyList, probeOnlyCell);
        [DYYYUtils showToast:[NSString stringWithFormat:@"已定位(按正文)：%@", probe]];
        return YES;
    }

    NSString *cidTail = firstCid ? [firstCid substringToIndex:MIN(10, firstCid.length)] : @"(空)";
    gDYYYWardLocateDiag = [NSString stringWithFormat:@"%ld列表可见%ld条无匹配 cid:%@ 内容:%@ 扫描%ld串 首cell:%@",
                           (long)lists.count, (long)totalVisible, cidTail, probe ?: @"(空)",
                           (long)gDYYYWardGraphStrCount, firstCellCls ?: @"(无)"];
    return NO;
}

// MARK: - v2.4-2：二级回复「父评论先定位」（实现见 DYYYWardLocateParentThenExpand，定义在宿主定位/扫描函数之后）
// 二级回复（cid 是子评论 id）在主评论列表里根本不存在，scrollToCommentWithID: 也常只认主列表 id。
// 思路：定位父评论 → 父 cell 上找「查看回复/展开」按钮点开 → 再让宿主定位/扫描子评论。
// 父评论 id 来自插眼时存的 parentIDs（不存在就跳过，绝不拿子 cid 去冒充父）。
static NSString *gDYYYWardParentDiag = nil; // 父评论定位状态（诊断用）

// v2.4-4：二级回复「父评论按屏扫描」。老链路只在可见区/高亮路径找父，父不在首屏
// （实测 213 条评论父在第几十行）必然失败 → 用 parentIDs 精确匹配扫全表，
// 命中父 cell 后点开回复，再回来定位子评论。
static NSArray *gDYYYWardChildCIDs = nil;   // 父扫描命中后回来定位子评论用
static NSString *gDYYYWardChildHint = nil;
static BOOL gDYYYWardSweepForParent = NO;   // 当前扫描是在找父评论（命中后点回复而非高亮）
static BOOL gDYYYWardParentHandled = NO;    // 父已展开/已扫描过，避免重复起父扫描

// v2.4-15：「在父 cell 上点开回复」的实现整体挪到「父扫描命中后的统一动作」那一段了
// （见 DYYYWardExpandRepliesOnCell 的实现 + 上方长注释）。挪的原因：它要用 v2.4-13 的
// Mach 安全读、v2.4-8 的 ivar 扫描（DYYYWardSafeCopy / DYYYWardIvarNamed），
// 那些定义在本文更后面的位置，C 里必须先声明后使用。


// MARK: - 数据源定位
// 只匹配「可见 cell」的致命短板：目标评论在第几百条时根本不在首屏，滚动几屏也覆盖不到。
// 改从列表 dataSource 的模型数组里直接算出目标评论的下标，再滚到对应 indexPath，
// 滚完后取该 indexPath 的 cell 复核（算错也不会误高亮）。
static NSInteger gDYYYWardLocateGen = 0;
static NSInteger gDYYYWardLocateDone = 0;
static NSInteger gDYYYWardLocatePending = 0; // 数据源已精确滚到目标下标，勿再滚动列表（否则把定位到的评论滚走）
static NSString *gDYYYWardDataSourceDiag = nil;
// v2.4-7：列表层直达（DYYYWardListLayerJump）诊断
static NSString *gDYYYWardListJumpDiag = nil;
// v2.4-7：Int64/裸扫/ASCII 扫的 depth 门。cell 根搜默认 5（cell 自身 depth 8、
// 直接模型 7、内嵌结构体 6+）；列表层直达时模型离 dataSource 根只有 2~4 层，
// 由 DYYYWardListLayerJump 临时降到 1，用完即恢复。
static NSInteger gDYYYWardRawScanMinDepth = 5;
// v2.4-7：图搜命中时记录「cid 藏在哪个对象实例里」（数值/裸扫/ASCII 三处命中点赋值）。
// 字符串/NSNumber 相等命中不赋值（那种命中拿不到模型指针）→ 调用方回退按数组内容搜。
static id gDYYYWardGraphHitNode = nil;

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
// 「地址可读性」判定（libmalloc zone / dyld 镜像，均不解引用候选地址）后才读 isa，
// 再拿 isa 去比对「运行时已注册类表」，三层兜住，伪对象在第一步就被拒。
static BOOL DYYYWardLooksLikeObject(id v);

// 运行时已注册类（含元类）集合：isa 只能命中真正存在的类，否则一律判为伪对象。
// 用裸指针开放寻址哈希表，避免把候选指针当对象（CF/NSValue 包装都可能产生需要解引用的操作）。
static uintptr_t *gDYYYWardClassSet = NULL;
static size_t gDYYYWardClassSetCap = 0;
// v2.4-8：objc_getClassList 拿不到类表（真机实测疑似断点）→ 置 broken，
// 之后不再重试，改走下方的「镜像 + 继承链」兜底校验。
static BOOL gDYYYWardClassSetBroken = NO;
// v2.4-8：LooksLikeObject 全链自检——按环节记拒绝次数 + 一次性探针断点，
// 失败 toast 带出来，不用再猜是哪一环把真对象拒了。
static NSInteger gDYYYWardLAORejectZone = 0;  // 可读性判定（zone/dladdr/mincore）拒
static NSInteger gDYYYWardLAORejectIsa = 0;   // isa 读不出来/为 0
static NSInteger gDYYYWardLAORejectClass = 0; // isa 不是已注册类
static NSInteger gDYYYWardLAOProbe = 0;       // 探针断点：0=没探到 1=窗口/对齐 2=可读性 3=isa 4=类表 5=全链通 9=tagged

static size_t DYYYWardClassHash(uintptr_t v) {
    return (size_t)(((v >> 4) ^ (v >> 20)) * 2654435761u);
}

static void DYYYWardBuildClassSet(void) {
    if (gDYYYWardClassSet || gDYYYWardClassSetBroken) return;
    int n = objc_getClassList(NULL, 0);
    if (n <= 0) { gDYYYWardClassSetBroken = YES; return; }
    Class *buf = (Class *)malloc(sizeof(Class) * (size_t)n);
    if (!buf) { gDYYYWardClassSetBroken = YES; return; }
    n = objc_getClassList(buf, n);
    size_t cap = 16;
    while (cap < (size_t)n * 4) cap <<= 1;
    uintptr_t *set = (uintptr_t *)calloc(cap, sizeof(uintptr_t));
    if (!set) { free(buf); gDYYYWardClassSetBroken = YES; return; }
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

// v2.4-8：类表不可用时的兜底「isa 像不像真类」校验（定义在 AddressReadable 之后）
static BOOL DYYYWardIsaLooksLikeClass(uintptr_t isa);

// v2.4-8：类表不可用时的兜底「isa 像不像真类」校验——
// ① isa 地址必须可读；② 必须落在某个已加载镜像里（类对象都在镜像 __DATA/__objc，
//    堆上的假指针/结构体字节不可能稳定指向镜像数据）；③ 从 isa 沿继承链最多 48 跳，
//    每跳解引用前都重新过可读性判定，能走到根类（nil）才收。
// 三层同时满足才放行——比类表哈希松一点，但远紧于「只查地址可读」。
// 注：定义排在 DYYYWardAddressReadable 之后（C 语言先声明后使用）。
static BOOL DYYYWardIsRegisteredClass(uintptr_t isa) {
    if (gDYYYWardClassSet) {
        size_t cap = gDYYYWardClassSetCap;
        size_t h = DYYYWardClassHash(isa) & (cap - 1);
        for (size_t p = 0; p < 64; p++) {
            uintptr_t cur = gDYYYWardClassSet[(h + p) & (cap - 1)];
            if (cur == 0) return NO;    // 开放寻址：遇到空槽就是不存在
            if (cur == isa) return YES;
        }
        return NO;
    }
    return DYYYWardIsaLooksLikeClass(isa); // 类表不可用 → 兜底
}

// 判断某地址「是否落在可读内存区域」——全程不解引用该地址，只查它属于谁：
// ① libmalloc 的 zone 范围（堆上的对象都在这里）；
// ② dyld 已加载镜像（字面量字符串、常量对象在 __DATA/__cstring）；
// ③ v2.4-8 新增 mincore：对未映射区间返回 ENOMEM 且不触发缺页——堆/栈/镜像全覆盖的
//    「已映射」判定。前两条在真机上疑似对堆对象失效（v2.4-7 实测 vm:0/对象ivar:0/
//    数据源0数组/列表层无根 四洞齐飞：非 tagged 堆对象被整批拒掉），mincore 不依赖
//    zone 内部实现，是这条链的保底。
// 注：本来想用 mach_vm_read_overwrite 直接做安全读，但 iOS SDK 的 <mach/mach_vm.h>
// 是 `#error mach_vm.h unsupported`，只能走 libmalloc + dyld + mincore 这条路。
// v2.4-11：判定地址所在页「已映射且可读」。
// ⚠️ v2.4-10 真机崩溃（ips：AwemeLite-2026-10-24-013017，PC=DYYY.dylib+0xD9220，
//    far=0x14c6a710000）根因：mincore 只报「驻留」不查「权限」——XNU 对 PROT_NONE
//    保留区（GPU Carveout 0x1000000000-0x7000000000 等）也返回 0（成功）。于是
//    Swift Double 位模式（0x014C6A7100000000 ≈ 1.2e-302：bit63=0、8 对齐、落在
//    4GB~256TB 窗口内）被 mincore 放行 → SafeReadPtr 读其 isa → SIGSEGV。
//    改用 vm_region_64 查保护位：必须含 VM_PROT_READ 才算可读。未映射 →
//    KERN_INVALID_ADDRESS → NO；PROT_NONE → protection 无 READ → NO。
//    单条目区域缓存：ASCII 扫描步进/连续堆查询免反复 mach trap（全部在主线程）。
static BOOL DYYYWardPageMapped(uintptr_t addr) {
#ifdef DYYY_HAVE_VM_REGION
    static uintptr_t cacheStart = 0, cacheEnd = 0;
    static BOOL cacheReadable = NO;
    if (cacheStart && addr >= cacheStart && addr < cacheEnd) return cacheReadable;
    vm_address_t region = (vm_address_t)addr;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objName = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &region, &regionSize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &objName);
    if (kr != KERN_SUCCESS) { cacheStart = cacheEnd = 0; return NO; }
    if (objName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objName); // 防 port 泄漏
    // v2.4-12：vm_region_64 在「地址落在区域空洞里」时**不报错**，而是返回后面那个
    // 区域（region > addr）。直接拿它的保护位当答案会把未映射空洞判成可读 → 崩。
    // 必须校验 addr 真的落在返回区间内，否则按不可读处理。
    if ((uintptr_t)region > addr || addr >= (uintptr_t)(region + regionSize)) return NO;
    cacheStart = (uintptr_t)region;
    cacheEnd = (uintptr_t)(region + regionSize);
    cacheReadable = (info.protection & VM_PROT_READ) != 0;
    return cacheReadable;
#else
    (void)addr;
    return NO; // 无 vm_region 头文件：宁拒不放（假指针全拒，功能退化为 v2.4-6 行为）
#endif
}

static BOOL DYYYWardAddressReadable(uintptr_t addr) {
    if (malloc_zone_from_ptr((void *)addr) != NULL) return YES;
    Dl_info info;
    if (dladdr((void *)addr, &info) != 0) return YES;
    return DYYYWardPageMapped(addr);
}

// MARK: - v2.4-13：安全读改走 Mach vm_read_overwrite（不再依赖进程级信号处理器）
//
// v2.4-12 的信号级兜底（sigsetjmp + SIGSEGV/SIGBUS 处理器 + siglongjmp）**在真机上没兜住**。
// ips AwemeLite-2026-10-24-031130 的铁证：
//   PC = DYYY.dylib + 0xD9A80 —— 反汇编确认正是 DYYYWardProbeRead8 自己的那次读：
//      0xD9A7C  str w21,[x9,#0x78C]   ; gDYYYWardProbeArmed = 1
//      0xD9A80  ldr x10,[x20]         ; ← 崩，x20 = 0xE8200000000
//      0xD9A88  str x10,[x19]         ; *out = v
//   处理器 DYYYWardProbeHandler @0xD9B0C 逻辑正确（先查 Armed → pthread_self →
//   pthread_equal → siglongjmp），sigaction(SIGSEGV/SIGBUS) 也确实装了（block 体
//   @0xD9AAC：sa_mask=0、sa_flags=SA_NODEFER、sa_handler 已 paciza 签名，两条
//   sigaction 调用都在）。faultingThread=0（主线程），termination.byProc="exc handler"。
//   ⇒ 代码没错，是「进程级 SIGSEGV 处理器」这个机制在本机不可靠：同一个进程里还
//   注入了 AppFixGuard / Shadow / AutoPatches / libellekit / libsandy 等一堆同样
//   在动异常与信号的 tweak。信号处理器/异常端口是进程级共享资源，谁后装谁赢，
//   拿它当安全网本身就是设计错误。
//
// 本版换成 vm_read_overwrite：由**内核**判定目标区间是否可读，不可读就返回
// KERN_INVALID_ADDRESS / KERN_PROTECTION_FAILURE 错误码，**根本不产生信号**。
// 与信号处理器、异常端口、其它 tweak 完全无关，无法被覆盖或抢占。
//
// 另加一道前五版真正缺的东西——**机制自证**：首次使用前先跑自检，
//   ① 负样本：读公认不可读地址 0x1，内核必须报错（若居然成功＝机制不可信）；
//   ② 正样本：读自己栈上的已知值，必须成功且字节一致；
//   ③ 符号缺失（dlsym 返回 NULL）直接判不可用。
// 任一不通过 → gDYYYWardSafeReadOK = NO → 所有裸读一律返回 NO（fail closed），
// 危险扫描路径整体停摆。**宁可「定位失败」，绝不再把 App 带走。**
//
// 用 dlsym 而不是直接引用符号：不强加链接期依赖，符号不存在也只是返回 NULL，
// 不会让 dylib 加载失败（那会让整个插件失效，比定位失败严重得多）。
typedef kern_return_t (*DYYYVMReadOverwriteFn)(vm_map_t, vm_address_t, vm_size_t, vm_address_t, vm_size_t *);

static DYYYVMReadOverwriteFn DYYYVMReadOverwrite(void) {
    static DYYYVMReadOverwriteFn fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (DYYYVMReadOverwriteFn)dlsym(RTLD_DEFAULT, "vm_read_overwrite");
    });
    return fn;
}

static BOOL gDYYYWardSafeReadOK = NO;         // 机制是否可信（自检通过才置 YES）
static NSString *gDYYYWardSafeReadNote = nil; // 自检结论，进诊断 toast

static BOOL DYYYWardSafeReadSelfTest(void) {
    DYYYVMReadOverwriteFn vmRead = DYYYVMReadOverwrite();
    if (!vmRead) { gDYYYWardSafeReadNote = @"安全读:无符号(vm_read_overwrite)"; return NO; }
    // ① 负样本：0x1 公认不可读。内核必须拒绝，绝不能「成功」（更不能崩）
    uint64_t badBuf = 0;
    vm_size_t badGot = 0;
    kern_return_t krBad = vmRead(mach_task_self(), (vm_address_t)0x1, sizeof(badBuf), (vm_address_t)&badBuf, &badGot);
    if (krBad == KERN_SUCCESS) { gDYYYWardSafeReadNote = @"安全读:自检不过(0x1竟可读)"; return NO; }
    // ② 正样本：读自己栈上的已知值，必须成功且字节一致
    uint64_t good = 0x5A5AA5A50F0F1234ULL;
    uint64_t goodOut = 0;
    vm_size_t goodGot = 0;
    kern_return_t krGood = vmRead(mach_task_self(), (vm_address_t)&good, sizeof(good), (vm_address_t)&goodOut, &goodGot);
    if (krGood != KERN_SUCCESS || goodGot != sizeof(good) || goodOut != good) {
        gDYYYWardSafeReadNote = [NSString stringWithFormat:@"安全读:自检不过(正样本kr=%d)", (int)krGood];
        return NO;
    }
    gDYYYWardSafeReadNote = @"安全读:vm_read_overwrite";
    return YES;
}

static BOOL DYYYWardSafeReadReady(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gDYYYWardSafeReadOK = DYYYWardSafeReadSelfTest(); });
    return gDYYYWardSafeReadOK;
}

// 安全拷贝任意长度：由内核判定可读性。整段可读 → YES 且 buf 填满；否则 NO（不崩、不产生信号）。
static BOOL DYYYWardSafeCopy(const void *addr, void *buf, size_t len) {
    if (!addr || !buf || len == 0) return NO;
    if (!DYYYWardSafeReadReady()) return NO; // 机制不可信 → fail closed，一律拒绝
    vm_size_t got = 0;
    kern_return_t kr = DYYYVMReadOverwrite()(mach_task_self(), (vm_address_t)addr,
                                             (vm_size_t)len, (vm_address_t)buf, &got);
    return (kr == KERN_SUCCESS && got == (vm_size_t)len);
}

// 同上，但允许「部分可读」：返回实际读到的字节数（0 = 首字节就不可读）。
// 用于 CIDAsciiScan 跟进堆缓冲——能读多少搜多少，不必要求整段都在。
static size_t DYYYWardSafeCopySome(const void *addr, void *buf, size_t len) {
    if (!addr || !buf || len == 0) return 0;
    if (!DYYYWardSafeReadReady()) return 0;
    vm_size_t got = 0;
    (void)DYYYVMReadOverwrite()(mach_task_self(), (vm_address_t)addr,
                                (vm_size_t)len, (vm_address_t)buf, &got);
    return (size_t)got;
}

// 安全读 8 字节：所有裸内存读取的唯一入口（SafeReadPtr / CIDRawScan / CIDIntsMatch /
// CIDAsciiScan 全走这里）。v2.4-13 起由 Mach 内核判定，不再依赖信号处理器。
static BOOL DYYYWardProbeRead8(uintptr_t addr, uintptr_t *out) {
    if (!out) return NO;
    uintptr_t v = 0;
    if (!DYYYWardSafeCopy((const void *)addr, &v, sizeof(v))) return NO;
    *out = v;
    return YES;
}

// v2.4-8：类表不可用时的兜底「isa 像不像真类」校验——
// ① isa 地址必须可读；② 必须落在某个已加载镜像里（类对象都在镜像 __DATA/__objc，
//    堆上的假指针/结构体字节不可能稳定指向镜像数据）；③ 从 isa 沿继承链最多 48 跳，
//    每跳解引用前都重新过可读性判定，能走到根类（nil）才收。
// 三层同时满足才放行——比类表哈希松一点，但远紧于「只查地址可读」。
static BOOL DYYYWardIsaLooksLikeClass(uintptr_t isa) {
    if (!isa) return NO;
    if (!DYYYWardAddressReadable(isa)) return NO;
    Dl_info info;
    if (dladdr((void *)isa, &info) == 0 || !info.dli_fbase) return NO;
    Class c = (__bridge Class)(void *)isa; // ARC 禁 uintptr_t 直转 Class，必须走 void* + __bridge（v2.4-8 CI 教训）
    for (int hops = 0; hops < 48; hops++) {
        if (!c) return YES; // 链走到根类 → 像真类
        if (!DYYYWardAddressReadable((uintptr_t)c)) return NO;
        c = class_getSuperclass(c); // c 上一跳已验可读，读它的 superclass 字段才安全
    }
    return NO; // 48 跳还没到头 → 伪类
}

// 安全读 8 字节：先确认地址可读，再读，避免把内联字符串/结构体位模式当指针解引用撞 SIGBUS
static BOOL DYYYWardSafeReadPtr(uintptr_t addr, uintptr_t *out) {
    if (!out) return NO;
    if (!DYYYWardAddressReadable(addr)) return NO; // 廉价预筛（zone/dladdr/vm_region），省 mach trap
    // v2.4-13：终闸改由 Mach 内核判定——预筛万一漏放（垃圾位模式、区域空洞等），
    // vm_read_overwrite 返回错误码而不是发信号，不依赖任何进程级信号处理器。
    return DYYYWardProbeRead8(addr, out);
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
    if (!DYYYWardSafeReadPtr(bits, &isa)) { gDYYYWardLAORejectZone++; return NO; } // 地址不可读 → 伪对象
    if (!isa) { gDYYYWardLAORejectIsa++; return NO; }
    if (!DYYYWardIsRegisteredClass(isa)) { gDYYYWardLAORejectClass++; return NO; } // isa 必须是运行时注册过的类
    return YES;
}

// v2.4-8：校验链自检探针——拿评论 VC（必然活着的真对象）手动跑一遍全链，
// 记录断在哪一环。v2.4-7 实测「vm:0/对象ivar:0/数据源0数组/列表层无根」四洞齐飞，
// 疑校验链把非 tagged 堆对象整批拒掉；这个探针让下一次失败 toast 直接指出断点，
// 不用再猜。断点码：0=没探到对象 1=窗口/对齐 2=可读性 3=isa 4=类表 5=全链通 9=tagged。
static void DYYYWardProbeValidator(void) {
    UIViewController *vc = DYYYWardFindCommentVC();
    if (!vc) { gDYYYWardLAOProbe = 0; return; }
    uintptr_t bits = (uintptr_t)vc;
    if (bits & 0x8000000000000000ULL) { gDYYYWardLAOProbe = 9; return; }
    if (bits < 0x100000000ULL || bits > 0x0000FFFFFFFFFFFFULL || (bits & 0x7)) { gDYYYWardLAOProbe = 1; return; }
    if (!DYYYWardAddressReadable(bits)) { gDYYYWardLAOProbe = 2; return; }
    uintptr_t isa = 0;
    if (!DYYYWardSafeReadPtr(bits, &isa) || !isa) { gDYYYWardLAOProbe = 3; return; }
    if (!DYYYWardIsRegisteredClass(isa)) { gDYYYWardLAOProbe = 4; return; }
    gDYYYWardLAOProbe = 5;
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

// v2.4-8：枚举宿主 VM 用的「深」对象 ivar 表。class_copyIvarList **只返回本类声明的
// ivar**——继承链上的全看不见（UIViewController 的 _view/_childViewControllers、
// Aweme 各基类上挂的 vm）。宿主 VM 若声明在父类，浅表枚举直接漏掉。
// 向上走 5 层继承链，按类缓存；Ivar 指针指向类元数据长期有效。
static NSArray *DYYYWardObjectIvarsDeep(Class cls) {
    if (!cls) return nil;
    static NSMutableDictionary *deepCache = nil;
    if (!deepCache) deepCache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromClass(cls);
    NSArray *cached = [deepCache objectForKey:key];
    if (cached) return cached;
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger depth = 0; cls && depth < 5; depth++) {
        unsigned int ic = 0;
        Ivar *ivars = class_copyIvarList(cls, &ic);
        for (unsigned int i = 0; i < ic; i++) {
            const char *t = ivar_getTypeEncoding(ivars[i]);
            if (t && t[0] == '@') [out addObject:[NSValue valueWithPointer:(void *)ivars[i]]];
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
    [deepCache setObject:out forKey:key];
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

// v2.4-5：标量整数 ivar 缓存（按类）。Swift 模型常把 cid 存成 Int64 存储属性——
// 那是 'q' 标量 ivar，对象 ivar 扫描（DYYYWardObjectIvars 只收 '@'）根本看不见，
// 导致「cell 就在屏上、cid 却永远匹配不上」（二级回复父扫描 380 串无命中的根因之一）。
static NSMutableDictionary *gDYYYWardIntIvarsCache = nil;

static NSArray *DYYYWardIntIvars(Class cls) {
    if (!cls) return nil;
    if (!gDYYYWardIntIvarsCache) gDYYYWardIntIvarsCache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromClass(cls);
    NSArray *cached = [gDYYYWardIntIvarsCache objectForKey:key];
    if (cached) return cached;
    NSMutableArray *out = [NSMutableArray array];
    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    for (unsigned int i = 0; i < ic; i++) {
        const char *t = ivar_getTypeEncoding(ivars[i]);
        // 只收 64 位有/无符号整型：cid 是 19 位雪花号，32 位整型装不下
        if (t && (t[0] == 'q' || t[0] == 'Q')) [out addObject:[NSValue valueWithPointer:(void *)ivars[i]]];
    }
    [gDYYYWardIntIvarsCache setObject:out forKey:key];
    return out;
}

// v2.4-5/6 共用：把 cid 字符串列表转成雪花号量级的 uint64 数值列表。
// v2.4-14：量级从「只认 19 位（1e18~1e19）」放宽到 1e15~1e19。
// 原因：二级回复的父评论 id 未必是 19 位（实测有 18 位），旧口径下 nums 为 nil，
// CIDIntsMatch / CIDRawScan 整段被跳过 —— 而那是 Swift 模型 cid 存成 Int64 时
// 唯一能命中的手段。
// 放宽后仍零误中：arm64 iOS 用户态指针 < 2^48 ≈ 2.81e14，任何 >= 1e15 的值不可能
// 是指针；时间戳 10/13 位（<1e13）、点赞/回复计数都远小于 1e15。
// ⚠️ 上界只能用 1e19（10^19 < ULLONG_MAX 1.8446e19）。写成 1e20 会直接
// 「integer literal is too large」编译失败（v2.4-14 CI run 40019789134 教训）。
static NSArray *DYYYWardCIDNums(NSArray *cidList) {
    if (cidList.count == 0) return nil;
    NSMutableArray *nums = [NSMutableArray arrayWithCapacity:cidList.count];
    for (id c in cidList) {
        if (![c isKindOfClass:[NSString class]]) continue;
        const char *s = [(NSString *)c UTF8String];
        if (!s) continue;
        unsigned long long v = strtoull(s, NULL, 10);
        if (v >= 1000000000000000ULL && v < 10000000000000000000ULL) [nums addObject:@(v)];
    }
    return nums.count > 0 ? nums : nil;
}

// v2.4-5：在对象的 64 位整型 ivar（声明为 'q'/'Q' 的字段）里找「值等于某个 cid」的。
static BOOL DYYYWardCIDIntsMatch(id node, NSArray *nums) {
    if (!node) return NO;
    // v2.4-11：tagged 指针（短 NSString/NSNumber）的「实例」就是指针值本身那 8 字节，
    // 没有实例区可扫；class_getInstanceSize 返回的是类的标称大小，照着扫 base+8 之后
    // 等于读 tagged 值相邻的随机内存 → 可能踩未映射页。GraphMatch 虽对字符串/数字
    // 提前返回，但 tagged 的其他类（NSDate 等）会漏到这里，必须显式刹车。
    if ((uintptr_t)(__bridge const void *)node & 0x8000000000000000ULL) return NO;
    NSArray *ivs = DYYYWardIntIvars(object_getClass(node));
    if (ivs.count == 0) return NO;
    const uint8_t *base = (const uint8_t *)(__bridge const void *)node; // ARC：先 __bridge 到 void*，再转 C 指针
    for (NSValue *iv in ivs) {
        Ivar v = (Ivar)[iv pointerValue];
        ptrdiff_t off = ivar_getOffset(v);
        uint64_t raw = 0;
        // v2.4-12：走信号保护读（memcpy 兼容未对齐偏移；probe 是 8 字节定长读）
        uintptr_t got = 0;
        if (!DYYYWardProbeRead8((uintptr_t)(base + off), &got)) break; // 读不了→整个对象放弃
        raw = (uint64_t)got;
        for (NSNumber *n in nums) {
            if (raw == [n unsignedLongLongValue]) return YES;
        }
    }
    return NO;
}

// v2.4-6：在整个对象实例区里按 8 字节原样搜 cid 数值——不依赖任何字段声明。
// 覆盖前面所有扫描看不见的存储形态：Swift 把评论模型存成「内嵌结构体」时 ivar
// encoding 是 {CommentModel=...}（既不是 '@' 也不是 'q'，对象/标量扫描全瞎），
// 还有定长 int64 数组等。实测 v2.4-5 父扫描 76 行无命中，这是最后一条盲扫路子。
// 安全边界：node 必经 DYYYWardLooksLikeObject 验证；扫描区间
// [base+8, base+class_getInstanceSize) 全部落在对象分配内；只按值精确比对，
// 不做任何解引用/代码执行。误中不可能：cid > 2^62，用户态指针高位必为 0。
static BOOL DYYYWardCIDRawScan(id node, NSArray *nums) {
    if (!node) return NO;
    // v2.4-11：tagged 指针无实例区，刹车（同 CIDIntsMatch 注释）
    if ((uintptr_t)(__bridge const void *)node & 0x8000000000000000ULL) return NO;
    Class cls = object_getClass(node);
    size_t size = class_getInstanceSize(cls);
    if (size <= sizeof(void *) + sizeof(uint64_t)) return NO;
    const uint8_t *base = (const uint8_t *)(__bridge const void *)node;
    size_t limit = size - sizeof(uint64_t);
    // v2.4-12：只探测首尾各一次——对象分配是一整块连续内存，首尾都读得到则中间安全，
    // 中间照旧走快 memcpy（逐字节走 mach trap 的开销没必要）。任一端读不到 → 放弃整个对象。
    uintptr_t guard = 0;
    if (!DYYYWardProbeRead8((uintptr_t)(base + sizeof(void *)), &guard)) return NO;
    if (!DYYYWardProbeRead8((uintptr_t)(base + limit), &guard)) return NO;
    for (size_t off = sizeof(void *); off <= limit; off++) {
        uint64_t raw = 0;
        memcpy(&raw, base + off, sizeof(uint64_t)); // memcpy 兼容未对齐偏移
        for (NSNumber *n in nums) {
            if (raw == [n unsignedLongLongValue]) return YES;
        }
    }
    return NO;
}

// v2.4-7：cid 的 ASCII 字节序列搜索。Swift String 把评论 id 存成字符串时，
// 字符数据在堆上裸缓冲区（不是对象，没有 isa），对象图遍历（LooksLikeObject 拒收）
// 和数值裸扫（存的不是数值）都看不见——只剩「跟进实例区里像堆指针的槽、按字节搜」
// 这一条路。这是对象图/Int64/结构体裸扫全部失手后的最后兜底。
// 安全边界：槽值先过地址窗口（4GB~256TB、8 对齐）+ DYYYWardAddressReadable
// （libmalloc zone / dyld 镜像，全程不解引用候选地址本身）；读的时候每 8 字节
// 一步、每步重新过 AddressReadable，任何一步不可读立即停，绝不越出已确认可读区；
// 只 memcmp 字节，不解引用、不执行任何代码。cid 要求 >=15 位（19 位雪花号，
// 短数字串在堆数据里极易误中）。最多跟进 12 个指针槽/节点，防止成本爆炸。
static BOOL DYYYWardBytesContains(const uint8_t *hay, size_t hayLen, const uint8_t *needle, size_t needleLen) {
    if (!hay || !needle || needleLen == 0 || hayLen < needleLen) return NO;
    for (size_t i = 0; i + needleLen <= hayLen; i++) {
        if (memcmp(hay + i, needle, needleLen) == 0) return YES;
    }
    return NO;
}

static BOOL DYYYWardCIDAsciiScan(id node, NSArray *cidList) {
    if (!node || cidList.count == 0) return NO;
    // v2.4-11：tagged 指针无实例区，刹车（同 CIDIntsMatch 注释）
    if ((uintptr_t)(__bridge const void *)node & 0x8000000000000000ULL) return NO;
    NSMutableArray *pats = [NSMutableArray array];
    for (id c in cidList) {
        if (![c isKindOfClass:[NSString class]]) continue;
        NSString *s = (NSString *)c;
        if (s.length < 15) continue;
        const char *u = [s UTF8String];
        if (!u) continue;
        size_t n = strlen(u);
        if (n < 15 || n > 32) continue;
        [pats addObject:[NSData dataWithBytes:u length:n]];
    }
    if (pats.count == 0) return NO;
    Class cls = object_getClass(node);
    size_t size = class_getInstanceSize(cls);
    if (size <= sizeof(void *) + sizeof(uint64_t)) return NO;
    const uint8_t *base = (const uint8_t *)(__bridge const void *)node;
    size_t limit = size - sizeof(uint64_t);
    NSInteger followed = 0;
    // v2.4-12：节点自身槽位区同样只探测首尾（连续分配），中间走快 memcpy
    uintptr_t guard = 0;
    if (!DYYYWardProbeRead8((uintptr_t)(base + sizeof(void *)), &guard)) return NO;
    if (!DYYYWardProbeRead8((uintptr_t)(base + limit), &guard)) return NO;
    for (size_t off = sizeof(void *); off <= limit && followed < 12; off++) {
        uintptr_t raw = 0;
        memcpy(&raw, base + off, sizeof(uintptr_t));
        if (raw < 0x100000000ULL) continue;          // 用户态窗口粗筛（与 LooksLikeObject 同款判据）
        if (raw > 0x0000FFFFFFFFFFFFULL) continue;   // 超窗口 = 内联字符串/结构体位模式，非指针
        if (raw & 0x7) continue;                     // 8 对齐
        if (!DYYYWardAddressReadable(raw)) continue; // 起始地址确认可读（不解引用）
        followed++;
        uint8_t buf[128];
        // v2.4-13：整块一次交给内核读（原先逐 8 字节试探，最差 16 次 mach trap；
        // 现在 1 次）。可读多少算多少，首字节就不可读则跳过这个槽。
        size_t got = DYYYWardSafeCopySome((const void *)raw, buf, sizeof(buf));
        if (got < 15) continue;
        for (NSData *p in pats) {
            if (DYYYWardBytesContains(buf, got, (const uint8_t *)p.bytes, p.length)) return YES;
        }
    }
    return NO;
}

// v2.4-6 诊断用：cell 字段概况（类名 + 前几个 ivar 名/类型编码，编码截断）。
// 父/子扫描把加载的行全扫遍仍不命中时，这条信息直接说明 cell 到底怎么存数据
// （对象 ivar / 内嵌结构体 / 根本没有模型），下一版精准修，不用继续猜。
static NSString *DYYYWardCellIvarSummary(id cell) {
    if (!cell) return @"";
    Class cls = [cell class];
    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@(%u)", NSStringFromClass(cls), ic];
    NSInteger shown = 0;
    for (unsigned int i = 0; i < ic && shown < 5; i++) {
        const char *n = ivar_getName(ivars[i]);
        const char *t = ivar_getTypeEncoding(ivars[i]);
        if (!n || !t) continue;
        NSString *tn = [NSString stringWithUTF8String:t] ?: @"";
        if (tn.length > 18) tn = [tn substringToIndex:18];
        [s appendFormat:@" %s:%@", n, tn];
        shown++;
    }
    NSString *out = [s copy];
    return out.length > 110 ? [out substringToIndex:110] : out;
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
    // v2.4-5：再扫 64 位整型 ivar 里的 cid（Swift Int64 存储属性，对象扫描看不见）
    // v2.4-6：再整个实例区原样搜（内嵌结构体模型，声明既非 '@' 也非 'q' 时唯一的路）。
    // v2.4-7：depth 门改全局 gDYYYWardRawScanMinDepth（默认 5，列表层直达临时降到 1）；
    // 命中时把「cid 藏在哪个对象实例里」记到 gDYYYWardGraphHitNode（列表层直达要拿模型指针算下标）。
    // ASCII 堆搜索（Swift String 堆存储）同门触发，预算 >100 才跑（尾部不值得再花成本）。
    if (cidList.count > 0 && depth >= gDYYYWardRawScanMinDepth) {
        NSArray *nums = DYYYWardCIDNums(cidList);
        if (nums && (DYYYWardCIDIntsMatch(node, nums) || DYYYWardCIDRawScan(node, nums))) {
            gDYYYWardGraphHitNode = node;
            return YES;
        }
        if (*budget > 100 && DYYYWardCIDAsciiScan(node, cidList)) {
            gDYYYWardGraphHitNode = node;
            return YES;
        }
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

// MARK: - v2.4-2：评论区「目标是否已在位」复核
// 用途：① URL 深链(comment_id)跳转后确认宿主是不是已经把目标评论滚到位（到位就不再跑脆弱的扫描）；
//      ② 二级回复：cid 在主列表不存在，先看它是不是在「已展开的回复列表」里在位，再决定是否按父评论兜底。
// v2.4-18：作者身份确认——在 cell 对象图里搜插眼人 secUid/uid 字符串（GraphMatch 复用，
// probe 走 containsString；secUid "MS4wLjAB…" 全网唯一，命中即该模型属于插眼人）。
// 只作确认信号，绝不单独宣告命中：同作者可有多条评论，单独命中 = 乱找。
static BOOL DYYYWardCellAuthorMatch(id cell, NSString *authorPat) {
    if (!cell || authorPat.length < 12) return NO;
    NSInteger b = 600;
    return DYYYWardGraphMatch(cell, nil, authorPat, 6, &b);
}

// v2.4-20：目标命中前的作者双条件闸（Highlight/TargetVisibleNow/扫描步/直达复核 共用）。
// 老插眼记录没存 secUid/uid → authorPat 为空 → 一律放行（与旧版一致，零回归）。
// 记过/拒计数供真机诊断。核心动机：cid 命中 ≠ 就是这条——回复评论会把目标 cid 当父评论
// 引用（其对象图里能搜到目标 cid），还常抄目标原文，probe+cid 双双命中 = 乱找；
// 作者身份是唯一能区分「这条是插眼人自己发的」与「别人回复/引用了它」的信号。
static BOOL DYYYWardAuthorGateOK(id cell) {
    if (gDYYYWardAuthorPat.length < 12) return YES;
    if (DYYYWardCellAuthorMatch(cell, gDYYYWardAuthorPat)) { gDYYYWardGatePass++; return YES; }
    gDYYYWardGateReject++;
    return NO;
}

// 只查可见 cell 的字符串文本（UILabel/text/accessibilityLabel/ivar），不做全图匹配，也不做任何滚动。
static BOOL DYYYWardCellTextsContain(NSString *txt, NSString *probe) {
    if (txt.length == 0 || probe.length == 0) return NO;
    return [txt rangeOfString:probe].location != NSNotFound;
}

static BOOL DYYYWardCellLooksTargeted(id cell, NSArray *cidList, NSString *contentHint) {
    if (!cell || ![cell isKindOfClass:[UIView class]]) return NO;
    NSString *probe = DYYYWardContentProbe(contentHint, 10);
    if (cidList.count == 0 && probe.length == 0) return NO;
    // v2.4-20：本函数只服务「父评论」搜索（VisibleTargetCell 的两个调用方 2495/2970 都是父路径）。
    // v2.4-18 曾在此加「短探针需作者确认」——但父评论作者≠插眼人（回复的对象通常是别人），
    // 该闸会把短正文的父评论误拒 =「找不到」回归，已移除。作者闸只加在目标（子/一级评论）
    // 命中点：HighlightComment / TargetVisibleNow / 扫描步 / 直达复核。
    UIView *root = (UIView *)cell;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < 200) {
        UIView *cur = [stack lastObject];
        [stack removeLastObject];
        visited++;
        // 无障碍标签里的 cid/正文（最省，且 iOS 上宿主不少 cell 会把整条评论塞进 accessibilityLabel）
        NSString *acc = cur.accessibilityLabel;
        if (acc.length > 0 && acc.length < 4000) {
            if (cidList.count > 0) {
                for (id c in cidList) {
                    if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 4 &&
                        [acc rangeOfString:(NSString *)c].location != NSNotFound) return YES;
                }
            }
            if (DYYYWardCellTextsContain(acc, probe)) return YES;
        }
        if ([cur isKindOfClass:[UILabel class]]) {
            NSString *s = [(UILabel *)cur text];
            if (s.length == 0) s = [(UILabel *)cur attributedText].string;
            if (s.length > 0 && s.length < 4000) {
                if (cidList.count > 0) {
                    for (id c in cidList) {
                        if ([c isKindOfClass:[NSString class]] && ((NSString *)c).length > 4 &&
                            [s isEqualToString:(NSString *)c]) return YES;
                    }
                }
                if (DYYYWardCellTextsContain(s, probe)) return YES;
            }
        } else if ([cur isKindOfClass:[UITextView class]]) {
            NSString *s = [(UITextView *)cur text];
            if (s.length > 0 && s.length < 4000 && DYYYWardCellTextsContain(s, probe)) return YES;
        }
        [stack addObjectsFromArray:cur.subviews];
    }
    // v2.4-14：文本匹配全部落空后，对 cell 对象本身跑 cid 数值/裸扫。
    //
    // 这是「扫尽 305 行 CommentNewCell 仍无命中」的真因：Swift 评论模型把 cid 存成
    // Int64 存储属性（或内嵌结构体），**cell 的 UILabel 里根本没有 cid 字符串**，
    // 上面那套文本匹配永远不可能中；而 v2.4-5/6 就写好的 CIDIntsMatch（'q' 标量
    // ivar 数值比对）/ CIDRawScan（整个实例区 8 字节裸搜）从来只被 DYYYWardGraphMatch
    // 调用，cell 这条最直接的路径一次都没接过——等于把唯一能命中的手段关在门外。
    //
    // 两个函数内部都自带 tagged 刹车 + v2.4-13 的 Mach 安全读，直接调即可。
    if (cidList.count > 0) {
        NSArray *nums = DYYYWardCIDNums(cidList);
        if (nums.count > 0 && (DYYYWardCIDIntsMatch(cell, nums) || DYYYWardCIDRawScan(cell, nums))) return YES;
    }
    return NO;
}

// 取某个列表当前可见 cell 里「看起来就是目标评论」的那一格；没有就返回 nil。不做任何滚动。
static id DYYYWardVisibleTargetCell(UIScrollView *list, NSArray *cidList, NSString *contentHint) {
    if (!list) return nil;
    NSArray *cells = nil;
    if ([list isKindOfClass:[UITableView class]]) cells = [(UITableView *)list visibleCells];
    else if ([list isKindOfClass:[UICollectionView class]]) cells = [(UICollectionView *)list visibleCells];
    for (id c in cells) {
        if (DYYYWardCellLooksTargeted(c, cidList, contentHint)) return c;
    }
    return nil;
}

// 看目标评论是否已在「可见区」就位：命中即返回 YES（不改滚动位置）。
// 正文优先（便宜、且不受字段名影响）；只有正文短/缺失才用 cid 做全图精确确认。
static BOOL DYYYWardTargetVisibleNow(NSArray *cidList, NSString *contentHint) {
    if (cidList.count == 0 && contentHint.length == 0) return NO;
    UIViewController *cvc = DYYYWardFindCommentVC();
    if (!cvc || !cvc.view) return NO;
    NSString *probe = DYYYWardContentProbe(contentHint, 10);
    for (UIScrollView *sv in DYYYWardCommentListViews(cvc)) {
        NSArray *cells = nil;
        if ([sv isKindOfClass:[UITableView class]]) cells = [(UITableView *)sv visibleCells];
        else cells = [(UICollectionView *)sv visibleCells];
        for (id cell in cells) {
            if (![cell isKindOfClass:[UIView class]]) continue;
            if (probe.length > 0 && DYYYWardCellQuickMatch(cell, probe)) {
                if (cidList.count == 0) { if (DYYYWardAuthorGateOK(cell)) return YES; } // v2.4-20
                NSInteger b = 1200;
                // v2.4-20：cid 复核通过后仍过作者闸（回复引用目标 cid + 抄原文会双双命中）
                if (DYYYWardGraphMatch(cell, cidList, nil, 8, &b) && DYYYWardAuthorGateOK(cell)) return YES;
            }
            if (probe.length == 0 && cidList.count > 0) {
                NSInteger b = 1500;
                if (DYYYWardGraphMatch(cell, cidList, nil, 8, &b) && DYYYWardAuthorGateOK(cell)) return YES; // v2.4-20
            }
        }
    }
    return NO;
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
            // v2.4-7：depth 3→8——v2.4-5/6 的 Int64/裸扫门是 depth>=5，depth 3 时它们
            // 从来没在数据源路径上跑过（只跑了字符串比对），Swift 模型 cid 是标量时必败。
            // 预算 200/项封顶：这是按屏扫描之外的兜底路径，不能为它把主线程卡住。
            if (cidList.count > 0) { NSInteger bg = 200; if (DYYYWardGraphMatch(item, cidList, nil, 8, &bg)) return (NSInteger)i; }
            if (probe.length > 0) { NSInteger bg = 200; if (DYYYWardGraphMatch(item, @[], probe, 8, &bg)) return (NSInteger)i; }
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

// 把「模型数组里的扁平下标」换算成 indexPath（table/CV 通用，分段感知）。
// 行数只用公开 API 问（不调 dataSource 回调）；段数封顶 8 防异常表。
// v2.4-7：从 DYYYWardScrollListToIndex 提取出来，供列表层直达的父/子两条路径共用。
static NSIndexPath *DYYYWardIndexPathForFlatIndex(UIScrollView *scroll, NSInteger idx) {
    if (!scroll || idx < 0) return nil;
    if ([scroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)scroll;
        NSInteger sections = tv.numberOfSections;
        if (sections < 1) sections = 1;
        if (sections > 8) sections = 8;
        NSInteger remain = idx;
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = 0;
            if (s < tv.numberOfSections) rows = [tv numberOfRowsInSection:s];
            if (rows > 0 && remain < rows) return [NSIndexPath indexPathForRow:remain inSection:s];
            remain -= rows;
        }
        return nil;
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
            if (items > 0 && remain < items) return [NSIndexPath indexPathForItem:remain inSection:s];
            remain -= items;
        }
        return nil;
    }
    return nil;
}

// v2.4-9：滚动前的最后一道界检。numberOfSections/Items 的查询与 scrollTo 之间，
// 宿主 Swift 数据源可能已变（评论面板刚打开时正在加载/分页），越界 index path 会让
// UICollectionView/UITableView 的 Swift 内部 trap（SIGTRAP，@try 拦不住）→ 秒退。
// v2.4-8 让校验链复活后，列表层直达/数据源定位第一次真正滚起来，必须补这道闸。
static BOOL DYYYWardIndexPathInBounds(UIScrollView *scroll, NSIndexPath *ip) {
    if (!scroll || !ip) return NO;
    if (!scroll.window) return NO; // v2.4-10：面板还没上屏/已被移除，别滚
    if (ip.section < 0 || ip.row < 0 || ip.item < 0) return NO;
    if ([scroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)scroll;
        if (ip.section >= tv.numberOfSections) return NO;
        return ip.row < [tv numberOfRowsInSection:ip.section];
    }
    if ([scroll isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)scroll;
        if (ip.section >= cv.numberOfSections) return NO;
        return ip.item < [cv numberOfItemsInSection:ip.section];
    }
    return NO;
}
static BOOL DYYYWardScrollListToIndex(UIScrollView *scroll, NSInteger idx, NSArray *cidList, NSString *contentHint) {
    if (!scroll || idx < 0) return NO;
    NSIndexPath *ip = DYYYWardIndexPathForFlatIndex(scroll, idx);
    if (!ip) return NO;
    if (!DYYYWardIndexPathInBounds(scroll, ip)) return NO; // v2.4-9：界检防 Swift trap 秒退
    if ([scroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)scroll;
        // v2.4-10：定位滚动一律 animated:NO——动画中途宿主数据源变化会让滚动目标
        // 失效，UIKit/宿主 Swift 内部对失效动画 trap（@try 拦不住）
        @try { [tv scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; } @catch (NSException *e) { return NO; }
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
                if (!DYYYWardAuthorGateOK(cell)) return; // v2.4-20：模型数组下标滚到的格子也要过作者闸
                DYYYWardScrollAndHighlight(tv, cell);
                [DYYYUtils showToast:@"已定位到该评论"];
                gDYYYWardLocateDone = gDYYYWardLocateGen;
            } @catch (NSException *e) {}
        });
        return YES;
    }
    if ([scroll isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)scroll;
        // v2.4-10：animated:NO，理由同上（防动画中途数据源变化 trap）
        @try { [cv scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO]; } @catch (NSException *e) { return NO; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
                if (!cell) return;
                // v2.4-7：CV 分支原来滚完只高亮、不复核也不置 done（table 分支却两者都做）——
                // 下标来自模型数组本就可信，补上与 table 一致的按值复核，命中才收尾。
                BOOL hit = NO;
                NSInteger budget = 400;
                if (cidList.count > 0) hit = DYYYWardGraphMatch(cell, cidList, nil, 4, &budget);
                if (!hit) {
                    NSString *p = DYYYWardContentProbe(contentHint, 10);
                    if (p.length > 0) { NSInteger b2 = 1500; hit = DYYYWardGraphMatch(cell, @[], p, 8, &b2); }
                }
                if (!hit) return;
                if (!DYYYWardAuthorGateOK(cell)) return; // v2.4-20：CV 分支同 table，过作者闸
                DYYYWardScrollAndHighlight(cv, cell);
                [DYYYUtils showToast:@"已定位到该评论"];
                gDYYYWardLocateDone = gDYYYWardLocateGen;
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
    // v2.4-10：总闸——模型未加载时不调宿主方法（防宿主 Swift trap 秒退，见上方注释）
    if (!DYYYWardCIDModelLoaded(commentID)) {
        gDYYYWardHostLocateMethods = @"宿主调用:跳过(模型未加载→防Swift trap)";
        return;
    }
    // v2.4-9：白名单只收「名字带 ID/CID」的选择器。scrollToComment:/locateComment:/
    // focusComment:/highlightComment: 收的是评论**模型对象**（v2.3-28 注释即警告），
    // 把 cid 字符串塞进去 → 宿主 Swift 强转失败 fatalError → SIGTRAP 秒退（@try 拦不住）。
    // v2.4-8 校验链复活后这些调用第一次真正执行，真机实测评论面板秒崩，必须删。
    NSArray *selNames = @[ @"scrollToCommentWithID:", @"scrollToCommentWithCommentID:",
                           @"scrollToCommentWithCID:", @"locateCommentWithCommentID:",
                           @"scrollToCommentWithCommentID:animated:" ];
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
        // v2.4-7：6 个固定名全 miss（Swift 面板的 vm 名不固定——实测 vm:0 的真因：
        // 类名对得上、vm 名一个都不对）→ 枚举 VC 及其子 VC 的**全部对象 ivar**，
        // 每个候选都当过签名校验的宿主 VM 试白名单。取值走 object_getIvar（不发消息，
        // 裸 '@' 槽也安全）+ DYYYWardLooksLikeObject（只读 isa + 查已注册类表）；
        // 调用走 DYYYWardInvokeHostLocate（respondsToSelector: + 参数个数/类型校验后才
        // performSelector:）——两层防护下盲调安全。封顶 24 个候选防耗时。
        // v2.4-8：ivar 表改深表（含 5 层继承链，class_copyIvarList 只看本类）；
        // 诊断改 tried/seen——「0/0」= 这个类压根没有对象 ivar，「0/37」= 有 37 个
        // 但校验链把值全拒了（v2.4-7 四洞齐飞疑点的直接证据）。
        if (invoked.length == 0) {
            NSMutableArray *owners = [NSMutableArray arrayWithObject:vc];
            for (UIViewController *ch in vc.childViewControllers) {
                if (owners.count >= 5) break;
                if (ch && ch != vc) [owners addObject:ch];
            }
            NSInteger tried = 0, seen = 0;
            for (id owner in owners) {
                if (invoked.length > 0 || tried >= 24) break;
                for (NSValue *iv in DYYYWardObjectIvarsDeep(object_getClass(owner))) {
                    if (tried >= 24) break;
                    seen++;
                    Ivar v = (Ivar)[iv pointerValue];
                    id val = object_getIvar(owner, v);
                    if (!DYYYWardLooksLikeObject(val)) continue;
                    if (val == owner || val == vc) continue;
                    // v2.4-9：深枚举只对「评论相关类」试调。v2.4-8 只验了 LooksLikeObject
                    // 就 performSelector，无关对象（播放控制/数据管理类）上的同名方法
                    // 语义未知，传 cid 字符串可能触发宿主 Swift trap 秒退（真机实测）。
                    // 类名闸 + id 类白名单双重收窄；真 VM 类名必含 Comment（面板即评论面板）。
                    NSString *valCls = NSStringFromClass([val class]);
                    if (![valCls containsString:@"omment"]) continue;
                    tried++;
                    NSString *d = DYYYWardInvokeHostLocate(val, selNames, commentID);
                    if (d.length > 0) {
                        invoked = d;
                        if (detail.length < 200) [detail appendFormat:@" ivarVM已调用(%@:%@)", d, NSStringFromClass([val class])];
                        break;
                    }
                }
            }
            vmCount += tried;
            if (detail.length < 220) [detail appendFormat:@" 对象ivar:%ld/%ld", (long)tried, (long)seen];
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
    NSString *jumpMsg = @""; // v2.4-7：列表层直达结果
    if (gDYYYWardListJumpDiag.length > 0) {
        jumpMsg = [NSString stringWithFormat:@" %@", gDYYYWardListJumpDiag];
    }
    // v2.4-8：对象校验链自检——探针断点 + 分环节拒绝次数。
    // 探针码：0=没探到VC 1=窗口/对齐断 2=可读性断 3=isa断 4=类表断 5=全链通 9=tagged。
    // 正常应是「探针:5」且 zone/isa/类 三个计数接近 0；若「探针:2/4」+ 类计数几千，
    // 就是校验链把真对象整批拒了（v2.4-7 四洞齐飞的那个疑点）。
    NSString *laoMsg = [NSString stringWithFormat:@" 校验:区%ld isa%ld 类%ld 探针:%ld",
                        (long)gDYYYWardLAORejectZone, (long)gDYYYWardLAORejectIsa,
                        (long)gDYYYWardLAORejectClass, (long)gDYYYWardLAOProbe];
    // v2.4-13：安全读机制自检结论。若这里不是「安全读:vm_read_overwrite」，说明
    // 内核安全读不可用 → 所有裸读已 fail closed（整条扫描停摆，定位必然失败），
    // 属「宁可定位失败也不崩」的既定行为，日志里必须能一眼看出。
    NSString *safeMsg = @"";
    if (gDYYYWardSafeReadNote.length > 0) {
        safeMsg = [NSString stringWithFormat:@" %@", gDYYYWardSafeReadNote];
    } else {
        safeMsg = [NSString stringWithFormat:@" 安全读:%@", DYYYWardSafeReadReady() ? @"可用" : @"不可用(已停摆)"];
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
    NSString *urlMsg = @"";
    if (gDYYYWardURLDiag.length > 0) {
        urlMsg = [NSString stringWithFormat:@" 深链:%@", gDYYYWardURLDiag];
    }
    NSString *parentMsg = @"";
    if (gDYYYWardParentDiag.length > 0) {
        parentMsg = [NSString stringWithFormat:@" 父:%@", gDYYYWardParentDiag];
    }
    // v2.4-20：作者双条件闸计数。过=作者确认过目标；拒=挡掉的疑似乱找（回复引用目标 cid /
    // 抄原文）。若「过0 拒N」= 目标自己都没过闸（secUid 不在 cell 对象图里 → 闸误伤真目标），
    // 下一版要把作者确认改从模型层取；若「过1 拒N」= 闸正常工作，乱找被挡。
    NSString *gateMsg = @"";
    if (gDYYYWardGatePass > 0 || gDYYYWardGateReject > 0) {
        gateMsg = [NSString stringWithFormat:@" 作者闸:过%ld/拒%ld", (long)gDYYYWardGatePass, (long)gDYYYWardGateReject];
    }
    [DYYYUtils showToast:[NSString stringWithFormat:@"%@：%@%@%@%@%@%@%@%@%@ 行:%ld 偏移:%.0f",
                          prefix, reason, urlMsg, parentMsg, hostMsg, dsMsg, jumpMsg, laoMsg, safeMsg, gateMsg,
                          (long)maxRows, off]];
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
            // v2.4-9：界检防查询-滚动竞态（分页期间行数在变）→ Swift trap 秒退
            if (DYYYWardIndexPathInBounds(t, lastIP)) {
                @try { [t scrollToRowAtIndexPath:lastIP atScrollPosition:UITableViewScrollPositionBottom animated:NO]; } @catch (NSException *e) {}
            }
        }
        @try { [t setContentOffset:CGPointMake(0, MAX(0, t.contentSize.height - t.bounds.size.height)) animated:NO]; } @catch (NSException *e) {}
        // 网络分页不是瞬时的（实测 0.7s 常不够），所以同一次到底最多重试 6 次（每次 1.2s）再判失败，
        // 避免「其实还能翻页、只是还没回来」被误报成定位失败（v2.4-6：3 次对 372 条评论不够）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen || token != gDYYYWardSweepToken) return;
            NSInteger nowTotal = 0;
            for (NSInteger s = 0; s < t.numberOfSections; s++) nowTotal += [t numberOfRowsInSection:s];
            if (nowTotal > total) {
                DYYYWardSweepStep(t, cidList, contentHint, gen, total, nowTotal, 0, token); // 已翻出更多，接着扫
            } else if (pageTry < 5) {
                DYYYWardSweepStep(t, cidList, contentHint, gen, total, total, pageTry + 1, token); // 还没回来，再等等
            } else {
                // v2.4-6：先释放 sweepGen，主循环才能在后续步（i==6/12）重起父扫描——
                // 渐进滚动期间宿主可能又加载出更多评论，父评论也许在新行里。
                gDYYYWardSweepGen = 0;
                gDYYYWardLocateDiag = [NSString stringWithFormat:@"扫尽%ld行 %@", (long)total, DYYYWardCellIvarSummary([t visibleCells].firstObject)];
                DYYYWardShowLocateFailure(); // 重试 6 次仍无新行，真到底了
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
    // v2.4-9：界检防查询-滚动竞态（分页期间行数在变）→ Swift trap 秒退
    if (!DYYYWardIndexPathInBounds(t, ip)) return;
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
            // v2.4-14：cid 全图搜不再要求「正文没匹配上」才跑。
            // 旧逻辑是「有正文时走便宜路径，只有正文太短/缺失（probe 为空）才做昂贵的
            // 全图 cid 搜索」——只要插眼时存到了正文（probe 非空）而 cell 文本又没命中
            // （正文被表情短码/[看] 破坏、换行截断，或父评论根本不是这条正文），
            // GraphMatch 就一次都不跑，cid 这条独立的路被白白跳过。
            // 「扫尽 305 行无命中」就是这么来的。quick 命中仍照旧只做确认性全图（省时间），
            // 未命中则必须靠 cid 兜底。
            if (quick) {
                if (cidList.count == 0) exact = YES;
                else { NSInteger b = 1200; exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b); }
            } else if (cidList.count > 0) {
                NSInteger b = 1500;
                exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b);
            }
            // v2.4-20：目标（非父）命中过作者双条件闸——回复引用目标 cid + 抄原文会
            // quick+exact 双双命中；作者不符即拒，继续扫后面的格子（真目标可能在下方）。
            if ((quick || exact) && !gDYYYWardSweepForParent && !DYYYWardAuthorGateOK(cell)) { /* 拒，继续 */ }
            else if (quick || exact) { hitCell = cell; }
        }
        if (hitCell) {
            if (gDYYYWardSweepForParent) { // v2.4-4：父扫描命中 → 点开回复再回来找子评论
                DYYYWardParentSweepHit(hitCell, t, gen);
                return;
            }
            DYYYWardScrollAndHighlight(t, hitCell);
            [DYYYUtils showToast:[NSString stringWithFormat:@"已定位：%@", probe.length > 0 ? probe : @"该评论"]];
            gDYYYWardLocateDone = gen;
            return;
        }
        NSInteger next = (maxFlat >= flat) ? (maxFlat + 1) : (flat + 1); // 本屏最大行之后继续；无可见行就前挪一行
        DYYYWardSweepStep(t, cidList, contentHint, gen, next, total, pageTry, token);
    });
}

// v2.4-3：table/collection 通吃的行数统计（选「行数最多的列表」扫描用）
static NSInteger DYYYWardListRowCount(UIScrollView *sv) {
    if ([sv isKindOfClass:[UITableView class]]) {
        UITableView *t = (UITableView *)sv;
        NSInteger c = 0;
        for (NSInteger s = 0; s < t.numberOfSections; s++) c += [t numberOfRowsInSection:s];
        return c;
    }
    if ([sv isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)sv;
        NSInteger c = 0;
        for (NSInteger s = 0; s < cv.numberOfSections; s++) c += [cv numberOfItemsInSection:s];
        return c;
    }
    return 0;
}

// v2.4-3：UICollectionView 版按屏扫描。新 Swift 评论区的列表是 collection view
//（cell 类名 AWECommentPanelHeaderSwiftImpl.CommentPanelHeaderNewCell 实测），
// v2.4-2 的 DYYYWardSweepRows 只挑 UITableView → 扫描整段根本没跑（失败 toast 只剩
// 可见区比对的那条「无匹配」诊断）。逻辑与 DYYYWardSweepStep 完全同构：
// 领头行滚到顶 → 0.14s 后整屏 cell 一次性比对 → 下一屏；到底滚最后一格触发分页，重试 3 次判失败。
static void DYYYWardSweepStepCV(UICollectionView *cv, NSArray *cidList, NSString *contentHint, NSInteger gen,
                                NSInteger flat, NSInteger total, NSInteger pageTry, NSInteger token) {
    if (!cv || gDYYYWardLocateDone == gen || total <= 0) return;
    if (token != gDYYYWardSweepToken) return; // 已被取消（宿主接管/重新起扫），旧链自行退出
    if (flat >= total) {
        // 已扫到当前已加载末尾：滚到最后一格触发分页加载，重新读行数，变多就接着扫
        NSIndexPath *lastIP = nil;
        for (NSInteger s = cv.numberOfSections - 1; s >= 0; s--) {
            NSInteger rows = [cv numberOfItemsInSection:s];
            if (rows > 0) { lastIP = [NSIndexPath indexPathForItem:rows - 1 inSection:s]; break; }
        }
        if (lastIP) {
            // v2.4-9：界检防查询-滚动竞态（分页期间行数在变）→ Swift trap 秒退
            if (DYYYWardIndexPathInBounds(cv, lastIP)) {
                @try { [cv scrollToItemAtIndexPath:lastIP atScrollPosition:UICollectionViewScrollPositionBottom animated:NO]; } @catch (NSException *e) {}
            }
        }
        @try { [cv setContentOffset:CGPointMake(0, MAX(0, cv.contentSize.height - cv.bounds.size.height)) animated:NO]; } @catch (NSException *e) {}
        // v2.4-6：分页耐心加到 6 次 × 1.2s（372 条评论的场景 3 次不够）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen || token != gDYYYWardSweepToken) return;
            NSInteger nowTotal = 0;
            for (NSInteger s = 0; s < cv.numberOfSections; s++) nowTotal += [cv numberOfItemsInSection:s];
            if (nowTotal > total) {
                DYYYWardSweepStepCV(cv, cidList, contentHint, gen, total, nowTotal, 0, token);
            } else if (pageTry < 5) {
                DYYYWardSweepStepCV(cv, cidList, contentHint, gen, total, total, pageTry + 1, token);
            } else {
                // v2.4-6：释放 sweepGen，让主循环后续步能重起父扫描；带 cell 字段概况便于下版精准修
                gDYYYWardSweepGen = 0;
                gDYYYWardLocateDiag = [NSString stringWithFormat:@"扫尽%ld行 %@", (long)total, DYYYWardCellIvarSummary([cv visibleCells].firstObject)];
                DYYYWardShowLocateFailure();
            }
        });
        return;
    }
    // 用户正在滑就别抢滚动条，等松手再继续
    if (cv.isDragging || cv.isDecelerating) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYWardSweepStepCV(cv, cidList, contentHint, gen, flat, total, pageTry, token);
        });
        return;
    }
    NSIndexPath *ip = nil;
    NSInteger remain = flat;
    for (NSInteger s = 0; s < cv.numberOfSections; s++) {
        NSInteger rows = [cv numberOfItemsInSection:s];
        if (rows > 0 && remain < rows) { ip = [NSIndexPath indexPathForItem:remain inSection:s]; break; }
        remain -= rows;
    }
    if (!ip) return;
    // v2.4-9：界检防查询-滚动竞态（分页期间行数在变）→ Swift trap 秒退
    if (!DYYYWardIndexPathInBounds(cv, ip)) return;
    // 领头行顶到列表顶部（不是 Middle），一屏能覆盖 flat 之后的 6~7 个新行
    @try { [cv scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionTop animated:NO]; } @catch (NSException *e) { return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.14 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDYYYWardLocateDone == gen || token != gDYYYWardSweepToken) return;
        NSString *probe = DYYYWardContentProbe(contentHint, 10);
        NSInteger sectionCount = cv.numberOfSections;
        // theos SDK 头文件里 UICollectionView 无 indexPathsForVisibleRows 声明（CI 实测编译错），
        // 用 visibleCells + indexPathForCell: 等价收集（iOS 6 起就有）
        NSMutableArray *visible = [NSMutableArray array];
        for (id c in [cv visibleCells]) {
            NSIndexPath *vip2 = [cv indexPathForCell:c];
            if (vip2) [visible addObject:vip2];
        }
        NSInteger maxFlat = -1;
        id hitCell = nil;
        for (NSIndexPath *vip in visible) {
            if (vip.section >= sectionCount) continue;
            NSInteger rowsInSection = [cv numberOfItemsInSection:vip.section];
            if (vip.row >= rowsInSection) continue;
            NSInteger fi = vip.row;
            for (NSInteger s = 0; s < vip.section; s++) fi += [cv numberOfItemsInSection:s];
            if (fi < flat) continue;                 // 上一屏已经查过
            if (fi > maxFlat) maxFlat = fi;
            if (hitCell) continue;
            id cell = [cv cellForItemAtIndexPath:vip];
            if (!cell) continue;
            BOOL quick = (probe.length > 0) && DYYYWardCellQuickMatch(cell, probe);
            BOOL exact = NO;
            // v2.4-14：cid 全图搜不再要求「正文没匹配上」才跑。
            // 旧逻辑是 `else if (probe.length == 0 && cidList.count > 0)`——只要插眼时
            // 存到了正文（probe 非空）而 cell 文本又没命中（正文被表情短码/[看] 破坏、
            // 换行截断、或父评论根本不是这条正文），GraphMatch 就一次都不跑，
            // cid 这条独立的路被白白跳过 → 「扫尽 305 行无命中」就是这么来的。
            // quick 命中仍照旧只做确认性全图（省时间），未命中则必须靠 cid 兜底。
            if (quick) {
                if (cidList.count == 0) exact = YES;
                else { NSInteger b = 1200; exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b); }
            } else if (cidList.count > 0) {
                NSInteger b = 1500;
                exact = DYYYWardGraphMatch(cell, cidList, nil, 8, &b);
            }
            // v2.4-20：目标（非父）命中过作者双条件闸——回复引用目标 cid + 抄原文会
            // quick+exact 双双命中；作者不符即拒，继续扫后面的格子（真目标可能在下方）。
            if ((quick || exact) && !gDYYYWardSweepForParent && !DYYYWardAuthorGateOK(cell)) { /* 拒，继续 */ }
            else if (quick || exact) { hitCell = cell; }
        }
        if (hitCell) {
            if (gDYYYWardSweepForParent) { // v2.4-4：父扫描命中 → 点开回复再回来找子评论
                DYYYWardParentSweepHit(hitCell, cv, gen);
                return;
            }
            DYYYWardScrollAndHighlight(cv, hitCell);
            [DYYYUtils showToast:[NSString stringWithFormat:@"已定位：%@", probe.length > 0 ? probe : @"该评论"]];
            gDYYYWardLocateDone = gen;
            return;
        }
        NSInteger next = (maxFlat >= flat) ? (maxFlat + 1) : (flat + 1);
        DYYYWardSweepStepCV(cv, cidList, contentHint, gen, next, total, pageTry, token);
    });
}

// MARK: - v2.4-15 展开回复入口：「有展开的能定位到、没展开的不行」的正面修复
//
// 老实现（v2.4-4 起）只有两条判定、一条点击：
//   判定① UILabel.text 含「回复/展开/reply」→ 判定② 沿 superview 找 UIButton → sendActions。
// 真机「未展开」的 cell 一个都走不通，直接落到「无回复按钮」，子评论从没被加载出来，
// 后面扫多少行都是白扫 —— 这正好解释用户实测「有展开的能定位到，没展开的还是不行」：
// 已展开时 cell 里有「收起」，老实现第 480 行 `return YES` 直接跳过点击，而子评论本来就在列表里。
//
// 三个漏洞，逐个补：
//  ① 取文字太窄：只认 UILabel。抖音新评论区的「展开N条回复」多半是 YYLabel / AWE 自定义
//     label（**不是 UILabel 子类**），text 走自定义 getter → 现在按 selector 取，先用
//     method_getReturnType 确认返回对象类型，再兜 accessibilityLabel/Value。
//  ② 点击太窄：只认 UIButton。Swift/AWE 侧大量入口是「普通 UIView + UITapGestureRecognizer」。
//     → 补两条：任意 UIControl 祖先、手势 target/action、以及无障碍 activate。
//  ③ 入口不在父 cell 里：分组布局下「展开N条回复」可能是独立的一格（父 cell 的下一格）。
//     → cell 内找不到就顺带看父 cell 的下一格。
// 另加一条：点了没生效就换下一个候选再点（最多 2 个），每个候选给 1s 观察窗。
//
// 安全边界（一条都不放松）：
//  · 所有内存读走 v2.4-13 的 Mach 安全读（DYYYWardSafeCopy），读之前就由内核判可读；
//  · 手势的 target/action 是私有 ivar，读不到（类布局变了）就 fail closed 返回 NO，不猜；
//  · 调用前用 methodSignature 校验：UIKit 触发手势永远是 (void)xxx:(UIGestureRecognizer *)，恰好 3 个参数，
//    签名对不上就不调 —— 不会重演 v2.3-20 那种「盲调参数未知的私有方法」的崩溃。

// 这里为什么不用 objc_msgSend 也不用 performSelector:withObject: ？
//  · performSelector: 的返回类型写死成 id，而手势回调是 void —— ARC 会拿 x0 里的残留值
//    当对象去 retain/autorelease，等于随机指针解引用。绝对不能用。
//  · objc_msgSend 强转虽然在 ARC 下通常可用，但每处都要手写精确原型，一旦类型对不上就是
//    未定义行为，且本机没有 clang 无法第一时间发现。
// 统一改用「声明一个只含目标方法的协议 + 转换」来取值（返回对象，ARC 语义正确），
// 以及 NSInvocation 来触发（它能正确区分 void 返回，不碰返回值）。
@protocol DYYYWardTextGetter <NSObject>
- (NSString *)text;
- (NSAttributedString *)attributedText;
@end

@protocol DYYYWardA11yActivate <NSObject>
- (BOOL)accessibilityActivate;
@end

// 取一个视图上的文字。UILabel 走常规字段；非 UILabel（YYLabel/AWE 自定义 label）按 selector 取，
// 先用 method_getReturnType 确认返回对象类型再调用 —— 返回标量时直接跳过，绝不把整数当对象 retain。
static NSString *DYYYWardViewText(UIView *v) {
    if (!v) return nil;
    NSString *out = nil;
    if ([v isKindOfClass:[UILabel class]]) {
        out = [(UILabel *)v text];
        if (out.length == 0) out = [(UILabel *)v attributedText].string;
    } else {
        id<DYYYWardTextGetter> g = (id<DYYYWardTextGetter>)v;
        SEL selText = NSSelectorFromString(@"text");
        SEL selAttr = NSSelectorFromString(@"attributedText");
        // 先 text：返回类型必须是对象，否则跳过（有些宿主类的 text 是结构体/枚举）
        Method mt = [v respondsToSelector:selText] ? class_getInstanceMethod(object_getClass(v), selText) : NULL;
        if (mt) {
            char rt[16];
            method_getReturnType(mt, rt, sizeof(rt));
            if (rt[0] == '@') {
                @try {
                    NSString *s = [g text];
                    if ([s isKindOfClass:[NSString class]]) out = s;
                } @catch (NSException *e) {}
            }
        }
        if (out.length == 0) {
            Method ma = [v respondsToSelector:selAttr] ? class_getInstanceMethod(object_getClass(v), selAttr) : NULL;
            if (ma) {
                char rt[16];
                method_getReturnType(ma, rt, sizeof(rt));
                if (rt[0] == '@') {
                    @try {
                        NSAttributedString *a = [g attributedText];
                        if ([a isKindOfClass:[NSAttributedString class]]) out = a.string;
                    } @catch (NSException *e) {}
                }
            }
        }
    }
    if (out.length == 0) out = v.accessibilityLabel;
    if (out.length == 0) out = v.accessibilityValue;
    return out;
}

// v2.4-22：定位高亮「精准框」的取框矩形。评论 cell 是整行（头像+昵称+正文+时间+操作行），
// 整行描边在窄屏上就是「一大块」。这里框 cell 的「内容列」：
//   左边界 = cell 内最左「有文字」视图的左沿（昵称/正文/时间/展开入口都贴在内容列左沿；
//            UIImageView 显式排除——头像是图片视图且可能带用户名 accessibilityLabel，
//            不排除会被它把左沿拽回头像位置，框又变回一大块）；
//   右/上/下 = 固定小内缩。
// 兜底链（任何命中路径都有框，零回归）：
//   ① 一个文本视图都没有（纯 cid 命中的 Swift cell 可能没有可见文本）→ 固定经验左内缩 52pt；
//   ② 内容列算废了（宽/高过低）→ 退整个 cell bounds（= v2.4-21 及以前的行为）。
static CGRect DYYYWardContentColumnRect(UIView *cellView) {
    CGRect bounds = cellView.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return bounds;
    CGFloat leftEdge = CGFLOAT_MAX;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:cellView];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < 300) {
        UIView *cur = [stack lastObject];
        [stack removeLastObject];
        visited++;
        // 跳过：cell 自身、图片视图（头像/徽章）、不可见视图（隐藏或全透明）
        if (cur != cellView && ![cur isKindOfClass:[UIImageView class]] && !cur.hidden && cur.alpha > 0.01) {
            if (DYYYWardViewText(cur).length > 0) {
                CGRect r = [cur convertRect:cur.bounds toView:cellView];
                // 只认「像文本行」的视图：够宽、在 cell 水平范围内（滤掉溢出/裁剪的子视图）
                if (r.size.width >= 20 && r.size.height >= 8 &&
                    r.origin.x >= -0.5 && CGRectGetMaxX(r) <= bounds.size.width + 0.5) {
                    if (r.origin.x < leftEdge) leftEdge = r.origin.x;
                }
            }
        }
        [stack addObjectsFromArray:cur.subviews];
    }
    CGFloat leftInset;
    if (leftEdge < CGFLOAT_MAX) {
        leftInset = MAX(leftEdge - 6.0, 0.0);   // 文本左沿再让 6pt 呼吸位
        CGFloat cap = bounds.size.width * 0.4;  // 防抖：左内缩不超过 40% 宽
        if (leftInset > cap) leftInset = cap;
    } else {
        leftInset = MIN(52.0, bounds.size.width * 0.25); // 无文本视图：按头像列经验值
    }
    CGFloat rightInset = MIN(12.0, bounds.size.width * 0.1);
    CGRect col = bounds;
    col.origin.x += leftInset;
    col.size.width -= (leftInset + rightInset);
    col.origin.y += 2.0;
    col.size.height -= 4.0;
    if (col.size.width < 48 || col.size.height < 16) return bounds; // 算废了退整框
    return col;
}

// 「展开N条回复 / 共N条回复 / 查看N条回复 / N条回复」判定：必须同时出现「回复」类词和
// 「展开/查看/更多/全部/共/条」类词。单靠「回复」会误中评论正文，单靠「展开」会误中「展开说说」。
static BOOL DYYYWardLooksLikeExpandText(NSString *t) {
    if (t.length == 0 || t.length > 40) return NO;
    if ([t rangeOfString:@"收起"].location != NSNotFound) return NO; // 那是收起入口，点了会折叠
    NSString *low = t.lowercaseString;
    BOOL hasReply = [t rangeOfString:@"回复"].location != NSNotFound ||
                    [t rangeOfString:@"回覆"].location != NSNotFound ||
                    [low rangeOfString:@"repl"].location != NSNotFound;
    if (!hasReply) return NO;
    return [t rangeOfString:@"展开"].location != NSNotFound ||
           [t rangeOfString:@"查看"].location != NSNotFound ||
           [t rangeOfString:@"更多"].location != NSNotFound ||
           [t rangeOfString:@"全部"].location != NSNotFound ||
           [t rangeOfString:@"共"].location != NSNotFound ||
           [t rangeOfString:@"条"].location != NSNotFound;
}

// 已展开判定：cell 里有「收起…回复」这类短文案 → 不必再点，直接找子评论。
static BOOL DYYYWardCellShowsCollapse(UIView *cell) {
    if (!cell) return NO;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:cell];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < 260) {
        UIView *cur = [stack lastObject];
        [stack removeLastObject];
        visited++;
        NSString *t = DYYYWardViewText(cur);
        if (t.length > 0 && t.length <= 24 &&
            [t rangeOfString:@"收起"].location != NSNotFound &&
            ([t rangeOfString:@"回复"].location != NSNotFound || [t rangeOfString:@"条"].location != NSNotFound)) {
            return YES;
        }
        [stack addObjectsFromArray:cur.subviews];
    }
    return NO;
}

// 按名字取「非对象」ivar 的原始 8 字节（SEL / 裸指针）。SEL 的 encoding 是 ':'，
// 走不了 object_getIvar —— 只能算偏移 + 安全读。偏移小于 isa 大小就跳过，别把 isa 读出来。
static BOOL DYYYWardIvarRaw8(id obj, NSString *name, uintptr_t *out) {
    if (!obj || name.length == 0 || !out) return NO;
    NSString *wantUnderscore = [@"_" stringByAppendingString:name];
    Class cls = object_getClass(obj);
    for (NSInteger depth = 0; cls && depth < 4; depth++) {
        unsigned int ic = 0;
        Ivar *ivars = class_copyIvarList(cls, &ic);
        BOOL hit = NO;
        for (unsigned int i = 0; i < ic; i++) {
            const char *n = ivar_getName(ivars[i]);
            if (!n) continue;
            NSString *cn = [NSString stringWithUTF8String:n];
            if (!cn) continue;
            if (![cn isEqualToString:name] && ![cn isEqualToString:wantUnderscore]) continue;
            ptrdiff_t off = ivar_getOffset(ivars[i]);
            uintptr_t raw = 0;
            if (off >= (ptrdiff_t)sizeof(void *) &&
                DYYYWardSafeCopy((const void *)((uintptr_t)(__bridge void *)obj + (uintptr_t)off), &raw, sizeof(raw))) {
                *out = raw;
                hit = YES;
            }
            break;
        }
        if (ivars) free(ivars);
        if (hit) return YES;
        cls = class_getSuperclass(cls);
    }
    return NO;
}

static BOOL DYYYWardViewHasTapGesture(UIView *v) {
    for (id gr in v.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) return YES;
    }
    return NO;
}

// 触发视图上第一个 UITapGestureRecognizer 的 target/action（等价于真点一下）。
// UIGestureRecognizer 没有公开的 action 列表，只能读私有 ivar：
//   _targets = NSArray<UIGestureRecognizerTarget *>，元素上是 _target(id) + _action(SEL)。
// 任一环节读不到/签名对不上 → 返回 NO（不猜、不盲调）。
static BOOL DYYYWardFireTapGesture(UIView *v) {
    NSArray *grs = v.gestureRecognizers;
    if (grs.count == 0) return NO;
    for (id gr in grs) {
        if (![gr isKindOfClass:[UITapGestureRecognizer class]]) continue;
        id targetsObj = DYYYWardIvarNamed(gr, @"targets");
        if (![targetsObj isKindOfClass:[NSArray class]]) continue;
        for (id t in (NSArray *)targetsObj) {
            if (!t) continue;
            id target = DYYYWardIvarNamed(t, @"target");
            if (!target) continue;
            uintptr_t raw = 0;
            if (!DYYYWardIvarRaw8(t, @"action", &raw)) continue;
            SEL action = (SEL)raw;
            if (!action) continue;
            if (![target respondsToSelector:action]) continue;
            NSMethodSignature *sig = [target methodSignatureForSelector:action];
            if (!sig || sig.numberOfArguments != 3) continue; // UIKit 触发手势固定 3 参：self/_cmd/gr
            // 用 NSInvocation 而不是 performSelector: —— 后者返回类型写死 id，
            // 遇到 void 的手势回调会把 x0 残留值当对象 retain（随机崩）。
            @try {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                if (!inv) continue;
                [inv setTarget:target];
                [inv setSelector:action];
                id arg = gr;
                [inv setArgument:&arg atIndex:2];
                [inv invoke];
                return YES;
            } @catch (NSException *e) { return NO; }
        }
    }
    return NO;
}

// 这个视图最终会被「点」在哪个对象上：UIControl 祖先 > 带点按手势的祖先 > 自己。
// 只用于候选去重和决定从哪一层点。
static UIView *DYYYWardActivationOwner(UIView *v) {
    UIView *p = v;
    for (NSInteger i = 0; i < 6 && p; i++) {
        if ([p isKindOfClass:[UIControl class]]) return p;
        p = p.superview;
    }
    p = v;
    for (NSInteger i = 0; i < 6 && p; i++) {
        if (DYYYWardViewHasTapGesture(p)) return p;
        p = p.superview;
    }
    return v;
}

// 把一个视图变成一次真实点击。三种手段按可靠性排序，任一成功即返回 YES 并写出手法（进诊断）。
static BOOL DYYYWardActivateView(UIView *v, NSString **how) {
    if (!v) return NO;
    // ① UIControl（UIButton / AWE 自定义 control）——最标准，等价于真点
    UIView *p = v;
    for (NSInteger i = 0; i < 6 && p; i++) {
        if ([p isKindOfClass:[UIControl class]]) {
            @try { [(UIControl *)p sendActionsForControlEvents:UIControlEventTouchUpInside]; }
            @catch (NSException *e) { return NO; }
            if (how) *how = @"按钮";
            return YES;
        }
        p = p.superview;
    }
    // ② 点按手势（Swift 侧最常见）
    p = v;
    for (NSInteger i = 0; i < 6 && p; i++) {
        if (DYYYWardFireTapGesture(p)) { if (how) *how = @"手势"; return YES; }
        p = p.superview;
    }
    // ③ 无障碍激活（公开能力，不保证宿主实现；返回 NO 就当没试过）
    p = v;
    for (NSInteger i = 0; i < 4 && p; i++) {
        if ([p respondsToSelector:@selector(accessibilityActivate)]) {
            BOOL ok = NO;
            @try { ok = [(id<DYYYWardA11yActivate>)p accessibilityActivate]; }
            @catch (NSException *e) { ok = NO; }
            if (ok) { if (how) *how = @"无障碍"; return YES; }
        }
        p = p.superview;
    }
    return NO;
}

// 在一个视图树里收集「展开回复」候选（按 DYYYWardActivationOwner 去重）
static void DYYYWardCollectExpandIn(UIView *root, NSMutableArray *out, NSInteger budget) {
    if (!root || !out) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < budget) {
        UIView *cur = [stack lastObject];
        [stack removeLastObject];
        visited++;
        if (DYYYWardLooksLikeExpandText(DYYYWardViewText(cur))) {
            UIView *owner = DYYYWardActivationOwner(cur);
            BOOL dup = NO;
            for (UIView *e in out) { if (e == owner) { dup = YES; break; } }
            if (!dup) [out addObject:owner];
        }
        [stack addObjectsFromArray:cur.subviews];
    }
}

static UIScrollView *DYYYWardOwningList(UIView *v) {
    UIView *cur = v;
    for (NSInteger i = 0; i < 12 && cur; i++) {
        if ([cur isKindOfClass:[UICollectionView class]] || [cur isKindOfClass:[UITableView class]]) {
            return (UIScrollView *)cur;
        }
        cur = cur.superview;
    }
    return nil;
}

// 同一 section 里的下一格（只取已上屏的 cell；没有就返回 nil）。
// 先过 isKindOfClass 再发消息：把非 cell 的 UIView 喂给 indexPathForCell: 在 Swift CV 上会 trap。
static UIView *DYYYWardNextCell(UIScrollView *list, UIView *cell) {
    if (!list || !cell) return nil;
    NSIndexPath *ip = nil;
    @try {
        if ([list isKindOfClass:[UICollectionView class]] && [cell isKindOfClass:[UICollectionViewCell class]]) {
            ip = [(UICollectionView *)list indexPathForCell:(UICollectionViewCell *)cell];
        } else if ([list isKindOfClass:[UITableView class]] && [cell isKindOfClass:[UITableViewCell class]]) {
            ip = [(UITableView *)list indexPathForCell:(UITableViewCell *)cell];
        }
    } @catch (NSException *e) { return nil; }
    if (!ip) return nil;
    NSInteger rows = 0;
    @try {
        if ([list isKindOfClass:[UICollectionView class]]) rows = [(UICollectionView *)list numberOfItemsInSection:ip.section];
        else rows = [(UITableView *)list numberOfRowsInSection:ip.section];
    } @catch (NSException *e) { return nil; }
    if (ip.row + 1 >= rows) return nil;
    NSIndexPath *nx = [NSIndexPath indexPathForItem:ip.row + 1 inSection:ip.section];
    @try {
        if ([list isKindOfClass:[UICollectionView class]]) return [(UICollectionView *)list cellForItemAtIndexPath:nx];
        return [(UITableView *)list cellForRowAtIndexPath:nx];
    } @catch (NSException *e) { return nil; }
    return nil;
}

// 候选收集：先父 cell 内部；一个都没有再看父 cell 的下一格（分组布局的独立「展开」行）。
// 排序：落在 cell 本身（说明只是正文里带了「回复+展开」字样）的候选排最后。
static void DYYYWardCollectExpandCandidates(UIView *cell, NSMutableArray *out) {
    if (!cell || !out) return;
    DYYYWardCollectExpandIn(cell, out, 300);
    if (out.count == 0) {
        UIView *nx = DYYYWardNextCell(DYYYWardOwningList(cell), cell);
        if (nx) DYYYWardCollectExpandIn(nx, out, 300);
    }
    if (out.count > 1) {
        NSMutableArray *selfOwned = [NSMutableArray array];
        NSMutableArray *others = [NSMutableArray array];
        for (UIView *v in out) {
            if (v == cell) [selfOwned addObject:v];
            else [others addObject:v];
        }
        [out removeAllObjects];
        [out addObjectsFromArray:others];
        [out addObjectsFromArray:selfOwned];
    }
}

// 注意：v2.4-4 那个「单发版」DYYYWardExpandRepliesOnCell 已被 DYYYWardExpandStep 完全取代
//（多候选 + 多手法 + 两轮 + 观察窗），这里不再保留单发实现，免得两条点击路互相抢。

// v2.4-15：本轮「父评论 cid」+ 展开轮次。点了没反应时按父 cid 重新把父 cell 找回来再点一轮
//（第一次点击可能让宿主重建了 cell，之前抓到的候选视图已经脱离视图树，再点等于点空气）。
static NSArray *gDYYYWardParentIDs = nil;
static NSInteger gDYYYWardExpandRound = 0;

// 按父 cid/正文在当前可见区重新找回父 cell；找不到返回 nil（不滚动、不猜测）
static UIView *DYYYWardRefindParentCell(void) {
    if (gDYYYWardParentIDs.count == 0) return nil;
    UIViewController *cvc = DYYYWardFindCommentVC();
    if (!cvc) return nil;
    for (UIScrollView *sv in DYYYWardCommentListViews(cvc)) {
        id c = DYYYWardVisibleTargetCell(sv, gDYYYWardParentIDs, @"");
        if (c && [c isKindOfClass:[UIView class]] && [(UIView *)c window]) return (UIView *)c;
    }
    return nil;
}

// 子评论一次性查找：宿主定位方法 → 可见区复核。命中即置 LocateDone 并返回 YES。
static BOOL DYYYWardChildLookupOnce(NSInteger gen) {
    NSArray *childCids = gDYYYWardChildCIDs ?: @[];
    NSString *childHint = gDYYYWardChildHint ?: @"";
    for (NSString *cid in childCids) {
        DYYYWardTryHostLocateComment(cid);
        if (gDYYYWardLocateDone == gen) { gDYYYWardFailCount = 0; return YES; }
    }
    if (DYYYWardTargetVisibleNow(childCids, childHint)) {
        gDYYYWardLocateDone = gen;
        gDYYYWardFailCount = 0;
        [DYYYUtils showToast:@"已定位到该评论"];
        return YES;
    }
    return NO;
}

// 子评论总兜底：还找不到就从头按行扫（回复没展开/没加载完时只能这样）
static void DYYYWardChildLookupFinal(NSInteger gen) {
    if (gDYYYWardLocateDone == gen) return;
    if (DYYYWardChildLookupOnce(gen)) return;
    gDYYYWardSweepGen = 0;
    DYYYWardSweepRows(gDYYYWardChildCIDs ?: @[], gDYYYWardChildHint ?: @"", gen);
}

// 候选逐个试：点不动就立刻换下一个；点动了给 1s 观察窗，子评论还没出来再换下一个。
// 全部试完仍没有 → 走总兜底（按行扫）。这比 v2.4-4「只点一个、点不中就放弃」多两层容错。
static void DYYYWardExpandStep(NSArray *cands, NSInteger idx, NSInteger gen) {
    if (gDYYYWardLocateDone == gen) return;
    if (idx >= (NSInteger)cands.count) {
        // v2.4-15：第一轮候选全试完还没结果 → 按父 cid 把父 cell 重新找回来再点第二轮
        //（第一轮点击常让宿主重建 cell，先前抓到的候选视图已脱离视图树，再点等于点空气）
        if (gDYYYWardExpandRound == 0) {
            gDYYYWardExpandRound = 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDYYYWardLocateDone == gen) return;
                UIView *fresh = DYYYWardRefindParentCell();
                if (fresh && DYYYWardCellShowsCollapse(fresh)) {
                    gDYYYWardParentDiag = @"父已展开";
                    DYYYWardChildLookupFinal(gen);
                    return;
                }
                NSMutableArray *round2 = [NSMutableArray array];
                if (fresh) DYYYWardCollectExpandCandidates(fresh, round2);
                if (round2.count > 0) {
                    gDYYYWardParentDiag = @"再试一轮";
                    DYYYWardExpandStep(round2, 0, gen);
                    return;
                }
                DYYYWardChildLookupFinal(gen);
            });
            return;
        }
        DYYYWardChildLookupFinal(gen);
        return;
    }
    id obj = [cands objectAtIndex:(NSUInteger)idx];
    UIView *v = [obj isKindOfClass:[UIView class]] ? (UIView *)obj : nil;
    NSString *how = nil;
    BOOL ok = DYYYWardActivateView(v, &how);
    if (!ok) {
        // 这个候选点不动（没有手势/不是 control/无障碍不认）→ 立刻换下一个，不必等
        if (idx + 1 >= (NSInteger)cands.count) gDYYYWardParentDiag = @"展开入口点不动";
        DYYYWardExpandStep(cands, idx + 1, gen);
        return;
    }
    gDYYYWardParentDiag = [NSString stringWithFormat:@"点展开(%@)", how ?: @"?"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDYYYWardLocateDone == gen) return;
        if (DYYYWardChildLookupOnce(gen)) return;
        DYYYWardExpandStep(cands, idx + 1, gen); // 点了但子评论没出来 → 换下一个候选
    });
}

// v2.4-4：父扫描命中后的统一动作：点开父 cell 的回复 → 1s 后回来定位子评论
// （宿主方法 → 可见区复核 → 都不中再起子扫描）。不置 LocateDone——子还没找到。
// v2.4-7：从 DYYYWardParentSweepHit 提取，父扫描命中/可见区命中/列表层直达命中三条父路径共用。
// v2.4-15：改成「多候选 + 多手法」；父已展开（有「收起」）时直接找子，不再空点。
// 前置：调用方必须先置 gDYYYWardParentHandled=YES、gDYYYWardSweepForParent=NO、
// gDYYYWardChildCIDs/ChildHint（子评论 cid/正文）。
static void DYYYWardExpandThenFindChild(id cell, NSInteger gen) {
    UIView *cellView = [cell isKindOfClass:[UIView class]] ? (UIView *)cell : nil;
    gDYYYWardExpandRound = 0; // 换了新的父 cell 命中 → 两轮展开额度重新给
    if (cellView && DYYYWardCellShowsCollapse(cellView)) {
        gDYYYWardParentDiag = @"父已展开";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYWardChildLookupFinal(gen);
        });
        return;
    }
    NSMutableArray *cands = [NSMutableArray array];
    if (cellView) DYYYWardCollectExpandCandidates(cellView, cands);
    if (cands.count == 0) {
        gDYYYWardParentDiag = @"无回复入口";
        // 入口找不到不代表子评论不在（父可能就是展开态，只是文案不同）→ 立刻找一次再扫
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYWardChildLookupFinal(gen);
        });
        return;
    }
    // 最多试 2 个（多试没收益，只会把时间拉长）
    while (cands.count > 2) [cands removeLastObject];
    DYYYWardExpandStep(cands, 0, gen);
}

static void DYYYWardParentSweepHit(id cell, UIScrollView *list, NSInteger gen) {
    (void)list;
    gDYYYWardSweepForParent = NO;
    gDYYYWardParentHandled = YES;
    DYYYWardExpandThenFindChild(cell, gen);
}

// v2.4-4：父评论按屏扫描（二级回复父不在首屏的唯一活路）。
// v2.4-5：probe 取父评论正文（parentTexts 里第一个非空）——Swift cell 的 cid 可能是
// Int64 标量，对象图搜不到，而 cell 上的 UILabel 文本永远可靠；cid 仍作辅助匹配。
// 老插眼记录没有 parentTexts 时退回纯 cid 匹配（v2.4-5 的整型 ivar 扫描也能兜底）。
static void DYYYWardSweepParentThenExpand(NSArray *parentIDs, NSArray *childCidList, NSString *childContentHint, NSArray *parentTexts, NSInteger gen) {
    if (parentIDs.count == 0) return;
    gDYYYWardChildCIDs = childCidList;
    gDYYYWardChildHint = childContentHint;
    gDYYYWardParentIDs = parentIDs; // v2.4-15：供「再试一轮」按父 cid 重新找回父 cell
    gDYYYWardSweepForParent = YES;
    NSString *parentProbe = @"";
    for (id t in parentTexts) {
        if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) { parentProbe = (NSString *)t; break; }
    }
    gDYYYWardParentDiag = (parentProbe.length > 0) ? @"扫描父评论(按文本)" : @"扫描父评论(仅cid)";
    DYYYWardSweepRows(parentIDs, parentProbe, gen);
}

// MARK: - v2.4-7 列表层直达（换根搜：从 cell 图换到列表数据层）
//
// 之前所有搜索都从 cell 出发，但 cell 只有屏上 ~10 个，模型全在列表数据层——
// 92 条已加载评论的模型在 dataSource/delegate 的对象图里。逐屏扫 cell 既慢又脆
// （二级回复父扫描「扫尽 92 行不命中」的真因：cid 不在 cell 可达图，cell 只有
// 8 个 ivar、viewmodel 是 cell 级 VM）。本链路换根：从列表的 dataSource/delegate
// （公开属性直接取，不爬 responder 链）和评论 VC 作根跑图搜，命中模型对象指针后
// 按**指针相等**在候选数组里算下标，scrollToItem/Row 一跳到位——已加载里有目标
// 就一次命中，不必翻屏；顺带能在目标未加载时给出明确诊断。

// 收集列表层搜索根：每个列表的 dataSource + delegate（公开属性）+ 数据源上挂的
// viewModel/model/listViewModel（ivar 名取值，不过 KVC）+ 评论 VC 本身。
// v2.4-8：ds/del/commentVC 都是公开 API 的返回值——按构造就是真对象，不再过
// LooksLikeObject（v2.4-7 实测「无根」：校验链疑把堆对象整批拒掉，公开 API 的
// 返回值不该再被自家校验卡一道）。它们随后进 GraphMatch，图搜内部对每个节点
// 的 ivar 值仍然逐层校验，安全边界不撤。
static NSArray *DYYYWardListLayerRoots(UIViewController *commentVC) {
    NSMutableArray *roots = [NSMutableArray array];
    NSArray *lists = commentVC ? DYYYWardCommentListViews(commentVC) : @[];
    for (UIScrollView *sv in lists) {
        if (![sv isKindOfClass:[UIScrollView class]]) continue;
        id ds = nil, del = nil;
        if ([sv isKindOfClass:[UITableView class]]) {
            ds = [(UITableView *)sv dataSource];
            del = [(UITableView *)sv delegate];
        } else if ([sv isKindOfClass:[UICollectionView class]]) {
            ds = [(UICollectionView *)sv dataSource];
            del = [(UICollectionView *)sv delegate];
        }
        if (ds && ds != sv) [roots addObject:ds];
        if (del && del != sv && del != ds) [roots addObject:del];
        for (NSString *k in @[ @"viewModel", @"model", @"listViewModel" ]) {
            id vm = DYYYWardIvarNamed(ds, k); // ds 为 nil 时安全返回 nil
            if (vm && vm != ds) {
                BOOL dup = NO;
                for (id e in roots) { if (e == vm) { dup = YES; break; } }
                if (!dup) [roots addObject:vm];
            }
        }
    }
    if (commentVC) {
        BOOL dup = NO;
        for (id e in roots) { if (e == commentVC) { dup = YES; break; } }
        if (!dup) [roots addObject:commentVC];
    }
    return roots;
}

// 在列表层对象图里找「cid 藏在哪个对象实例里」。临时把裸扫门降到 1
// （模型离 dataSource 根只有 2~4 层，默认门 5 会整段瞎），用完即恢复。
// 命中节点由数值/裸扫/ASCII 三处命中点记到 gDYYYWardGraphHitNode；
// 字符串/NSNumber 相等命中拿不到模型指针（hitNode 为 nil），调用方回退按数组内容搜。
static BOOL DYYYWardListLayerFindModel(NSArray *roots, NSArray *cidList, id *outModel) {
    if (outModel) *outModel = nil;
    if (roots.count == 0 || cidList.count == 0) return NO;
    NSInteger savedGate = gDYYYWardRawScanMinDepth;
    gDYYYWardRawScanMinDepth = 1;
    BOOL found = NO;
    @try {
        for (id root in roots) {
            if (!DYYYWardLooksLikeObject(root)) continue;
            NSInteger budget = 500;
            gDYYYWardGraphHitNode = nil;
            if (DYYYWardGraphMatch(root, cidList, nil, 5, &budget)) { found = YES; break; }
        }
    } @catch (NSException *e) {
        found = NO;
    }
    gDYYYWardRawScanMinDepth = savedGate; // 任何路径都恢复，别让门漏回去
    if (found && outModel) *outModel = gDYYYWardGraphHitNode;
    return found;
}

// v2.4-7：广口收集候选数组——不靠 ivar 名启发式（Swift 字段名不在白名单，
// 「数据源0数组」的真因之一），任何 '@' ivar 只要是规模合理的 NSArray 就要。
// 内容命中由图搜/指针相等把关，伪数组只花时间不错判。封顶防爆。
static NSArray *DYYYWardListLayerArrays(id obj) {
    if (!obj) return @[];
    NSMutableArray *out = [NSMutableArray array];
    Class cls = object_getClass(obj);
    for (NSInteger depth = 0; cls && depth < 3 && out.count < 16; depth++) {
        unsigned int ic = 0;
        Ivar *ivars = class_copyIvarList(cls, &ic);
        for (unsigned int i = 0; i < ic && out.count < 16; i++) {
            const char *t = ivar_getTypeEncoding(ivars[i]);
            if (!DYYYWardIvarTypeIsDeclaredObject(t)) continue;
            id v = object_getIvar(obj, ivars[i]); // 不发消息，裸 '@' 槽安全
            if (!DYYYWardLooksLikeObject(v)) continue;
            if (![v isKindOfClass:[NSArray class]]) continue;
            NSUInteger c = [(NSArray *)v count];
            if (c == 0 || c > 5000) continue;
            BOOL dup = NO;
            for (NSArray *exist in out) { if (exist == (NSArray *)v) { dup = YES; break; } }
            if (!dup) [out addObject:v];
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
    return out;
}

// 在候选数组里按**指针相等**找模型下标（数组元素就是模型本身；极快且零误判）。
// 元素是包装对象（section/wrapper）时，往下看一层对象 ivar 是否指向同一模型。
static NSInteger DYYYWardIndexOfModelInArrays(NSArray *arrays, id model) {
    if (arrays.count == 0 || !model) return NSNotFound;
    for (NSArray *arr in arrays) {
        if (![arr isKindOfClass:[NSArray class]]) continue;
        NSUInteger n = arr.count;
        if (n == 0 || n > 5000) continue;
        for (NSUInteger i = 0; i < n; i++) {
            @autoreleasepool {
                id e = [arr objectAtIndex:i];
                if (e == model) return (NSInteger)i; // 指针比对，不发消息
                if (!e || !DYYYWardLooksLikeObject(e)) continue;
                for (NSValue *iv in DYYYWardObjectIvars(object_getClass(e))) {
                    Ivar v = (Ivar)[iv pointerValue];
                    if (object_getIvar(e, v) == model) return (NSInteger)i;
                }
            }
        }
    }
    return NSNotFound;
}

// v2.4-7：列表层直达核心。根搜命中模型 → 指针相等算下标 → 滚动 → 0.7s 复核。
// isParent=YES 时滚到的是父评论：复核命中后不置 done，而是点开回复、1s 后
// 回来定位子评论（二级回复全流程收尾，与父扫描命中走同一条 ExpandThenFindChild）。
// 返回 YES = 已发起滚动（复核在 0.7s 后的 block 里，命中才收尾）。
static BOOL DYYYWardListLayerJumpCore(NSArray *targetCIDs, NSString *contentHint, NSInteger gen, NSInteger urlGen, BOOL isParent, NSArray *childCidList) {
    if (targetCIDs.count == 0) { gDYYYWardListJumpDiag = @"列表层:无cid"; return NO; }
    UIViewController *commentVC = DYYYWardFindCommentVC();
    if (!commentVC) { gDYYYWardListJumpDiag = @"列表层:评论区未打开"; return NO; }
    NSArray *lists = DYYYWardCommentListViews(commentVC);
    NSArray *roots = DYYYWardListLayerRoots(commentVC);
    // v2.4-8：无根时带上列表数——列表 0 = 找错了 VC（面板不在这个 VC 的视图树里）；
    // 列表 >0 却无根 = 根收集逻辑出问题。两者修法完全不同，必须分清。
    if (roots.count == 0) { gDYYYWardListJumpDiag = [NSString stringWithFormat:@"列表层:无根(列表%ld)", (long)lists.count]; return NO; }
    id model = nil;
    BOOL found = DYYYWardListLayerFindModel(roots, targetCIDs, &model);
    if (!found) { gDYYYWardListJumpDiag = @"列表层:未命中(未加载?)"; return NO; }
    // 候选数组：所有根对象的广口收集，指针去重
    NSMutableArray *arrays = [NSMutableArray array];
    for (id root in roots) {
        for (NSArray *a in DYYYWardListLayerArrays(root)) {
            BOOL dup = NO;
            for (NSArray *exist in arrays) { if (exist == a) { dup = YES; break; } }
            if (!dup) [arrays addObject:a];
        }
    }
    NSInteger idx = NSNotFound;
    if (model) idx = DYYYWardIndexOfModelInArrays(arrays, model);
    if (idx == NSNotFound) {
        // 回退：按数组内容搜（cid 图搜/正文）。v2.4-7 起 depth 8，Int64/裸扫真正生效
        for (NSArray *a in arrays) {
            NSInteger i2 = DYYYWardIndexInArray(a, targetCIDs, contentHint);
            if (i2 != NSNotFound) { idx = i2; break; }
        }
    }
    if (idx == NSNotFound) { gDYYYWardListJumpDiag = @"列表层:命中模型但算不出下标"; return NO; }
    // 选行数最多的列表滚（评论区可能同时存在多个列表实例）
    UIScrollView *best = nil; NSInteger total = 0;
    for (UIScrollView *sv in DYYYWardCommentListViews(commentVC)) {
        NSInteger c = DYYYWardListRowCount(sv);
        if (c > total) { total = c; best = sv; }
    }
    if (!best || total <= 0 || idx >= total) {
        gDYYYWardListJumpDiag = [NSString stringWithFormat:@"列表层:idx%ld超行数%ld", (long)idx, (long)total];
        return NO;
    }
    NSIndexPath *ip = DYYYWardIndexPathForFlatIndex(best, idx);
    if (!ip) { gDYYYWardListJumpDiag = @"列表层:下标换算失败"; return NO; }
    // v2.4-9：滚前界检——flat 下标按模型数组算，与列表实际段/行布局可能有偏差
    // （段头、加载中 cell、分页竞态），越界会让宿主 CV 的 Swift 内部 trap 秒退
    if (!DYYYWardIndexPathInBounds(best, ip)) {
        gDYYYWardListJumpDiag = [NSString stringWithFormat:@"列表层:下标越界(s%ld,i%ld)", (long)ip.section, (long)ip.item];
        return NO;
    }
    gDYYYWardListJumpDiag = [NSString stringWithFormat:@"列表层:idx%ld/行%ld", (long)idx, (long)total];
    if ([best isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)best;
        // v2.4-10：animated:NO，防动画中途数据源变化 trap
        @try { [tv scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; } @catch (NSException *e) { return NO; }
    } else {
        UICollectionView *cv = (UICollectionView *)best;
        @try { [cv scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO]; } @catch (NSException *e) { return NO; }
    }
    gDYYYWardLocatePending = gDYYYWardLocateGen; // 已精确滚到目标，勿再渐进滚动
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDYYYWardLocatePending == gen) gDYYYWardLocatePending = 0; // 复核失败则放行主循环继续兜底
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDYYYWardLocateDone == gen) return;
        if (gDYYYWardURLGen != urlGen) return; // 新一次「查看」已开始，旧链作废
        @try {
            id cell = nil;
            if ([best isKindOfClass:[UITableView class]]) cell = [(UITableView *)best cellForRowAtIndexPath:ip];
            else cell = [(UICollectionView *)best cellForItemAtIndexPath:ip];
            if (!cell) return;
            // 按值复核（cid 或正文片段），不因此否定——下标来自模型数组本就可信
            BOOL hit = NO;
            NSInteger budget = 400;
            if (targetCIDs.count > 0) hit = DYYYWardGraphMatch(cell, targetCIDs, nil, 4, &budget);
            if (!hit && contentHint.length > 0) {
                NSString *p = DYYYWardContentProbe(contentHint, 10);
                if (p.length > 0) { NSInteger b2 = 1500; hit = DYYYWardGraphMatch(cell, @[], p, 8, &b2); }
            }
            if (!hit) return;
            // v2.4-20：一级/子目标过作者闸；父路径（isParent）不过——父评论作者≠插眼人
            if (!isParent && !DYYYWardAuthorGateOK(cell)) return;
            DYYYWardScrollAndHighlight(best, cell);
            if (isParent) {
                // 父路径：不置 done——点开回复，1s 后回来定位子评论
                gDYYYWardParentHandled = YES;
                gDYYYWardChildCIDs = childCidList ?: @[];
                gDYYYWardChildHint = contentHint ?: @"";
                gDYYYWardListJumpDiag = @"列表层:命中父,已展开";
                DYYYWardExpandThenFindChild(cell, gen);
            } else {
                [DYYYUtils showToast:@"已定位到该评论"];
                gDYYYWardLocateDone = gen;
                gDYYYWardFailCount = 0;
            }
        } @catch (NSException *e) {}
    });
    return YES;
}

// v2.4-7：一级评论的列表层直达（二级回复的父评论在 LocateParentThenExpand 里直接走 Core）。
static BOOL DYYYWardListLayerJump(NSArray *cidList, NSString *contentHint, NSInteger gen, NSInteger urlGen) {
    return DYYYWardListLayerJumpCore(cidList, contentHint, gen, urlGen, NO, nil);
}

static void DYYYWardSweepRows(NSArray *cidList, NSString *contentHint, NSInteger gen) {
    if (gDYYYWardSweepGen == gen) return;      // 本代已经在扫，别叠加第二条扫描链（两条会互相抢滚动）
    // 多实例：把每个候选评论 VC 里的 table/collection 都算进来，选行数最多的那个
    //（v2.4-3 起不再只认 UITableView —— Swift 新评论区列表是 collection view，之前整段扫描没跑）
    UIScrollView *bestList = nil; NSInteger total = 0;
    NSArray *vcs = DYYYWardAllCommentVCs();
    if (vcs.count == 0) {
        UIViewController *one = DYYYWardFindCommentVC();
        if (one) vcs = @[ one ];
    }
    for (UIViewController *vc in vcs) {
        for (UIScrollView *sv in DYYYWardCommentListViews(vc)) {
            NSInteger c = DYYYWardListRowCount(sv);
            if (c > total) { total = c; bestList = sv; }
        }
    }
    if (!bestList || total <= 0) return;
    gDYYYWardSweepGen = gen;                  // 告知主循环：已在按行扫描，跳过渐进滚动（防互相打架）
    gDYYYWardSweepToken++;                    // 新令牌：让上一代还在排队的步骤失效
    NSInteger token = gDYYYWardSweepToken;
    // 起点不一定是 0：宿主定位方法常已经把列表带到目标附近（二级回复尤其），
    // 这时从当前可见处往上留一屏重叠再往下扫，比每次从第 0 行重扫既快又更容易命中。
    NSInteger start = 0;
    NSArray *visIPs = nil;
    if ([bestList isKindOfClass:[UITableView class]]) visIPs = [(UITableView *)bestList indexPathsForVisibleRows];
    else if ([bestList isKindOfClass:[UICollectionView class]]) {
        // theos SDK 无 UICollectionView.indexPathsForVisibleRows 声明 → visibleCells 等价收集
        NSMutableArray *tmp = [NSMutableArray array];
        UICollectionView *bcv = (UICollectionView *)bestList;
        for (id c in [bcv visibleCells]) {
            NSIndexPath *ip2 = [bcv indexPathForCell:c];
            if (ip2) [tmp addObject:ip2];
        }
        visIPs = tmp;
    }
    NSIndexPath *firstVisible = visIPs.firstObject;
    if (firstVisible) {
        NSInteger fi = firstVisible.row;
        for (NSInteger s = 0; s < firstVisible.section; s++) {
            if ([bestList isKindOfClass:[UITableView class]]) fi += [(UITableView *)bestList numberOfRowsInSection:s];
            else if ([bestList isKindOfClass:[UICollectionView class]]) fi += [(UICollectionView *)bestList numberOfItemsInSection:s];
        }
        start = MAX(0, fi - 6);
    }
    if ([bestList isKindOfClass:[UITableView class]]) {
        DYYYWardSweepStep((UITableView *)bestList, cidList, contentHint, gen, start, total, 0, token);
    } else {
        DYYYWardSweepStepCV((UICollectionView *)bestList, cidList, contentHint, gen, start, total, 0, token);
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

// v2.4-21 起整条「父定位→展开→找子」链停用（用户拍板放弃未加载/未展开的二级回复定位：
// 连续多轮实测，展开入口点不中/子评论不加载/宿主深链高亮父评论造成「乱找」观感，投入产出比
// 已经为负）。函数体保留备查，不再被调用；二级回复改走 DYYYWardLocateComment 开头的
// 「在位即定位（TargetVisibleNow+作者闸）/ 不在位即明确放弃」策略。
// 先按父评论定位，再点开「回复」，最后把子 cid 交给宿主定位/扫描。
// parentIDs 为空（老插眼记录没有）直接返回 NO，不拿子 cid 去冒充父。
// v2.4-7：加 urlGen 参数（列表层直达的 0.7s 复核 block 要校验「还是本次查看」），
// 并在 ① 宿主方法 与 ② 可见区之间插入「列表层直达跳父评论」。
// v2.4-14：parentTexts 也参与「可见区直接找父」——v2.4-5 起父正文只喂给了
// DYYYWardSweepParentThenExpand（按屏扫描），可见区这条最便宜的路径一直传 nil，
// 等于把文本匹配关掉、只按 cid 找，白白多滚一屏。
static BOOL DYYYWardLocateParentThenExpand(NSArray *parentIDs, NSArray *cidList, NSString *contentHint, NSInteger gen, NSInteger urlGen, NSArray *parentTexts) {
    if (parentIDs.count == 0) return NO;
    NSMutableArray *pids = [NSMutableArray array];
    for (id p in parentIDs) {
        if ([p isKindOfClass:[NSString class]] && ((NSString *)p).length > 0 && ![pids containsObject:(NSString *)p]) {
            [pids addObject:(NSString *)p];
        }
    }
    if (pids.count == 0) return NO;
    gDYYYWardParentIDs = pids; // v2.4-15：供「再试一轮」按父 cid 重新找回父 cell
    gDYYYWardParentDiag = @"按父定位";
    // ① 宿主方法：父 cid 是主列表 id，scrollToCommentWithID: 通常有效
    for (NSString *pid in pids) {
        DYYYWardTryHostLocateComment(pid);
        if (gDYYYWardLocateDone == gen) return YES;
    }
    // ①.5 v2.4-7：列表层直达跳父评论——从 dataSource/delegate 根搜到父模型指针，
    // 按指针相等算下标一跳到位（已加载 92 条里有父评论就不必逐屏扫 92 行）。
    // 滚到后点开回复、1s 后回来定位子评论，整条二级回复链在这里一步到位。
    if (DYYYWardListLayerJumpCore(pids, nil, gen, urlGen, YES, cidList)) return YES;
    // ② 直接可见区找父评论（便宜、不滚动）：命中就展开回复。
    // v2.4-14：probe 传父评论正文（parentTexts 第一个非空）——cid 可能是 Swift
    // Int64 标量匹配不上，而 cell 上的 UILabel 文本永远可靠；没有正文才退回纯 cid。
    NSString *parentProbe = @"";
    for (id t in parentTexts) {
        if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) { parentProbe = (NSString *)t; break; }
    }
    if (parentProbe.length > 0) gDYYYWardParentDiag = @"可见区找父(按文本)";
    UIViewController *cvc = DYYYWardFindCommentVC();
    if (cvc) {
        for (UIScrollView *sv in DYYYWardCommentListViews(cvc)) {
            id pc = DYYYWardVisibleTargetCell(sv, pids, parentProbe);
            if (pc && [pc isKindOfClass:[UIView class]]) {
                gDYYYWardParentHandled = YES;
                // ExpandThenFindChild 从 globals 取子评论 cid/正文，先灌进去
                gDYYYWardChildCIDs = cidList;
                gDYYYWardChildHint = contentHint ?: @"";
                DYYYWardExpandThenFindChild(pc, gen); // v2.4-7：与父扫描命中共用收尾（点回复→1s 后定位子）
                return YES;
            }
        }
    }
    // ③ 父评论不在可见区：不再用 DYYYWardHighlightComment 试一次——它命中后会把
    //    LocateDone 置位，导致子评论永远不再被定位（v2.4-3 前的隐性 bug）。
    //    v2.4-4 起改由 DYYYWardLocateComment 主循环 i==2 步起「父评论按屏扫描」
    //    （DYYYWardSweepParentThenExpand），扫到父 → 点开回复 → 再回来找子评论。
    gDYYYWardParentDiag = @"父不在可见区";
    return NO;
}

static void DYYYWardLocateComment(NSString *awemeID, NSArray *cidList, NSString *contentHint, NSArray *parentIDs, NSArray *parentTexts) {
    (void)awemeID;
    // v2.4-4：二级回复父状态每次「查看」重置
    gDYYYWardParentHandled = NO;
    gDYYYWardSweepForParent = NO;
    gDYYYWardChildCIDs = nil;
    gDYYYWardChildHint = nil;
    gDYYYWardParentIDs = nil;   // v2.4-15：父 cid / 展开轮次每次「查看」重置
    gDYYYWardExpandRound = 0;
    // v2.4-7：父/列表层诊断段也每次重置，避免上一轮的「父:已点回复」糊到本轮 toast 里
    gDYYYWardParentDiag = nil;
    gDYYYWardListJumpDiag = nil;
    // v2.4-8：校验链分环节计数每次「查看」重置；探针在 2.2s 块/主循环首步跑
    gDYYYWardLAORejectZone = 0;
    gDYYYWardLAORejectIsa = 0;
    gDYYYWardLAORejectClass = 0;
    gDYYYWardLAOProbe = 0;
    // v2.4-20：作者闸计数每次「查看」重置（真机复测看 过/拒 分布判断闸是否生效）
    gDYYYWardGatePass = 0;
    gDYYYWardGateReject = 0;
    // v2.4-2：URL 深链已把目标评论滚到位 → 本次「查看」结束，不再跑脆弱的扫描/滚动。
    if (gDYYYWardURLDirectOK) {
        gDYYYWardURLDirectOK = NO;
        gDYYYWardURLGen++;
        gDYYYWardFailCount = 0;
        return;
    }
    // 上一次已经定位成功 → 失败计数归零（「连点两次才给诊断」只在连续失败时生效）
    if (gDYYYWardLocateGen > 0 && gDYYYWardLocateDone == gDYYYWardLocateGen) gDYYYWardFailCount = 0;
    gDYYYWardLocateGen++;
    NSInteger gen = gDYYYWardLocateGen;
    NSInteger urlGen = gDYYYWardURLGen; // 捕获本次「查看」的代号，供所有延迟步骤校验

    // 详情页起来后，如果评论区没自动开，就主动打开
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            DYYYWardOpenCommentPanelIfNeeded();
        } @catch (NSException *e) {}
    });

    // v2.4-21：用户拍板放弃「未加载/未展开的二级回复」定位（连续多轮实测：父定位→展开→找子
    // 要么点不中展开入口、要么子评论根本不加载；且深链传父 cid 会让宿主把父评论高亮/滚到位，
    // 子定位失败后那个高亮还挂着 = 用户看到的「乱找了一个」）。新策略：
    //   ① 子评论已展开在位 → TargetVisibleNow（v2.4-20 起带作者闸，不会假阳性）立即定位；
    //   ② 两轮检测都不在位 = 未展开/未加载 → 明确放弃并提示手动展开，不长跑 18 步扫描。
    // 一级评论（parentIDs 为空）完全不受影响，照常走下面的常规兜底。
    if (parentIDs.count > 0) {
        for (NSInteger r = 0; r < 2; r++) {
            NSTimeInterval rd = (r == 0) ? 2.8 : 4.2; // 给评论区打开/展开留时间，两轮
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(rd * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDYYYWardLocateDone == gen || gDYYYWardURLGen != urlGen) return;
                DYYYWardProbeValidator(); // v2.4-8：先自检对象校验链
                if (DYYYWardTargetVisibleNow(cidList, contentHint)) {
                    gDYYYWardLocateDone = gen;
                    gDYYYWardFailCount = 0;
                    [DYYYUtils showToast:@"已定位到该评论"];
                    return;
                }
                if (r == 1) {
                    [DYYYUtils showToast:@"未展开的二级回复暂不支持定位，请先展开该回复再查看"];
                }
            });
        }
        return; // 二级回复不走主循环（省掉 10 秒白扫 + 乱找面）
    }

    // 滚动搜索：评论列表分页加载，目标评论常不在首屏可见区（cid 与内容匹配都只看 visibleCells）。
    // 每 1s 一步：先试宿主内部定位方法（抖音自身支持跳指定评论），
    // 再 cid/内容匹配当前可见 cell，失败就滚动一屏继续（前 8 步向下、后 4 步回头向上），
    // 滚动同时触发宿主加载更多评论。第 4 步起若仍失败先 toast 首因（不用等 12 秒），
    // 12 步全失败静默结束。
    for (NSInteger i = 0; i < 18; i++) {
        NSTimeInterval delay = 2.6 + i * 0.9;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gDYYYWardLocateDone == gen) return;
            if (gDYYYWardURLGen != urlGen) return; // 新一次「查看」已开始，旧链作废
            @try {
                DYYYWardProbeValidator(); // v2.4-8：一级评论路径也自检（二级回复在 2.2s 块已探过，重复跑无害）
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
                    // v2.4-21：二级回复已在函数开头单独处理（在位即定位/不在位即放弃并 return），
                    // 主循环现在只服务一级评论，直接按行扫。
                    DYYYWardSweepRows(cidList, contentHint, gen);
                }
                // 数据源定位：直接按模型数组算下标再滚过去（第 1/5/9 步各试一次，
                // 扫数组较贵，不必每步都做）。命中后由 0.7s 后的复核去置 done。
                // 注意：按行扫描一旦接管（gDYYYWardSweepGen==gen），就绝不能再让数据源定位去 scrollToRow，
                // 否则两边抢滚动位置——实测表现为「扫描到一半被拽回顶部附近」，扫描永远走不完（v2.3-26 偏移停在 991 的真因）。
                // v2.4-7：i==1 先走新的「列表层直达」（dataSource/delegate 根搜 + 指针相等算下标，
                // 比旧的名字启发式数组发现广，且 Int64/裸扫真正生效）；一级评论专属，
                // 二级回复的父评论在 2.2s 块里已走过父直达。跳过了才退旧数据源定位。
                if ((i == 1 || i == 5 || i == 9) && gDYYYWardSweepGen != gen) {
                    BOOL jumped = (i == 1 && parentIDs.count == 0) ? DYYYWardListLayerJump(cidList, contentHint, gen, urlGen) : NO;
                    if (!jumped) DYYYWardLocateViaDataSource(cidList, contentHint);
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

    // 头像点击 → 进入该用户主页（所有插眼类型通用：视频/主页插眼存的是作者本身或该用户，
    // 评论插眼存的是评论作者；旧评论插眼记录没存 secUid/uid 时点头像会 toast 无主页信息）。
    // v2.4-19：手势 + tag 901 必须无条件挂上——旧评论插眼（secUid/uid 为空）的头像若没挂手势、
    // tag 又不是 901，点头像会穿透 shouldReceiveTouch 落到 cardTapped → 打开视频而非主页（用户实测）。
    NSString *secUid = [ward objectForKey:@"secUid"];
    if (![secUid isKindOfClass:[NSString class]]) secUid = @"";
    NSString *uid = [ward objectForKey:@"uid"];
    if (![uid isKindOfClass:[NSString class]]) uid = @"";
    avatar.tag = 901; // 与 cardTap 的 shouldReceiveTouch 配合：tag 901 区域不触发「打开插眼」
    avatar.userInteractionEnabled = YES;
    [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped:)]];
    objc_setAssociatedObject(avatar, "wardUser", @{@"secUid":secUid, @"uid":uid}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

// 按钮区域不触发卡片跳转，避免与 编辑/复制/删除 重复响应；头像区域交给头像手势，卡片手势不响应
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UIButton class]]) return NO;
    if (touch.view.tag == 901) return NO; // 点头像只走 avatarTapped:，不让 cardTapped 也跳「打开插眼」
    return YES;
}

// 插眼卡片头像点击 → 打开对应抖音用户主页（复用宿主 snssdk scheme 的 user/profile 路由）
- (void)avatarTapped:(UITapGestureRecognizer *)gesture {
    NSDictionary *info = objc_getAssociatedObject(gesture.view, "wardUser");
    if (![info isKindOfClass:[NSDictionary class]]) return;
    NSString *secUid = info[@"secUid"] ?: @"";
    NSString *uid = info[@"uid"] ?: @"";
    NSString *idValue = secUid.length > 0 ? secUid : uid;
    if (idValue.length == 0) { [DYYYUtils showToast:@"无用户主页信息"]; return; }
    [self resignSearchKeyboard];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://user/profile/%@", [self hostSnssdkScheme], idValue]];
    if (url && [[UIApplication sharedApplication] openURL:url]) return;
    // scheme 调不起时兜底：复制主页链接（浏览器/宿主 webview 可打开）
    NSString *share = secUid.length > 0
        ? [NSString stringWithFormat:@"https://www.douyin.com/user/%@", secUid]
        : [NSString stringWithFormat:@"https://www.douyin.com/share/user/%@", uid];
    [UIPasteboard generalPasteboard].string = share;
    [DYYYUtils showToast:@"已复制主页链接"];
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
        // v2.4-2：父评论 id（二级回复定位用）；老插眼记录没有此字段，直接为空
        NSMutableArray *parentIDs = [NSMutableArray array];
        id savedP = [ward objectForKey:@"parentIDs"];
        if ([savedP isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)savedP) {
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                    if (![parentIDs containsObject:(NSString *)v]) [parentIDs addObject:(NSString *)v];
                }
            }
        }
        // v2.4-5：与 parentIDs 同序的父评论正文（按文本扫父 cell 用）；老记录没有此字段
        NSMutableArray *parentTexts = [NSMutableArray array];
        id savedPT = [ward objectForKey:@"parentTexts"];
        if ([savedPT isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)savedPT) {
                [parentTexts addObject:([v isKindOfClass:[NSString class]] ? v : @"")];
            }
        }
        // v2.4-18：插眼人身份，供「短探针双条件确认」防乱找用（secUid 优先，缺失退 15 位以上数字 uid；
        // 老插眼记录没存 secUid 则为空 → 双条件自动退化为旧行为）
        NSString *aSec = [ward objectForKey:@"secUid"];
        if (![aSec isKindOfClass:[NSString class]]) aSec = @"";
        NSString *aUid = [ward objectForKey:@"uid"];
        if (![aUid isKindOfClass:[NSString class]]) aUid = @"";
        gDYYYWardAuthorPat = (aSec.length >= 12) ? aSec : ((aUid.length >= 15) ? aUid : @"");
        // v2.4-20：深链复核（TargetVisibleNow）在 LocateComment 之前跑，闸计数在这里也重置一次
        gDYYYWardGatePass = 0;
        gDYYYWardGateReject = 0;
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
        // v2.4-21：深链改传「子评论 cid」。放弃父展开链路后，传父 cid 的唯一效果就是让宿主
        // 把父评论滚到位并高亮（子定位又已放弃 = 红框挂在错误评论上 = 用户截图的「乱找」观感）。
        // 传子 cid：宿主若认（打开评论详情页）白赚，不认就当只开评论区，不会留下错误高亮。
        NSString *linkCID = commentID;
        BOOL ok = NO;
        if (linkCID.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@&comment_id=%@", base, linkCID]];
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
        // v2.4-2：URL 直达优先。深链跳完后延时复核目标是否已在可见区：
        //   在位 → 直接结束（不再跑脆弱扫描，这是最稳的定位方式，和 YYDS 的「直达」等价）；
        //   不在位 → 才调 DYYYWardLocateComment 做兜底（宿主定位/数据源/按行扫描）。
        // 用 gDYYYWardURLGen 代号：连点两次「查看」时，前一次还在排队的复核/扫描步骤自行作废。
        gDYYYWardURLGen++;
        NSInteger urlGen = gDYYYWardURLGen;
        gDYYYWardURLDirectOK = NO;
        gDYYYWardURLDiag = nil;
        // v2.4-3：复核改 3 轮阶梯（首轮按是否带 comment_id 取 1.8/1.2s，之后每轮 +1.4s）。
        // 评论区收起/数据慢时宿主可能 2~4s 才把目标滚到位：首轮就兜底会让扫描把深链的定位成果拽走。
        NSTimeInterval baseDelay = (linkCID.length > 0) ? 1.8 : 1.2;
        for (NSInteger round = 0; round < 3; round++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((baseDelay + round * 1.4) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDYYYWardURLGen != urlGen) return; // 新一次「查看」已开始
                if (gDYYYWardURLDirectOK) return;      // 之前轮已命中
                if (DYYYWardTargetVisibleNow(cidList, contentHint)) {
                    gDYYYWardURLDirectOK = YES;
                    gDYYYWardURLDiag = @"直达到位";
                    gDYYYWardFailCount = 0;
                    // 一级/二级都已可见 → 直接 toast，不再跑兜底
                    [DYYYUtils showToast:@"已定位到该评论"];
                    return;
                }
                gDYYYWardURLDiag = @"深链未到位";
                if (round < 2) return; // 还有后续复核轮，先不动列表
                // 3 轮都没到位 → 走完整兜底（含二级回复父定位）
                DYYYWardLocateComment(awemeID, cidList, contentHint, parentIDs, parentTexts);
            });
        }
        // v2.4-3 关键修复：这里必须 return。缺了它代码会穿透到函数尾部的裸深链（不带
        // comment_id）再 openURL 一次 —— 表现为「跳两次视频」，且第二次把深链刚展开的
        // 评论区定位直接冲掉（v2.4-2 用户实测）。
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
