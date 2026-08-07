//
//  DYYYHideCommentAIAnalysisHooks.m
//  移植自 VexCove/DYYY — 评论区 AI 解析 / 门店评价 / 商品评价等扩展 Tab 隐藏
//
//  说明（与 VexCove 原始实现保持一致，仅将原始 IMP 保存方式统一为 IMP 类型、
//      并自行实现 swizzling helper，不依赖其未公开的 install 内部函数）：
//  - 控制开关：DYYYHideCommentAIAnalysis（经本地 DYYYGetBool 读取；与本地已有的
//    DYYYHideCommentViews「隐藏评论视图」互相独立，后者隐藏评论区头部/锚点视图）
//  - 通过 hook setTitle: 动态缓存被隐藏的 tabType，再在 multiTabs:/containsTab:/
//    viewControllerForType:/componentTypes:/configSegmentedControl: 等入口过滤
//  - 额外隐藏视频流里的「AI 解析」双列入口（AWEFeedDoubleColumnAITabUtil）
//

#import "AwemeHeaders.h"
#import "DYYYPreferences.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 控制开关

static NSString *const kDYYYHideCommentAIAnalysisKey = @"DYYYHideCommentAIAnalysis";

static BOOL DYYYHideCommentViewsEnabled(void) {
    return DYYYGetBool(kDYYYHideCommentAIAnalysisKey);
}

#pragma mark - 类名常量（含 Swift 模块带点名 + mangled 回退）

static NSString *const kDYYYCommentDCFeedAIParseTabComponentClassName = @"AWECommentDCFeedSwiftImpl.CommentDCFeedAIParseTabComponent";
static NSString *const kDYYYCommentTemplatePOITabComponentClassName = @"AWECommentPOISwiftImpl.CommentTemplatePOITabComponent";
static NSString *const kDYYYCommentEvaluateTabComponentClassName = @"AWECommentCommerceSwiftImpl.CommentEvaluateTabComponent";
static NSString *const kDYYYCommentProductCommentTabComponentClassName = @"AWECommentCommerceSwiftImpl.CommentProductCommentTabComponent";
static NSString *const kDYYYCommentTabManagerClassName = @"AWECommentPanelTabSwiftImpl.CommentTabManager";
static NSString *const kDYYYCommentTabServiceClassName = @"AWECommentTabService";
static NSString *const kDYYYFeedDoubleColumnAITabUtilClassName = @"AWEFeedDoubleColumnAITabUtil";
static NSString *const kDYYYCommentTabModelClassName = @"AWECommentPanelTabSwiftImpl.CommentTabModel";
static NSString *const kDYYYCommentContainerTabModelClassName = @"AWECommentPanelContainerSwiftImpl.CommentTabModel";
static NSString *const kDYYYCommentAIParseViewControllerClassName = @"AWEFeedDoubleColumnCommentAIParseViewController";
static NSString *const kDYYYPOIRateListInCommentViewControllerClassName = @"AWEPOIUGCRateListInCommentViewController";
static NSString *const kDYYYLocalLifeCommentBizServiceClassName = @"IESLocalLifeCommentBizService";
static NSString *const kDYYYECModuleServiceClassName = @"AWEECModuleService";
static NSString *const kDYYYCommentPanelTabBasicParamsClassName = @"AWECommentPanelTabBasicParams";
static NSString *const kDYYYCommentContainerInnerViewControllerClassName = @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController";

// Swift mangled 名回退（NSClassFromString 失败时尝试）
static NSString *const kDYYYCommentTabManagerMangled = @"_TtC27AWECommentPanelTabSwiftImpl17CommentTabManager";
static NSString *const kDYYYCommentDCFeedAIParseTabComponentMangled = @"_TtC25AWECommentDCFeedSwiftImpl32CommentDCFeedAIParseTabComponent";
static NSString *const kDYYYCommentTemplatePOITabComponentMangled = @"_TtC22AWECommentPOISwiftImpl30CommentTemplatePOITabComponent";
static NSString *const kDYYYCommentEvaluateTabComponentMangled = @"_TtC27AWECommentCommerceSwiftImpl27CommentEvaluateTabComponent";
static NSString *const kDYYYCommentProductCommentTabComponentMangled = @"_TtC27AWECommentCommerceSwiftImpl33CommentProductCommentTabComponent";
static NSString *const kDYYYCommentContainerInnerViewControllerMangled = @"_TtC33AWECommentPanelContainerSwiftImpl35CommentContainerInnerViewController";
static NSString *const kDYYYCommentTabModelMangled = @"_TtC27AWECommentPanelTabSwiftImplP33_63C657C2E18159D394914B02AA302F2B15CommentTabModel";
static NSString *const kDYYYCommentContainerTabModelMangled = @"_TtC33AWECommentPanelContainerSwiftImpl15CommentTabModel";

