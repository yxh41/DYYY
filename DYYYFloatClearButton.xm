/*
 * Tweak Name: 1KeyHideDYUI
 * Target App: com.ss.iphone.ugc.Aweme
 * Dev: @c00kiec00k 曲奇的坏品味🍻
 * iOS Version: 16.5
 */
#import "DYYYFloatSpeedButton.h"
#import "DYYYFloatClearButton.h"
#import "DYYYUtils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <signal.h>

void updateClearButtonVisibility(void);
void showClearButton(void);
void hideClearButton(void);

BOOL isInPlayInteractionVC = NO;
BOOL isPureViewVisible = NO;
BOOL clearButtonForceHidden = NO;
BOOL isAppActive = YES;
BOOL dyyyIsPerformingFloatClearOperation = NO;

static NSInteger dyyyClearButtonMutationDepth = 0;

static inline void DYYYBeginClearButtonMutation(void) {
    dyyyClearButtonMutationDepth++;
    dyyyIsPerformingFloatClearOperation = YES;
}

static inline void DYYYEndClearButtonMutation(void) {
    if (dyyyClearButtonMutationDepth > 0) {
        dyyyClearButtonMutationDepth--;
    }
    dyyyIsPerformingFloatClearOperation = dyyyClearButtonMutationDepth > 0;
}

static void DYYYPerformClearButtonMutation(dispatch_block_t block) {
    if (!block) {
        return;
    }
    DYYYBeginClearButtonMutation();
    @try {
        block();
    } @finally {
        DYYYEndClearButtonMutation();
    }
}


HideUIButton *hideButton;
BOOL isAppInTransition = NO;
NSArray *targetClassNames;

// 清屏隐藏状态栏（b15）：遍历所有 window 的 VC 层级，触发系统重新评估状态栏显隐。
// 与 DYYY.xm 里 6 处 prefersStatusBarHidden 判定互补：那里决定"要不要隐藏"，这里负责"立即重算"。
static void DYYYRefreshStatusBarVisibility(void) {
    if (!DYYYGetBool(@"DYYYHideStatusBarOnClear") ||
        DYYYGetBool(@"DYYYHideStatusbar")) {
        return;
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *rootVC = window.rootViewController;
        if (!rootVC) continue;
        [rootVC setNeedsStatusBarAppearanceUpdate];
        for (UIViewController *child in rootVC.childViewControllers) {
            [child setNeedsStatusBarAppearanceUpdate];
        }
    }
}
static CGFloat DYGetGlobalAlpha(void) {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYGlobalTransparency"];
    CGFloat a = value.length ? value.floatValue : 1.0;
    return (a >= 0.0 && a <= 1.0) ? a : 1.0;
}
static void findViewsOfClassHelper(UIView *view, Class viewClass, NSMutableArray *result) {
    if ([view isKindOfClass:viewClass]) {
        [result addObject:view];
    }
    for (UIView *subview in view.subviews) {
        findViewsOfClassHelper(subview, viewClass, result);
    }
}
UIWindow *getKeyWindow(void) {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}

static void DYYYApplyClearButtonHiddenState(HideUIButton *button, BOOL hidden) {
    if (!button) {
        return;
    }
    void (^applyBlock)(HideUIButton *) = ^(HideUIButton *target) {
        if (!target) {
            return;
        }
        if (target.hidden != hidden) {
            target.hidden = hidden;
        }
    };

    if ([NSThread isMainThread]) {
        applyBlock(button);
    } else {
        __weak HideUIButton *weakButton = button;
        dispatch_async(dispatch_get_main_queue(), ^{
            applyBlock(weakButton);
        });
    }
}

static BOOL DYYYShouldHideClearButton(void) {
    BOOL clearModeActive = (hideButton && hideButton.isElementsHidden);
    if (clearModeActive) {
        if (!isAppActive) {
            return YES;
        }
        return clearButtonForceHidden;
    }
    if (!isAppActive) {
        return YES;
    }
    if (!dyyyInteractionViewVisible) {
        return YES;
    }
    if (dyyyCommentViewVisible) {
        return YES;
    }
    if (isPureViewVisible) {
        return YES;
    }
    if (clearButtonForceHidden) {
        return YES;
    }
    return NO;
}

void updateClearButtonVisibility() {
    if (!hideButton) {
        return;
    }
    DYYYApplyClearButtonHiddenState(hideButton, DYYYShouldHideClearButton());
}

