// DYYYHighFPS.xm
// 移植自 VexCove 的高帧率强制 + 实时帧率浮窗功能。
// 关键约束：
//  - 高帧率三板斧（CFBundle 解锁 / 禁止降帧 / 调用 ProMotion Booster）均基于 Aweme 39.8 私有类，
//    仅在「标准版抖音」(com.ss.iphone.ugc.Aweme) 下挂载，极速版(lite)连尝试都不发生。
//  - 全部开关默认关闭，由设置页切换时即时应用。
//  - 用 Logos %hook + MSHookFunction（自带缺失类静默跳过/判空），不使用裸 method_exchangeImplementations。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "DYYYConstants.h"
#import "DYYYPreferences.h"
#import "DYYYUtils.h"
#import "DYYYHighFPS.h"

#pragma mark - 设置键读取
static BOOL DYYYHighFPSEnabled(void) {
    return [DYYYPreferences boolForKey:DYYYEnableHighFPS];
}
static BOOL DYYYFPSOverlayShouldShow(void) {
    return [DYYYPreferences boolForKey:DYYYEnableFPSOverlay];
}

#pragma mark - 高帧率核心

// 原始 CFBundle 函数指针（系统函数，全进程有效；体内已判开关）
static CFTypeRef (*gOrigCFBundleGetValueForInfoDictionaryKey)(CFBundleRef bundle, CFStringRef key) = NULL;

static CFTypeRef DYYYCFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    // 解锁系统对 CADisplayLink 的 60Hz 钳制：当宿主查询该 Info.plist 键时强制返回 true
    if (DYYYHighFPSEnabled() && key &&
        CFStringCompare(key, CFSTR("CADisableMinimumFrameDurationOnPhone"), 0) == kCFCompareEqualTo) {
        return kCFBooleanTrue;
    }
    if (gOrigCFBundleGetValueForInfoDictionaryKey) {
        return gOrigCFBundleGetValueForInfoDictionaryKey(bundle, key);
    }
    return NULL;
}

// 宿主降帧管理：在需要 boost 时强制禁止 degrade
%group DYYYHighFPSGroup
%hook AWEDisplayLinkDegradeManager
- (void)setDisableDegradeOperation:(BOOL)disable {
    if (DYYYHighFPSEnabled()) {
        disable = YES;
    }
    %orig(disable);
}
%end
%end

// 调用 AWEProMotionFPSBooster 拉高刷新率（类缺失则安全返回）
static void DYYYInvokeProMotionFPSBooster(void) {
    Class cls = NSClassFromString(@"AWEProMotionFPSBooster");
    if (!cls) {
        return;
    }
    id target = nil;
    if ([cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
        target = [cls performSelector:NSSelectorFromString(@"sharedInstance")];
    } else if ([cls respondsToSelector:NSSelectorFromString(@"sharedManager")]) {
        target = [cls performSelector:NSSelectorFromString(@"sharedManager")];
    } else {
        target = cls;
    }
    if (!target) return;

    // 依次尝试各 boost 选择器，存在才调用
    NSArray<NSString *> *boostSels = @[ @"boostFPSForScrolling", @"boostFPSForAppearance", @"boostFPSForVCAppearance" ];
    for (NSString *selName in boostSels) {
        SEL sel = NSSelectorFromString(selName);
        if ([target respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [target performSelector:sel];
#pragma clang diagnostic pop
        }
    }

    // setHighRefreshRate: 在不同版本参数类型不同（BOOL / CGFloat），按签名自适应
    SEL setHigh = NSSelectorFromString(@"setHighRefreshRate:");
    if ([target respondsToSelector:setHigh]) {
        NSMethodSignature *sig = [target methodSignatureForSelector:setHigh];
        const char *argType = (sig && [sig numberOfArguments] > 2) ? [sig getArgumentTypeAtIndex:2] : "c";
        if (strcmp(argType, "c") == 0 || strcmp(argType, "B") == 0) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(target, setHigh, YES);
        } else {
            CGFloat maxFPS = [UIScreen mainScreen].maximumFramesPerSecond;
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(target, setHigh, maxFPS);
        }
    }
}

// 高帧率开关变化后的应用入口（供设置页调用）
void DYYYApplyHighFPSSettingChange(BOOL enabled) {
    if (enabled) {
        DYYYInvokeProMotionFPSBooster();
    }
    // CFBundle hook 与 degrade hook 均为「实时读取开关」，无需额外拆除；
    // 关闭时 degrade 钩子自然停止强制，刷新率回落交由宿主 degrade 管理。
}

static BOOL gDYYYHighFPSStarted = NO;
static void DYYYStartHighFPSHooks(void) {
    if (gDYYYHighFPSStarted) return;
    gDYYYHighFPSStarted = YES;

    // 安装 CFBundle 函数 hook（仅在标准版调用，故极速版不会被触碰）
    MSHookFunction((void *)CFBundleGetValueForInfoDictionaryKey,
                   (void *)DYYYCFBundleGetValueForInfoDictionaryKey,
                   (void **)&gOrigCFBundleGetValueForInfoDictionaryKey);

    if (DYYYHighFPSEnabled()) {
        DYYYInvokeProMotionFPSBooster();
    }

    // App 重新激活时重新评估（负载恢复后可快速回到高刷）
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if (DYYYHighFPSEnabled()) {
            DYYYInvokeProMotionFPSBooster();
        }
    }];
}