#pragma mark - 全局状态

static NSMutableSet<NSNumber *> *gHiddenCommentTabTypes = nil;
static NSMutableDictionary<NSString *, NSValue *> *gOrigCommentTabSetNeedsUpdateIMPs = nil;

static IMP gOrigShouldShowDCFeedAITabWithScene = NULL;
static IMP gOrigCurrentVideoShouldShowAITab = NULL;
static IMP gOrigCommentTabServiceMultiTabs = NULL;
static IMP gOrigCommentTabServiceContainsTab = NULL;
static IMP gOrigCommentTabManagerContainsTab = NULL;
static IMP gOrigCommentTabManagerComponentTypes = NULL;
static IMP gOrigCommentTabManagerViewControllerForType = NULL;
static IMP gOrigCommentTabManagerConfigSegmentedControl = NULL;
static IMP gOrigCommentPanelTabBasicParamsInit = NULL;
static IMP gOrigCommentPanelTabBasicParamsNoTabScene = NULL;
static IMP gOrigCommentContainerHeightForSegmentedControl = NULL;
static IMP gOrigCommentTabModelSetTitle = NULL;
static IMP gOrigCommentContainerTabModelSetTitle = NULL;
static IMP gOrigShouldShowRateTabInCommentWithAweme = NULL;
static IMP gOrigShouldShowProductCommentWithAwemeModel = NULL;

#pragma mark - 工具函数

static Class DYYYGetCommentClass(NSString *name, NSString *mangled) {
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    if (mangled.length > 0) {
        cls = objc_getClass([mangled UTF8String]);
    }
    return cls;
}

static NSString *DYYYNormalizedCommentTabTitle(NSString *text) {
    if (text.length == 0) return @"";
    return [[text stringByReplacingOccurrencesOfString:@" " withString:@""] lowercaseString];
}

static BOOL DYYYStringLooksLikePrimaryCommentTab(NSString *text) {
    if (text.length == 0) return NO;
    NSString *normalized = DYYYNormalizedCommentTabTitle(text);
    if ([normalized containsString:@"条评论"]) return YES;
    return [normalized isEqualToString:@"评论"];
}

static BOOL DYYYStringLooksLikeExtraCommentTab(NSString *text) {
    if (text.length == 0 || text.length > 16) return NO;
    if (DYYYStringLooksLikePrimaryCommentTab(text)) return NO;

    NSString *normalized = DYYYNormalizedCommentTabTitle(text);
    static NSArray<NSString *> *hiddenPatterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hiddenPatterns = @[
            @"ai解析",
            @"门店评价",
            @"商品评价",
            @"种草评价",
            @"评价",
            @"看过",
            @"赞过",
            @"收藏",
            @"火焰",
            @"金币",
            @"游戏",
            @"娱乐",
        ];
    });

    for (NSString *pattern in hiddenPatterns) {
        if ([normalized containsString:pattern]) return YES;
    }
    return NO;
}

static BOOL DYYYShouldHideExtraCommentTabTypeString(NSString *typeString) {
    if (typeString.length == 0) return NO;
    if ([typeString isEqualToString:@"Comment"] || [typeString isEqualToString:@"CommentLike"]) return NO;

    static NSArray<NSString *> *hiddenTypePatterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hiddenTypePatterns = @[
            @"CommentAIParse",
            @"CommentDCFeedAIParse",
            @"CommentTemplatePOI",
            @"CommentEvaluate",
            @"CommentProductComment",
            @"CommentViewer",
            @"CommentFavorite",
            @"CommentGoldLike",
            @"CommentHTSFlame",
            @"CommentSendGoldCollect",
            @"CommentADComment",
            @"CommentGameCP",
            @"CommentTemplateEntertainment",
            @"CommentTemplateGameCP",
        ];
    });

    for (NSString *pattern in hiddenTypePatterns) {
        if ([typeString containsString:pattern]) return YES;
    }
    return NO;
}

