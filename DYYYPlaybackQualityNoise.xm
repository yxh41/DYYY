#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "DYYYUtils.h"
#import "AwemeHeaders.h"

// 移植自 pxx917144686/DYYY 的 AWEPlayerPlayControlHandler 部分
// 仅保留：分档清晰度按钮 + 音频降噪。
//
// 与原版的关键差异（本仓库之前两版踩坑的修正）：
// 1) 入口挂到本仓库确定存在且正在工作的 AWEPlayInteractionViewController（双击菜单/倍速按钮均 hook 它），
//    通过它的 `model` 属性（不是 awemeModel）拿 AWEAwemeModel。
// 2) 清晰度 URL 取自 AWEVideoModel.playURL / playLowBitURL（AWEURLModel，含 originURLList），
//    以及 bitrateModels（用 KVC 兜底取 playURL），而不是不存在的 videoURLModel。
// 3) 按钮的 target 指向一个单例控制器（DYYYPlaybackQualityNoiseController），永不释放，
//    避免 VC 被抖音复用/释放后点按按钮发送消息给野指针导致闪退；
//    单例在每次点击时实时从 keyWindow 扫描当前 AVPlayer，不持有任何 VC/player 引用。

#pragma mark - 通用：从 keyWindow 实时找正在播放的 AVPlayer

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

#pragma mark - 单例控制器（按钮 target，永不被释放）

@interface DYYYPlaybackQualityNoiseController : NSObject
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *availableQualities;
@property (nonatomic, assign) NSInteger currentQualityIndex;
@property (nonatomic, strong) UIButton *qualityButton;
@property (nonatomic, strong) UIButton *noiseButton;
+ (instancetype)shared;
- (void)configureWithAwemeModel:(AWEAwemeModel *)model
                 qualityEnabled:(BOOL)qualityEnabled
                  noiseEnabled:(BOOL)noiseEnabled;
- (void)qualityButtonTapped;
- (void)noiseButtonTapped;
@end

@implementation DYYYPlaybackQualityNoiseController

+ (instancetype)shared {
    static DYYYPlaybackQualityNoiseController *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[DYYYPlaybackQualityNoiseController alloc] init];
        inst.availableQualities = [NSMutableArray array];
    });
    return inst;
}

- (UIViewController *)topViewController {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

- (void)removeButtons {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (window) {
        UIView *q = [window viewWithTag:9877];
        if (q) [q removeFromSuperview];
        UIView *n = [window viewWithTag:9876];
        if (n) [n removeFromSuperview];
    }
    self.qualityButton = nil;
    self.noiseButton = nil;
    [self.availableQualities removeAllObjects];
    self.currentQualityIndex = 0;
}

#pragma mark 质量解析

- (void)parseQualitiesFromURLs:(NSArray *)urls {
    [self.availableQualities removeAllObjects];
    NSMutableSet *seen = [NSMutableSet set];

    NSArray *patterns = @[
        @{@"type": @"original", @"title": @"原画",  @"keys": @[@"original", @"source"]},
        @{@"type": @"1080p",    @"title": @"1080P", @"keys": @[@"1080", @"fhd", @"x1080"]},
        @{@"type": @"720p",     @"title": @"720P",  @"keys": @[@"720",  @"hd",  @"x720"]},
        @{@"type": @"540p",     @"title": @"540P",  @"keys": @[@"540",  @"sd",  @"x540"]},
    ];

    for (id obj in urls) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *url = (NSString *)obj;
        if (url.length == 0) continue;
        NSString *lower = [url lowercaseString];
        for (NSDictionary *p in patterns) {
            BOOL matched = NO;
            for (NSString *k in p[@"keys"]) {
                if ([lower containsString:k]) { matched = YES; break; }
            }
            if (matched && ![seen containsObject:p[@"type"]]) {
                [seen addObject:p[@"type"]];
                [self.availableQualities addObject:@{@"title": p[@"title"], @"url": url, @"type": p[@"type"]}];
                break;
            }
        }
    }

    if (self.availableQualities.count == 0 && urls.count > 0) {
        [self.availableQualities addObject:@{@"title": @"默认", @"url": urls.firstObject, @"type": @"default"}];
    }
    self.currentQualityIndex = 0;
}

#pragma mark 入口配置

