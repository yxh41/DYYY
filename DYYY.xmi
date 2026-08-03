//
//  DYYY
//
//  Copyright (c) 2024 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2024/10/04
//
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <float.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <syslog.h>

#import "AwemeHeaders.h"
#import "CityManager.h"
#import "DYYYBottomAlertView.h"
#import "DYYYManager.h"

#import "AWMSafeDispatchTimer.h"
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingViewController.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"

static CGFloat gStartY = 0.0;
static CGFloat gStartVal = 0.0;
static DYEdgeMode gMode = DYEdgeModeNone;
static __weak UICollectionView *gFeedCV = nil;

static const CGFloat kInvalidAlpha = -1.0;
static const CGFloat kInvalidHeight = -1.0;
static CGFloat gGlobalTransparency = kInvalidAlpha;
static CGFloat gCurrentTabBarHeight = kInvalidHeight;
static CGFloat originalTabBarHeight = kInvalidHeight;
static NSString *const kDYYYGlobalTransparencyKey = @"DYYYGlobalTransparency";
static NSString *const kDYYYGlobalTransparencyDidChangeNotification = @"DYYYGlobalTransparencyDidChangeNotification";
static char kDYYYGlobalTransparencyBaseAlphaKey;
static NSInteger dyyyGlobalTransparencyMutationDepth = 0;

static void updateGlobalTransparencyCache() {
    NSString *transparentValue = DYYYGetString(kDYYYGlobalTransparencyKey);
    if (transparentValue.length > 0) {
        float alphaValue;
        NSScanner *scanner = [NSScanner scannerWithString:transparentValue];
        if ([scanner scanFloat:&alphaValue] && scanner.isAtEnd) {
            gGlobalTransparency = MIN(MAX(alphaValue, 0.0), 1.0);
            return;
        }
    }
    gGlobalTransparency = kInvalidAlpha;
}

static NSDictionary<NSString *, NSString *> *DYYYTopTabTitleMapping(void) {
    static NSString *cachedRawValue = nil;
    static NSDictionary<NSString *, NSString *> *cachedMapping = nil;

    NSString *currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYModifyTopTabText"];
    BOOL rawValueChanged = (cachedRawValue != currentValue) && ![cachedRawValue isEqualToString:currentValue];

    if (!rawValueChanged) {
        return cachedMapping;
    }

    cachedRawValue = [currentValue copy];

    if (currentValue.length == 0) {
        cachedMapping = nil;
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *mapping = [NSMutableDictionary dictionary];
    NSArray<NSString *> *titlePairs = [currentValue componentsSeparatedByString:@"#"];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *pair in titlePairs) {
        NSArray<NSString *> *components = [pair componentsSeparatedByString:@"="];
        if (components.count != 2) {
            continue;
        }

        NSString *originalTitle = [components[0] stringByTrimmingCharactersInSet:whitespace];
        NSString *newTitle = [components[1] stringByTrimmingCharactersInSet:whitespace];

        if (originalTitle.length == 0 || newTitle.length == 0) {
            continue;
        }

        mapping[originalTitle] = newTitle;
    }

    cachedMapping = mapping.count > 0 ? [mapping copy] : nil;
    return cachedMapping;
}

static NSString *DYYYCustomAssetsDirectory(void) {
    static NSString *customDirectory = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
      customDirectory = [documentsPath stringByAppendingPathComponent:@"DYYY"];
      [[NSFileManager defaultManager] createDirectoryAtPath:customDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    });

    return customDirectory;
}

static NSString *DYYYCustomIconFileNameForButtonName(NSString *nameString) {
    if (nameString.length == 0) {
        return nil;
    }

    static NSDictionary<NSString *, NSString *> *prefixMapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      prefixMapping = @{
          @"icon_home_like_after" : @"like_after.png",
          @"icon_home_like_before" : @"like_before.png",
          @"icon_home_comment" : @"comment.png",
          @"icon_home_unfavorite" : @"unfavorite.png",
          @"icon_home_favorite" : @"favorite.png",
          @"iconHomeShareRight" : @"share.png"
      };
    });

    for (NSString *prefix in prefixMapping) {
        if ([nameString hasPrefix:prefix]) {
            return prefixMapping[prefix];
        }
    }

    if ([nameString containsString:@"_comment"]) {
        return @"comment.png";
    }
    if ([nameString containsString:@"_like"]) {
        BOOL isLikedState = [nameString containsString:@"_after"] || [nameString containsString:@"_liked"];
        return isLikedState ? @"like_after.png" : @"like_before.png";
    }
    if ([nameString containsString:@"_collect"]) {
        return @"unfavorite.png";
    }
    if ([nameString containsString:@"_share"]) {
        return @"share.png";
    }

    return nil;
}

static UIImage *DYYYLoadCustomImage(NSString *fileName, CGSize targetSize) {
    if (fileName.length == 0) {
        return nil;
    }

    static NSCache<NSString *, UIImage *> *imageCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      imageCache = [[NSCache alloc] init];
      imageCache.name = @"com.dyyy.customIcons.cache";
    });

    NSString *cacheKey = (targetSize.width > 0.0 && targetSize.height > 0.0) ? [NSString stringWithFormat:@"%@_%0.1f_%0.1f", fileName, targetSize.width, targetSize.height] : fileName;

    UIImage *cachedImage = [imageCache objectForKey:cacheKey];
    if (cachedImage) {
        return cachedImage;
    }

    NSString *fullPath = [DYYYCustomAssetsDirectory() stringByAppendingPathComponent:fileName];
    UIImage *sourceImage = [UIImage imageWithContentsOfFile:fullPath];
    if (!sourceImage) {
        return nil;
    }

    if (targetSize.width <= 0.0 || targetSize.height <= 0.0) {
        [imageCache setObject:sourceImage forKey:cacheKey];
        return sourceImage;
    }

    CGSize originalSize = sourceImage.size;
    if (originalSize.width <= 0.0 || originalSize.height <= 0.0) {
        return sourceImage;
    }

    CGFloat widthScale = targetSize.width / originalSize.width;
    CGFloat heightScale = targetSize.height / originalSize.height;
    CGFloat scale = fmin(widthScale, heightScale);

    if (fabs(1.0 - scale) <= FLT_EPSILON) {
        [imageCache setObject:sourceImage forKey:cacheKey];
        return sourceImage;
    }

    CGSize newSize = CGSizeMake(originalSize.width * scale, originalSize.height * scale);
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [sourceImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIImage *resultImage = resizedImage ?: sourceImage;
    [imageCache setObject:resultImage forKey:cacheKey];
    return resultImage;
}

static BOOL DYYYShouldHandleSpeedFeatures(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFloatSpeedButton"]) {
        return YES;
    }

    float defaultSpeed = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYDefaultSpeed"];
    if (defaultSpeed <= 0.0f) {
        return NO;
    }

    return fabsf(defaultSpeed - 1.0f) > FLT_EPSILON;
}

static __weak AWEPlayInteractionViewController *dyyyActiveSpeedInteractionController = nil;
static __weak AWEAwemeModel *dyyyCurrentSpeedAweme = nil;
static NSString *dyyyLastAutoRestoredSpeedAwemeIdentifier = nil;
static BOOL dyyyLongPressFastSpeedActive = NO;
static BOOL dyyyLongPressLockedSpeedActive = NO;

static void DYYYClearLongPressSpeedState(void) {
    dyyyLongPressFastSpeedActive = NO;
    dyyyLongPressLockedSpeedActive = NO;
}

static CGFloat DYYYViewControllerVisibilityScore(UIViewController *viewController) {
    if (!viewController || !viewController.isViewLoaded) {
        return -1.0;
    }

    UIView *view = viewController.view;
    UIWindow *window = view.window;
    if (!window || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return -1.0;
    }

    CGRect frameInWindow = [view convertRect:view.bounds toView:window];
    CGRect visibleFrame = CGRectIntersection(frameInWindow, window.bounds);
    if (CGRectIsNull(visibleFrame) || CGRectIsEmpty(visibleFrame)) {
        return -1.0;
    }

    CGFloat visibleArea = CGRectGetWidth(visibleFrame) * CGRectGetHeight(visibleFrame);
    CGFloat totalArea = CGRectGetWidth(frameInWindow) * CGRectGetHeight(frameInWindow);
    CGFloat visibleRatio = totalArea > 0.0 ? visibleArea / totalArea : 0.0;
    CGPoint windowCenter = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    CGFloat centerBonus = CGRectContainsPoint(visibleFrame, windowCenter) ? 1000000000.0 : 0.0;
    return centerBonus + visibleRatio * 1000000.0 + visibleArea;
}

static BOOL DYYYAwemeModelsMatch(AWEAwemeModel *lhs, AWEAwemeModel *rhs) {
    if (!lhs || !rhs) {
        return NO;
    }
    if (lhs == rhs) {
        return YES;
    }

    NSString *lhsItemID = lhs.itemID;
    NSString *rhsItemID = rhs.itemID;
    return lhsItemID.length > 0 && rhsItemID.length > 0 && [lhsItemID isEqualToString:rhsItemID];
}

static NSString *DYYYSpeedAwemeIdentifier(AWEAwemeModel *aweme) {
    if (!aweme) {
        return nil;
    }
    if (aweme.itemID.length > 0) {
        return aweme.itemID;
    }
    return [NSString stringWithFormat:@"%p", aweme];
}

static AWEAwemeModel *DYYYSpeedAwemeFromObject(id object) {
    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (!object || !awemeClass) {
        return nil;
    }
    if ([object isKindOfClass:awemeClass]) {
        return (AWEAwemeModel *)object;
    }

    for (NSString *key in @[ @"model", @"awemeModel", @"currentAweme" ]) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:awemeClass]) {
                return (AWEAwemeModel *)value;
            }
        } @catch (NSException *exception) {
        }
    }
    return nil;
}

static double DYYYDefaultPlaybackSpeed(void) {
    double defaultSpeed = [[NSUserDefaults standardUserDefaults] doubleForKey:@"DYYYDefaultSpeed"];
    if (isfinite(defaultSpeed) && defaultSpeed > 0.0) {
        return defaultSpeed;
    }
    return 1.0;
}

static void DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(AWEAwemeModel *aweme) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL shouldAutoRestore = [defaults boolForKey:@"DYYYEnableFloatSpeedButton"] && [defaults boolForKey:@"DYYYAutoRestoreSpeed"];
    if (!shouldAutoRestore) {
        dyyyLastAutoRestoredSpeedAwemeIdentifier = nil;
        return;
    }

    NSString *awemeIdentifier = DYYYSpeedAwemeIdentifier(aweme);
    if (awemeIdentifier.length == 0 || [awemeIdentifier isEqualToString:dyyyLastAutoRestoredSpeedAwemeIdentifier]) {
        return;
    }

    dyyyLastAutoRestoredSpeedAwemeIdentifier = [awemeIdentifier copy];
    if (!setCurrentSpeedValue((float)DYYYDefaultPlaybackSpeed())) {
        setCurrentSpeedIndex(0);
    }
    updateSpeedButtonUI();
}