static void DYYYCacheHiddenCommentTabTypeIfNeeded(unsigned long long tabType, NSString *title) {
    if (tabType == 0 || title.length == 0) return;
    if (!DYYYStringLooksLikeExtraCommentTab(title)) return;
    if (!gHiddenCommentTabTypes) gHiddenCommentTabTypes = [NSMutableSet set];
    [gHiddenCommentTabTypes addObject:@(tabType)];
}

static BOOL DYYYIsHiddenCommentTabType(unsigned long long tabType) {
    return tabType != 0 && gHiddenCommentTabTypes && [gHiddenCommentTabTypes containsObject:@(tabType)];
}

static BOOL DYYYObjectIsCommentAIParseViewController(id object) {
    if (!object) return NO;
    Class aiParseVCClass = NSClassFromString(kDYYYCommentAIParseViewControllerClassName);
    return aiParseVCClass && [object isKindOfClass:aiParseVCClass];
}

static BOOL DYYYObjectIsExtraCommentTabViewController(id object) {
    if (!object) return NO;
    if (DYYYObjectIsCommentAIParseViewController(object)) return YES;

    Class rateVCClass = NSClassFromString(kDYYYPOIRateListInCommentViewControllerClassName);
    if (rateVCClass && [object isKindOfClass:rateVCClass]) return YES;

    NSString *className = NSStringFromClass([object class]);
    if ([className containsString:@"ProductEvaluation"] ||
        [className containsString:@"RateListInComment"] ||
        [className containsString:@"CommentAIParse"]) {
        return YES;
    }
    return NO;
}

static BOOL DYYYShouldHideCommentTab(unsigned long long tabType, id viewController, NSString *title) {
    if (!DYYYHideCommentViewsEnabled()) return NO;
    if (DYYYIsHiddenCommentTabType(tabType)) return YES;
    if (DYYYObjectIsExtraCommentTabViewController(viewController)) {
        if (tabType != 0) {
            if (!gHiddenCommentTabTypes) gHiddenCommentTabTypes = [NSMutableSet set];
            [gHiddenCommentTabTypes addObject:@(tabType)];
        }
        return YES;
    }
    if (title.length > 0 && DYYYStringLooksLikeExtraCommentTab(title)) {
        if (tabType != 0) DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
        return YES;
    }
    return NO;
}

static NSArray *DYYYFilterExtraCommentTabTypes(NSArray *types) {
    if (!DYYYHideCommentViewsEnabled() || types.count == 0) return types;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:types.count];
    for (id item in types) {
        if ([item isKindOfClass:[NSNumber class]]) {
            unsigned long long value = [(NSNumber *)item unsignedLongLongValue];
            if (DYYYIsHiddenCommentTabType(value)) continue;
        } else if ([item isKindOfClass:[NSString class]]) {
            if (DYYYShouldHideExtraCommentTabTypeString((NSString *)item)) continue;
        }
        [filtered addObject:item];
    }
    return filtered.count == types.count ? types : [filtered copy];
}

static void DYYYHideCommentPanelSegmentedControlView(UIView *segmentedControl) {
    if (!segmentedControl || ![segmentedControl isKindOfClass:[UIView class]]) return;
    segmentedControl.hidden = YES;
    segmentedControl.alpha = 0.0;
    segmentedControl.userInteractionEnabled = NO;
}

static IMP DYYYOriginalIMPValueForObject(NSMutableDictionary *dict, id obj) {
    if (!dict || !obj) return NULL;
    NSValue *v = [dict objectForKey:NSStringFromClass([obj class])];
    return v ? (IMP)v.pointerValue : NULL;
}

#pragma mark - 替换体（IMP）