void showClearButton(void) {
    clearButtonForceHidden = NO;
    updateClearButtonVisibility(); // Call the central visibility logic
}

void hideClearButton(void) {
    clearButtonForceHidden = YES;
    updateClearButtonVisibility();
}

// AWEAwemePlayVideoPauseIcon 的 alpha 由抖音业务层动态控制（播放=0、暂停=1），
// 用 hidden 属性隐藏而非修改 alpha，避免与业务层 alpha 控制冲突（b15）。
static char dyyyClearOriginalAlphaKey;
static char dyyyClearOriginalHiddenKey;
static char dyyyClearStateCapturedKey;

static BOOL DYYYIsDynamicAlphaView(UIView *view) {
    static Class pauseIconClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      pauseIconClass = NSClassFromString(@"AWEAwemePlayVideoPauseIcon");
    });
    return pauseIconClass && [view isKindOfClass:pauseIconClass];
}

static BOOL DYYYHasCapturedClearTargetViewState(UIView *view) {
    return view && objc_getAssociatedObject(view, &dyyyClearStateCapturedKey) != nil;
}

static void DYYYCaptureClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || DYYYHasCapturedClearTargetViewState(view)) return;
    objc_setAssociatedObject(view, &dyyyClearStateCapturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyClearOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyClearOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYApplyClearTargetViewHiddenState(UIView *view) {
    if (!view) return;
    DYYYCaptureClearTargetViewStateIfNeeded(view);
    if (DYYYIsDynamicAlphaView(view)) {
        view.hidden = YES;
    } else {
        view.alpha = 0.0;
    }
}

static void DYYYRestoreClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || !DYYYHasCapturedClearTargetViewState(view)) return;
    NSNumber *originalHidden = objc_getAssociatedObject(view, &dyyyClearOriginalHiddenKey);
    NSNumber *originalAlpha = objc_getAssociatedObject(view, &dyyyClearOriginalAlphaKey);
    if (originalHidden) view.hidden = originalHidden.boolValue;
    if (originalAlpha) view.alpha = originalAlpha.floatValue;
    objc_setAssociatedObject(view, &dyyyClearOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dyyyClearOriginalAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dyyyClearStateCapturedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void forceResetAllUIElements(void) {
    DYYYPerformClearButtonMutation(^{
        initTargetClassNames();
        NSArray<UIView *> *trackedViews = [hideButton.hiddenViewsList copy];
        for (UIView *view in trackedViews) {
            DYYYRestoreClearTargetViewStateIfNeeded(view);
        }
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            for (NSString *className in targetClassNames) {
                Class viewClass = NSClassFromString(className);
                if (!viewClass) continue;
                NSMutableArray *views = [NSMutableArray array];
                findViewsOfClassHelper(window, viewClass, views);
                for (UIView *view in views) {
                    DYYYRestoreClearTargetViewStateIfNeeded(view);
                    // 非状态捕获视图仍需恢复 alpha（上游原有行为）
                    if (!DYYYHasCapturedClearTargetViewState(view)) {
                        view.alpha = 1.0;
                    }
                }
            }
        }
    });
}
static void reapplyHidingToAllElements(HideUIButton *button) {
    if (!button || !button.isElementsHidden)
        return;
    [button hideUIElements];
}
// 清屏隐藏暂停图标（b15）：配置缓存，避免每次点击都重建类名数组。
static NSUInteger dyyyTargetClassConfiguration = NSUIntegerMax;