static NSArray<AWEPlayInteractionViewController *> *DYYYSpeedInteractionControllers(AWEPlayInteractionViewController *preferredController) {
    NSMutableArray<AWEPlayInteractionViewController *> *controllers = [NSMutableArray array];
    Class interactionControllerClass = NSClassFromString(@"AWEPlayInteractionViewController");
    UIWindow *window = [DYYYUtils getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    for (UIViewController *viewController in rootViewController ? findViewControllersInHierarchy(rootViewController) : @[]) {
        if (interactionControllerClass && [viewController isKindOfClass:interactionControllerClass]) {
            [controllers addObject:(AWEPlayInteractionViewController *)viewController];
        }
    }

    if (preferredController && ![controllers containsObject:preferredController]) {
        [controllers addObject:preferredController];
    }
    return controllers;
}

static AWEPlayInteractionViewController *DYYYResolveSpeedInteractionController(AWEPlayInteractionViewController *preferredController, AWEAwemeModel *targetAweme, BOOL allowVisibleFallback) {
    AWEPlayInteractionViewController *bestModelMatch = nil;
    AWEPlayInteractionViewController *bestVisibleController = nil;
    CGFloat bestModelMatchScore = -1.0;
    CGFloat bestVisibleScore = -1.0;

    for (AWEPlayInteractionViewController *controller in DYYYSpeedInteractionControllers(preferredController)) {
        CGFloat visibilityScore = DYYYViewControllerVisibilityScore(controller);
        if (visibilityScore < 0.0) {
            continue;
        }

        if (visibilityScore > bestVisibleScore) {
            bestVisibleScore = visibilityScore;
            bestVisibleController = controller;
        }
        if (targetAweme && DYYYAwemeModelsMatch(controller.model, targetAweme) && visibilityScore > bestModelMatchScore) {
            bestModelMatchScore = visibilityScore;
            bestModelMatch = controller;
        }
    }

    return bestModelMatch ?: (allowVisibleFallback ? bestVisibleController : nil);
}

static AWEPlayInteractionViewController *DYYYResolveCurrentSpeedInteractionController(AWEPlayInteractionViewController *preferredController) {
    return DYYYResolveSpeedInteractionController(preferredController, dyyyCurrentSpeedAweme, YES);
}

id DYYYCurrentSpeedInteractionController(void) {
    return DYYYResolveCurrentSpeedInteractionController(dyyyActiveSpeedInteractionController);
}

static void DYYYEnsureFloatSpeedButton(AWEPlayInteractionViewController *interactionController) {
    [FloatingSpeedButton reloadConfiguration];
    AWEAwemeModel *targetAweme = dyyyCurrentSpeedAweme;
    BOOL allowVisibleFallback = !targetAweme || (interactionController && DYYYAwemeModelsMatch(interactionController.model, targetAweme));
    AWEPlayInteractionViewController *currentController = DYYYResolveSpeedInteractionController(interactionController, targetAweme, allowVisibleFallback);
    if (!currentController) {
        updateSpeedButtonVisibility();
        return;
    }

    if ((dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) &&
        currentController.model &&
        !DYYYAwemeModelsMatch(dyyyCurrentSpeedAweme, currentController.model)) {
        DYYYClearLongPressSpeedState();
    }

    dyyyActiveSpeedInteractionController = currentController;
    dyyyCurrentSpeedAweme = currentController.model;
    dyyyInteractionViewVisible = YES;

    if (!isFloatSpeedButtonEnabled) {
        updateSpeedButtonVisibility();
        return;
    }

    UIWindow *keyWindow = [DYYYUtils getActiveWindow];
    if (!keyWindow) {
        return;
    }

    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(currentController.model);

    if (!speedButton) {
        CGRect windowBounds = keyWindow.bounds;
        CGRect initialFrame = CGRectMake((windowBounds.size.width - speedButtonSize) / 2.0, (windowBounds.size.height - speedButtonSize) / 2.0, speedButtonSize, speedButtonSize);
        speedButton = [[FloatingSpeedButton alloc] initWithFrame:initialFrame];
        speedButton.interactionController = currentController;
        updateSpeedButtonUI();
    } else if (speedButton.interactionController != currentController) {
        speedButton.interactionController = currentController;
        [speedButton resetButtonState];
    }

    if (![speedButton isDescendantOfView:keyWindow]) {
        [keyWindow addSubview:speedButton];
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }

    [keyWindow bringSubviewToFront:speedButton];
    updateSpeedButtonVisibility();
}

// 提供给跨文件调用的刷新入口：根据当前可见 PlayInteractionVC 重新评估并恢复倍速按钮，
// 用于清屏退出等场景，避免清屏期间 viewDidDisappear 把 dyyyInteractionViewVisible 置 NO 后状态卡住。
void DYYYRefreshFloatSpeedButton(void) {
    void (^applyBlock)(void) = ^{
        AWEPlayInteractionViewController *currentController = (AWEPlayInteractionViewController *)DYYYCurrentSpeedInteractionController();
        DYYYEnsureFloatSpeedButton(currentController);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static BOOL DYYYSetPlaybackRateOnTarget(id target, double speed) {
    if (!target || ![target respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) {
        return NO;
    }

    @try {
        [(AWEAwemePlayVideoViewController *)target setVideoControllerPlaybackRate:speed];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

static BOOL DYYYApplyPlaybackSpeed(AWEPlayInteractionViewController *interactionController, double speed) {
    interactionController = DYYYResolveCurrentSpeedInteractionController(interactionController);
    if (!interactionController) {
        return NO;
    }

    Protocol *speedControllerProtocol = NSProtocolFromString(@"AWEFastSpeedControllerProtocol");
    if (speedControllerProtocol && [interactionController respondsToSelector:@selector(controllerByProtocol:)]) {
        @try {
            id speedController = [interactionController controllerByProtocol:speedControllerProtocol];
            if ([speedController respondsToSelector:@selector(playVideoViewController)]) {
                id playVideoViewController = [(AWEPlayInteractionSpeedController *)speedController playVideoViewController];
                if (DYYYSetPlaybackRateOnTarget(playVideoViewController, speed)) {
                    return YES;
                }
            }
        } @catch (NSException *exception) {
        }
    }

    if ([interactionController respondsToSelector:@selector(videoDelegate)] && DYYYSetPlaybackRateOnTarget([interactionController videoDelegate], speed)) {
        return YES;
    }

    UIWindow *window = [DYYYUtils getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    UIViewController *bestPlayerViewController = nil;
    CGFloat bestPlayerVisibilityScore = -1.0;
    for (UIViewController *viewController in rootViewController ? findViewControllersInHierarchy(rootViewController) : @[]) {
        if ([viewController isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
            CGFloat visibilityScore = DYYYViewControllerVisibilityScore(viewController);
            if (visibilityScore > bestPlayerVisibilityScore) {
                bestPlayerVisibilityScore = visibilityScore;
                bestPlayerViewController = viewController;
            }
        }
    }

    return DYYYSetPlaybackRateOnTarget(bestPlayerViewController, speed);
}

static double DYYYConfiguredPlaybackSpeed(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"DYYYEnableFloatSpeedButton"]) {
        return getCurrentSpeed();
    }

    if ([defaults boolForKey:@"DYYYUserAgreementAccepted"]) {
        return DYYYDefaultPlaybackSpeed();
    }
    return 1.0;
}

static BOOL DYYYShouldPrepareDefaultPlaybackSpeedForPlayer(id playerViewController) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"DYYYEnableFloatSpeedButton"] || ![defaults boolForKey:@"DYYYAutoRestoreSpeed"]) {
        return NO;
    }

    AWEAwemeModel *targetAweme = DYYYSpeedAwemeFromObject(playerViewController) ?: dyyyCurrentSpeedAweme;
    NSString *awemeIdentifier = DYYYSpeedAwemeIdentifier(targetAweme);
    return awemeIdentifier.length > 0 && ![awemeIdentifier isEqualToString:dyyyLastAutoRestoredSpeedAwemeIdentifier];
}

static double DYYYPreparedPlaybackSpeedForPlayer(id playerViewController) {
    // Auto-restore belongs to aweme transitions; current-video refreshes should keep the selected quick speed.
    if (DYYYShouldPrepareDefaultPlaybackSpeedForPlayer(playerViewController)) {
        return DYYYDefaultPlaybackSpeed();
    }
    return DYYYConfiguredPlaybackSpeed();
}

static void DYYYApplyPreparedPlaybackSpeedToPlayer(id playerViewController) {
    if (!DYYYShouldHandleSpeedFeatures() || !playerViewController || dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) {
        return;
    }

    double speed = DYYYPreparedPlaybackSpeedForPlayer(playerViewController);
    void (^applyBlock)(void) = ^{
      DYYYSetPlaybackRateOnTarget(playerViewController, speed);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static void DYYYBindAndApplyCurrentPlaybackSpeed(void) {
    if (!DYYYShouldHandleSpeedFeatures() || dyyyLongPressFastSpeedActive || dyyyLongPressLockedSpeedActive) {
        return;
    }

    AWEAwemeModel *targetAweme = dyyyCurrentSpeedAweme;
    AWEPlayInteractionViewController *currentController = DYYYResolveSpeedInteractionController(nil, targetAweme, targetAweme == nil);
    if (!currentController) {
        return;
    }

    DYYYEnsureFloatSpeedButton(currentController);
    DYYYApplyPlaybackSpeed(currentController, DYYYConfiguredPlaybackSpeed());
}

static void DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(NSTimeInterval delay) {
    dispatch_block_t restoreBlock = ^{
      DYYYBindAndApplyCurrentPlaybackSpeed();
    };
    if (delay <= 0.0) {
        dispatch_async(dispatch_get_main_queue(), restoreBlock);
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), restoreBlock);
    }
}

static void DYYYScheduleConfiguredPlaybackSpeedRestore(void) {
    DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.0);
    DYYYScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.2);
}

static void DYYYEndLockedLongPressSpeedAndRestoreIfNeeded(void) {
    if (!dyyyLongPressLockedSpeedActive) {
        return;
    }
    dyyyLongPressLockedSpeedActive = NO;
    DYYYScheduleConfiguredPlaybackSpeedRestore();
}

static void DYYYHandleCurrentSpeedAwemeChanged(id aweme) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DYYYHandleCurrentSpeedAwemeChanged(aweme);
        });
        return;
    }

    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (awemeClass && [aweme isKindOfClass:awemeClass]) {
        dyyyCurrentSpeedAweme = (AWEAwemeModel *)aweme;
    }
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }

    DYYYClearLongPressSpeedState();
    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(dyyyCurrentSpeedAweme);

    DYYYBindAndApplyCurrentPlaybackSpeed();
    DYYYScheduleConfiguredPlaybackSpeedRestore();
}

@interface AWEFeedProgressSlider (DYYYProgressLabel)
- (NSString *)dyyy_formatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dyyy_modelDurationInSeconds;
- (CGFloat)dyyy_scheduleVerticalOffset;
- (void)dyyy_removeScheduleLabels;
- (void)dyyy_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEPlayInteractionProgressController (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEDProgressCoreContainer (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface UIView (DYYYProgressLabelLegacy)
- (void)dyyy_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model;
@end

@implementation UIView (DYYYProgressLabelLegacy)

- (NSString *)dyyy_legacyFormatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) {
        safeSeconds = 0;
    }

    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

- (CGFloat)dyyy_legacyScheduleVerticalOffset {
    CGFloat verticalOffset = -12.5;
    NSString *offsetValueString = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTimelineVerticalPosition"];
    if (offsetValueString.length > 0) {
        CGFloat configuredOffset = [offsetValueString floatValue];
        if (configuredOffset != 0) {
            verticalOffset = configuredOffset;
        }
    }
    return verticalOffset;
}

- (CGFloat)dyyy_legacyModelDurationInSeconds:(id)model {
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) {
        return 0;
    }

    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) {
        return 0;
    }
    return videoDurationMs / 1000.0;
}

