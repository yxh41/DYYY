#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "DYYYManager.h"
#import "DYYYUtils.h"
#import "AwemeHeaders.h"

// 移植自 pxx917144686/DYYY 的 AWEPlayerPlayControlHandler 部分
// 仅保留：分档清晰度按钮 + 音频降噪（不含下载用的 getDYYYSrcURLDownload 与 AWEVideoModel 最高画质 hook，本地均已存在）

// AWEPlayerPlayControlHandler 在本仓库头文件中仅为前向声明(@class)，没有完整 @interface。
// 因此不能让它直接依附分类，也不能用 %property（均会报 forward declaration）。
// 做法：先补一个完整基类声明 @interface ... : NSObject @end（编译期虚构类型，
//   运行期 Logos 按类名 hook 真实私有类，互不影响），再在分类中声明本文件扩展的
//   方法与属性存取器。属性实际由下方手写 associated object 存取器(%new)实现。
@interface AWEPlayerPlayControlHandler : NSObject
@end

@interface AWEPlayerPlayControlHandler (DYYYQualityNoise)
- (void)parseAvailableQualities:(AWEURLModel *)urlModel;
- (void)addQualityButton;
- (void)applyDefaultQualityPreference;
- (void)showQualityOptions;
- (void)switchToQuality:(NSInteger)index;
- (void)setupNoiseFilter;
- (void)addNoiseFilterButton;
- (void)toggleNoiseFilter;
- (UIButton *)qualityButton;
- (void)setQualityButton:(UIButton *)btn;
- (UIButton *)noiseFilterButton;
- (void)setNoiseFilterButton:(UIButton *)btn;
- (NSArray *)availableQualities;
- (void)setAvailableQualities:(NSArray *)arr;
- (NSInteger)currentQualityIndex;
- (void)setCurrentQualityIndex:(NSInteger)idx;
- (BOOL)noiseFilterEnabled;
- (void)setNoiseFilterEnabled:(BOOL)v;
@end

%hook AWEPlayerPlayControlHandler