void initTargetClassNames(void) {
    NSUInteger configuration = 0;
    configuration |= DYYYGetBool(@"DYYYHidePauseVideoIcon") ? (1U << 4) : 0;
    if (targetClassNames && dyyyTargetClassConfiguration == configuration) {
        return;
    }
    dyyyTargetClassConfiguration = configuration;

    NSMutableArray<NSString *> *list = [@[
        @"AWEHPTopBarCTAContainer", @"AWEHPDiscoverFeedEntranceView", @"AWELeftSideBarEntranceView", @"DUXBadge", @"AWEBaseElementView", @"AWEElementStackView", @"AWEPlayInteractionDescriptionLabel",
        @"AWEUserNameLabel", @"ACCEditTagStickerView", @"AWEFeedTemplateAnchorView", @"AWESearchFeedTagView", @"AWEPlayInteractionSearchAnchorView", @"AFDRecommendToFriendTagView",
        @"AWELandscapeFeedEntryView", @"AWEFeedAnchorContainerView", @"AFDAIbumFolioView", @"DUXPopover", @"AWEMixVideoPanelMoreView", @"AWEHotSearchInnerBottomView", @"AWEHPSegmentControlScrollView"
    ] mutableCopy];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTabBar"]) {
        [list addObject:@"AWENormalModeTabBar"];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDanmaku"]) {
        [list addObject:@"AWEVideoPlayDanmakuContainerView"];
        [list addObject:@"AWEDanmakuContainerView"];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSlider"]) {
        [list addObject:@"AWEStoryProgressSlideView"];
        [list addObject:@"AWEStoryProgressContainerView"];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideChapter"]) {
        [list addObject:@"AWEDemaciaChapterProgressSlider"];
    }
    if (configuration & (1U << 4)) {
        [list addObject:@"AWEAwemePlayVideoPauseIcon"];
    }

    targetClassNames = [list copy];
}
@implementation HideUIButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.isElementsHidden = NO;
        self.hiddenViewsList = [NSMutableArray array];

        self.originalAlpha = 1.0;
        self.alpha = 0.5;
        
        [self loadLockState];
        [self loadIcons];
        [self setImage:self.showIcon forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:panGesture];
        
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(handleTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchUpOutside) forControlEvents:UIControlEventTouchUpOutside];
        
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPressGesture];
        
        [self startPeriodicCheck];
        [self resetFadeTimer];

        // Start as hidden, will be shown by updateClearButtonVisibility if conditions are met
        self.hidden = YES;
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) {
        [self loadSavedPosition];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        return;
    }
    [self startPeriodicCheck];
    [self resetFadeTimer];
}

- (void)startPeriodicCheck {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                    repeats:YES
                                                      block:^(NSTimer *timer) {
                                                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                        if (!strongSelf) {
                                                            return;
                                                        }
                                                        if (strongSelf.isElementsHidden) {
                                                            [strongSelf hideUIElements];
                                                        }
                                                      }];
    self.checkTimer = timer;
}

- (void)resetFadeTimer {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         repeats:NO
                                                           block:^(NSTimer *timer) {
                                                             __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                             if (!strongSelf) {
                                                                 return;
                                                             }
                                                             [UIView animateWithDuration:0.3
                                                                              animations:^{
                                                                                strongSelf.alpha = 0.5;
                                                                              }];
                                                             strongSelf.fadeTimer = nil;
                                                           }];
    self.fadeTimer = fadeTimer;
    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
    }
}

- (void)stopTimers {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        CGFloat centerXPercent = self.center.x / self.superview.bounds.size.width;
        CGFloat centerYPercent = self.center.y / self.superview.bounds.size.height;
        
        [defaults setFloat:centerXPercent forKey:@"DYYYHideButtonCenterXPercent"];
        [defaults setFloat:centerYPercent forKey:@"DYYYHideButtonCenterYPercent"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    float centerXPercent = [defaults floatForKey:@"DYYYHideButtonCenterXPercent"];
    float centerYPercent = [defaults floatForKey:@"DYYYHideButtonCenterYPercent"];
    
    if (centerXPercent > 0 && centerYPercent > 0) {
        self.center = CGPointMake(centerXPercent * self.superview.bounds.size.width,
                                  centerYPercent * self.superview.bounds.size.height);
    } else {
        self.center = CGPointMake(self.superview.bounds.size.width / 2.0f,
                                  self.superview.bounds.size.height / 3.0f);
    }
}

- (void)saveLockState {
    [[NSUserDefaults standardUserDefaults] setBool:self.isLocked forKey:@"DYYYHideUIButtonLockState"];
}

- (void)loadLockState {
    self.isLocked = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideUIButtonLockState"];
}

- (void)loadIcons {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *iconPath = [documentsPath stringByAppendingPathComponent:@"DYYY/qingping.gif"];
    NSData *gifData = [NSData dataWithContentsOfFile:iconPath];

    NSArray<UIImage *> *frames = nil;
    CGFloat totalDuration = 0.0;
    BOOL hasFrames = gifData.length > 0 &&
                     [DYYYUtils framesFromAnimatedData:gifData
                                                scale:[UIScreen mainScreen].scale
                                               images:&frames
                                        totalDuration:&totalDuration];

    if (hasFrames && frames.count > 0) {
        UIImageView *animatedImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        animatedImageView.animationImages = frames;
        animatedImageView.animationDuration = totalDuration;
        animatedImageView.animationRepeatCount = 0;
        [self addSubview:animatedImageView];

        animatedImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [animatedImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [animatedImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [animatedImageView.widthAnchor constraintEqualToAnchor:self.widthAnchor], [animatedImageView.heightAnchor constraintEqualToAnchor:self.heightAnchor]
        ]];

        [animatedImageView startAnimating];
        return;
    }

    [self setTitle:@"隐藏" forState:UIControlStateNormal];
    [self setTitle:@"显示" forState:UIControlStateSelected];
    self.titleLabel.font = [UIFont systemFontOfSize:10];
}

- (void)handleTouchDown {
    if ([self dyyy_isInSelfHiddenState]) return;
    [self resetFadeTimer];
}

- (void)handleTouchUpInside {
    if ([self dyyy_isInSelfHiddenState]) return;
    [self resetFadeTimer];
}

- (void)handleTouchUpOutside {
    if ([self dyyy_isInSelfHiddenState]) return;
    [self resetFadeTimer];
}

- (UIViewController *)findViewController:(UIView *)view {
    __weak UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
        if (!responder)
            break;
    }
    return nil;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.isLocked)
        return;

    [self resetFadeTimer];
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    newCenter.x = MAX(self.frame.size.width / 2, MIN(newCenter.x, self.superview.frame.size.width - self.frame.size.width / 2));
    newCenter.y = MAX(self.frame.size.height / 2, MIN(newCenter.y, self.superview.frame.size.height - self.frame.size.height / 2));
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self saveButtonPosition];
    }
}