- (void)dyyy_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        UIView *parentView = self.superview;
        if (parentView) {
            [[parentView viewWithTag:10001] removeFromSuperview];
            [[parentView viewWithTag:10002] removeFromSuperview];
        }
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
        });
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];

    NSString *scheduleStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYScheduleStyle"];
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];

    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;

    CGFloat modelDuration = [self dyyy_legacyModelDurationInSeconds:model];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) {
        effectiveTotalDuration = 0;
    }

    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) {
        effectiveCurrentTime = 0;
    }
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) {
        effectiveCurrentTime = effectiveTotalDuration;
    }

    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) {
        return;
    }
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyyy_legacyScheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYProgressLabelColor"];

    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) {
        [leftLabel removeFromSuperview];
        leftLabel = nil;
    }

    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }
        leftLabel.font = labelFont;

        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dyyy_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime];
        }

        if (![leftLabel.text isEqualToString:newLeftText]) {
            leftLabel.text = newLeftText;
        }
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:leftLabel colorHexString:labelColorHex];
    } else {
        [leftLabel removeFromSuperview];
    }

    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) {
        [rightLabel removeFromSuperview];
        rightLabel = nil;
    }

    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }
        rightLabel.font = labelFont;

        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dyyy_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyyy_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyyy_legacyFormatTimeFromSeconds:effectiveTotalDuration];
        }

        if (![rightLabel.text isEqualToString:newRightText]) {
            rightLabel.text = newRightText;
        }
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
        [DYYYUtils applyColorSettingsToLabel:rightLabel colorHexString:labelColorHex];
    } else {
        [rightLabel removeFromSuperview];
    }
}

@end

// 关闭不可见水印

// 长按复制个人简介

// 抖音 39.1.0 访问他人主页时会由详情组件直接上传访客记录

// 兼容旧版访客记录上传路径

@interface AWENowPlayingInfoCenter : NSObject
@property(nonatomic, weak) id playingPlayer;
@end

@interface MPNowPlayingInfoCenter : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
+ (instancetype)defaultCenter;
@end

static BOOL dyyyClearingFeedNowPlayingSystemInfo = NO;
static CFTimeInterval dyyyLastFeedNowPlayingSystemClearTime = 0.0;

static void DYYYClearFeedNowPlayingSystemInfoThrottled(void) {
    if (!DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo") || dyyyClearingFeedNowPlayingSystemInfo) {
        return;
    }

    CFTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    if (currentTime - dyyyLastFeedNowPlayingSystemClearTime < 0.25) {
        return;
    }
    dyyyLastFeedNowPlayingSystemClearTime = currentTime;

    Class nowPlayingInfoCenterClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!nowPlayingInfoCenterClass || ![nowPlayingInfoCenterClass respondsToSelector:@selector(defaultCenter)]) {
        return;
    }

    id center = ((id (*)(Class, SEL))objc_msgSend)(nowPlayingInfoCenterClass, @selector(defaultCenter));
    if (!center) {
        return;
    }

    dyyyClearingFeedNowPlayingSystemInfo = YES;
    @try {
        if ([center respondsToSelector:@selector(setNowPlayingInfo:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(center, @selector(setNowPlayingInfo:), nil);
        }

        SEL setPlaybackStateSelector = NSSelectorFromString(@"setPlaybackState:");
        if ([center respondsToSelector:setPlaybackStateSelector]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(center, setPlaybackStateSelector, 0);
        }
    } @catch (__unused NSException *exception) {
    } @finally {
        dyyyClearingFeedNowPlayingSystemInfo = NO;
    }
}

static BOOL DYYYShouldBlockFeedNowPlayingSystemInfoWrite(void) {
    return DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo") && !dyyyClearingFeedNowPlayingSystemInfo;
}



// 采用 HideNowPlayingInfo 的强屏蔽思路：播放中心写入时直接清空系统 Now Playing，不再走原实现。

// 耳机或系统媒体会话可能绕过抖音播放中心，最终都要写入 MPNowPlayingInfoCenter。

static BOOL DYYYShouldDisableAllHDR(void);
static NSArray *DYYYFilteredSDRBitrateModels(NSArray *models);
static NSArray *DYYYFilteredSDRRawBitrateData(NSArray *rawData);
static void DYYYStripHDRHintsFromBitrateModels(NSArray *models);

// 默认视频流最高画质

static NSString *const kDYYYHDRModeKey = @"DYYYHDRMode";
static NSString *const kDYYYHDRModeOff = @"关闭";
static NSString *const kDYYYHDRModeDisable = @"全局屏蔽HDR效果";
static NSString *const kDYYYHDRModeFilter = @"全局过滤HDR作品";
static char kDYYYHDRStrippedAwemeModelKey;
static char kDYYYHDRStrippedVideoModelKey;
static char kDYYYHDROnlyAwemeModelKey;
static char kDYYYHDROnlyVideoModelKey;

static void DYYYMigrateCombinedHDRModeIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:@"DYYYHDRModeMigratedV1"]) {
            return;
        }

        NSString *mode = [defaults stringForKey:kDYYYHDRModeKey];
        BOOL hasValidMode = [mode isEqualToString:kDYYYHDRModeOff] ||
                            [mode isEqualToString:kDYYYHDRModeDisable] ||
                            [mode isEqualToString:kDYYYHDRModeFilter];
        if (!hasValidMode) {
            if ([defaults boolForKey:@"DYYYDisableAllHDR"]) {
                mode = kDYYYHDRModeDisable;
            } else if ([defaults boolForKey:@"DYYYFilterFeedHDR"]) {
                mode = kDYYYHDRModeFilter;
            } else {
                mode = kDYYYHDRModeOff;
            }
        }

        [defaults setObject:mode forKey:kDYYYHDRModeKey];
        [defaults removeObjectForKey:@"DYYYDisableAllHDR"];
        [defaults removeObjectForKey:@"DYYYFilterFeedHDR"];
        [defaults setBool:YES forKey:@"DYYYHDRModeMigratedV1"];
    });
}

static BOOL DYYYShouldDisableAllHDR(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:kDYYYHDRModeKey] isEqualToString:kDYYYHDRModeDisable];
}

static BOOL DYYYShouldFilterGlobalHDR(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:kDYYYHDRModeKey] isEqualToString:kDYYYHDRModeFilter];
}

static id DYYYKVCValueIfPossible(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void DYYYSetKVCValueIfPossible(id object, NSString *key, id value) {
    if (!object || key.length == 0) {
        return;
    }

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static id DYYYIvarValueIfPossible(id object, const char *ivarName) {
    if (!object || !ivarName) {
        return nil;
    }

    Class cls = object_getClass(object);
    while (cls) {
        Ivar ivar = class_getInstanceVariable(cls, ivarName);
        if (ivar) {
            return object_getIvar(object, ivar);
        }
        cls = class_getSuperclass(cls);
    }

    return nil;
}

static id DYYYValuePreferringIvar(id object, const char *ivarName, NSString *key) {
    id ivarValue = DYYYIvarValueIfPossible(object, ivarName);
    if (ivarValue) {
        return ivarValue;
    }
    return DYYYKVCValueIfPossible(object, key);
}

static NSInteger DYYYIntegerValueForKeyIfPossible(id object, NSString *key, NSInteger fallback) {
    id value = DYYYKVCValueIfPossible(object, key);
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

static BOOL DYYYStringValueLooksHDR(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *lowercaseValue = [(NSString *)value lowercaseString];
    return [lowercaseValue containsString:@"hdr"] ||
           [lowercaseValue containsString:@"hlg"] ||
           [lowercaseValue containsString:@"dolby"] ||
           [lowercaseValue containsString:@"vivid"] ||
           [lowercaseValue isEqualToString:@"pq"] ||
           [lowercaseValue containsString:@"_pq"] ||
           [lowercaseValue containsString:@"pq_"];
}

static BOOL DYYYRawBitrateDictionaryLooksHDR(NSDictionary *dictionary);

static BOOL DYYYBitrateModelLooksHDR(id bitrateModel) {
    if (!bitrateModel) {
        return NO;
    }

    if ([bitrateModel isKindOfClass:[NSDictionary class]]) {
        return DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)bitrateModel);
    }

    id hdrTypeValue = DYYYKVCValueIfPossible(bitrateModel, @"hdrType");
    id hdrBitValue = DYYYKVCValueIfPossible(bitrateModel, @"hdrBit");
    NSInteger hdrType = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hdrType", 0);
    NSInteger hdrBit = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hdrBit", 0);
    BOOL hasHdrType = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrType", 0) > 0;
    BOOL hasHdrBit = DYYYIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrBit", 0) > 0;

    return hdrType > 0 ||
           hdrBit >= 10 ||
           hasHdrType ||
           hasHdrBit ||
           DYYYStringValueLooksHDR(hdrTypeValue) ||
           DYYYStringValueLooksHDR(hdrBitValue);
}

static BOOL DYYYStringKeyLooksVideoBitrateList(NSString *key) {
    NSString *lowercaseKey = key.lowercaseString;
    if (lowercaseKey.length == 0 || [lowercaseKey containsString:@"audio"]) {
        return NO;
    }

    return [lowercaseKey containsString:@"bit_rate"] ||
           [lowercaseKey containsString:@"bitrate"] ||
           [lowercaseKey containsString:@"bit_rate_model"] ||
           [lowercaseKey containsString:@"bitratemodel"];
}

static BOOL DYYYRawBitrateDictionaryLooksHDR(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    for (id rawKey in dictionary) {
        id value = dictionary[rawKey];
        NSString *key = [[rawKey description] lowercaseString];
        NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;

        if (([key isEqualToString:@"hdr_type"] ||
             [key isEqualToString:@"hdrtype"] ||
             [key isEqualToString:@"videohdrtype"] ||
             [key isEqualToString:@"video_hdr_type"] ||
             [key isEqualToString:@"source_hdr_type"]) && numericValue > 0) {
            return YES;
        }

        if (([key isEqualToString:@"hdr_bit"] ||
             [key isEqualToString:@"hdrbit"] ||
             [key isEqualToString:@"bit_depth"] ||
             [key isEqualToString:@"bitdepth"]) && numericValue >= 10) {
            return YES;
        }

        if (([key isEqualToString:@"is_source_hdr"] ||
             [key isEqualToString:@"source_hdr"] ||
             [key isEqualToString:@"is_hdr"] ||
             [key isEqualToString:@"ishdr"] ||
             [key isEqualToString:@"has_hdr"] ||
             [key isEqualToString:@"hashdr"] ||
             [key isEqualToString:@"has_filter_hdr"] ||
             [key isEqualToString:@"filter_hdr"] ||
             [key isEqualToString:@"has_hdr_type"] ||
             [key isEqualToString:@"hashdrtype"] ||
             [key isEqualToString:@"has_hdr_bit"] ||
             [key isEqualToString:@"hashdrbit"]) && numericValue > 0) {
            return YES;
        }

        if (DYYYStringValueLooksHDR(value)) {
            return YES;
        }
    }

    return NO;
}

static void DYYYCollectRawBitrateHDRStatus(id object, NSUInteger depth, BOOL *foundHDRBitrate, BOOL *foundSDRBitrate) {
    if (!object || depth > 8 || (foundSDRBitrate && *foundSDRBitrate)) {
        return;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [rawKey description];

            if (DYYYStringKeyLooksVideoBitrateList(key) && [value isKindOfClass:[NSArray class]]) {
                for (id entry in (NSArray *)value) {
                    if (![entry isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }

                    if (DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
                        if (foundHDRBitrate) {
                            *foundHDRBitrate = YES;
                        }
                    } else if (foundSDRBitrate) {
                        *foundSDRBitrate = YES;
                        return;
                    }
                }
                continue;
            }

            if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                DYYYCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            DYYYCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
        }
    }
}

static BOOL DYYYRawObjectHasOnlyHDRBitrateModels(id object) {
    BOOL foundHDRBitrate = NO;
    BOOL foundSDRBitrate = NO;
    DYYYCollectRawBitrateHDRStatus(object, 0, &foundHDRBitrate, &foundSDRBitrate);
    return foundHDRBitrate && !foundSDRBitrate;
}

static BOOL DYYYVideoModelHasOnlyHDRBitrateModels(id video) {
    if (!video) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(video, &kDYYYHDROnlyVideoModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    NSMutableArray *models = [NSMutableArray array];
    NSArray *bitrateModels = DYYYValuePreferringIvar(video, "_bitrateModels", @"bitrateModels");
    if ([bitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateModels];
    }

    NSArray *manualBitrateModels = DYYYValuePreferringIvar(video, "_manualBitrateModels", @"manualBitrateModels");
    if ([manualBitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:manualBitrateModels];
    }

    NSArray *bitrateRawData = DYYYValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    if ([bitrateRawData isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateRawData];
    }

    if (models.count == 0) {
        return NO;
    }

    BOOL onlyHDR = YES;
    for (id model in models) {
        if (!DYYYBitrateModelLooksHDR(model)) {
            onlyHDR = NO;
            break;
        }
    }

    objc_setAssociatedObject(video, &kDYYYHDROnlyVideoModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return onlyHDR;
}

static BOOL DYYYAwemeModelHasOnlyHDRBitrateModels(id aweme) {
    if (!aweme) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(aweme, &kDYYYHDROnlyAwemeModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    BOOL onlyHDR = NO;
    BOOL shouldCacheResult = NO;
    id video = DYYYValuePreferringIvar(aweme, "_video", @"video");
    if (video) {
        shouldCacheResult = YES;
    }
    if (DYYYVideoModelHasOnlyHDRBitrateModels(video)) {
        onlyHDR = YES;
    } else {
        NSArray *albumImages = DYYYValuePreferringIvar(aweme, "_albumImages", @"albumImages");
        if ([albumImages isKindOfClass:[NSArray class]]) {
            shouldCacheResult = shouldCacheResult || albumImages.count > 0;
            for (id imageModel in albumImages) {
                id clipVideo = DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo");
                if (DYYYVideoModelHasOnlyHDRBitrateModels(clipVideo)) {
                    onlyHDR = YES;
                    break;
                }
            }
        }
    }

    if (shouldCacheResult || onlyHDR) {
        objc_setAssociatedObject(aweme, &kDYYYHDROnlyAwemeModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return onlyHDR;
}

static NSArray *DYYYFilteredSDRRawBitrateData(NSArray *rawData) {
    if (![rawData isKindOfClass:[NSArray class]] || rawData.count == 0) {
        return rawData;
    }

    NSMutableArray *sdrData = [NSMutableArray arrayWithCapacity:rawData.count];
    NSUInteger hdrCount = 0;
    for (id entry in rawData) {
        if ([entry isKindOfClass:[NSDictionary class]] && DYYYRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
            hdrCount++;
            continue;
        }
        [sdrData addObject:entry];
    }

    if (hdrCount == 0 || sdrData.count == 0) {
        return rawData;
    }

    return [sdrData copy];
}

static NSArray *DYYYFilteredSDRBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]] || models.count == 0) {
        return models;
    }

    NSMutableArray *sdrModels = [NSMutableArray arrayWithCapacity:models.count];
    NSUInteger hdrCount = 0;
    for (id model in models) {
        if (DYYYBitrateModelLooksHDR(model)) {
            hdrCount++;
            continue;
        }
        [sdrModels addObject:model];
    }

    // 只有 HDR 档的作品在模型层过滤；这里不清空列表，避免播放器拿不到可播档导致有声黑屏。
    if (hdrCount == 0 || sdrModels.count == 0) {
        return models;
    }

    return [sdrModels copy];
}

static void DYYYStripHDRHintsFromBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id model in models) {
        DYYYSetKVCValueIfPossible(model, @"hdrType", @0);
        DYYYSetKVCValueIfPossible(model, @"hdrBit", @8);
        DYYYSetKVCValueIfPossible(model, @"hasHdrType", @NO);
        DYYYSetKVCValueIfPossible(model, @"hasHdrBit", @NO);
    }
}