static BOOL DYYYShouldShowDCFeedAITabWithScene(id self, SEL _cmd, id scene) {
    if (DYYYHideCommentViewsEnabled()) return NO;
    if (gOrigShouldShowDCFeedAITabWithScene) {
        return ((BOOL (*)(id, SEL, id))gOrigShouldShowDCFeedAITabWithScene)(self, _cmd, scene);
    }
    return YES;
}

static BOOL DYYYCurrentVideoShouldShowAITab(id self, SEL _cmd, id aweme, id enterFrom) {
    if (DYYYHideCommentViewsEnabled()) return NO;
    if (gOrigCurrentVideoShouldShowAITab) {
        return ((BOOL (*)(id, SEL, id, id))gOrigCurrentVideoShouldShowAITab)(self, _cmd, aweme, enterFrom);
    }
    return YES;
}

static BOOL DYYYShouldShowRateTabInCommentWithAweme(id self, SEL _cmd, id aweme) {
    if (DYYYHideCommentViewsEnabled()) return NO;
    if (gOrigShouldShowRateTabInCommentWithAweme) {
        return ((BOOL (*)(id, SEL, id))gOrigShouldShowRateTabInCommentWithAweme)(self, _cmd, aweme);
    }
    return YES;
}

static BOOL DYYYShouldShowProductCommentWithAwemeModel(id self, SEL _cmd, id aweme) {
    if (DYYYHideCommentViewsEnabled()) return NO;
    if (gOrigShouldShowProductCommentWithAwemeModel) {
        return ((BOOL (*)(id, SEL, id))gOrigShouldShowProductCommentWithAwemeModel)(self, _cmd, aweme);
    }
    return YES;
}

static BOOL DYYYCommentTabServiceMultiTabs(id self, SEL _cmd, id context) {
    if (DYYYHideCommentViewsEnabled()) return NO;
    if (gOrigCommentTabServiceMultiTabs) {
        return ((BOOL (*)(id, SEL, id))gOrigCommentTabServiceMultiTabs)(self, _cmd, context);
    }
    return YES;
}

static BOOL DYYYCommentTabServiceContainsTab(id self, SEL _cmd, id context, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) return NO;
    if (gOrigCommentTabServiceContainsTab) {
        return ((BOOL (*)(id, SEL, id, unsigned long long))gOrigCommentTabServiceContainsTab)(self, _cmd, context, type);
    }
    return YES;
}

static id DYYYCommentTabManagerViewControllerForType(id self, SEL _cmd, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) return nil;
    id viewController = nil;
    if (gOrigCommentTabManagerViewControllerForType) {
        viewController = ((id (*)(id, SEL, unsigned long long))gOrigCommentTabManagerViewControllerForType)(self, _cmd, type);
    }
    if (DYYYShouldHideCommentTab(type, viewController, nil)) return nil;
    return viewController;
}

static BOOL DYYYCommentTabManagerContainsTab(id self, SEL _cmd, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) return NO;
    if (gOrigCommentTabManagerViewControllerForType) {
        id viewController = ((id (*)(id, SEL, unsigned long long))gOrigCommentTabManagerViewControllerForType)(self, @selector(viewControllerForType:), type);
        if (DYYYShouldHideCommentTab(type, viewController, nil)) return NO;
    }
    if (gOrigCommentTabManagerContainsTab) {
        return ((BOOL (*)(id, SEL, unsigned long long))gOrigCommentTabManagerContainsTab)(self, _cmd, type);
    }
    return YES;
}

static NSArray *DYYYCommentTabManagerComponentTypes(id self, SEL _cmd, NSArray *types) {
    NSArray *originalTypes = types;
    if (gOrigCommentTabManagerComponentTypes) {
        originalTypes = ((NSArray *(*)(id, SEL, NSArray *))gOrigCommentTabManagerComponentTypes)(self, _cmd, types);
    }
    return DYYYFilterExtraCommentTabTypes(originalTypes);
}