- (void)configureWithAwemeModel:(AWEAwemeModel *)model
                 qualityEnabled:(BOOL)qualityEnabled
                  noiseEnabled:(BOOL)noiseEnabled {
    [self removeButtons];

    if (qualityEnabled && model && model.awemeType != 68) {
        AWEVideoModel *vm = model.video;
        NSMutableArray *urls = [NSMutableArray array];
        // 全防御式取值：逐层 isKindOfClass 校验，避免头文件与真机二进制布局不符时
        // 取到错类型对象 / 野指针导致 EXC_BAD_ACCESS（信号级，@try/@catch 抓不住）。
        if ([vm isKindOfClass:NSClassFromString(@"AWEVideoModel")]) {
            id playURL = vm.playURL;
            if ([playURL isKindOfClass:NSClassFromString(@"AWEURLModel")] && [playURL originURLList].count) {
                [urls addObjectsFromArray:[playURL originURLList]];
            }
            id lowBit = vm.playLowBitURL;
            if ([lowBit isKindOfClass:NSClassFromString(@"AWEURLModel")] && [lowBit originURLList].count) {
                [urls addObjectsFromArray:[lowBit originURLList]];
            }
            NSArray *bitrates = vm.bitrateModels;
            for (id bm in bitrates ?: @[]) {
                @try {
                    id bmURL = [bm valueForKey:@"playURL"] ?: [bm valueForKey:@"url"];
                    if ([bmURL isKindOfClass:NSClassFromString(@"AWEURLModel")] && [bmURL originURLList].count) {
                        [urls addObjectsFromArray:[bmURL originURLList]];
                    }
                } @catch (NSException *e) {}
            }
        }
        [self parseQualitiesFromURLs:urls];
        if (self.availableQualities.count > 0) {
            [self addQualityButton];
            // 关键修复：默认清晰度切换会改动正在播放的 AVPlayer（replaceCurrentItem），
            // 绝不能在 viewDidAppear 的 Appearance 事务里同步执行——会在内部 KVO/状态访问中
            // 触发 EXC_BAD_ACCESS(0x10)。延迟到下一个 runloop，等 Appearance 提交完成后再切。
            // 单例永不释放，block 直接捕获 self 不会形成循环引用（无需 weak/strong dance）。
            __typeof__(self) __weak blockSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                __typeof__(blockSelf) __strong strongSelf = blockSelf;
                if (!strongSelf) return;
                @try { [strongSelf applyDefaultQualityPreference]; }
                @catch (NSException *e) {}
            });
        }
    }

    if (noiseEnabled) {
        [self addNoiseButton];
    }
}

#pragma mark 按钮