static void DYYYStripHDRHintsFromVideoModel(id video) {
    if (!DYYYShouldDisableAllHDR() || !video) {
        return;
    }

    if (objc_getAssociatedObject(video, &kDYYYHDRStrippedVideoModelKey)) {
        return;
    }
    objc_setAssociatedObject(video, &kDYYYHDRStrippedVideoModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([video respondsToSelector:@selector(setIsSourceHDR:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(video, @selector(setIsSourceHDR:), 0);
    }
    if ([video respondsToSelector:@selector(setHasFilterHDR:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(video, @selector(setHasFilterHDR:), NO);
    }

    NSArray *bitrateModels = DYYYKVCValueIfPossible(video, @"bitrateModels");
    NSArray *filteredBitrateModels = DYYYFilteredSDRBitrateModels(bitrateModels);
    if (filteredBitrateModels && filteredBitrateModels != bitrateModels) {
        DYYYSetKVCValueIfPossible(video, @"bitrateModels", filteredBitrateModels);
        bitrateModels = filteredBitrateModels;
    }
    DYYYStripHDRHintsFromBitrateModels(bitrateModels);

    NSArray *manualBitrateModels = DYYYKVCValueIfPossible(video, @"manualBitrateModels");
    NSArray *filteredManualBitrateModels = DYYYFilteredSDRBitrateModels(manualBitrateModels);
    if (filteredManualBitrateModels && filteredManualBitrateModels != manualBitrateModels) {
        DYYYSetKVCValueIfPossible(video, @"manualBitrateModels", filteredManualBitrateModels);
        manualBitrateModels = filteredManualBitrateModels;
    }
    DYYYStripHDRHintsFromBitrateModels(manualBitrateModels);

    NSArray *bitrateRawData = DYYYValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    NSArray *filteredBitrateRawData = DYYYFilteredSDRRawBitrateData(bitrateRawData);
    if (filteredBitrateRawData && filteredBitrateRawData != bitrateRawData) {
        DYYYSetKVCValueIfPossible(video, @"bitrateRawData", filteredBitrateRawData);
    }
}

static void DYYYStripHDRHintsFromAwemeModel(id aweme) {
    if (!DYYYShouldDisableAllHDR() || !aweme) {
        return;
    }

    if (objc_getAssociatedObject(aweme, &kDYYYHDRStrippedAwemeModelKey)) {
        return;
    }
    objc_setAssociatedObject(aweme, &kDYYYHDRStrippedAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id video = DYYYValuePreferringIvar(aweme, "_video", @"video");
    DYYYStripHDRHintsFromVideoModel(video);

    NSArray *albumImages = DYYYValuePreferringIvar(aweme, "_albumImages", @"albumImages");
    if ([albumImages isKindOfClass:[NSArray class]]) {
        for (id imageModel in albumImages) {
            DYYYStripHDRHintsFromVideoModel(DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
}

static id DYYYStandardCADynamicRange(void) {
    static id standardDynamicRange = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "CADynamicRangeStandard");
        if (symbol) {
            id __unsafe_unretained *value = (id __unsafe_unretained *)symbol;
            standardDynamicRange = *value;
        }
    });
    return standardDynamicRange;
}

static id DYYYToneMapModeIfSupported(void) {
    static id toneMapMode = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "CAToneMapModeIfSupported");
        if (symbol) {
            id __unsafe_unretained *value = (id __unsafe_unretained *)symbol;
            toneMapMode = *value;
        }
    });
    return toneMapMode;
}

static void DYYYApplySDRDynamicRangeToImageView(UIImageView *imageView) {
    if (!DYYYShouldDisableAllHDR() || !imageView) {
        return;
    }

    if (@available(iOS 17.0, *)) {
        imageView.preferredImageDynamicRange = UIImageDynamicRangeStandard;
    }
}

// 头像加号可能由异步动画重建图层，需要在 CALayer 写入点继续压制。
static BOOL DYYYShouldForceHideAvatarActionLayer(CALayer *layer);
static BOOL DYYYShouldClearAvatarActionLayer(CALayer *layer);
static void DYYYPrepareAvatarActionSublayer(CALayer *parentLayer, CALayer *sublayer);

static void DYYYDisableExtendedRangeForLayer(CALayer *layer) {
    if (!DYYYShouldDisableAllHDR() || !layer) {
        return;
    }

    SEL setWantsEDRSelector = @selector(setWantsExtendedDynamicRangeContent:);
    if ([layer respondsToSelector:setWantsEDRSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, setWantsEDRSelector, NO);
    }

    id toneMapMode = DYYYToneMapModeIfSupported();
    SEL setToneMapModeSelector = @selector(setToneMapMode:);
    if (toneMapMode && [layer respondsToSelector:setToneMapModeSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(layer, setToneMapModeSelector, toneMapMode);
    }

    id standardDynamicRange = DYYYStandardCADynamicRange();
    SEL setPreferredDynamicRangeSelector = @selector(setPreferredDynamicRange:);
    if (standardDynamicRange && [layer respondsToSelector:setPreferredDynamicRangeSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(layer, setPreferredDynamicRangeSelector, standardDynamicRange);
    }

    if (@available(iOS 16.0, *)) {
        if ([layer isKindOfClass:[CAMetalLayer class]]) {
            ((CAMetalLayer *)layer).EDRMetadata = nil;
        }
    }
}

static void DYYYDisableExtendedRangeForMetalLayer(CAMetalLayer *metalLayer) {
    if (!DYYYShouldDisableAllHDR() || !metalLayer) {
        return;
    }

    DYYYDisableExtendedRangeForLayer(metalLayer);
}

static void DYYYDisableAVPlayerItemHDRMetadata(AVPlayerItem *item) {
    if (!DYYYShouldDisableAllHDR() || !item) {
        return;
    }

    if (@available(iOS 14.0, *)) {
        item.appliesPerFrameHDRDisplayMetadata = NO;
    }
}

// 保留 HDR 解码及原生 HDR -> SDR 转换，只关闭亮度增强、SDR -> HDR 和最终 EDR 输出。













































// 直播间真实人数

// 评论具体时间



// 前面的AWEDateTimeFormatter会导致图文视频展开时间文本变成时间戳，这里处理下

// 禁用自动进入直播间








// 设置修改顶栏标题














// 对新版文案的偏移（33.0以上）




// 获取资源的地址

// 屏蔽版本更新

// 应用内推送毛玻璃效果

// 为 AWEUserActionSheetView 添加毛玻璃效果


// 启用自动勾选原图

// 屏蔽直播PCDN

// PCDN启动任务hook

// 投屏忽略 VPN 检测





// 调整直播默认清晰度功能
static NSArray<NSString *> *dyyy_qualityRank = nil;


// 强制启用新版抖音长按 UI（现代风）



// 禁用个人资料自动进入橱窗




// 强制启用保存他人头像





static NSString *DYYYIMMessageStringValue(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (!selector || ![object respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [object performSelector:selector];
#pragma clang diagnostic pop
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return value;
    }
    return nil;
}

static NSURL *DYYYIMEmotionDownloadURLFromMessage(AWEIMGiphyMessage *giphyMessage) {
    if (!giphyMessage) {
        return nil;
    }
    NSString *urlString = nil;
    if (giphyMessage.giphyURL.originURLList.count > 0) {
        urlString = giphyMessage.giphyURL.originURLList.firstObject;
    }
    if (urlString.length == 0) {
        NSString *animateURL = DYYYIMMessageStringValue(giphyMessage, @"animateURL");
        if (animateURL.length > 0) {
            urlString = animateURL;
        }
    }
    if (urlString.length == 0) {
        NSString *displayIconURL = DYYYIMMessageStringValue(giphyMessage, @"displayIconURL");
        if (displayIconURL.length > 0) {
            urlString = displayIconURL;
        }
    }
    if (urlString.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:urlString];
}

static AWEIMCustomMenuModel *DYYYIMCreateDownloadMenuItem(AWEIMReusableCommonCell *cell) {
    if (!cell) {
        return nil;
    }
    __weak AWEIMReusableCommonCell *weakCell = cell;
    AWEIMCustomMenuModel *menuItem = [%c(AWEIMCustomMenuModel) new];
    menuItem.title = @"保存表情";
    menuItem.imageName = @"im_emoticon_interactive_tab_new";
    menuItem.trackerName = @"保存表情";
    menuItem.willPerformMenuActionSelectorBlock = ^(id arg1) {
      AWEIMReusableCommonCell *strongCell = weakCell;
      if (!strongCell) {
          [DYYYUtils showToast:@"无法获取表情包信息"];
          return;
      }
      AWEIMMessageComponentContext *context = (AWEIMMessageComponentContext *)strongCell.currentContext;
      if (!context || ![context.message isKindOfClass:%c(AWEIMGiphyMessage)]) {
          [DYYYUtils showToast:@"无法获取表情包信息"];
          return;
      }
      NSURL *downloadURL = DYYYIMEmotionDownloadURLFromMessage((AWEIMGiphyMessage *)context.message);
      if (!downloadURL) {
          [DYYYUtils showToast:@"无法获取表情包链接"];
          return;
      }
      [DYYYManager downloadMedia:downloadURL
                       mediaType:MediaTypeHeic
                           audio:nil
                      completion:^(BOOL success){
                      }];
    };
    return menuItem;
}

static NSArray *DYYYIMMenuItemsByAddingDownloadAction(NSArray *menuItems, id cell) {
    if (!DYYYGetBool(@"DYYYForceDownloadIMEmotion")) {
        return menuItems;
    }
    if (!menuItems || !cell) {
        return menuItems;
    }
    AWEIMReusableCommonCell *commonCell = [cell isKindOfClass:%c(AWEIMReusableCommonCell)] ? (AWEIMReusableCommonCell *)cell : nil;
    if (!commonCell) {
        return menuItems;
    }
    AWEIMMessageComponentContext *context = (AWEIMMessageComponentContext *)commonCell.currentContext;
    if (!context || ![context.message isKindOfClass:%c(AWEIMGiphyMessage)]) {
        return menuItems;
    }
    for (AWEIMCustomMenuModel *item in menuItems) {
        if ([item isKindOfClass:%c(AWEIMCustomMenuModel)] && [item.title isEqualToString:@"保存表情"]) {
            return menuItems;
        }
    }
    NSMutableArray *newMenuItems = [menuItems mutableCopy];
    AWEIMCustomMenuModel *downloadItem = DYYYIMCreateDownloadMenuItem(commonCell);
    if (downloadItem) {
        [newMenuItems addObject:downloadItem];
    }
    return newMenuItems ?: menuItems;
}






static id DYYYAvatarObjectForSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

static UIView *DYYYAvatarViewForSelector(id object, SEL selector) {
    id value = DYYYAvatarObjectForSelector(object, selector);
    return [value isKindOfClass:[UIView class]] ? value : nil;
}

static char kDYYYAvatarFollowDeferredApplyKey;
static char kDYYYAvatarFollowScopeViewKey;
static char kDYYYAvatarActionHiddenViewKey;
static char kDYYYAvatarActionRemovedViewKey;
static char kDYYYAvatarActionChromeViewKey;
static char kDYYYAvatarActionHiddenLayerKey;
static char kDYYYAvatarActionChromeLayerKey;
static char kDYYYAvatarSurroundingHiddenViewKey;

static BOOL DYYYAvatarFollowOptionsEnabled(void) {
    return DYYYGetBool(@"DYYYHideLOTAnimationView") || DYYYGetBool(@"DYYYHideFollowPromptView");
}

static BOOL DYYYShouldForceHideAvatarActionLayer(CALayer *layer) {
    return layer && objc_getAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey) && DYYYAvatarFollowOptionsEnabled();
}

static BOOL DYYYShouldClearAvatarActionLayer(CALayer *layer) {
    if (!layer || (!objc_getAssociatedObject(layer, &kDYYYAvatarActionChromeLayerKey) &&
                   !objc_getAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey))) {
        return NO;
    }
    return DYYYAvatarFollowOptionsEnabled();
}

static void DYYYMarkAvatarActionLayerHidden(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDYYYAvatarActionHiddenLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.hidden = YES;
    for (CALayer *sublayer in [layer.sublayers copy]) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYMarkAvatarActionLayerChrome(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDYYYAvatarActionChromeLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.contents = nil;
    layer.opaque = NO;
    layer.backgroundColor = UIColor.clearColor.CGColor;
    layer.borderWidth = 0.0;
    layer.borderColor = UIColor.clearColor.CGColor;
    layer.shadowOpacity = 0.0;
    layer.shadowColor = UIColor.clearColor.CGColor;
    if ([layer isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *shapeLayer = (CAShapeLayer *)layer;
        shapeLayer.fillColor = UIColor.clearColor.CGColor;
        shapeLayer.strokeColor = UIColor.clearColor.CGColor;
    }

    for (CALayer *sublayer in [layer.sublayers copy]) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYPrepareAvatarActionSublayer(CALayer *parentLayer, CALayer *sublayer) {
    if (!parentLayer || !sublayer) {
        return;
    }

    BOOL isSuppressedTree = objc_getAssociatedObject(parentLayer, &kDYYYAvatarActionChromeLayerKey) ||
                            objc_getAssociatedObject(parentLayer, &kDYYYAvatarActionHiddenLayerKey);
    if (isSuppressedTree && DYYYAvatarFollowOptionsEnabled()) {
        DYYYMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DYYYMarkAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
}

static BOOL DYYYShouldForceAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return NO;
    }

    BOOL hideVisual = objc_getAssociatedObject(view, &kDYYYAvatarActionHiddenViewKey) != nil;
    BOOL removeView = objc_getAssociatedObject(view, &kDYYYAvatarActionRemovedViewKey) != nil;
    if (!hideVisual && !removeView) {
        return NO;
    }
    return (hideVisual && DYYYAvatarFollowOptionsEnabled()) || (removeView && DYYYGetBool(@"DYYYHideFollowPromptView"));
}

static BOOL DYYYShouldClearAvatarActionViewChrome(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDYYYAvatarActionChromeViewKey) && DYYYGetBool(@"DYYYHideLOTAnimationView");
}

static void DYYYHideAvatarVisualForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    if (view) {
        view.hidden = YES;
    }
}

static void DYYYMarkAvatarSurroundingViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarSurroundingHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

static BOOL DYYYShouldForceAvatarSurroundingViewHidden(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDYYYAvatarSurroundingHiddenViewKey) && DYYYGetBool(@"DYYYHideAvatarButton");
}

static void DYYYHideAvatarSurroundingVisualForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    DYYYMarkAvatarSurroundingViewHidden(view);
}

static void DYYYApplyAvatarSurroundingSettingsForOwner(id owner) {
    if (!owner || !DYYYGetBool(@"DYYYHideAvatarButton")) {
        return;
    }

    for (NSString *selectorName in @[
             @"colorRingView",
             @"storyRingView",
             @"story25RingView",
             @"decorationView",
             @"avatarDecorationView",
             @"avatarPendantView",
             @"avatarLiveMarkView",
             @"liveMarkView",
             @"avatarLiveTagView",
             @"liveTagView",
         ]) {
        DYYYHideAvatarSurroundingVisualForSelector(owner, NSSelectorFromString(selectorName));
    }
}

static void DYYYRemoveAvatarView(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDYYYAvatarActionRemovedViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

static void DYYYRemoveAvatarViewForSelector(id object, SEL selector) {
    UIView *view = DYYYAvatarViewForSelector(object, selector);
    DYYYRemoveAvatarView(view);
}

static void DYYYHideAvatarFollowLayerContents(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYMarkAvatarActionLayerChrome(view.layer);
}

static void DYYYClearAvatarActionLayerChrome(CALayer *layer) {
    DYYYMarkAvatarActionLayerChrome(layer);
}

static void DYYYClearAvatarActionSubviewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DYYYClearAvatarActionSubviewChrome(subview);
    }
}

static void DYYYClearAvatarActionViewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDYYYAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DYYYClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DYYYClearAvatarActionSubviewChrome(subview);
    }
}