static void DYYYCommentTabManagerConfigSegmentedControl(id self, SEL _cmd, id segmentedControl) {
    if (gOrigCommentTabManagerConfigSegmentedControl) {
        ((void (*)(id, SEL, id))gOrigCommentTabManagerConfigSegmentedControl)(self, _cmd, segmentedControl);
    }
    if (DYYYHideCommentViewsEnabled()) {
        DYYYHideCommentPanelSegmentedControlView((UIView *)segmentedControl);
    }
}

static id DYYYCommentPanelTabBasicParamsInit(id self, SEL _cmd, id preNode) {
    id params = nil;
    if (gOrigCommentPanelTabBasicParamsInit) {
        params = ((id (*)(id, SEL, id))gOrigCommentPanelTabBasicParamsInit)(self, _cmd, preNode);
    }
    if (DYYYHideCommentViewsEnabled() && params) {
        [params setValue:@YES forKey:@"noTabScene"];
    }
    return params;
}

static BOOL DYYYCommentPanelTabBasicParamsNoTabScene(id self, SEL _cmd) {
    if (DYYYHideCommentViewsEnabled()) return YES;
    if (gOrigCommentPanelTabBasicParamsNoTabScene) {
        return ((BOOL (*)(id, SEL))gOrigCommentPanelTabBasicParamsNoTabScene)(self, _cmd);
    }
    return NO;
}

static double DYYYCommentContainerHeightForSegmentedControl(id self, SEL _cmd) {
    if (DYYYHideCommentViewsEnabled()) return 0.0;
    if (gOrigCommentContainerHeightForSegmentedControl) {
        return ((double (*)(id, SEL))gOrigCommentContainerHeightForSegmentedControl)(self, _cmd);
    }
    return 0.0;
}

static void DYYYCommentExtraTabSetNeedsUpdate(id self, SEL _cmd, BOOL needsUpdate, id completion) {
    if (DYYYHideCommentViewsEnabled()) {
        if (completion) {
            ((void (^)(void))completion)();
        }
        return;
    }

    IMP orig = DYYYOriginalIMPValueForObject(gOrigCommentTabSetNeedsUpdateIMPs, self);
    if (orig) {
        ((void (*)(id, SEL, BOOL, id))orig)(self, _cmd, needsUpdate, completion);
    }
}

static void DYYYCommentTabModelSetTitle(id self, SEL _cmd, NSString *title) {
    if (gOrigCommentTabModelSetTitle) {
        ((void (*)(id, SEL, NSString *))gOrigCommentTabModelSetTitle)(self, _cmd, title);
    }
    if (!DYYYStringLooksLikeExtraCommentTab(title)) return;
    if ([self respondsToSelector:@selector(tab)]) {
        unsigned long long tabType = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, @selector(tab));
        DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
    }
}

static void DYYYCommentContainerTabModelSetTitle(id self, SEL _cmd, NSString *title) {
    if (gOrigCommentContainerTabModelSetTitle) {
        ((void (*)(id, SEL, NSString *))gOrigCommentContainerTabModelSetTitle)(self, _cmd, title);
    }
    if (!DYYYStringLooksLikeExtraCommentTab(title)) return;
    if ([self respondsToSelector:@selector(tab)]) {
        unsigned long long tabType = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, @selector(tab));
        DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
    }
}

#pragma mark - swizzling 安装 helper

static BOOL DYYYInstallInstanceHook(NSString *className, NSString *mangled, SEL selector, IMP newIMP, IMP *origPtr) {
    Class cls = DYYYGetCommentClass(className, mangled);
    if (!cls) return NO;
    Method m = class_getInstanceMethod(cls, selector);
    if (!m) return NO;
    if (origPtr) *origPtr = method_getImplementation(m);
    method_setImplementation(m, newIMP);
    return YES;
}

static BOOL DYYYInstallClassHook(NSString *className, NSString *mangled, SEL selector, IMP newIMP, IMP *origPtr) {
    Class cls = DYYYGetCommentClass(className, mangled);
    if (!cls) return NO;
    Method m = class_getClassMethod(cls, selector);
    if (!m) return NO;
    if (origPtr) *origPtr = method_getImplementation(m);
    method_setImplementation(m, newIMP);
    return YES;
}