- (void)addQualityButton {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;

    UIButton *qualityButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat screenW = window.bounds.size.width;
    qualityButton.frame = CGRectMake(screenW - 90, 210, 70, 30);
    qualityButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    qualityButton.layer.cornerRadius = 15;

    NSString *qualityText = self.availableQualities.count > 0
        ? self.availableQualities[self.currentQualityIndex][@"title"] : @"清晰度";
    [qualityButton setTitle:qualityText forState:UIControlStateNormal];
    [qualityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    qualityButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [qualityButton addTarget:self
                      action:@selector(qualityButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];
    qualityButton.tag = 9877;

    [window addSubview:qualityButton];
    [window bringSubviewToFront:qualityButton];
    self.qualityButton = qualityButton;
}

- (void)addNoiseButton {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;

    UIButton *filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat screenW = window.bounds.size.width;
    filterButton.frame = CGRectMake(screenW - 90, 160, 70, 30);
    filterButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    filterButton.layer.cornerRadius = 15;
    [filterButton setTitle:@"降噪" forState:UIControlStateNormal];
    [filterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    filterButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [filterButton addTarget:self
                     action:@selector(noiseButtonTapped)
           forControlEvents:UIControlEventTouchUpInside];
    filterButton.tag = 9876;

    [window addSubview:filterButton];
    [window bringSubviewToFront:filterButton];
    self.noiseButton = filterButton;
}

- (void)qualityButtonTapped {
    [self showQualityOptions];
}

- (void)noiseButtonTapped {
    [self toggleNoiseFilter];
}

#pragma mark 清晰度选择

- (void)showQualityOptions {
    if (self.availableQualities.count == 0) return;
    UIViewController *top = [self topViewController];
    if (!top) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"选择清晰度"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSInteger i = 0; i < (NSInteger)self.availableQualities.count; i++) {
        NSDictionary *q = self.availableQualities[i];
        NSString *title = q[@"title"];
        if (i == self.currentQualityIndex) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }
        [alert addAction:[UIAlertAction
            actionWithTitle:title
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction * _Nonnull action) {
            [self switchToQualityAtIndex:i];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && self.qualityButton) {
        alert.popoverPresentationController.sourceView = self.qualityButton;
        alert.popoverPresentationController.sourceRect = self.qualityButton.bounds;
    }

    [top presentViewController:alert animated:YES completion:nil];
}

- (void)switchToQualityAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.availableQualities.count) return;

    AVPlayer *player = DYYYFindActivePlayer();
    if (!player) return;

    @try {
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
        if (CMTIME_IS_VALID(currentTime)) {
            [newItem seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
        if (wasPlaying) {
            [player play];
        }

        self.currentQualityIndex = index;
        if (self.qualityButton) {
            [self.qualityButton setTitle:self.availableQualities[index][@"title"] forState:UIControlStateNormal];
        }
        NSString *qualityName = self.availableQualities[index][@"title"];
        [DYYYUtils showToast:[NSString stringWithFormat:@"已切换到%@清晰度", qualityName]];
    } @catch (NSException *e) {
        [DYYYUtils showToast:@"切换清晰度失败"];
    }
}

- (void)applyDefaultQualityPreference {
    if (self.availableQualities.count == 0) return;

    id pref = [DYYYPreferences objectForKey:@"DYYYDefaultQuality"];
    NSString *prefStr = pref ? [NSString stringWithFormat:@"%@", pref] : @"最高";

    // 播放器默认即最高画质，无需切换——既符合预期，也避免无谓改动 AVPlayer 引发异常。
    if ([prefStr isEqualToString:@"最高"]) {
        return;
    }

    NSDictionary *typeMap = @{@"原画": @"original", @"1080P": @"1080p", @"720P": @"720p", @"540P": @"540p"};
    NSString *targetType = typeMap[prefStr];
    if (!targetType) {
        [self switchToQualityAtIndex:0];
        return;
    }
    for (NSInteger i = 0; i < (NSInteger)self.availableQualities.count; i++) {
        if ([self.availableQualities[i][@"type"] isEqualToString:targetType]) {
            [self switchToQualityAtIndex:i];
            return;
        }
    }
    [self switchToQualityAtIndex:0];
}

#pragma mark 音频降噪

- (void)toggleNoiseFilter {
    AVPlayer *player = DYYYFindActivePlayer();
    if (!player) return;

    @try {
        BOOL isActive = ![[DYYYPreferences objectForKey:@"DYYYNoiseFilterActive"] boolValue];
        [DYYYPreferences setObject:@(isActive) forKey:@"DYYYNoiseFilterActive"];

        CMTime currentTime = player.currentTime;

        if (isActive) {
            AVPlayerItem *item = player.currentItem;
            if (item) {
                NSArray *audioTracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
                AVAssetTrack *audioTrack = audioTracks.firstObject;
                if (audioTrack) {
                    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
                    AVMutableAudioMixInputParameters *inputParams =
                        [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
                    inputParams.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmSpectral;
                    audioMix.inputParameters = @[inputParams];
                    item.audioMix = audioMix;
                }
            }
            [DYYYUtils showToast:@"已启用噪音过滤"];
        } else {
            player.currentItem.audioMix = nil;
            [DYYYUtils showToast:@"已关闭噪音过滤"];
        }

        if (CMTIME_IS_VALID(currentTime)) {
            [player seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
    } @catch (NSException *e) {
        [DYYYUtils showToast:@"降噪操作失败"];
    }
}

@end

#pragma mark - Hook 入口

%hook AWEPlayInteractionViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BOOL qualityEnabled = DYYYGetBool(@"DYYYEnableQualitySelection");
    BOOL noiseEnabled = DYYYGetBool(@"DYYYEnableNoiseFilter");
    if (qualityEnabled || noiseEnabled) {
        [[DYYYPlaybackQualityNoiseController shared]
            configureWithAwemeModel:self.model
                     qualityEnabled:qualityEnabled
                      noiseEnabled:noiseEnabled];
    }
}

%end