static BOOL DYYYIsLegacyAvatarFollowAnimationView(UIView *view) {
    Class promptClass = NSClassFromString(@"AWEPlayInteractionFollowPromptView");
    UIView *ancestor = view.superview;
    for (NSInteger depth = 0; ancestor && depth < 6; depth++, ancestor = ancestor.superview) {
        if (promptClass && [ancestor isKindOfClass:promptClass]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYHideAvatarFollowIconInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"LOTAnimationView"]) {
        DYYYHideAvatarFollowLayerContents(view);
        return YES;
    }

    if ([className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"]) {
        BOOL foundIcon = NO;
        for (NSString *selectorName in @[ @"plusImageView", @"tickImageView" ]) {
            UIView *iconView = DYYYAvatarViewForSelector(view, NSSelectorFromString(selectorName));
            if (iconView) {
                DYYYMarkAvatarActionViewHidden(iconView);
                foundIcon = YES;
            }
        }
        if (!foundIcon) {
            DYYYHideAvatarFollowLayerContents(view);
        }
        return YES;
    }

    BOOL foundIcon = NO;
    for (UIView *subview in view.subviews) {
        foundIcon = DYYYHideAvatarFollowIconInView(subview) || foundIcon;
    }
    return foundIcon;
}

static BOOL DYYYIsAvatarFollowContainerView(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"Follow"] || [className containsString:@"follow"] ||
           [className containsString:@"Prompt"] || [className containsString:@"Add"] ||
           [className containsString:@"SendMessage"] || [className containsString:@"sendMessage"] ||
           [className containsString:@"SendMsg"] || [className containsString:@"sendMsg"] ||
           [className containsString:@"EnterStore"] || [className containsString:@"enterStore"] ||
           [className containsString:@"LinkIcon"] || [className containsString:@"linkIcon"];
}

static BOOL DYYYIsSmallAvatarFollowBadgeView(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    return width > 0.0 && height > 0.0 && width <= 52.0 && height <= 52.0;
}

static UIView *DYYYAvatarFollowRemovalTargetForView(UIView *view, UIView *rootView) {
    UIView *target = view;
    UIView *ancestor = view.superview;
    while (ancestor && ancestor != rootView) {
        if (DYYYIsAvatarFollowContainerView(ancestor) || DYYYIsSmallAvatarFollowBadgeView(ancestor)) {
            target = ancestor;
            ancestor = ancestor.superview;
            continue;
        }
        break;
    }
    return target;
}

static BOOL DYYYHideAvatarAuxiliaryActionVisualsInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    BOOL isActionVisual = [view isKindOfClass:[UIImageView class]] ||
                          [className containsString:@"GuideAnimation"] ||
                          [className containsString:@"SendMessageImage"] ||
                          [className containsString:@"SendMsgImage"] ||
                          [className containsString:@"EnterStoreImage"] ||
                          [className containsString:@"LinkIcon"];
    if (isActionVisual) {
        DYYYMarkAvatarActionViewHidden(view);
        return YES;
    }

    BOOL foundVisual = NO;
    for (UIView *subview in [view.subviews copy]) {
        foundVisual = DYYYHideAvatarAuxiliaryActionVisualsInView(subview) || foundVisual;
    }
    return foundVisual;
}

static NSArray<NSArray<NSString *> *> *DYYYAvatarAuxiliaryActionSelectorGroups(void) {
    return @[
        @[ @"sendMessageView", @"avatarSendMessageImageView", @"sendMessageGuideView" ],
        @[ @"enterStoreView", @"avatarEnterStoreImageView", @"enterStoreGuideView" ],
        @[ @"linkIconContainerView", @"userAvatarLinkIcon" ],
    ];
}