#pragma mark - FPS 浮窗

// 穿透窗口：空白处不拦截点击，不抢 key 窗口
@interface DYYYFPSOverlayPassthroughWindow : UIWindow
@end
@implementation DYYYFPSOverlayPassthroughWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || (self.rootViewController && hit == self.rootViewController.view)) return nil;
    return hit;
}
@end

@interface DYYYFPSOverlayView : UIView
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) NSInteger displayedFPS;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CGPoint dragOffset;
- (void)startSampling;
- (void)stopSampling;
@end

@implementation DYYYFPSOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.42];
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
        self.layer.borderWidth = 0.5;

        _fpsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _fpsLabel.textColor = [UIColor whiteColor];
        _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _fpsLabel.textAlignment = NSTextAlignmentCenter;
        _fpsLabel.adjustsFontSizeToFitWidth = YES;
        _fpsLabel.minimumScaleFactor = 0.75;
        _fpsLabel.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        _fpsLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        _fpsLabel.text = @"-- FPS";
        [self addSubview:_fpsLabel];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _fpsLabel.frame = CGRectInset(self.bounds, 7.0, 2.0);
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = self.window;
    if (!window) return;
    CGPoint loc = [pan locationInView:window];
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.dragOffset = CGPointMake(self.center.x - loc.x, self.center.y - loc.y);
    }
    CGPoint newCenter = CGPointMake(loc.x + self.dragOffset.x, loc.y + self.dragOffset.y);
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    newCenter.x = MAX(halfW, MIN(window.bounds.size.width - halfW, newCenter.x));
    newCenter.y = MAX(halfH + window.safeAreaInsets.top, MIN(window.bounds.size.height - halfH, newCenter.y));
    self.center = newCenter;
    if (pan.state == UIGestureRecognizerStateEnded) {
        // 位置以百分比存盘，重启后恢复
        NSDictionary *pos = @{ @"x" : @(self.center.x / window.bounds.size.width),
                               @"y" : @(self.center.y / window.bounds.size.height) };
        [DYYYPreferences setObject:pos forKey:@"DYYYFPSOverlayPosition"];
    }
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (self.lastTimestamp <= 0) {
        self.lastTimestamp = link.timestamp;
        self.frameCount = 0;
        return;
    }
    self.frameCount += 1;
    CFTimeInterval delta = link.timestamp - self.lastTimestamp;
    if (delta < 0.25) return;
    NSInteger fps = (NSInteger)llround((double)self.frameCount / delta);
    if (fps < 0) fps = 0;
    self.lastTimestamp = link.timestamp;
    self.frameCount = 0;
    if (fps == self.displayedFPS) return;
    self.displayedFPS = fps;
    self.fpsLabel.text = [NSString stringWithFormat:@"%ld FPS", (long)fps];
}