static BOOL DYYYInstallSetNeedsUpdateHookForClassName(NSString *className, NSString *mangled) {
    Class cls = DYYYGetCommentClass(className, mangled);
    if (!cls) return NO;
    Method m = class_getInstanceMethod(cls, @selector(setNeedsUpdate:completion:));
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    if (orig) {
        if (!gOrigCommentTabSetNeedsUpdateIMPs) gOrigCommentTabSetNeedsUpdateIMPs = [NSMutableDictionary dictionary];
        [gOrigCommentTabSetNeedsUpdateIMPs setObject:[NSValue valueWithPointer:orig] forKey:NSStringFromClass(cls)];
    }
    method_setImplementation(m, (IMP)DYYYCommentExtraTabSetNeedsUpdate);
    return YES;
}

#pragma mark - 各模块 installer

static BOOL DYYYInstallFeedDoubleColumnAITabUtilHooks(void) {
    BOOL a = DYYYInstallClassHook(kDYYYFeedDoubleColumnAITabUtilClassName, nil,
                                  @selector(shouldShowDCFeedAITabWithScene:),
                                  (IMP)DYYYShouldShowDCFeedAITabWithScene, &gOrigShouldShowDCFeedAITabWithScene);
    BOOL b = DYYYInstallClassHook(kDYYYFeedDoubleColumnAITabUtilClassName, nil,
                                  @selector(currentVideoShouldShowAITab:enterFrom:),
                                  (IMP)DYYYCurrentVideoShouldShowAITab, &gOrigCurrentVideoShouldShowAITab);
    return a || b;
}

static BOOL DYYYInstallLocalLifeCommentBizServiceHooks(void) {
    return DYYYInstallInstanceHook(kDYYYLocalLifeCommentBizServiceClassName, nil,
                                   @selector(shouldShowRateTabInCommentWithAweme:),
                                   (IMP)DYYYShouldShowRateTabInCommentWithAweme, &gOrigShouldShowRateTabInCommentWithAweme);
}

static BOOL DYYYInstallECModuleServiceHooks(void) {
    return DYYYInstallInstanceHook(kDYYYECModuleServiceClassName, nil,
                                   @selector(shouldShowProductCommentWithAwemeModel:),
                                   (IMP)DYYYShouldShowProductCommentWithAwemeModel, &gOrigShouldShowProductCommentWithAwemeModel);
}

static BOOL DYYYInstallCommentPanelTabBasicParamsHooks(void) {
    BOOL a = DYYYInstallInstanceHook(kDYYYCommentPanelTabBasicParamsClassName, nil,
                                     @selector(initWithPreNode:),
                                     (IMP)DYYYCommentPanelTabBasicParamsInit, &gOrigCommentPanelTabBasicParamsInit);
    BOOL b = DYYYInstallInstanceHook(kDYYYCommentPanelTabBasicParamsClassName, nil,
                                     @selector(noTabScene),
                                     (IMP)DYYYCommentPanelTabBasicParamsNoTabScene, &gOrigCommentPanelTabBasicParamsNoTabScene);
    return a || b;
}

static BOOL DYYYInstallCommentContainerInnerHooks(void) {
    return DYYYInstallInstanceHook(kDYYYCommentContainerInnerViewControllerClassName, kDYYYCommentContainerInnerViewControllerMangled,
                                   @selector(heightForSegmentedControl),
                                   (IMP)DYYYCommentContainerHeightForSegmentedControl, &gOrigCommentContainerHeightForSegmentedControl);
}

static BOOL DYYYInstallCommentTabServiceHooks(void) {
    BOOL a = DYYYInstallInstanceHook(kDYYYCommentTabServiceClassName, nil,
                                     @selector(multiTabs:),
                                     (IMP)DYYYCommentTabServiceMultiTabs, &gOrigCommentTabServiceMultiTabs);
    BOOL b = DYYYInstallInstanceHook(kDYYYCommentTabServiceClassName, nil,
                                     @selector(containsTab:type:),
                                     (IMP)DYYYCommentTabServiceContainsTab, &gOrigCommentTabServiceContainsTab);
    return a || b;
}

