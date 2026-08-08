#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "DYYYUtils.h"
#import "AwemeHeaders.h"

// 移植自 pxx917144686/DYYY 的 AWEPlayerPlayControlHandler 部分
// 仅保留：分档清晰度按钮 + 音频降噪（下载用的 getDYYYSrcURLDownload 与 AWEVideoModel 最高画质 hook 本地均已存在）
//
// 关键修正：原版 hook 的 AWEPlayerPlayControlHandler 在当前抖音版本中可能不存在/被改名，
// 导致整个 %hook 被 Logos 静默跳过、按钮永不被创建。此处改挂到本仓库已验证存在且
// 正在工作的 AWEPlayInteractionViewController（双击菜单/倍速按钮均 hook 它）。
// 该类的基类声明见 AwemeHeaders.h:359（完整 @interface），故此处仅加分类声明 %new 方法，
// 不补基类声明（避免与已有完整 @interface 冲突）。

@interface AWEPlayInteractionViewController (DYYYQualityNoise)
- (void)dyyySetupQualityAndNoise;
- (void)dyyyAddQualityButton;
- (void)dyyyAddNoiseFilterButton;
- (void)dyyyParseAvailableQualities:(AWEURLModel *)urlModel;
- (void)dyyyApplyDefaultQualityPreference;
- (void)dyyyShowQualityOptions;
- (void)dyyySwitchToQuality:(NSInteger)index;
- (void)dyyyToggleNoiseFilter;
- (UIButton *)dyyyQualityButton;
- (void)setDyyyQualityButton:(UIButton *)btn;
- (UIButton *)dyyyNoiseFilterButton;
- (void)setDyyyNoiseFilterButton:(UIButton *)btn;
- (NSArray *)dyyyAvailableQualities;
- (void)setDyyyAvailableQualities:(NSArray *)arr;
- (NSInteger)dyyyCurrentQualityIndex;
- (void)setDyyyCurrentQualityIndex:(NSInteger)idx;
- (BOOL)dyyyNoiseFilterEnabled;
- (void)setDyyyNoiseFilterEnabled:(BOOL)v;
@end

// 通用：从 keyWindow 找正在播放的 AVPlayer（反向扫描 AVPlayerLayer.player）。
// 不依赖任何抖音私有播放器类名，规避"类名不存在/被混淆"的坑。
static AVPlayer *DYYYFindActivePlayer(void) {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return nil;
    __block AVPlayer *result = nil;
    void (^scan)(UIView *) = ^(UIView *view) {
        if (result) return;
        if ([view.layer isKindOfClass:[AVPlayerLayer class]]) {
            AVPlayerLayer *playerLayer = (AVPlayerLayer *)view.layer;
            if (playerLayer.player) {
                result = playerLayer.player;
                return;
            }
        }
        for (UIView *sub in view.subviews) {
            scan(sub);
        }
    };
    scan(window);
    return result;
}

%hook AWEPlayInteractionViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (DYYYGetBool(@"DYYYEnableQualitySelection") || DYYYGetBool(@"DYYYEnableNoiseFilter")) {
        [self dyyySetupQualityAndNoise];
    }
}

#pragma mark - 关联对象属性存取器（替代 %property，前向声明类下更稳妥；完整类下同样安全）