- (void)startSampling {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopSampling {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.frameCount = 0;
    self.lastTimestamp = 0;
}
@end

static UIWindow *gDYYYFPSOverlayWindow = nil;
static DYYYFPSOverlayView *gDYYYFPSOverlayView = nil;

static CGRect DYYYFPSOverlayDefaultFrame(UIWindow *root) {
    CGFloat w = 72.0, h = 24.0;
    CGFloat x = root.bounds.size.width - root.safeAreaInsets.right - w - 12.0;
    CGFloat y = root.safeAreaInsets.top + 12.0;
    return CGRectMake(x, y, w, h);
}

static void DYYYFPSOverlayTearDown(void) {
    if (gDYYYFPSOverlayView) {
        [gDYYYFPSOverlayView stopSampling];
        [gDYYYFPSOverlayView removeFromSuperview];
        gDYYYFPSOverlayView = nil;
    }
    if (gDYYYFPSOverlayWindow) {
        gDYYYFPSOverlayWindow.hidden = YES;
        gDYYYFPSOverlayWindow.rootViewController = nil;
        gDYYYFPSOverlayWindow = nil;
    }
}

static void DYYYFPSOverlayEnsureOnMain(void) {
    if (!DYYYFPSOverlayShouldShow()) {
        DYYYFPSOverlayTearDown();
        return;
    }
    if (gDYYYFPSOverlayWindow && gDYYYFPSOverlayView) {
        [gDYYYFPSOverlayView startSampling];
        gDYYYFPSOverlayWindow.hidden = NO;
        return;
    }
    UIWindow *base = [DYYYUtils getActiveWindow];
    if (!base) base = [UIApplication sharedApplication].windows.firstObject;
    if (!base) return;

    DYYYFPSOverlayPassthroughWindow *win = [[DYYYFPSOverlayPassthroughWindow alloc] initWithFrame:base.bounds];
    win.backgroundColor = [UIColor clearColor];
    win.opaque = NO;
    win.windowLevel = 1120.0; // 高于状态栏(1000)，低于系统 Alert(2000)
    win.rootViewController = [[UIViewController alloc] init];

    DYYYFPSOverlayView *view = [[DYYYFPSOverlayView alloc] initWithFrame:DYYYFPSOverlayDefaultFrame(base)];
    NSDictionary *pos = [DYYYPreferences objectForKey:@"DYYYFPSOverlayPosition"];
    if ([pos isKindOfClass:[NSDictionary class]] && pos[@"x"] && pos[@"y"]) {
        CGFloat cx = [pos[@"x"] floatValue] * base.bounds.size.width;
        CGFloat cy = [pos[@"y"] floatValue] * base.bounds.size.height;
        view.center = CGPointMake(cx, cy);
    }
    [win.rootViewController.view addSubview:view];
    gDYYYFPSOverlayWindow = win;
    gDYYYFPSOverlayView = view;
    [view startSampling];
    win.hidden = NO;
}

// FPS 浮窗开关变化入口（设置页调用）；非主线程则切回主线程
void DYYYApplyFPSOverlaySettingChange(void) {
    if ([NSThread isMainThread]) {
        DYYYFPSOverlayEnsureOnMain();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            DYYYFPSOverlayEnsureOnMain();
        });
    }
}

static void DYYYStartFPSOverlaySetup(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        DYYYFPSOverlayEnsureOnMain();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if (gDYYYFPSOverlayView && gDYYYFPSOverlayWindow) {
            gDYYYFPSOverlayView.frame = DYYYFPSOverlayDefaultFrame(gDYYYFPSOverlayWindow);
        }
    }];
    DYYYFPSOverlayEnsureOnMain();
}

#pragma mark - 入口：仅标准版挂载

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    BOOL isStandard = [bid isEqualToString:@"com.ss.iphone.ugc.Aweme"];
    if (isStandard) {
        %init(DYYYHighFPSGroup);
        DYYYStartHighFPSHooks();
        DYYYStartFPSOverlaySetup();
    }
}