static BOOL DYYYInstallCommentTabManagerHooks(void) {
    BOOL a = DYYYInstallInstanceHook(kDYYYCommentTabManagerClassName, kDYYYCommentTabManagerMangled,
                                     @selector(viewControllerForType:),
                                     (IMP)DYYYCommentTabManagerViewControllerForType, &gOrigCommentTabManagerViewControllerForType);
    BOOL b = DYYYInstallInstanceHook(kDYYYCommentTabManagerClassName, kDYYYCommentTabManagerMangled,
                                     @selector(containsTab:),
                                     (IMP)DYYYCommentTabManagerContainsTab, &gOrigCommentTabManagerContainsTab);
    BOOL c = DYYYInstallInstanceHook(kDYYYCommentTabManagerClassName, kDYYYCommentTabManagerMangled,
                                     @selector(componentTypes:),
                                     (IMP)DYYYCommentTabManagerComponentTypes, &gOrigCommentTabManagerComponentTypes);
    BOOL d = DYYYInstallInstanceHook(kDYYYCommentTabManagerClassName, kDYYYCommentTabManagerMangled,
                                     @selector(configSegmentedControl:),
                                     (IMP)DYYYCommentTabManagerConfigSegmentedControl, &gOrigCommentTabManagerConfigSegmentedControl);
    return a || b || c || d;
}

static BOOL DYYYInstallExtraCommentTabComponentHooks(void) {
    BOOL a = DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentDCFeedAIParseTabComponentClassName, kDYYYCommentDCFeedAIParseTabComponentMangled);
    BOOL b = DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentTemplatePOITabComponentClassName, kDYYYCommentTemplatePOITabComponentMangled);
    BOOL c = DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentEvaluateTabComponentClassName, kDYYYCommentEvaluateTabComponentMangled);
    BOOL d = DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentProductCommentTabComponentClassName, kDYYYCommentProductCommentTabComponentMangled);
    return a || b || c || d;
}

static BOOL DYYYInstallCommentTabModelHooks(void) {
    BOOL a = DYYYInstallInstanceHook(kDYYYCommentTabModelClassName, kDYYYCommentTabModelMangled,
                                     @selector(setTitle:),
                                     (IMP)DYYYCommentTabModelSetTitle, &gOrigCommentTabModelSetTitle);
    BOOL b = DYYYInstallInstanceHook(kDYYYCommentContainerTabModelClassName, kDYYYCommentContainerTabModelMangled,
                                     @selector(setTitle:),
                                     (IMP)DYYYCommentContainerTabModelSetTitle, &gOrigCommentContainerTabModelSetTitle);
    return a || b;
}

#pragma mark - 安装入口

void DYYYStartHideCommentAIAnalysisHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL utilHooked = DYYYInstallFeedDoubleColumnAITabUtilHooks();
        BOOL localLifeHooked = DYYYInstallLocalLifeCommentBizServiceHooks();
        BOOL ecomHooked = DYYYInstallECModuleServiceHooks();
        BOOL basicParamsHooked = DYYYInstallCommentPanelTabBasicParamsHooks();
        BOOL containerHooked = DYYYInstallCommentContainerInnerHooks();
        BOOL serviceHooked = DYYYInstallCommentTabServiceHooks();
        BOOL managerHooked = DYYYInstallCommentTabManagerHooks();
        BOOL componentHooked = DYYYInstallExtraCommentTabComponentHooks();
        BOOL modelHooked = DYYYInstallCommentTabModelHooks();

        NSLog(@"[DYYY][RuntimeHook][HideCommentExtraTabs] 安装完成 util=%@ localLife=%@ ecom=%@ basicParams=%@ container=%@ service=%@ manager=%@ component=%@ model=%@",
              utilHooked ? @"YES" : @"NO",
              localLifeHooked ? @"YES" : @"NO",
              ecomHooked ? @"YES" : @"NO",
              basicParamsHooked ? @"YES" : @"NO",
              containerHooked ? @"YES" : @"NO",
              serviceHooked ? @"YES" : @"NO",
              managerHooked ? @"YES" : @"NO",
              componentHooked ? @"YES" : @"NO",
              modelHooked ? @"YES" : @"NO");
    });
}