static BOOL DYYYApplyAvatarAuxiliaryActionSettingsForOwner(id owner) {
    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    BOOL handled = NO;
    for (NSArray<NSString *> *selectorGroup in DYYYAvatarAuxiliaryActionSelectorGroups()) {
        UIView *containerView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup.firstObject));
        NSMutableArray<UIView *> *visualViews = [NSMutableArray array];
        for (NSUInteger index = 1; index < selectorGroup.count; index++) {
            UIView *visualView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup[index]));
            if (visualView) {
                [visualViews addObject:visualView];
            }
        }

        if (removePlus) {
            UIView *fallbackVisual = visualViews.firstObject;
            UIView *removalTarget = containerView ?: DYYYAvatarFollowRemovalTargetForView(fallbackVisual, nil);
            DYYYRemoveAvatarView(removalTarget);
            for (UIView *visualView in visualViews) {
                DYYYRemoveAvatarView(visualView);
            }
            handled = (removalTarget || visualViews.count > 0) || handled;
            continue;
        }

        for (UIView *visualView in visualViews) {
            visualView.hidden = YES;
            handled = YES;
        }
        if (containerView) {
            DYYYClearAvatarActionViewChrome(containerView);
            BOOL foundVisual = DYYYHideAvatarAuxiliaryActionVisualsInView(containerView);
            if (!foundVisual && visualViews.count == 0) {
                DYYYHideAvatarFollowLayerContents(containerView);
            }
            handled = YES;
        }
    }
    return handled;
}

static BOOL DYYYApplyAvatarFollowSettingsInView(UIView *view, UIView *rootView) {
    if (!view) {
        return NO;
    }

    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    // 记录已识别的头像操作树，便于异步追加子视图时立即再识别。
    objc_setAssociatedObject(view, &kDYYYAvatarFollowScopeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *className = NSStringFromClass(view.class);
    BOOL isAvatarView = [className isEqualToString:@"AWEPlayInteractionUserAvatarView"];
    BOOL isStaticFollowView = [className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"];
    BOOL isLegacyFollowAnimation = [className isEqualToString:@"LOTAnimationView"] && DYYYIsLegacyAvatarFollowAnimationView(view);
    BOOL isLegacyPromptContainer = [className isEqualToString:@"AWEPlayInteractionFollowPromptView"];
    BOOL handled = NO;

    if (isAvatarView) {
        handled = DYYYApplyAvatarAuxiliaryActionSettingsForOwner(view) || handled;
    }

    if (isStaticFollowView || isLegacyFollowAnimation) {
        if (removePlus) {
            DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(view, rootView));
        } else {
            DYYYHideAvatarFollowIconInView(view);
        }
        handled = YES;
    } else if (removePlus && isLegacyPromptContainer) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
        handled = YES;
    }

    for (UIView *subview in [view.subviews copy]) {
        handled = DYYYApplyAvatarFollowSettingsInView(subview, rootView) || handled;
    }
    return handled;
}

static void DYYYApplyAvatarFollowSettingsForContext(id context) {
    UIView *elementView = DYYYAvatarViewForSelector(context, NSSelectorFromString(@"elementView"));
    if (elementView) {
        DYYYApplyAvatarFollowSettingsInView(elementView, elementView);
    }
}

static void DYYYApplyAvatarFollowPromptSettings(id owner) {
    BOOL hidePlus = DYYYGetBool(@"DYYYHideLOTAnimationView");
    BOOL removePlus = DYYYGetBool(@"DYYYHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return;
    }

    for (NSString *selectorName in @[ @"followAnimationView", @"unfollowAnimationView", @"staticFollowAnimationView" ]) {
        UIView *animationView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(selectorName));
        if (!animationView) {
            continue;
        }
        if (removePlus) {
            DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(animationView, nil));
        } else {
            DYYYHideAvatarFollowIconInView(animationView);
        }
    }

    UIView *followAddView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"followAddView"));
    if (removePlus) {
        DYYYRemoveAvatarView(followAddView);
    } else {
        BOOL foundIcon = DYYYHideAvatarFollowIconInView(followAddView);
        if (hidePlus && followAddView) {
            DYYYClearAvatarActionViewChrome(followAddView);
            if (!foundIcon) {
                DYYYHideAvatarFollowLayerContents(followAddView);
            }
        }
    }

    UIView *followPromptView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"followPromptView"));
    if (removePlus) {
        DYYYRemoveAvatarView(followPromptView);
    } else {
        DYYYApplyAvatarFollowSettingsInView(followPromptView, followPromptView);
    }

    DYYYApplyAvatarAuxiliaryActionSettingsForOwner(owner);

    if ([owner isKindOfClass:[UIView class]]) {
        DYYYApplyAvatarFollowSettingsInView((UIView *)owner, (UIView *)owner);
    } else if ([owner isKindOfClass:[UIViewController class]]) {
        DYYYApplyAvatarFollowSettingsInView(((UIViewController *)owner).view, ((UIViewController *)owner).view);
    }
    UIView *userAvatarView = DYYYAvatarViewForSelector(owner, NSSelectorFromString(@"userAvatarView"));
    if (userAvatarView) {
        DYYYApplyAvatarFollowSettingsInView(userAvatarView, userAvatarView);
    }
    DYYYApplyAvatarFollowSettingsForContext(DYYYAvatarObjectForSelector(owner, NSSelectorFromString(@"userAvatarContext")));
}

static void DYYYApplyAvatarFollowPromptSettingsWithRetry(id owner) {
    DYYYApplyAvatarFollowPromptSettings(owner);
    if (!owner || !DYYYAvatarFollowOptionsEnabled() || objc_getAssociatedObject(owner, &kDYYYAvatarFollowDeferredApplyKey)) {
        return;
    }

    objc_setAssociatedObject(owner, &kDYYYAvatarFollowDeferredApplyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id target = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYYYApplyAvatarFollowPromptSettings(target);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYYYApplyAvatarFollowPromptSettings(target);
            objc_setAssociatedObject(target, &kDYYYAvatarFollowDeferredApplyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}

// 隐藏头像加号和透明


// 首页头像隐藏和透明

// 移除同城吃喝玩乐提示框


// 隐藏右下音乐和取消静音按钮

// 隐藏弹幕按钮

// 隐藏评论区免费去看短剧

// 隐藏评论区定位

// 隐藏评论音乐

// Swift 类组

// 去除隐藏大家都在搜后的留白

// 隐藏观看历史搜索

// 隐藏校园提示



// 隐藏消息页顶栏头像气泡

// 隐藏消息页开启通知提示

// 隐藏消息页顶栏红包

// 隐藏我的添加朋友

// 隐藏朋友"关注/不关注"按钮

// 隐藏朋友日常按钮

// 隐藏分享给朋友提示















// 隐藏双指缩放虾线

// 隐藏状态栏

static const void *kDYYYLiveDurationViewKey = &kDYYYLiveDurationViewKey;
static const void *kDYYYLiveDurationTimerKey = &kDYYYLiveDurationTimerKey;
static const void *kDYYYLiveDurationRoomKey = &kDYYYLiveDurationRoomKey;
static NSString *const kDYYYLiveDurationCenterXPercentKey = @"DYYYLiveDurationCenterXPercent";
static NSString *const kDYYYLiveDurationCenterYPercentKey = @"DYYYLiveDurationCenterYPercent";
static NSString *const kDYYYLiveDurationPositionLockedKey = @"DYYYLiveDurationPositionLocked";

static UIEdgeInsets DYYYLiveDurationSafeInsets(UIView *root) {
    return [root respondsToSelector:@selector(safeAreaInsets)] ? root.safeAreaInsets : UIEdgeInsetsZero;
}

static CGPoint DYYYLiveDurationClampedCenter(CGPoint center, CGSize viewSize, UIView *root) {
    if (!root) {
        return center;
    }

    UIEdgeInsets safeInsets = DYYYLiveDurationSafeInsets(root);
    CGFloat halfWidth = viewSize.width / 2.0;
    CGFloat halfHeight = viewSize.height / 2.0;
    CGFloat minX = safeInsets.left + halfWidth + 4.0;
    CGFloat maxX = fmax(minX, CGRectGetWidth(root.bounds) - safeInsets.right - halfWidth - 4.0);
    CGFloat minY = safeInsets.top + halfHeight + 4.0;
    CGFloat maxY = fmax(minY, CGRectGetHeight(root.bounds) - safeInsets.bottom - halfHeight - 4.0);
    return CGPointMake(fmin(fmax(center.x, minX), maxX), fmin(fmax(center.y, minY), maxY));
}

@interface DYYYLiveDurationWeakViewBox : NSObject
@property(nonatomic, weak) UIView *view;
@end

@implementation DYYYLiveDurationWeakViewBox
@end

@interface DYYYLiveDurationView : UIView
@property(nonatomic, strong) UILabel *durationLabel;
@property(nonatomic, assign, getter=isDragging) BOOL dragging;
@property(nonatomic, assign, getter=isMovementLocked) BOOL movementLocked;
- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root;
@end

@implementation DYYYLiveDurationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.42];
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
        self.layer.borderWidth = 0.5;
        self.accessibilityIdentifier = @"dyyy_live_duration_view";

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        _durationLabel.adjustsFontSizeToFitWidth = YES;
        _durationLabel.minimumScaleFactor = 0.75;
        _durationLabel.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        _durationLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_durationLabel];

        _movementLocked = [[NSUserDefaults standardUserDefaults] boolForKey:kDYYYLiveDurationPositionLockedKey];

        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [panGesture requireGestureRecognizerToFail:longPressGesture];
        [self addGestureRecognizer:panGesture];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.durationLabel.frame = CGRectInset(self.bounds, 7.0, 2.0);
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *root = self.superview;
    if (self.isMovementLocked || !root) {
        return;
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.alpha = 0.8;
    }

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:root];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        self.center = DYYYLiveDurationClampedCenter(newCenter, self.bounds.size, root);
        [gesture setTranslation:CGPointZero inView:root];
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.alpha = 1.0;
        [self savePosition];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    self.movementLocked = !self.isMovementLocked;
    [DYYYPreferences setBool:self.isMovementLocked forKey:kDYYYLiveDurationPositionLockedKey];
    if (self.isMovementLocked) {
        [self savePosition];
    }

    [DYYYUtils showToast:self.isMovementLocked ? @"开播时长位置已锁定" : @"开播时长位置已解锁"];
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }
}

- (void)savePosition {
    UIView *root = self.superview;
    if (!root) {
        return;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:self.center.x / rootWidth forKey:kDYYYLiveDurationCenterXPercentKey];
    [defaults setDouble:self.center.y / rootHeight forKey:kDYYYLiveDurationCenterYPercentKey];
}

- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kDYYYLiveDurationCenterXPercentKey] || ![defaults objectForKey:kDYYYLiveDurationCenterYPercentKey]) {
        return frame;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return frame;
    }

    CGFloat centerXPercent = fmin(fmax([defaults doubleForKey:kDYYYLiveDurationCenterXPercentKey], 0.0), 1.0);
    CGFloat centerYPercent = fmin(fmax([defaults doubleForKey:kDYYYLiveDurationCenterYPercentKey], 0.0), 1.0);
    CGPoint center = CGPointMake(centerXPercent * rootWidth, centerYPercent * rootHeight);
    center = DYYYLiveDurationClampedCenter(center, frame.size, root);
    return CGRectIntegral(CGRectMake(center.x - frame.size.width / 2.0, center.y - frame.size.height / 2.0, frame.size.width, frame.size.height));
}

@end