- (BOOL)dyyy_shouldSelfHideOnClear {
    return DYYYGetBool(@"DYYYHideClearButtonOnTap");
}

- (BOOL)dyyy_isInSelfHiddenState {
    return self.isElementsHidden && [self dyyy_shouldSelfHideOnClear];
}

- (void)dyyy_applySelfHiddenAlpha {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    // alpha 必须 > 0.01 才能继续接收 hit-test，0.02 在动态背景下几乎不可见
    self.alpha = 0.02;
    [self dyyy_showEdgeIndicator];
}

- (void)dyyy_showEdgeIndicator {
    if (!self.superview) return;
    CGFloat indicatorHeight = self.bounds.size.height;
    CGFloat indicatorWidth = 2.0;
    CGFloat screenWidth = self.superview.bounds.size.width;
    CGFloat centerY = self.center.y;

    if (!self.edgeIndicatorView) {
        self.edgeIndicatorView = [[UIView alloc] init];
        self.edgeIndicatorView.backgroundColor = [UIColor blackColor];
        self.edgeIndicatorView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
        self.edgeIndicatorView.layer.cornerRadius = indicatorWidth;
        self.edgeIndicatorView.layer.masksToBounds = YES;
        self.edgeIndicatorView.userInteractionEnabled = NO;
    }
    self.edgeIndicatorView.frame = CGRectMake(screenWidth - indicatorWidth,
                                              centerY - indicatorHeight / 2.0,
                                              indicatorWidth,
                                              indicatorHeight);
    self.edgeIndicatorView.alpha = 1.0;
    self.edgeIndicatorView.hidden = NO;
    if (![self.edgeIndicatorView isDescendantOfView:self.superview]) {
        [self.superview addSubview:self.edgeIndicatorView];
    }
}

- (void)dyyy_hideEdgeIndicator {
    if (self.edgeIndicatorView) {
        self.edgeIndicatorView.hidden = YES;
    }
}

- (void)handleTap {
    if (isAppInTransition)
        return;

    BOOL selfHide = [self dyyy_shouldSelfHideOnClear];
    BOOL willEnterHidden = !self.isElementsHidden;
    // 仅在不会进入"按钮自隐藏"状态时才重置淡出动画
    if (!(selfHide && willEnterHidden)) {
        [self resetFadeTimer];
    }

    if (!self.isElementsHidden) {
        initTargetClassNames();
        [self hideUIElements];
        self.isElementsHidden = YES;
        self.selected = YES;

        BOOL hideSpeed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
        if (hideSpeed) {
            hideSpeedButton();
        }

        if (selfHide) {
            [self dyyy_applySelfHiddenAlpha];
        }
        DYYYRefreshStatusBarVisibility();
    } else {
        forceResetAllUIElements();
        [self restoreAWEPlayInteractionProgressContainerView];
        self.isElementsHidden = NO;
        [self.hiddenViewsList removeAllObjects];
        self.selected = NO;

        BOOL hideSpeed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
        if (hideSpeed) {
            showSpeedButton();
        }

        self.alpha = self.originalAlpha;
        [self resetFadeTimer];
        [self dyyy_hideEdgeIndicator];
        DYYYRefreshStatusBarVisibility();
    }
}