%new
- (UIButton *)dyyyQualityButton {
    return objc_getAssociatedObject(self, @selector(dyyyQualityButton));
}
%new
- (void)setDyyyQualityButton:(UIButton *)btn {
    objc_setAssociatedObject(self, @selector(dyyyQualityButton), btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (UIButton *)dyyyNoiseFilterButton {
    return objc_getAssociatedObject(self, @selector(dyyyNoiseFilterButton));
}
%new
- (void)setDyyyNoiseFilterButton:(UIButton *)btn {
    objc_setAssociatedObject(self, @selector(dyyyNoiseFilterButton), btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (NSArray *)dyyyAvailableQualities {
    return objc_getAssociatedObject(self, @selector(dyyyAvailableQualities));
}
%new
- (void)setDyyyAvailableQualities:(NSArray *)arr {
    objc_setAssociatedObject(self, @selector(dyyyAvailableQualities), arr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (NSInteger)dyyyCurrentQualityIndex {
    return [objc_getAssociatedObject(self, @selector(dyyyCurrentQualityIndex)) integerValue];
}
%new
- (void)setDyyyCurrentQualityIndex:(NSInteger)idx {
    objc_setAssociatedObject(self, @selector(dyyyCurrentQualityIndex), @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (BOOL)dyyyNoiseFilterEnabled {
    return [objc_getAssociatedObject(self, @selector(dyyyNoiseFilterEnabled)) boolValue];
}
%new
- (void)setDyyyNoiseFilterEnabled:(BOOL)v {
    objc_setAssociatedObject(self, @selector(dyyyNoiseFilterEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 入口

%new
- (void)dyyySetupQualityAndNoise {
    if (DYYYGetBool(@"DYYYEnableQualitySelection")) {
        AWEAwemeModel *awemeModel = nil;
        @try {
            awemeModel = [self performSelector:@selector(awemeModel)];
        } @catch (NSException *exception) {
            awemeModel = nil;
        }
        // 仅视频内容显示清晰度按钮（图片 68 无 videoURLModel）
        if (awemeModel && awemeModel.awemeType != 68) {
            AWEVideoModel *videoModel = awemeModel.video;
            AWEURLModel *urlModel = [videoModel valueForKey:@"videoURLModel"];
            if (urlModel && urlModel.originURLList && urlModel.originURLList.count > 0) {
                [self dyyyParseAvailableQualities:urlModel];
                [self dyyyAddQualityButton];
                [self dyyyApplyDefaultQualityPreference];
            }
        }
    }
    if (DYYYGetBool(@"DYYYEnableNoiseFilter")) {
        [self dyyyAddNoiseFilterButton];
    }
}

#pragma mark - 分档清晰度

%new
- (void)dyyyParseAvailableQualities:(AWEURLModel *)urlModel {
    NSMutableArray *qualities = [NSMutableArray array];
    NSArray *urls = urlModel.originURLList;

    for (NSString *url in urls) {
        if ([url containsString:@"original"] || [url containsString:@"source"]) {
            [qualities addObject:@{@"title": @"原画", @"url": url, @"type": @"original"}];
            break;
        }
    }
    for (NSString *url in urls) {
        if ([url containsString:@"1080"] || [url containsString:@"FHD"]) {
            [qualities addObject:@{@"title": @"1080P", @"url": url, @"type": @"1080p"}];
            break;
        }
    }
    for (NSString *url in urls) {
        if ([url containsString:@"720"] || [url containsString:@"HD"]) {
            [qualities addObject:@{@"title": @"720P", @"url": url, @"type": @"720p"}];
            break;
        }
    }
    for (NSString *url in urls) {
        if ([url containsString:@"540"] || [url containsString:@"SD"]) {
            [qualities addObject:@{@"title": @"540P", @"url": url, @"type": @"540p"}];
            break;
        }
    }
    if (qualities.count == 0 && urls.count > 0) {
        [qualities addObject:@{@"title": @"默认", @"url": urls.firstObject, @"type": @"default"}];
    }
    [self setDyyyAvailableQualities:qualities];
    [self setDyyyCurrentQualityIndex:0];
}

%new
- (void)dyyyAddQualityButton {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;

    // 去重：每次 viewDidAppear 先移除旧按钮
    UIView *existing = [window viewWithTag:9877];
    if (existing) [existing removeFromSuperview];

    UIButton *qualityButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat screenW = window.bounds.size.width;
    qualityButton.frame = CGRectMake(screenW - 90, 210, 70, 30);
    qualityButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    qualityButton.layer.cornerRadius = 15;

    NSString *qualityText = @"清晰度";
    if (self.dyyyAvailableQualities.count > 0 &&
        self.dyyyCurrentQualityIndex < (NSInteger)self.dyyyAvailableQualities.count) {
        qualityText = self.dyyyAvailableQualities[self.dyyyCurrentQualityIndex][@"title"];
    }
    [qualityButton setTitle:qualityText forState:UIControlStateNormal];
    [qualityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    qualityButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [qualityButton addTarget:self
                      action:@selector(dyyyShowQualityOptions)
            forControlEvents:UIControlEventTouchUpInside];
    qualityButton.tag = 9877;

    [window addSubview:qualityButton];
    [window bringSubviewToFront:qualityButton];
    [self setDyyyQualityButton:qualityButton];
}

%new
- (void)dyyyApplyDefaultQualityPreference {
    if (self.dyyyAvailableQualities.count == 0) return;

    id pref = [DYYYPreferences objectForKey:@"DYYYDefaultQuality"];
    NSString *prefStr = pref ? [NSString stringWithFormat:@"%@", pref] : @"最高";

    if ([prefStr isEqualToString:@"最高"]) {
        [self dyyySwitchToQuality:0];
        return;
    }

    NSDictionary *typeMap = @{@"原画": @"original", @"1080P": @"1080p", @"720P": @"720p", @"540P": @"540p"};
    NSString *targetType = typeMap[prefStr];
    if (!targetType) {
        [self dyyySwitchToQuality:0];
        return;
    }
    for (int i = 0; i < (int)self.dyyyAvailableQualities.count; i++) {
        if ([self.dyyyAvailableQualities[i][@"type"] isEqualToString:targetType]) {
            [self dyyySwitchToQuality:i];
            return;
        }
    }
    [self dyyySwitchToQuality:0];
}

%new
- (void)dyyyShowQualityOptions {
    if (!self.dyyyAvailableQualities || self.dyyyAvailableQualities.count == 0) return;

    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    if (!rootVC) return;

    UIAlertController *alertController = [UIAlertController
                                         alertControllerWithTitle:@"选择清晰度"
                                         message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];

    for (int i = 0; i < (int)self.dyyyAvailableQualities.count; i++) {
        NSDictionary *quality = self.dyyyAvailableQualities[i];
        NSString *title = quality[@"title"];
        if (i == self.dyyyCurrentQualityIndex) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }
        UIAlertAction *action = [UIAlertAction
                                 actionWithTitle:title
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * _Nonnull action) {
            [self dyyySwitchToQuality:i];
        }];
        [alertController addAction:action];
    }

    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:@"取消"
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    [alertController addAction:cancelAction];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = self.dyyyQualityButton;
        alertController.popoverPresentationController.sourceRect = self.dyyyQualityButton.bounds;
    }

    [rootVC presentViewController:alertController animated:YES completion:nil];
}

%new
- (void)dyyySwitchToQuality:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.dyyyAvailableQualities.count) return;

    AVPlayer *player = DYYYFindActivePlayer();
    if (!player) return;

    AVPlayerItem *currentItem = player.currentItem;
    if (!currentItem) return;

    CMTime currentTime = currentItem.currentTime;
    BOOL wasPlaying = player.rate > 0;

    NSString *urlString = self.dyyyAvailableQualities[index][@"url"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:url];
    if (!newItem) return;

    [player replaceCurrentItemWithPlayerItem:newItem];
    [newItem seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];

    if (wasPlaying) {
        [player play];
    }

    [self setDyyyCurrentQualityIndex:index];

    if (self.dyyyQualityButton) {
        NSString *qualityText = self.dyyyAvailableQualities[index][@"title"];
        [self.dyyyQualityButton setTitle:qualityText forState:UIControlStateNormal];
    }

    NSString *qualityName = self.dyyyAvailableQualities[index][@"title"];
    [DYYYUtils showToast:[NSString stringWithFormat:@"已切换到%@清晰度", qualityName]];
}

#pragma mark - 音频降噪

%new
- (void)dyyyAddNoiseFilterButton {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;

    if ([window viewWithTag:9876]) return;

    UIButton *filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat screenW = window.bounds.size.width;
    filterButton.frame = CGRectMake(screenW - 90, 160, 70, 30);
    filterButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    filterButton.layer.cornerRadius = 15;
    [filterButton setTitle:@"降噪" forState:UIControlStateNormal];
    [filterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    filterButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [filterButton addTarget:self
                     action:@selector(dyyyToggleNoiseFilter)
           forControlEvents:UIControlEventTouchUpInside];
    filterButton.tag = 9876;

    [window addSubview:filterButton];
    [window bringSubviewToFront:filterButton];
}

%new
- (void)dyyyToggleNoiseFilter {
    AVPlayer *player = DYYYFindActivePlayer();
    if (!player) return;

    BOOL isActive = ![[DYYYPreferences objectForKey:@"DYYYNoiseFilterActive"] boolValue];
    [DYYYPreferences setObject:@(isActive) forKey:@"DYYYNoiseFilterActive"];

    CMTime currentTime = player.currentTime;

    if (isActive) {
        NSArray *audioTracks = [player.currentItem.asset tracksWithMediaType:AVMediaTypeAudio];
        AVAssetTrack *audioTrack = audioTracks.firstObject;
        if (audioTrack) {
            AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
            AVMutableAudioMixInputParameters *inputParams =
                [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
            inputParams.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmSpectral;
            audioMix.inputParameters = @[inputParams];
            player.currentItem.audioMix = audioMix;
        }
        [DYYYUtils showToast:@"已启用噪音过滤"];
    } else {
        player.currentItem.audioMix = nil;
        [DYYYUtils showToast:@"已关闭噪音过滤"];
    }

    [player seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

%end