static id DYYYLiveDurationSafeValue(id obj, NSString *key) {
    if (!obj || key.length == 0) {
        return nil;
    }

    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static long long DYYYLiveDurationLongValue(id obj, NSString *key) {
    id value = DYYYLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

static BOOL DYYYLiveDurationBoolValue(id obj, NSString *key) {
    id value = DYYYLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSTimeInterval DYYYLiveDurationNowSeconds(void) {
    return [[NSDate date] timeIntervalSince1970];
}

static NSTimeInterval DYYYLiveDurationNormalizeTimestamp(long long timestamp) {
    if (timestamp <= 0) {
        return 0.0;
    }
    return timestamp > 20000000000LL ? ((NSTimeInterval)timestamp / 1000.0) : (NSTimeInterval)timestamp;
}

static long long DYYYLiveDurationFirstPositiveValue(id obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        long long value = DYYYLiveDurationLongValue(obj, key);
        if (value > 0) {
            return value;
        }
    }
    return 0;
}

static BOOL DYYYLiveDurationLooksLikeRoomObject(id obj) {
    if (!obj) {
        return NO;
    }

    NSString *className = NSStringFromClass([obj class]);
    NSArray<NSString *> *excludedParts = @[ @"Cell", @"Item", @"Aisle", @"Context", @"Config", @"Controller", @"View", @"Factory" ];
    for (NSString *part in excludedParts) {
        if ([className rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return NO;
        }
    }

    if ([className rangeOfString:@"LiveRoom" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"RoomModel" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"WebcastRoom" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return DYYYLiveDurationSafeValue(obj, @"roomID") || DYYYLiveDurationSafeValue(obj, @"idStr");
}

static NSTimeInterval DYYYLiveDurationElapsedSeconds(id roomModel) {
    if (!DYYYLiveDurationLooksLikeRoomObject(roomModel)) {
        return -1.0;
    }

    id rawRoom = DYYYLiveDurationSafeValue(roomModel, @"rawRoom") ?: roomModel;
    NSArray<NSString *> *startKeys = @[ @"startTime", @"createTime", @"liveStartTime", @"start_time", @"create_time" ];
    long long startTime = DYYYLiveDurationFirstPositiveValue(rawRoom, startKeys);
    if (startTime <= 0) {
        startTime = DYYYLiveDurationFirstPositiveValue(roomModel, startKeys);
    }

    NSTimeInterval timestamp = DYYYLiveDurationNormalizeTimestamp(startTime);
    NSTimeInterval now = DYYYLiveDurationNowSeconds();
    if (timestamp > 1000000000.0 && timestamp <= now + 3600.0) {
        return fmax(0.0, now - timestamp);
    }

    NSArray<NSString *> *durationKeys = @[ @"liveDuration", @"liveTime", @"duration", @"totalDuration" ];
    long long duration = DYYYLiveDurationFirstPositiveValue(rawRoom, durationKeys);
    if (duration <= 0) {
        duration = DYYYLiveDurationFirstPositiveValue(roomModel, durationKeys);
    }
    if (duration > 0 && duration < 365LL * 24LL * 3600LL) {
        return (NSTimeInterval)duration;
    }

    return -1.0;
}

static BOOL DYYYLiveDurationHasValidLiveTime(id obj) {
    return DYYYLiveDurationElapsedSeconds(obj) >= 0.0;
}

static id DYYYLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth);

static id DYYYLiveDurationRoomFromKnownKeys(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    NSArray<NSString *> *keys = @[
        @"rawHTSLiveRoomModel", @"rawDataRoomModel", @"roomModel", @"rawRoom", @"liveRoom", @"room", @"currentRoom",
        @"containerContext", @"roomDI", @"roomConfig", @"roomAisle"
    ];
    for (NSString *key in keys) {
        id value = DYYYLiveDurationSafeValue(obj, key);
        if (DYYYLiveDurationHasValidLiveTime(value)) {
            return value;
        }

        id nestedRawRoom = DYYYLiveDurationSafeValue(value, @"rawRoom");
        if (DYYYLiveDurationHasValidLiveTime(nestedRawRoom)) {
            return value;
        }

        id nestedRoom = DYYYLiveDurationRoomFromCarrierDepth(value, depth + 1);
        if (nestedRoom) {
            return nestedRoom;
        }
    }
    return nil;
}

static id DYYYLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    if (DYYYLiveDurationHasValidLiveTime(obj)) {
        return obj;
    }

    id room = DYYYLiveDurationRoomFromKnownKeys(obj, depth + 1);
    if (room) {
        return room;
    }

    if ([obj respondsToSelector:@selector(liveRoomModel)]) {
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(liveRoomModel));
            if (DYYYLiveDurationHasValidLiveTime(value)) {
                return value;
            }
        } @catch (__unused NSException *exception) {
        }
    }

    NSArray<NSString *> *carrierKeys = @[ @"itemModel", @"awemeModel", @"aweme", @"model", @"item" ];
    for (NSString *key in carrierKeys) {
        id carrier = DYYYLiveDurationSafeValue(obj, key);
        room = DYYYLiveDurationRoomFromCarrierDepth(carrier, depth + 1);
        if (room) {
            return room;
        }
    }

    return nil;
}

static id DYYYLiveDurationRoomFromCarrier(id obj) {
    return DYYYLiveDurationRoomFromCarrierDepth(obj, 0);
}

static NSString *DYYYLiveDurationFormatElapsed(NSTimeInterval seconds) {
    long long totalSeconds = (long long)fmax(0.0, floor(seconds));
    long long days = totalSeconds / 86400;
    long long hours = (totalSeconds % 86400) / 3600;
    long long minutes = (totalSeconds % 3600) / 60;
    long long secs = totalSeconds % 60;

    if (days > 0) {
        return [NSString stringWithFormat:@"已开播 %lld天%02lld:%02lld:%02lld", days, hours, minutes, secs];
    }
    return [NSString stringWithFormat:@"已开播 %02lld:%02lld:%02lld", hours, minutes, secs];
}

static DYYYLiveDurationView *DYYYLiveDurationEnsureView(UIView *root) {
    DYYYLiveDurationView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    if (durationView && durationView.superview == root) {
        return durationView;
    }

    durationView = [[DYYYLiveDurationView alloc] initWithFrame:CGRectZero];
    objc_setAssociatedObject(root, kDYYYLiveDurationViewKey, durationView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [root addSubview:durationView];
    return durationView;
}

static CGRect DYYYLiveDurationFrameForRoot(UIView *root, id roomModel, NSString *text) {
    UIEdgeInsets safeInsets = DYYYLiveDurationSafeInsets(root);

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    BOOL isLandscape = rootWidth > rootHeight || DYYYLiveDurationBoolValue(roomModel, @"isLandscape");
    if (!isLandscape) {
        long long orientation = DYYYLiveDurationLongValue(roomModel, @"orientation");
        isLandscape = orientation == 2 || orientation == 90 || orientation == 270;
    }

    UIFont *font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    CGSize textSize = [text ?: @"已开播 00:00:00" sizeWithAttributes:@{NSFontAttributeName : font}];
    CGFloat width = fmin(ceil(fmax(textSize.width + 18.0, 118.0)), isLandscape ? 190.0 : 170.0);
    CGFloat height = 26.0;

    CGFloat minX = safeInsets.left + 4.0;
    CGFloat maxX = fmax(minX, rootWidth - safeInsets.right - width - 4.0);
    CGFloat minY = safeInsets.top + 4.0;
    CGFloat maxY = fmax(minY, rootHeight - safeInsets.bottom - height - 4.0);

    CGFloat x = fmin(fmax(safeInsets.left + 12.0, minX), maxX);
    CGFloat y = fmin(fmax(safeInsets.top + (isLandscape ? 12.0 : 86.0), minY), maxY);
    return CGRectIntegral(CGRectMake(x, y, width, height));
}

static void DYYYLiveDurationRemoveFromView(UIView *root) {
    if (!root) {
        return;
    }

    NSTimer *timer = objc_getAssociatedObject(root, kDYYYLiveDurationTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(root, kDYYYLiveDurationTimerKey, nil, OBJC_ASSOCIATION_ASSIGN);

    UIView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    [durationView removeFromSuperview];
    objc_setAssociatedObject(root, kDYYYLiveDurationViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDYYYLiveDurationRoomKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DYYYLiveDurationUpdateView(UIView *root) {
    if (!root) {
        return;
    }

    if (!DYYYGetBool(@"DYYYShowLiveDuration")) {
        DYYYLiveDurationRemoveFromView(root);
        return;
    }

    id roomModel = objc_getAssociatedObject(root, kDYYYLiveDurationRoomKey);
    NSTimeInterval elapsed = DYYYLiveDurationElapsedSeconds(roomModel);
    DYYYLiveDurationView *durationView = objc_getAssociatedObject(root, kDYYYLiveDurationViewKey);
    if (elapsed < 0.0) {
        durationView.hidden = YES;
        return;
    }

    NSString *text = DYYYLiveDurationFormatElapsed(elapsed);
    durationView = DYYYLiveDurationEnsureView(root);
    durationView.durationLabel.text = text;
    if (!durationView.isDragging) {
        CGRect defaultFrame = DYYYLiveDurationFrameForRoot(root, roomModel, text);
        durationView.frame = [durationView frameByApplyingSavedPositionToFrame:defaultFrame inRoot:root];
        durationView.alpha = 1.0;
    }
    durationView.hidden = NO;
    [root bringSubviewToFront:durationView];
}

@interface DYYYLiveDurationTicker : NSObject
+ (instancetype)sharedTicker;
- (void)tick:(NSTimer *)timer;
@end

@implementation DYYYLiveDurationTicker

+ (instancetype)sharedTicker {
    static DYYYLiveDurationTicker *ticker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      ticker = [DYYYLiveDurationTicker new];
    });
    return ticker;
}

- (void)tick:(NSTimer *)timer {
    DYYYLiveDurationWeakViewBox *box = (DYYYLiveDurationWeakViewBox *)timer.userInfo;
    UIView *root = box.view;
    if (![root isKindOfClass:[UIView class]]) {
        [timer invalidate];
        return;
    }
    if (!root.window) {
        DYYYLiveDurationRemoveFromView(root);
        return;
    }
    DYYYLiveDurationUpdateView(root);
}

@end

static void DYYYLiveDurationEnsureTimer(UIView *root) {
    NSTimer *timer = objc_getAssociatedObject(root, kDYYYLiveDurationTimerKey);
    if (timer && timer.isValid) {
        return;
    }

    DYYYLiveDurationWeakViewBox *box = [DYYYLiveDurationWeakViewBox new];
    box.view = root;
    timer = [NSTimer timerWithTimeInterval:1.0 target:[DYYYLiveDurationTicker sharedTicker] selector:@selector(tick:) userInfo:box repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(root, kDYYYLiveDurationTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYLiveDurationInstallOnView(UIView *root, id carrier) {
    if (!root) {
        return;
    }

    void (^installBlock)(void) = ^{
      if (!DYYYGetBool(@"DYYYShowLiveDuration")) {
          DYYYLiveDurationRemoveFromView(root);
          return;
      }

      id room = DYYYLiveDurationRoomFromCarrier(carrier);
      if (!DYYYLiveDurationHasValidLiveTime(room)) {
          UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:root];
          room = DYYYLiveDurationRoomFromCarrier(viewController);
      }

      if (DYYYLiveDurationHasValidLiveTime(room)) {
          objc_setAssociatedObject(root, kDYYYLiveDurationRoomKey, room, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }

      DYYYLiveDurationUpdateView(root);
      if (DYYYLiveDurationHasValidLiveTime(objc_getAssociatedObject(root, kDYYYLiveDurationRoomKey))) {
          DYYYLiveDurationEnsureTimer(root);
      }
    };

    if ([NSThread isMainThread]) {
        installBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), installBlock);
    }
}

static UIViewController *DYYYLiveDurationContainerAudienceVC(id container) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(container, @"audienceVC");
    if (![viewController isKindOfClass:[UIViewController class]] && [container respondsToSelector:@selector(audienceViewController)]) {
        @try {
            viewController = ((id (*)(id, SEL))objc_msgSend)(container, @selector(audienceViewController));
        } @catch (__unused NSException *exception) {
            viewController = nil;
        }
    }
    return [viewController isKindOfClass:[UIViewController class]] ? viewController : nil;
}

static void DYYYLiveDurationInstallFromContainer(id container) {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(container);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, DYYYLiveDurationSafeValue(container, @"roomModel") ?: container);
    }
}

static void DYYYLiveDurationInstallFromAudienceWrapper(id wrapper) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(wrapper, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, DYYYLiveDurationSafeValue(wrapper, @"roomModel") ?: wrapper);
    }
}