- (void)restoreAWEPlayInteractionProgressContainerView {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYRemoveTimeProgress"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTimeProgress"]) {
        DYYYPerformClearButtonMutation(^{
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                [self recursivelyRestoreAWEPlayInteractionProgressContainerViewInView:window];
            }
        });
    }
}

- (void)recursivelyRestoreAWEPlayInteractionProgressContainerViewInView:(UIView *)view {
    if ([view isKindOfClass:NSClassFromString(@"AWEPlayInteractionProgressContainerView")]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYRemoveTimeProgress"]) {
            view.hidden = NO;
        } else {
            view.alpha = DYGetGlobalAlpha();
        }
        return;
    }

    for (UIView *subview in view.subviews) {
        [self recursivelyRestoreAWEPlayInteractionProgressContainerViewInView:subview];
    }
}
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];
        self.isLocked = !self.isLocked;
        [self saveLockState];
        NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
        [DYYYUtils showToast:toastMessage];
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [generator prepare];
            [generator impactOccurred];
        }
    }
}
- (void)hideUIElements {
    DYYYPerformClearButtonMutation(^{
        [self.hiddenViewsList removeAllObjects];
        [self findAndHideViews:targetClassNames];
        [self hideAWEPlayInteractionProgressContainerView];
        self.isElementsHidden = YES;
        // self.hidden should be managed by updateClearButtonVisibility
        updateClearButtonVisibility();
        if (self.superview) {
            [self.superview bringSubviewToFront:self];
        }
    });
}

- (void)hideAWEPlayInteractionProgressContainerView {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYRemoveTimeProgress"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTimeProgress"]) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            [self recursivelyHideAWEPlayInteractionProgressContainerViewInView:window];
        }
    }
}

- (void)recursivelyHideAWEPlayInteractionProgressContainerViewInView:(UIView *)view {
    if ([view isKindOfClass:NSClassFromString(@"AWEPlayInteractionProgressContainerView")]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYRemoveTimeProgress"]) {
            view.hidden = YES;
        } else {
            view.tag = DYYY_IGNORE_GLOBAL_ALPHA_TAG;
            view.alpha = 0.0;
        }
        [self.hiddenViewsList addObject:view];
        return;
    }

    for (UIView *subview in view.subviews) {
        [self recursivelyHideAWEPlayInteractionProgressContainerViewInView:subview];
    }
}
- (void)findAndHideViews:(NSArray *)classNames {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        for (NSString *className in classNames) {
            Class viewClass = NSClassFromString(className);
            if (!viewClass)
                continue;
            NSMutableArray *views = [NSMutableArray array];
            findViewsOfClassHelper(window, viewClass, views);
            for (UIView *view in views) {
                if ([view isKindOfClass:[UIView class]]) {
                    if (view == self)
                        continue;
                    if ([view isKindOfClass:NSClassFromString(@"AWELeftSideBarEntranceView")]) {
                        UIViewController *controller = [self findViewController:view];
                        if (![controller isKindOfClass:NSClassFromString(@"AWEFeedContainerViewController")]) {
                            continue;
                        }
                    }
                    DYYYApplyClearTargetViewHiddenState(view);
                    if (![self.hiddenViewsList containsObject:view]) {
                        [self.hiddenViewsList addObject:view];
                    }
                }
            }
        }
    }
}
- (void)safeResetState {
    forceResetAllUIElements();
    self.isElementsHidden = NO;
    [self.hiddenViewsList removeAllObjects];
    self.selected = NO;

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }

    BOOL hideSpeed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
    if (hideSpeed) {
        showSpeedButton();
    }

    // 切场景/重置状态时恢复按钮自隐藏 alpha，避免一直近乎透明
    if (self.alpha < 0.1) {
        self.alpha = self.originalAlpha;
        [self resetFadeTimer];
    }
    [self dyyy_hideEdgeIndicator];
    DYYYRefreshStatusBarVisibility();
}
- (void)dealloc {
    [self stopTimers];
    [self.edgeIndicatorView removeFromSuperview];
}
@end