#pragma mark - 关联对象属性存取器(替代 %property，前向声明类下更稳妥)
%new
- (UIButton *)qualityButton {
    return objc_getAssociatedObject(self, @selector(qualityButton));
}
%new
- (void)setQualityButton:(UIButton *)btn {
    objc_setAssociatedObject(self, @selector(qualityButton), btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (UIButton *)noiseFilterButton {
    return objc_getAssociatedObject(self, @selector(noiseFilterButton));
}
%new
- (void)setNoiseFilterButton:(UIButton *)btn {
    objc_setAssociatedObject(self, @selector(noiseFilterButton), btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (NSArray *)availableQualities {
    return objc_getAssociatedObject(self, @selector(availableQualities));
}
%new
- (void)setAvailableQualities:(NSArray *)arr {
    objc_setAssociatedObject(self, @selector(availableQualities), arr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (NSInteger)currentQualityIndex {
    return [objc_getAssociatedObject(self, @selector(currentQualityIndex)) integerValue];
}
%new
- (void)setCurrentQualityIndex:(NSInteger)idx {
    objc_setAssociatedObject(self, @selector(currentQualityIndex), @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (BOOL)noiseFilterEnabled {
    return [objc_getAssociatedObject(self, @selector(noiseFilterEnabled)) boolValue];
}
%new
- (void)setNoiseFilterEnabled:(BOOL)v {
    objc_setAssociatedObject(self, @selector(noiseFilterEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 分档清晰度

- (void)setupAVPlayerItem:(AVPlayerItem *)item {
    %orig;

    if (!DYYYGetBool(@"DYYYEnableQualitySelection")) return;

    id videoModel = [self valueForKey:@"videoModel"];
    if (!videoModel) return;

    AWEURLModel *urlModel = [videoModel valueForKey:@"videoURLModel"];
    if (!urlModel || !urlModel.originURLList || urlModel.originURLList.count == 0) return;

    [self parseAvailableQualities:urlModel];
    [self addQualityButton];
    [self applyDefaultQualityPreference];
}

%new
- (void)parseAvailableQualities:(AWEURLModel *)urlModel {
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
    self.availableQualities = qualities;
    self.currentQualityIndex = 0;
}

%new
- (void)addQualityButton {
    UIViewController *parentVC = nil;
    id currentResponder = self;
    while ((currentResponder = [currentResponder nextResponder])) {
        if ([currentResponder isKindOfClass:[UIViewController class]]) {
            parentVC = (UIViewController *)currentResponder;
            break;
        }
    }
    if (!parentVC || !parentVC.view) return;

    if (self.qualityButton) {
        [self.qualityButton removeFromSuperview];
        self.qualityButton = nil;
    }

    UIButton *qualityButton = [UIButton buttonWithType:UIButtonTypeCustom];
    qualityButton.frame = CGRectMake(parentVC.view.frame.size.width - 90, 210, 70, 30);
    qualityButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    qualityButton.layer.cornerRadius = 15;

    NSString *qualityText = @"清晰度";
    if (self.availableQualities.count > 0 && self.currentQualityIndex < self.availableQualities.count) {
        qualityText = self.availableQualities[self.currentQualityIndex][@"title"];
    }
    [qualityButton setTitle:qualityText forState:UIControlStateNormal];
    [qualityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    qualityButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [qualityButton addTarget:self action:@selector(showQualityOptions) forControlEvents:UIControlEventTouchUpInside];
    qualityButton.tag = 9877;

    [parentVC.view addSubview:qualityButton];
    self.qualityButton = qualityButton;
}

%new
- (void)applyDefaultQualityPreference {
    if (self.availableQualities.count == 0) return;

    id pref = [DYYYPreferences objectForKey:@"DYYYDefaultQuality"];
    NSString *prefStr = pref ? [NSString stringWithFormat:@"%@", pref] : @"最高";

    if ([prefStr isEqualToString:@"最高"]) {
        [self switchToQuality:0];
        return;
    }

    NSDictionary *typeMap = @{@"原画": @"original", @"1080P": @"1080p", @"720P": @"720p", @"540P": @"540p"};
    NSString *targetType = typeMap[prefStr];
    if (!targetType) {
        [self switchToQuality:0];
        return;
    }
    for (int i = 0; i < self.availableQualities.count; i++) {
        if ([self.availableQualities[i][@"type"] isEqualToString:targetType]) {
            [self switchToQuality:i];
            return;
        }
    }
    [self switchToQuality:0];
}

%new
- (void)showQualityOptions {
    if (!self.availableQualities || self.availableQualities.count == 0) return;

    UIViewController *parentVC = nil;
    id currentResponder = self;
    while ((currentResponder = [currentResponder nextResponder])) {
        if ([currentResponder isKindOfClass:[UIViewController class]]) {
            parentVC = (UIViewController *)currentResponder;
            break;
        }
    }
    if (!parentVC) return;

    UIAlertController *alertController = [UIAlertController
                                         alertControllerWithTitle:@"选择清晰度"
                                         message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];

    for (int i = 0; i < self.availableQualities.count; i++) {
        NSDictionary *quality = self.availableQualities[i];
        NSString *title = quality[@"title"];
        if (i == self.currentQualityIndex) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }
        UIAlertAction *action = [UIAlertAction
                                 actionWithTitle:title
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * _Nonnull action) {
            [self switchToQuality:i];
        }];
        [alertController addAction:action];
    }

    UIAlertAction *cancelAction = [UIAlertAction
                                   actionWithTitle:@"取消"
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    [alertController addAction:cancelAction];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = self.qualityButton;
        alertController.popoverPresentationController.sourceRect = self.qualityButton.bounds;
    }

    [parentVC presentViewController:alertController animated:YES completion:nil];
}

%new
- (void)switchToQuality:(NSInteger)index {
    if (index < 0 || index >= self.availableQualities.count) return;

    id playerObject = [self valueForKey:@"player"];
    if (!playerObject || ![playerObject isKindOfClass:[AVPlayer class]]) return;

    AVPlayer *player = (AVPlayer *)playerObject;
    AVPlayerItem *currentItem = player.currentItem;
    if (!currentItem) return;

    CMTime currentTime = currentItem.currentTime;
    BOOL wasPlaying = player.rate > 0;

    NSString *urlString = self.availableQualities[index][@"url"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:url];
    if (!newItem) return;

    [player replaceCurrentItemWithPlayerItem:newItem];
    [newItem seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];

    if (wasPlaying) {
        [player play];
    }

    self.currentQualityIndex = index;

    if (self.qualityButton) {
        NSString *qualityText = self.availableQualities[index][@"title"];
        [self.qualityButton setTitle:qualityText forState:UIControlStateNormal];
    }

    NSString *qualityName = self.availableQualities[index][@"title"];
    [DYYYUtils showToast:[NSString stringWithFormat:@"已切换到%@清晰度", qualityName]];
}

#pragma mark - 音频降噪

- (void)play {
    %orig;
    if (DYYYGetBool(@"DYYYEnableNoiseFilter")) {
        [self setupNoiseFilter];
    }
}

%new
- (void)setupNoiseFilter {
    if (self.noiseFilterEnabled) return;
    [self addNoiseFilterButton];
    self.noiseFilterEnabled = YES;
}

%new
- (void)addNoiseFilterButton {
    UIViewController *parentVC = nil;
    id currentResponder = self;
    while ((currentResponder = [currentResponder nextResponder])) {
        if ([currentResponder isKindOfClass:[UIViewController class]]) {
            parentVC = (UIViewController *)currentResponder;
            break;
        }
    }
    if (!parentVC || !parentVC.view) return;
    if ([parentVC.view viewWithTag:9876]) return;

    UIButton *filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    filterButton.frame = CGRectMake(parentVC.view.frame.size.width - 90, 160, 70, 30);
    filterButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    filterButton.layer.cornerRadius = 15;
    [filterButton setTitle:@"降噪" forState:UIControlStateNormal];
    [filterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    filterButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [filterButton addTarget:self action:@selector(toggleNoiseFilter) forControlEvents:UIControlEventTouchUpInside];
    filterButton.tag = 9876;

    [parentVC.view addSubview:filterButton];
}

%new
- (void)toggleNoiseFilter {
    AVPlayer *player = [self valueForKey:@"player"];
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