static void DYYYLiveDurationInstallFromInnerFeedCell(id cell) {
    UIViewController *viewController = DYYYLiveDurationSafeValue(cell, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationInstallOnView(viewController.view, cell);
    }
}




// 直播状态栏

// 主页状态栏

// 热点状态栏

// 图文状态栏

// 纯净模式状态栏




// 隐藏暂停关键词

// 隐藏视频顶部搜索框、隐藏搜索框背景、应用全局透明

// 隐藏视频滑条

// 隐藏好友分享私信



// 隐藏直播发现








// 隐藏直播点歌

// 隐藏昵称右侧

// 隐藏顶栏关注下的提示线


// 隐藏自己无公开作品的视图




// 隐藏关注直播顶端的直播视图

// 隐藏关注直播


// 隐藏同城顶端

// 隐藏笔记

// 屏蔽模板按钮组件（底部互动）- hook button 方法返回 nil

// 隐藏右上搜索，但可点击

// 隐藏点击进入直播间

// 去除消息群直播提示




// 隐藏首页直播胶囊

// 隐藏群商店

// 去除群聊天输入框上方快捷方式

// 隐藏相机定位

// 隐藏侧栏红点

// 隐藏搜同款

// 隐藏礼物展馆


// 隐藏直播广场

// 隐藏直播退出清屏、投屏按钮

// 隐藏直播间右上方关闭直播按钮

// 隐藏直播间流量弹窗

// 隐藏直播间商品和推广







// 隐藏直播间点赞动画

// 隐藏直播间文字贴纸

// 隐藏直播间礼物挑战

// 预约直播

// 隐藏会员进场特效

// 会员进场特效: 高版本启用swift类名

// 隐藏特殊进场特效

// 特殊视频进场特效:高版本启用swift类名












//以下部分为新增
// 屏蔽头像直播


// 屏蔽头像光圈


// 屏蔽挑战贴纸

// 屏蔽互动贴纸


// 隐藏下面底部热点框

// 屏蔽精选标签

// 隐藏好友推荐

// 屏蔽汽水音乐锚点 - hook AWERelatedMusicAnchorModel

// 屏蔽汽水音乐 - 清空 commentTopBarInfo


// 拦截开屏广告 - hook TTAdSplashModel，直接返回 nil


// 屏蔽 AWEGeneralSearchModel 中的广告卡（搜索卡片、动态卡及其作品模型统一判定）

// 去除启动视频广告

// 屏蔽青少年模式弹窗

// 屏蔽青少年模式弹窗






























// 底栏高度


// 精简平板底栏


// 禁用点击首页刷新






// 开启评论区毛玻璃后滚动区域填满底部














static id dyyyWindowKeyObserverToken = nil;
static id dyyyDidBecomeActiveToken = nil;
static id dyyyWillResignActiveToken = nil;
static id dyyyKeyboardWillShowToken = nil;
static void *DYYYGlobalTransparencyContext = &DYYYGlobalTransparencyContext;

static void DYYYRemoveAppLifecycleObservers(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (dyyyWindowKeyObserverToken) {
        [center removeObserver:dyyyWindowKeyObserverToken];
        dyyyWindowKeyObserverToken = nil;
    }
    if (dyyyDidBecomeActiveToken) {
        [center removeObserver:dyyyDidBecomeActiveToken];
        dyyyDidBecomeActiveToken = nil;
    }
    if (dyyyWillResignActiveToken) {
        [center removeObserver:dyyyWillResignActiveToken];
        dyyyWillResignActiveToken = nil;
    }
}

static void DYYYRemoveKeyboardObserver(void) {
    if (dyyyKeyboardWillShowToken) {
        [[NSNotificationCenter defaultCenter] removeObserver:dyyyKeyboardWillShowToken];
        dyyyKeyboardWillShowToken = nil;
    }
}


static Class GuideViewClass = nil;
static Class MuteViewClass = nil;
static Class TagViewClass = nil;









// 隐藏图片滑条





// 聊天视频底部评论框背景透明

// 隐藏上次看到



// 移除极速版我的片面红包横幅

static NSString *const kHideRecentAppsKey = @"DYYYHideSidebarRecentApps";
static NSString *const kHideRecentUsersKey = @"DYYYHideSidebarRecentUsers";


@interface UIDropShadowView : UIView
@end

// 修复 ios26 模态透明效果
// %hook UIDropShadowView

// - (void)didMoveToSuperview {
//     %orig;

//     if (@available(iOS 26.0, *)) {
//         self.backgroundColor = UIColor.clearColor;
//         self.opaque = NO;
//     }
// }

// - (void)layoutSubviews {
//     %orig;

//     if (@available(iOS 26.0, *)) {
//         self.backgroundColor = UIColor.clearColor;
//         self.opaque = NO;
//     }
// }

// - (void)setBackgroundColor:(UIColor *)color {
//     if (@available(iOS 26.0, *)) {
//         %orig(UIColor.clearColor);
//         return;
//     }
//     %orig;
// }

// %end


// 极速版红包激励挂件容器视图类组（移除逻辑）

// View scaling fix when comment blur is enabled




// 隐藏键盘 AI
static __weak UIView *cachedHideView = nil;
static void hideParentViewsSubviews(UIView *view) {
    if (!view)
        return;
    UIView *parentView = [view superview];
    if (!parentView)
        return;
    UIView *grandParentView = [parentView superview];
    if (!grandParentView)
        return;
    UIView *greatGrandParentView = [grandParentView superview];
    if (!greatGrandParentView)
        return;
    cachedHideView = greatGrandParentView;
    for (UIView *subview in greatGrandParentView.subviews) {
        subview.hidden = YES;
    }
}

// 递归查找目标视图
static void findTargetViewInView(UIView *view) {
    if (cachedHideView)
        return;
    if ([view isKindOfClass:NSClassFromString(@"AWESearchKeyboardVoiceSearchEntranceView")]) {
        hideParentViewsSubviews(view);
        return;
    }
    for (UIView *subview in view.subviews) {
        findTargetViewInView(subview);
        if (cachedHideView)
            break;
    }
}

#include "DYYYDownload.xm"
#include "DYYYPlayback.xm"
#include "DYYYUI.xm"
#include "DYYYFeed.xm"
#include "DYYYInteraction.xm"
#include "DYYYMisc.xm"

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"DYYYDisableFeedNowPlayingInfo" : @YES
    }];

    DYYYMigrateCombinedHDRModeIfNeeded();

    Class interactionBaseLabelClass = objc_getClass("AWECommentSwiftBizUI.CommentInteractionBaseLabel");
    if (interactionBaseLabelClass) {
        %init(DYYYCommentExactTimeGroup, AWECommentSwiftBizUI_CommentInteractionBaseLabel = interactionBaseLabelClass);
    }
    
    Class imMenuComponentClass = objc_getClass("AWEIMCustomMenuComponent");
    if (imMenuComponentClass) {
        SEL legacySelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:tapLocationInScreen:menuItemList:moreEmoticon:onCell:extra:");
        SEL tapLocationSelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:tapLocationInScreen:menuItemList:menuPanelOptions:moreEmoticon:onCell:extra:");
        SEL highLowSelector = NSSelectorFromString(@"msg_showMenuForBubbleFrameInScreen:highLocationInScreen:lowLocationInScreen:tryHighLocationFirst:menuItemList:menuPanelOptions:onCell:extra:");
        if (legacySelector && class_getInstanceMethod(imMenuComponentClass, legacySelector)) {
            %init(DYYYIMMenuLegacyGroup);
        }
        if (tapLocationSelector && class_getInstanceMethod(imMenuComponentClass, tapLocationSelector)) {
            %init(DYYYIMMenuTapLocationGroup);
        }
        if (highLowSelector && class_getInstanceMethod(imMenuComponentClass, highLowSelector)) {
            %init(DYYYIMMenuHighLowGroup);
        }
    }

    if (!DYYYGetBool(@"DYYYDisableSettingsGesture")) {
        %init(DYYYSettingsGesture);
    }
    if (DYYYGetBool(@"DYYYUserAgreementAccepted")) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class wSwiftImpl = objc_getClass("AWECommentInputViewSwiftImpl.CommentInputContainerView");
          %init(CommentInputContainerView = wSwiftImpl);
        });
        BOOL isAutoPlayEnabled = DYYYGetBool(@"DYYYEnableAutoPlay");
        if (isAutoPlayEnabled) {
            %init(AutoPlay);
        }
        if (DYYYGetBool(@"DYYYForceDownloadEmotion") ||
            DYYYGetBool(@"DYYYForceDownloadCommentAudio") ||
            DYYYGetBool(@"DYYYForceDownloadCommentImage")) {
            %init(EnableStickerSaveMenu);
        }
        [FloatingSpeedButton reloadConfiguration];

        // 初始化红包激励挂件容器视图类组
        Class incentivePendantClass = objc_getClass("AWEIncentiveSwiftImplDOUYINLite.IncentivePendantContainerView");
        if (incentivePendantClass) {
            %init(IncentivePendantGroup, AWEIncentiveSwiftImplDOUYINLite_IncentivePendantContainerView = incentivePendantClass);
        }
        Class imageContentClass = objc_getClass("BDMultiContentContainer.ImageContentView");
        if (imageContentClass) {
            %init(BDMultiContentImageViewGroup, BDMultiContentContainer_ImageContentView = imageContentClass);
        }

        // 动态获取 Swift 类并初始化对应的组
        Class commentHeaderGeneralClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderGeneralView");
        if (commentHeaderGeneralClass) {
            %init(CommentHeaderGeneralGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView = commentHeaderGeneralClass);
        }

        Class commentHeaderGoodsClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderGoodsView");
        if (commentHeaderGoodsClass) {
            %init(CommentHeaderGoodsGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView = commentHeaderGoodsClass);
        }
        Class commentHeaderTemplateClass = objc_getClass("AWECommentPanelHeaderSwiftImpl.CommentHeaderTemplateAnchorView");
        if (commentHeaderTemplateClass) {
            %init(CommentHeaderTemplateGroup, AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView = commentHeaderTemplateClass);
        }

        Class tipsVCClass = objc_getClass("AWECommentPanelListSwiftImpl.CommentBottomTipsContainerViewController");
        if (tipsVCClass) {
            %init(CommentBottomTipsVCGroup, AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController = tipsVCClass);
        }

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        DYYYRemoveKeyboardObserver();
        dyyyKeyboardWillShowToken = [center addObserverForName:UIKeyboardWillShowNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *notification) {
                                                      if (DYYYGetBool(@"DYYYHideKeyboardAI")) {
                                                          if (cachedHideView) {
                                                              for (UIView *subview in cachedHideView.subviews) {
                                                                  subview.hidden = YES;
                                                              }
                                                          } else {
                                                              for (UIWindow *window in [UIApplication sharedApplication].windows) {
                                                                  findTargetViewInView(window);
                                                                  if (cachedHideView)
                                                                      break;
                                                              }
                                                          }
                                                      }
                                                    }];
    }
}
