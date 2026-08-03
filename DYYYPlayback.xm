//
//  DYYY - 自动拆分片段（由 DYYY.xmi 通过 #include 引入，勿单独编译）
//  分类: DYYYPlayback
//

%hook AWEAwemeBackgroundPlayModule

- (id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return nil;
    }

    return %orig;
}

- (void)refreshNowPlayingInfoIfNeeded {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)updateNowPlayingInfoPlayback {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

%hook AWEFeedBackgroundPlayManager

- (id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return nil;
    }

    return %orig;
}

- (void)setNowPlayingInfo:(id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)resetNowPlayingInfo:(id)model {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfoIsForce:(BOOL)isForce {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)updateNowPlayingInfoPlayback {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

%hook AWENowPlayingInfoCenter

- (void)becomePlayingPlayer:(id)player {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)setNowPlayingInfo:(id)nowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

- (void)refreshNowPlayingInfo {
    if (DYYYGetBool(@"DYYYDisableFeedNowPlayingInfo")) {
        DYYYClearFeedNowPlayingSystemInfoThrottled();
        return;
    }

    %orig;
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)nowPlayingInfo {
    if (DYYYShouldBlockFeedNowPlayingSystemInfoWrite()) {
        %orig(nil);
        return;
    }

    %orig;
}

- (void)setPlaybackState:(NSInteger)playbackState {
    if (DYYYShouldBlockFeedNowPlayingSystemInfoWrite()) {
        %orig(0);
        return;
    }

    %orig;
}

%end

%hook AVPlayer

+ (AVPlayerHDRMode)availableHDRModes {
    if (DYYYShouldDisableAllHDR()) {
        return 0;
    }
    return %orig;
}

+ (BOOL)eligibleForHDRPlayback {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (instancetype)playerWithURL:(NSURL *)URL {
    AVPlayer *player = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(player.currentItem);
    return player;
}

+ (instancetype)playerWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return %orig;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self.currentItem);
    return self;
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return %orig;
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    DYYYDisableAVPlayerItemHDRMetadata(item);
    %orig;
}

%end

%hook AVPlayerItem

+ (instancetype)playerItemWithURL:(NSURL *)URL {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

+ (instancetype)playerItemWithAsset:(AVAsset *)asset {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

+ (instancetype)playerItemWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)automaticallyLoadedAssetKeys {
    AVPlayerItem *item = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(item);
    return item;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (instancetype)initWithAsset:(AVAsset *)asset {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (instancetype)initWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)automaticallyLoadedAssetKeys {
    self = %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self);
    return self;
}

- (void)setAppliesPerFrameHDRDisplayMetadata:(BOOL)appliesPerFrameHDRDisplayMetadata {
    %orig(DYYYShouldDisableAllHDR() ? NO : appliesPerFrameHDRDisplayMetadata);
}

- (BOOL)appliesPerFrameHDRDisplayMetadata {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AVPlayerLayer

- (void)setPlayer:(AVPlayer *)player {
    DYYYDisableAVPlayerItemHDRMetadata(player.currentItem);
    %orig;
    DYYYDisableExtendedRangeForLayer(self);
}

- (void)layoutSublayers {
    %orig;
    DYYYDisableAVPlayerItemHDRMetadata(self.player.currentItem);
    DYYYDisableExtendedRangeForLayer(self);
}

%end

%hook BDSimPlayerBizConfig

- (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEBDSimPlayerBizConfig

- (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEVideoPlayerConfiguration

+ (void)setHDRBrightnessStrategy:(id)strategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

+ (double)getHDRBrightnessOffset:(id)configuration brightness:(double)brightness {
    if (DYYYShouldDisableAllHDR()) {
        return 0.0;
    }
    return %orig;
}

%end

%hook AWEDPlayerVideoDisplayOptState

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%end

%hook AWEPlayVideoPlayerContext

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%end

%hook AWEDPlayerVideoModel

- (BOOL)awe_isHDRVideo {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setAwe_isHDRVideo:(BOOL)awe_isHDRVideo {
    %orig(DYYYShouldDisableAllHDR() ? NO : awe_isHDRVideo);
}

%end

%hook AWEPlayVideoViewController

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

- (BOOL)awe_isCurrentVideoHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setPlayerLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook AWEDPlayerBrightnessContainer

- (BOOL)awe_isCurrentVideoHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEVideoPlayerScreenBrightnessManager

- (BOOL)isHDRVideo {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDRVideo:(BOOL)isHDRVideo {
    // 播放器复用时会重新写入当前作品的 HDR 状态，需同时清除写入值和读取结果。
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDRVideo);
}

%end

%hook ALMOwnPlayerWrapper

- (void)setLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook ALMSysPlayerWrapper

- (void)setLutFilter:(id)lutFilter HDRLutImage:(id)HDRLutImage {
    %orig(lutFilter, DYYYShouldDisableAllHDR() ? nil : HDRLutImage);
}

%end

%hook ALMVideoPlayerConfig

+ (void)setPlayerEffectHDRLutImageEnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook IESVideoPlayerConfig

+ (void)setPlayerEffectHDRLutImageEnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook IESIMVideoPlayerWrapper

- (void)setupHDREnable:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook IESLivePlayerController

- (BOOL)isVideoSDR2HDRSupport {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (BOOL)enableCloseSDR2HDR {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

%end

%hook AWELivePreStreamPlayer

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook HTSLiveStreamPlayer

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook IESLiveStreamPlayerVideoAudioEffectPlugin

- (void)setEnableVideoSDR2HDR:(BOOL)enable callTrace:(id)callTrace {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable, callTrace);
}

- (void)changeSDR2HDRWithStrategy {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook TVLPlayerItemPreferences

- (BOOL)forbidSDR2HDRInPreview {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

- (void)setForbidSDR2HDRInPreview:(BOOL)forbid {
    %orig(DYYYShouldDisableAllHDR() ? YES : forbid);
}

- (BOOL)enableUseSDR2HDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEnableUseSDR2HDR:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook AWEPlayInteractionUserAvatarElement
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYFollowTips")) {
        // 获取用户信息
        AWEUserModel *author = nil;
        NSString *nickname = @"";
        NSString *signature = @"";
        NSString *avatarURL = @"";

        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) {
                author = [model valueForKey:@"author"];
            }
        }

        if (author) {
            // 获取昵称
            if ([author respondsToSelector:@selector(nickname)]) {
                nickname = [author valueForKey:@"nickname"] ?: @"";
            }

            // 获取签名
            if ([author respondsToSelector:@selector(signature)]) {
                signature = [author valueForKey:@"signature"] ?: @"";
            }

            // 获取头像URL
            if ([author respondsToSelector:@selector(avatarThumb)]) {
                AWEURLModel *avatarThumb = [author valueForKey:@"avatarThumb"];
                if (avatarThumb && avatarThumb.originURLList.count > 0) {
                    avatarURL = avatarThumb.originURLList.firstObject;
                }
            }
        }

        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }

        NSString *title = nickname.length > 0 ? nickname : @"关注确认";

        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:messageContent
                                      avatarURL:avatarURL
                               cancelButtonText:@"取消"
                              confirmButtonText:@"关注"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    %orig(gesture);
                                  }];
    } else {
        %orig;
    }
}

%end

%hook AWEPlayInteractionUserAvatarFollowController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYFollowTips")) {
        // 获取用户信息
        AWEUserModel *author = nil;
        NSString *nickname = @"";
        NSString *signature = @"";
        NSString *avatarURL = @"";

        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) {
                author = [model valueForKey:@"author"];
            }
        }

        if (author) {
            // 获取昵称
            if ([author respondsToSelector:@selector(nickname)]) {
                nickname = [author valueForKey:@"nickname"] ?: @"";
            }

            // 获取签名
            if ([author respondsToSelector:@selector(signature)]) {
                signature = [author valueForKey:@"signature"] ?: @"";
            }

            // 获取头像URL
            if ([author respondsToSelector:@selector(avatarThumb)]) {
                AWEURLModel *avatarThumb = [author valueForKey:@"avatarThumb"];
                if (avatarThumb && avatarThumb.originURLList.count > 0) {
                    avatarURL = avatarThumb.originURLList.firstObject;
                }
            }
        }

        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }

        NSString *title = nickname.length > 0 ? nickname : @"关注确认";

        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:messageContent
                                      avatarURL:avatarURL
                               cancelButtonText:@"取消"
                              confirmButtonText:@"关注"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    %orig(gesture);
                                  }];
    } else {
        %orig;
    }
}

%end

%hook XIGDanmakuPlayerView

- (id)initWithFrame:(CGRect)frame {
    id orig = %orig;

    ((UIView *)orig).tag = DYYY_IGNORE_GLOBAL_ALPHA_TAG;

    return orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYCommentShowDanmaku") && alpha == 0.0) {
        return;
    } else {
        %orig(alpha);
    }
}

%end

%hook DDanmakuPlayerView

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYCommentShowDanmaku") && alpha == 0.0) {
        return;
    } else {
        %orig(alpha);
    }
}

%end

%hook AWEPlayInteractionProgressContainerView
- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    static char kDYProgressBgKey;
    NSArray *bgViews = objc_getAssociatedObject(self, &kDYProgressBgKey);
    if (!bgViews) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [tmp addObject:subview];
            }
        }
        bgViews = [tmp copy];
        objc_setAssociatedObject(self, &kDYProgressBgKey, bgViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *v in bgViews) {
        v.backgroundColor = [UIColor clearColor];
    }
}

%end

%hook AWEPlayInteractionTimestampElement

- (id)timestampLabel {
    UILabel *label = %orig;
    BOOL isEnableArea = DYYYGetBool(@"DYYYEnableArea");
    if (!isEnableArea) {
        return label;
    }

    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelColor"];
    if (DYYYGetBool(@"DYYYEnableRandomGradient")) {
        labelColorHex = @"random_gradient";
    }

    BOOL boldEnabled = DYYYGetBool(@"DYYYBoldTimestamp");
    if (boldEnabled && label.font) {
        UIFont *boldFont = [UIFont boldSystemFontOfSize:label.font.pointSize];
        label.font = boldFont;
    }

    NSString *cityCode = self.model.cityCode;
    NSString *regionCode = nil;
    if ([self.model respondsToSelector:@selector(region)]) {
        regionCode = [self.model performSelector:@selector(region)];
    }

    if (cityCode && ([cityCode isEqualToString:@"0"] || [cityCode integerValue] == 0)) {
        cityCode = nil;
    }

    static NSCache *locationCache;
    static NSMutableSet *inFlight;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locationCache = [[NSCache alloc] init];
        locationCache.countLimit = 100;
        inFlight = [[NSMutableSet alloc] init];
    });

    void (^updateLabelWithLocation)(UILabel *, NSString *) = ^(UILabel *lbl, NSString *location) {
        if (location.length == 0) return;

        NSString *currentText = lbl.text ?: @"";
        if ([currentText containsString:location]) return;

        if ([currentText containsString:@"IP属地："]) {
            NSRange range = [currentText rangeOfString:@"IP属地："];
            NSString *baseText = [currentText substringToIndex:range.location];
            lbl.text = [NSString stringWithFormat:@"%@IP属地：%@", baseText, location];
        } else if (currentText.length > 0) {
            lbl.text = [NSString stringWithFormat:@"%@  IP属地：%@", currentText, location];
        }

        [DYYYUtils applyColorSettingsToLabel:lbl colorHexString:labelColorHex];
    };

    if (cityCode.length == 0 && regionCode.length == 0) {
        updateLabelWithLocation(label, @"未知地区");
        return label;
    }

    NSString *cacheKey = cityCode.length > 0 ? cityCode : regionCode;

    NSString *cachedLocation = [locationCache objectForKey:cacheKey];
    if (cachedLocation) {
        updateLabelWithLocation(label, cachedLocation);

        NSString *ipScaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
        if (ipScaleValue.length > 0) {
            UIFont *originalFont = label.font;
            CGFloat offset = DYYYGetFloat(@"DYYYIPLabelVerticalOffset");
            if (offset > 0) {
                label.transform = CGAffineTransformMakeTranslation(0, -offset);
            } else {
                label.transform = CGAffineTransformMakeTranslation(0, -3);
            }
            label.font = originalFont;
        }
        return label;
    }

    NSString *displayLocation = nil;

    if (cityCode.length > 0) {
        displayLocation = [CityManager.sharedInstance getCityNameWithCode:cityCode];

        if (!displayLocation) {
            @synchronized(inFlight) {
                if ([inFlight containsObject:cityCode]) {
                    return label;
                }
                [inFlight addObject:cityCode];
            }

            [CityManager fetchLocationWithGeonameId:cityCode completionHandler:^(NSDictionary *locationInfo, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized(inFlight) {
                        [inFlight removeObject:cityCode];
                    }

                    NSString *apiLocation = nil;

                    if (!error && locationInfo) {
                        NSString *localName = locationInfo[@"name"];
                        NSString *adminName1 = locationInfo[@"adminName1"];
                        NSString *countryName = locationInfo[@"countryName"];

                        if (![localName isKindOfClass:[NSString class]]) {
                            localName = nil;
                        }
                        if (![adminName1 isKindOfClass:[NSString class]]) {
                            adminName1 = nil;
                        }
                        if (![countryName isKindOfClass:[NSString class]]) {
                            countryName = nil;
                        }

                        if (countryName.length > 0) {
                            if (adminName1.length > 0 && localName.length > 0 && ![countryName isEqualToString:localName]) {
                                if ([adminName1 isEqualToString:localName]) {
                                    apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                                } else {
                                    apiLocation = [NSString stringWithFormat:@"%@ %@ %@", countryName, adminName1, localName];
                                }
                            } else if (localName.length > 0 && ![countryName isEqualToString:localName]) {
                                apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                            } else if (adminName1.length > 0 && ![countryName isEqualToString:adminName1]) {
                                apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, adminName1];
                            } else {
                                apiLocation = countryName;
                            }
                        } else if (localName.length > 0) {
                            apiLocation = localName;
                        } else if (adminName1.length > 0) {
                            apiLocation = adminName1;
                        }
                    }

                    if (apiLocation.length > 0) {
                        [locationCache setObject:apiLocation forKey:cacheKey];
                        updateLabelWithLocation(label, apiLocation);
                    } else {
                        if (regionCode.length > 0) {
                            NSString *fallbackCountry = [CityManager.sharedInstance getCountryNameWithCode:regionCode];
                            updateLabelWithLocation(label, fallbackCountry);
                        }
                    }
                });
            }];

            return label;
        }
    }

    if (!displayLocation && !cityCode && regionCode.length > 0) {
        displayLocation = [CityManager.sharedInstance getCountryNameWithCode:regionCode];
    }

    if (!displayLocation) {
        displayLocation = @"未知地区";
        updateLabelWithLocation(label, displayLocation);
        return label;
    }

    [locationCache setObject:displayLocation forKey:cacheKey];
    updateLabelWithLocation(label, displayLocation);

    NSString *ipScaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
    if (ipScaleValue.length > 0) {
        UIFont *originalFont = label.font;
        CGFloat offset = DYYYGetFloat(@"DYYYIPLabelVerticalOffset");
        if (offset > 0) {
            label.transform = CGAffineTransformMakeTranslation(0, -offset);
        } else {
            label.transform = CGAffineTransformMakeTranslation(0, -3);
        }
        label.font = originalFont;
    }
    return label;
}

+ (BOOL)shouldActiveWithData:(id)arg1 context:(id)arg2 {
    return DYYYGetBool(@"DYYYEnableArea");
}

%end

%hook AWEPlayInteractionProgressController

%new
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (progressSlider && [progressSlider respondsToSelector:@selector(dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:self.model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

%hook AWEPlayInteractionDescriptionScrollView

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

%hook AWEPlayInteractionDescriptionLabel

static char kLongPressGestureKey;
static NSString *const kDYYYLongPressCopyEnabledKey = @"DYYYLongPressCopyTextEnabled";

- (void)didMoveToWindow {
    %orig;

    BOOL longPressCopyEnabled = DYYYGetBool(kDYYYLongPressCopyEnabledKey);

    if (![[NSUserDefaults standardUserDefaults] objectForKey:kDYYYLongPressCopyEnabledKey]) {
        longPressCopyEnabled = NO;
        [DYYYPreferences setBool:NO forKey:kDYYYLongPressCopyEnabledKey];
    }

    UIGestureRecognizer *existingGesture = objc_getAssociatedObject(self, &kLongPressGestureKey);
    if (existingGesture && !longPressCopyEnabled) {
        [self removeGestureRecognizer:existingGesture];
        objc_setAssociatedObject(self, &kLongPressGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (longPressCopyEnabled && !objc_getAssociatedObject(self, &kLongPressGestureKey)) {
        UILongPressGestureRecognizer *highPriorityLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHighPriorityLongPress:)];
        highPriorityLongPress.minimumPressDuration = 0.3;

        [self addGestureRecognizer:highPriorityLongPress];

        UIView *currentView = self;
        while (currentView.superview) {
            currentView = currentView.superview;

            for (UIGestureRecognizer *recognizer in currentView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]] || [recognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
                    [recognizer requireGestureRecognizerToFail:highPriorityLongPress];
                }
            }
        }

        objc_setAssociatedObject(self, &kLongPressGestureKey, highPriorityLongPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return NO;
    }
    return YES;
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

%new
- (void)handleHighPriorityLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {

        NSString *description = self.text;

        if (description.length > 0) {
            [[UIPasteboard generalPasteboard] setString:description];
            [DYYYToast showSuccessToastWithMessage:@"视频文案已复制"];
        }
    }
}

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement

- (void)elementTapped {
    if (!DYYYGetBool(@"DYYYCommentCopyText")) {
        %orig;
        return;
    }

    AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
    AWECommentModel *selectdComment = [commentPageContext selectdComment];
    if (!selectdComment) {
        AWECommentLongPressPanelParam *params = [commentPageContext params];
        selectdComment = [params selectdComment];
    }
    NSString *descText = [selectdComment content];
    if (descText.length == 0) {
        %orig;
        return;
    }

    [[UIPasteboard generalPasteboard] setString:descText];
    [DYYYToast showSuccessToastWithMessage:@"评论已复制"];
}
%end

%hook AWELongPressPanelDataManager
+ (BOOL)enableModernLongPressPanelConfigWithSceneIdentifier:(id)arg1 {
    return DYYYGetBool(@"DYYYEnableModernPanel");
}
%end

%hook AWELongPressPanelABSettings
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

%hook AWEModernLongPressPanelUIConfig
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

%hook AWEPlayInteractionSpeedController

static CGFloat currentLongPressSpeed = 0;
static CGFloat initialTouchX = 0;
static BOOL isGestureActive = NO;

- (CGFloat)longPressFastSpeedValue {
    float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");
    if (longPressSpeed == 0) {
        longPressSpeed = 2.0;
    }
    return longPressSpeed;
}

- (void)changeSpeed:(double)speed {
    float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");

    if (isGestureActive && currentLongPressSpeed > 0) {
        %orig(currentLongPressSpeed);
        return;
    }

    if (speed == 2.0 && longPressSpeed != 0 && longPressSpeed != 2.0) {
        %orig(longPressSpeed);
        return;
    }

    if (speed <= 1.0 && dyyyLongPressLockedSpeedActive) {
        DYYYEndLockedLongPressSpeedAndRestoreIfNeeded();
    }

    %orig(speed);
}

- (void)handleLongPressFastSpeed:(UILongPressGestureRecognizer *)gesture {
    BOOL enableSpeedGesture = DYYYGetBool(@"DYYYEnableLongPressSpeedGesture");
    CGPoint location = [gesture locationInView:gesture.view];
    static CGFloat initialTouchY = 0;
    BOOL isBeginning = gesture.state == UIGestureRecognizerStateBegan;
    BOOL isEnding = gesture.state == UIGestureRecognizerStateEnded ||
                    gesture.state == UIGestureRecognizerStateCancelled ||
                    gesture.state == UIGestureRecognizerStateFailed;

    if (isBeginning) {
        dyyyLongPressFastSpeedActive = YES;
        dyyyLongPressLockedSpeedActive = NO;
    } else if (isEnding) {
        isGestureActive = NO;
        currentLongPressSpeed = 0;
        initialTouchY = 0;
        dyyyLongPressFastSpeedActive = NO;
    }

    %orig;

    if (isEnding) {
        DYYYScheduleConfiguredPlaybackSpeedRestore();
    }

    if (!enableSpeedGesture) {
        return;
    }

    if (isBeginning) {
        initialTouchY = location.y;
        isGestureActive = YES;

        float longPressSpeed = DYYYGetFloat(@"DYYYLongPressSpeed");
        if (longPressSpeed == 0) {
            longPressSpeed = 2.0;
        }
        currentLongPressSpeed = longPressSpeed;
    }
    else if (gesture.state == UIGestureRecognizerStateChanged && isGestureActive) {
        CGFloat deltaY = location.y - initialTouchY;
        CGFloat threshold = 10.0;

        if (fabs(deltaY) > threshold) {
            CGFloat speedChange;
            speedChange = (deltaY > 0) ? 0.25 : -0.25;

            CGFloat newSpeed = currentLongPressSpeed + speedChange;
            newSpeed = MAX(0.5, MIN(3.0, newSpeed));

            if (newSpeed != currentLongPressSpeed) {
                currentLongPressSpeed = newSpeed;
                initialTouchY = location.y;
                [self changeSpeed:currentLongPressSpeed];
            }
        }
    }
}

- (void)handleLongPressLockedSpeedBegan {
    dyyyLongPressFastSpeedActive = YES;
    dyyyLongPressLockedSpeedActive = NO;
    %orig;
}

- (void)handleLongPressLockedDoubleSpeedChanged:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    dyyyLongPressFastSpeedActive = YES;
    dyyyLongPressLockedSpeedActive = NO;
    %orig(arg1, gesture);
}

- (void)handleLongPressLockedDoubleSpeedEnded:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    %orig(arg1, gesture);
    dyyyLongPressFastSpeedActive = NO;
    dyyyLongPressLockedSpeedActive = YES;
}

- (void)longPressSpeedControlDidChangeSpeed:(double)speed {
    %orig(speed);
    if (speed <= 1.0 && dyyyLongPressLockedSpeedActive) {
        DYYYEndLockedLongPressSpeedAndRestoreIfNeeded();
    }
}
%end

%group EnableStickerSaveMenu
static __weak YYAnimatedImageView *targetStickerView = nil;
static BOOL dyyyShouldUseLastStickerURL = NO;

%hook _TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellStickerComponent

- (void)handleLongPressWithGes:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([gesture.view isKindOfClass:%c(YYAnimatedImageView)]) {
            targetStickerView = (YYAnimatedImageView *)gesture.view;
            NSLog(@"DYYY 长按表情：%@", targetStickerView);
        } else {
            targetStickerView = nil;
        }
    }

    %orig;
}

%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl37CommentLongPressPanelSaveImageElement

- (BOOL)elementShouldShow {
    BOOL shouldShow = %orig;
    if (!DYYYGetBool(@"DYYYForceDownloadEmotion") && !DYYYGetBool(@"DYYYForceDownloadCommentAudio")) {
        return shouldShow;
    }
    AWECommentLongPressPanelContext *context = [self commentPageContext];
    AWECommentModel *selected = [context selectdComment] ?: [[context params] selectdComment];
    AWEIMStickerModel *sticker = [selected sticker];
    NSArray *originURLList = sticker.staticURLModel.originURLList;
    if (originURLList.count > 0) {
        return YES;
    }
    AWECommentAudioModel *audio = [selected audioModel];
    if (audio && audio.content) {
        return YES;
    }
    return shouldShow;
}

- (void)elementTapped {
    AWECommentLongPressPanelContext *context = [self commentPageContext];
    AWECommentLongPressPanelParam *params = [context params];
    AWECommentModel *comment = [context selectdComment] ?: [params selectdComment];
    
    // 判断保存类型(表情包/音频/图片)
    AWEIMStickerModel *sticker = [comment sticker];
    NSArray *stickerURLList = sticker.staticURLModel.originURLList;
    BOOL hasSticker = (stickerURLList.count > 0);

    AWECommentAudioModel *audio = [comment audioModel];
    BOOL hasAudio = (audio && audio.content);
    
    NSArray *imageList = nil;
    if ([comment respondsToSelector:@selector(imageList)]) {
        imageList = [comment imageList];
    }
    BOOL hasImages = (imageList && imageList.count > 0);
    
    // 表情包保存逻辑
    if (hasSticker && DYYYGetBool(@"DYYYForceDownloadEmotion")) {
        NSString *urlString = dyyyShouldUseLastStickerURL ? stickerURLList.lastObject : stickerURLList.firstObject;
        dyyyShouldUseLastStickerURL = NO;
        NSURL *stickerURL = [NSURL URLWithString:urlString];
        
        if (stickerURL) {
            [DYYYManager downloadMedia:stickerURL
                             mediaType:MediaTypeHeic
                                 audio:nil
                            completion:^(BOOL success) {
                              if (!success && stickerURLList.count > 1) {
                                  dyyyShouldUseLastStickerURL = YES;
                              }
                            }];
            return;
        }
    }

    // 音频保存逻辑
    if (hasAudio && DYYYGetBool(@"DYYYForceDownloadCommentAudio")) {
        NSString *audioContent = audio.content;
        
        NSString *userName = @"未知用户";
        if (comment.author && [comment.author respondsToSelector:@selector(nickname)]) {
            NSString *nickname = [comment.author performSelector:@selector(nickname)];
            if (nickname && nickname.length > 0) {
                userName = nickname;
            }
        }
        
        [DYYYManager downloadAndShareCommentAudio:audioContent
                                         userName:userName
                                       createTime:comment.createTime];
        return;
    }

    // 图片保存逻辑
    if (hasImages && DYYYGetBool(@"DYYYForceDownloadCommentImage")) {
        // 检查 is_pic_inflow 判断是保存全部还是单张
        // is_pic_inflow = 1: 点开具体图片后长按 -> 只保存当前图片
        // is_pic_inflow = 0: 直接在评论区长按 -> 保存全部图片
        NSDictionary *extraParams = [params extraParams];
        BOOL isPicInflow = NO;
        if (extraParams && [extraParams isKindOfClass:[NSDictionary class]]) {
            id isPicInflowValue = extraParams[@"is_pic_inflow"];
            if (isPicInflowValue) {
                isPicInflow = [isPicInflowValue integerValue] == 1;
            }
        }
        
        NSInteger currentIndex = -1; // -1 表示保存全部
        
        if (isPicInflow) {
            // 使用 DYYYUtils 封装的方法查找目标控制器
            UIViewController *topVC = [DYYYUtils topView];
            
            // 获取 Ivar 定义的类和目标控制器类
            Class ivarClass = NSClassFromString(@"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCellViewController");
            Class targetClass = NSClassFromString(@"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCommonImageCellViewController");
            
            if (ivarClass && targetClass && topVC) {
                Ivar multiIndexIvar = class_getInstanceVariable(ivarClass, "currentIndexInMultiImageList");
                if (multiIndexIvar) {
                    UIViewController *cellVC = [DYYYUtils findViewControllerOfClass:targetClass inViewController:topVC];
                    if (cellVC) {
                        ptrdiff_t offset = ivar_getOffset(multiIndexIvar);
                        NSInteger *ptr = (NSInteger *)((char *)(__bridge void *)cellVC + offset);
                        currentIndex = *ptr;
                    }
                }
            }
        }
        
        NSString *hint = (currentIndex >= 0) ? @"正在保存当前图片..." : 
            [NSString stringWithFormat:@"正在保存 %lu 张图片...", (unsigned long)imageList.count];
        [DYYYUtils showToast:hint];
        
        [DYYYManager saveCommentImages:imageList
                            currentIndex:currentIndex
                            completion:^(NSInteger successCount, NSInteger livePhotoCount, NSInteger failedCount) {
            NSMutableString *message = [NSMutableString stringWithFormat:@"成功保存 %ld 张", (long)successCount];
            if (livePhotoCount > 0) {
                [message appendFormat:@"\n(含 %ld 张实况照片)", (long)livePhotoCount];
            }
            if (failedCount > 0) {
                [message appendFormat:@"\n失败 %ld 张", (long)failedCount];
            }
            [DYYYUtils showToast:message];
        }];
        return;
    }
    
    // 默认行为
    %orig;
}

%end

%hook UIMenu

+ (instancetype)menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children {
    BOOL hasAddStickerOption = NO;
    BOOL hasSaveLocalOption = NO;

    for (UIMenuElement *element in children) {
        NSString *elementTitle = nil;

        if ([element isKindOfClass:%c(UIAction)]) {
            elementTitle = [(UIAction *)element title];
        } else if ([element isKindOfClass:%c(UICommand)]) {
            elementTitle = [(UICommand *)element title];
        }

        if ([elementTitle isEqualToString:@"添加到表情"]) {
            hasAddStickerOption = YES;
        } else if ([elementTitle isEqualToString:@"保存到相册"]) {
            hasSaveLocalOption = YES;
        }
    }

    if (hasAddStickerOption && !hasSaveLocalOption) {
        NSMutableArray *newChildren = [children mutableCopy];

        UIAction *saveAction = [%c(UIAction) actionWithTitle:@"保存到相册"
                                                                 image:nil
                                                            identifier:nil
                                                               handler:^(__kindof UIAction *_Nonnull action) {
                                                                 // 使用全局变量 targetStickerView 保存当前长按的表情
                                                                 if (targetStickerView) {
                                                                     [DYYYManager saveAnimatedSticker:targetStickerView];
                                                                 } else {
                                                                     [DYYYUtils showToast:@"无法获取表情视图"];
                                                                 }
                                                               }];

        [newChildren addObject:saveAction];
        return %orig(title, image, identifier, options, newChildren);
    }

    return %orig;
}

%end
%end

%hook AWEPlayInteractionStaticFollowAnimationView
- (void)layoutSubviews {
    %orig;
    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowSettingsInView((UIView *)self, nil);
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
    }
}
%end

%hook AWEPlayDanmakuInputContainView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDanmuButton")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWEShowPlayletCommentHeaderView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        self.hidden = YES;
        return;
    }
}

%end

%group CommentHeaderGeneralGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentHeaderGoodsGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentHeaderTemplateGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentBottomTipsVCGroup
%hook AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if (DYYYGetBool(@"DYYYHideCommentTips")) {
        ((UIViewController *)self).view.hidden = YES;
    }
}
%end
%end

%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideShareContentView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWEIMFeedVideoQuickReplayInputViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideReply")) {
        [self.view removeFromSuperview];
        return;
    }
}

%end

%hook AWEPlayInteractionListenFeedView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideMusicButton")) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
            return;
        }
    }
}

- (void)didMoveToWindow {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    }
}

- (void)didMoveToSuperview {
    %orig;

    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
}

%end

%hook AWEPlayInteractionElementMaskView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}

%end

%hook AWEPlayInteractionTemplateButton
- (id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return nil;
	}
	return %orig;
}

- (void)setButton:(id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return;  // 不设置按钮
	}
	%orig;
}
%end

%hook AWEPlayInteractionLiveExtendGuideView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook IESLivePreAnnouncementPanelViewNew
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideStickerView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEMixVideoDetailPlayListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

%end

%hook AWEPlayInteractionUserAvatarView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        DYYYHideAvatarVisualForSelector(self, NSSelectorFromString(@"userAvatarView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }

    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToWindow {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToSuperview {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateRightContainerElement {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_resetFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarFollowPromptController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }

    if (DYYYGetBool(@"DYYYFollowTips")) {
        AWEPlayInteractionUserAvatarContext *context = nil;
        if ([self respondsToSelector:@selector(userAvatarContext)]) {
            context = [self valueForKey:@"userAvatarContext"];
        }

        AWEUserModel *author = context.model.author;
        NSString *nickname = @"";
        NSString *signature = @"";
        NSString *avatarURL = @"";

        if (author) {
            if ([author respondsToSelector:@selector(nickname)]) {
                nickname = [author valueForKey:@"nickname"] ?: @"";
            }

            if ([author respondsToSelector:@selector(signature)]) {
                signature = [author valueForKey:@"signature"] ?: @"";
            }

            if ([author respondsToSelector:@selector(avatarThumb)]) {
                AWEURLModel *avatarThumb = [author valueForKey:@"avatarThumb"];
                if (avatarThumb && avatarThumb.originURLList.count > 0) {
                    avatarURL = avatarThumb.originURLList.firstObject;
                }
            }
        }

        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }

        NSString *title = nickname.length > 0 ? nickname : @"关注确认";

        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:messageContent
                                      avatarURL:avatarURL
                               cancelButtonText:@"取消"
                              confirmButtonText:@"关注"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    %orig(gesture);
                                  }];
    } else {
        %orig;
    }
}

- (void)onUnFollowViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)followPromptViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowFollowAddWithModel:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSpecialFollowWithModel:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (void)showFollowAddView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateFollowStatus {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)followStatusChanged:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)_ensureStaticFollowAnimationView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarMainBusinessController
- (void)layoutElementView {
    %orig;
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        DYYYHideAvatarVisualForSelector(self, NSSelectorFromString(@"avatarPicView"));
        id context = DYYYAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DYYYHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarOptElementElement
- (void)layoutElementView {
    %orig;
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        id context = DYYYAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DYYYHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DYYYApplyAvatarSurroundingSettingsForOwner(self);
    }
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setAppear:(BOOL)appear {
    %orig(appear);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarStoryController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
}

- (void)showStory25RingView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
}
%end

%hook AWEPlayInteractionUserAvatarDecorationController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setDecorationStyle:(long long)style {
    %orig(style);
    DYYYApplyAvatarSurroundingSettingsForOwner(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarSendMessageController
- (void)controllerViewDidLayout {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerStartConfigAvatarView:(id)view {
    %orig(view);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)controllerWillDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerPlay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerReset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateSendMessageView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_updateSendMessageView:(BOOL)show {
    %orig(show);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_showSendMessageView:(id)view shouldShowSendMessageView:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (BOOL)shouldShowSendMessageView {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarSendMsgController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidDisappear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showSendMessageView:(id)view show:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)showSendMessageViewWithAnimation:(BOOL)animated {
    %orig(animated);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowSendMessageView:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)updateSendMsgWithFollowShow:(BOOL)show animation:(BOOL)animated {
    %orig(show, animated);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarEnterStoreController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showEnterStore {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)hideEnterStore {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowEnterStoreView {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowEnterStoreGuideAnimation {
    if (DYYYAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playEnterStoreGuideAnimationIfNeeded {
    if (DYYYAvatarFollowOptionsEnabled()) {
        DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onEnterStoreViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarAdLinkController
- (void)layoutElementView {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateCommerceHotSplashLinkIconImageIfNeeded:(id)arg1 {
    %orig(arg1);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onLinkIconContainerViewClicked:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionViewController

- (void)performCommentAction {
    %orig;
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setIsCommentVCShowing:(BOOL)showing {
    %orig(showing);
    DYYYApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onPlayer:(id)arg0 didDoubleClick:(id)arg1 {
    BOOL isPopupEnabled = DYYYGetBool(@"DYYYEnableDoubleTapMenu");
    BOOL isDirectCommentEnabled = DYYYGetBool(@"DYYYEnableDoubleOpenComment");

    // 直接打开评论区的情况
    if (isDirectCommentEnabled) {
        [self performCommentAction];
        return;
    }

    if (isPopupEnabled) {
        AWEAwemeModel *awemeModel = nil;

        awemeModel = [self performSelector:@selector(awemeModel)];

        AWEVideoModel *videoModel = awemeModel.video;
        AWEMusicModel *musicModel = awemeModel.music;
        NSURL *audioURL = nil;
        if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
            audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
        }

        // 确定内容类型（视频或图片）
        BOOL isImageContent = (awemeModel.awemeType == 68);
        // 判断是否为新版实况照片
        BOOL isNewLivePhoto = (awemeModel.video && awemeModel.animatedImageVideoInfo != nil);
        NSString *downloadTitle;

        if (isImageContent) {
            AWEImageAlbumImageModel *currentImageModel = nil;
            if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
            } else {
                currentImageModel = awemeModel.albumImages.firstObject;
            }

            if (awemeModel.albumImages.count > 1) {
                downloadTitle = (currentImageModel.clipVideo != nil || awemeModel.isLivePhoto) ? @"保存当前实况" : @"保存当前图片";
            } else {
                downloadTitle = (currentImageModel.clipVideo != nil || awemeModel.isLivePhoto) ? @"保存实况" : @"保存图片";
            }
        } else if (isNewLivePhoto) {
            downloadTitle = @"保存实况";
        } else {
            downloadTitle = @"保存视频";
        }

        AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
        NSMutableArray *actions = [NSMutableArray array];

        // 添加下载选项
        if (DYYYGetBool(@"DYYYDoubleTapDownload") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownload"]) {

            AWEUserSheetAction *downloadAction = [NSClassFromString(@"AWEUserSheetAction")
                actionWithTitle:downloadTitle
                        imgName:nil
                        handler:^{
                          if (isImageContent) {
                              // 图片内容
                              AWEImageAlbumImageModel *currentImageModel = nil;
                              if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                                  currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
                              } else {
                                  currentImageModel = awemeModel.albumImages.firstObject;
                              }

                              // 查找非.image后缀的URL
                              NSURL *downloadURL = nil;
                              for (NSString *urlString in currentImageModel.urlList) {
                                  NSURL *url = [NSURL URLWithString:urlString];
                                  NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                  if (![pathExtension isEqualToString:@"image"]) {
                                      downloadURL = url;
                                      break;
                                  }
                              }

                              if (currentImageModel.clipVideo != nil) {
                                  NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                  [DYYYManager downloadLivePhoto:downloadURL
                                                        videoURL:videoURL
                                                      completion:^{
                                                      }];
                              } else if (currentImageModel && currentImageModel.urlList.count > 0) {
                                  if (downloadURL) {
                                      [DYYYManager downloadMedia:downloadURL
                                                       mediaType:MediaTypeImage
                                                           audio:nil
                                                      completion:^(BOOL success) {
                                                        if (success) {
                                                        } else {
                                                            [DYYYUtils showToast:@"图片保存已取消"];
                                                        }
                                                      }];
                                  } else {
                                      [DYYYUtils showToast:@"没有找到合适格式的图片"];
                                  }
                              }
                          } else if (isNewLivePhoto) {
                              // 新版实况照片
                              // 使用封面URL作为图片URL
                              NSURL *imageURL = nil;
                              if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
                                  imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
                              }

                              // 视频URL从视频模型获取
                              NSURL *videoURL = nil;
                              if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
                                  videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
                              } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                                  videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                              }

                              // 下载实况照片
                              if (imageURL && videoURL) {
                                  [DYYYManager downloadLivePhoto:imageURL
                                                        videoURL:videoURL
                                                      completion:^{
                                                      }];
                              }
                          } else {
                              if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                                  NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                                  [DYYYManager downloadMedia:url
                                                   mediaType:MediaTypeVideo
                                                       audio:audioURL
                                                  completion:^(BOOL success){
                                                  }];
                              }
                          }
                        }];
            [actions addObject:downloadAction];

            // 如果是图集，添加下载所有图片选项
            if (isImageContent && awemeModel.albumImages.count > 1) {
                // 检查是否有实况照片
                BOOL hasLivePhoto = NO;
                for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                    if (imageModel.clipVideo != nil) {
                        hasLivePhoto = YES;
                        break;
                    }
                }

                NSString *actionTitle = hasLivePhoto ? @"保存所有实况" : @"保存所有图片";

                AWEUserSheetAction *downloadAllAction = [NSClassFromString(@"AWEUserSheetAction")
                    actionWithTitle:actionTitle
                            imgName:nil
                            handler:^{
                              NSMutableArray *imageURLs = [NSMutableArray array];
                              NSMutableArray *livePhotos = [NSMutableArray array];

                              for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                                  if (imageModel.urlList.count > 0) {
                                      // 查找非.image后缀的URL
                                      NSURL *downloadURL = nil;
                                      for (NSString *urlString in imageModel.urlList) {
                                          NSURL *url = [NSURL URLWithString:urlString];
                                          NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                          if (![pathExtension isEqualToString:@"image"]) {
                                              downloadURL = url;
                                              break;
                                          }
                                      }

                                      if (!downloadURL && imageModel.urlList.count > 0) {
                                          downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                                      }

                                      // 检查是否是实况照片
                                      if (imageModel.clipVideo != nil) {
                                          NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                          [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                                      } else {
                                          [imageURLs addObject:downloadURL.absoluteString];
                                      }
                                  }
                              }

                              // 分别处理普通图片和实况照片
                              if (livePhotos.count > 0) {
                                  [DYYYManager downloadAllLivePhotos:livePhotos];
                              }

                              if (imageURLs.count > 0) {
                                  [DYYYManager downloadAllImages:imageURLs];
                              }

                              if (livePhotos.count == 0 && imageURLs.count == 0) {
                                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
                              }
                            }];
                [actions addObject:downloadAllAction];
            }
        }

        // 添加下载音频选项
        if (DYYYGetBool(@"DYYYDoubleTapDownloadAudio") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownloadAudio"]) {

            AWEUserSheetAction *downloadAudioAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"保存音频"
                                                                                                        imgName:nil
                                                                                                        handler:^{
                                                                                                          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                                                                                                              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
                                                                                                              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
                                                                                                          }
                                                                                                        }];
            [actions addObject:downloadAudioAction];
        }

        // 添加接口保存选项
        if (DYYYGetBool(@"DYYYDoubleInterfaceDownload")) {
            NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
            if (apiKey.length > 0) {
                AWEUserSheetAction *apiDownloadAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"接口保存"
                                                                                                          imgName:nil
                                                                                                          handler:^{
                                                                                                            NSString *shareLink = [awemeModel valueForKey:@"shareURL"];
                                                                                                            if (shareLink.length == 0) {
                                                                                                                [DYYYUtils showToast:@"无法获取分享链接"];
                                                                                                                return;
                                                                                                            }

                                                                                                            // 使用封装的方法进行解析下载
                                                                                                            [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
                                                                                                          }];
                [actions addObject:apiDownloadAction];
            }
        }

        // 添加制作视频功能
        if (DYYYGetBool(@"DYYYDoubleCreateVideo") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleCreateVideo"]) {
            if (isImageContent) {
                AWEUserSheetAction *createVideoAction = [NSClassFromString(@"AWEUserSheetAction")
                    actionWithTitle:@"制作视频"
                            imgName:nil
                            handler:^{
                              // 收集普通图片URL
                              NSMutableArray *imageURLs = [NSMutableArray array];
                              // 收集实况照片信息（图片URL+视频URL）
                              NSMutableArray *livePhotos = [NSMutableArray array];

                              // 获取背景音乐URL
                              NSString *bgmURL = nil;
                              if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                                  bgmURL = musicModel.playURL.originURLList.firstObject;
                              }

                              // 处理所有图片和实况
                              for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                                  if (imageModel.urlList.count > 0) {
                                      // 查找非.image后缀的URL
                                      NSString *bestURL = nil;
                                      for (NSString *urlString in imageModel.urlList) {
                                          NSURL *url = [NSURL URLWithString:urlString];
                                          NSString *pathExtension = [url.path.lowercaseString pathExtension];
                                          if (![pathExtension isEqualToString:@"image"]) {
                                              bestURL = urlString;
                                              break;
                                          }
                                      }

                                      if (!bestURL && imageModel.urlList.count > 0) {
                                          bestURL = imageModel.urlList.firstObject;
                                      }

                                      // 如果是实况照片，需要收集图片和视频URL
                                      if (imageModel.clipVideo != nil) {
                                          NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                                          if (videoURL) {
                                              [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                                          }
                                      } else {
                                          // 普通图片
                                          [imageURLs addObject:bestURL];
                                      }
                                  }
                              }

                              // 调用视频创建API
                              [DYYYManager createVideoFromMedia:imageURLs
                                  livePhotos:livePhotos
                                  bgmURL:bgmURL
                                  progress:^(NSInteger current, NSInteger total, NSString *status) {
                                  }
                                  completion:^(BOOL success, NSString *message) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                                    }
                                  }];
                            }];
                [actions addObject:createVideoAction];
            }
        }

        // 添加复制文案选项
        if (DYYYGetBool(@"DYYYDoubleTapCopyDesc") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapCopyDesc"]) {

            AWEUserSheetAction *copyTextAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"复制文案"
                                                                                                   imgName:nil
                                                                                                   handler:^{
                                                                                                     NSString *descText = [awemeModel valueForKey:@"descriptionString"];
                                                                                                     [[UIPasteboard generalPasteboard] setString:descText];
                                                                                                     [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
                                                                                                   }];
            [actions addObject:copyTextAction];
        }

        // 添加打开评论区选项
        if (DYYYGetBool(@"DYYYDoubleTapComment") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapComment"]) {

            AWEUserSheetAction *openCommentAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"打开评论"
                                                                                                      imgName:nil
                                                                                                      handler:^{
                                                                                                        [self performCommentAction];
                                                                                                      }];
            [actions addObject:openCommentAction];
        }

        // 添加分享选项
        if (DYYYGetBool(@"DYYYDoubleTapshowSharePanel") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapshowSharePanel"]) {

            AWEUserSheetAction *showSharePanel = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"分享视频"
                                                                                                   imgName:nil
                                                                                                   handler:^{
                                                                                                     [self showSharePanel];
                                                                                                   }];
            [actions addObject:showSharePanel];
        }

        // 添加点赞视频选项
        if (DYYYGetBool(@"DYYYDoubleTapLike") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapLike"]) {

            AWEUserSheetAction *likeAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"点赞视频"
                                                                                               imgName:nil
                                                                                               handler:^{
                                                                                                 [self performLikeAction];
                                                                                               }];
            [actions addObject:likeAction];
        }

        // 添加长按面板
        if (DYYYGetBool(@"DYYYDoubleTapshowDislikeOnVideo") || ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapshowDislikeOnVideo"]) {

            AWEUserSheetAction *showDislikeOnVideo = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"长按面板"
                                                                                                       imgName:nil
                                                                                                       handler:^{
                                                                                                         [self showDislikeOnVideo];
                                                                                                       }];
            [actions addObject:showDislikeOnVideo];
        }

        // 显示操作表
        [actionSheet setActions:actions];
        [actionSheet show];

        return;
    }

    // 默认行为
    %orig;
}

%end

%hook AWEPlayInteractionViewController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = DYYYGetBool(@"DYYYDisableDoubleTapLike");
    if (!isSwitchOn) {
        %orig;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isInPlayInteractionVC = YES;
    dyyyCurrentSpeedAweme = self.model;
    DYYYRestoreFloatSpeedButtonForAwemeIfNeeded(self.model);
    DYYYEnsureFloatSpeedButton(self);
    reloadClearButtonConfiguration();
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (self.view.window && !self.view.hidden) {
        DYYYEnsureFloatSpeedButton(self);
        reloadClearButtonConfiguration();
    } else {
        [FloatingSpeedButton reloadConfiguration];
        updateClearButtonVisibility();
    }

    UIWindow *keyWindow = [DYYYUtils getActiveWindow];
    if (keyWindow && keyWindow.safeAreaInsets.bottom == 0) {
        return;
    }

    if (!DYYYGetBool(@"DYYYEnableFullScreen")) {
        return;
    }

    UIViewController *directParentVC = self.parentViewController;
    UIViewController *parentVC = directParentVC;
    int maxIterations = 3;
    int count = 0;

    while (parentVC && count < maxIterations) {
        if ([parentVC isKindOfClass:%c(AFDPlayRemoteFeedTableViewController)]) {
            return;
        }
        parentVC = parentVC.parentViewController;
        count++;
    }

    if (!self.view.superview) {
        return;
    }

    CGRect frame = self.view.frame;
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat superviewHeight = self.view.superview.frame.size.height;

    if (frame.size.width != screenWidth && frame.size.height < superviewHeight) {
        return;
    }

    NSString *currentReferString = self.referString;

    BOOL useFullHeight = [currentReferString isEqualToString:@"general_search"] || [currentReferString isEqualToString:@"search_result"] || [currentReferString isEqualToString:@"search_ecommerce"] ||
                         [currentReferString isEqualToString:@"close_friends_moment"] || [currentReferString isEqualToString:@"offline_mode"] || [currentReferString isEqualToString:@"challenge"] ||
                         [currentReferString isEqualToString:@"general_search_scan"] || currentReferString == nil;

    if (!useFullHeight && [currentReferString isEqualToString:@"co_play_watch"]) {
        Class richContentVCClass = NSClassFromString(@"AWEFriendsImpl.RichContentNewListViewController");
        if (richContentVCClass && [directParentVC isKindOfClass:richContentVCClass]) {
            useFullHeight = YES;
        }
    }

    if (!useFullHeight && [currentReferString isEqualToString:@"chat"]) {
        NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (currentVersion.length == 0) {
            Class managerClass = %c(AWEVersionUpdateManager);
            if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
                AWEVersionUpdateManager *manager = [managerClass sharedInstance];
                if ([manager respondsToSelector:@selector(currentVersion)]) {
                    currentVersion = manager.currentVersion;
                }
            }
        }

        // 39.2.0 及更早版本的私信播放页以完整高度布局信息区，否则底部约束会整体上移。 （靠版本号判断不靠谱，这个是 abtest 的）
        if (currentVersion.length > 0 && [DYYYUtils compareVersion:currentVersion toVersion:@"39.2.0"] != NSOrderedDescending) {
            useFullHeight = YES;
        }
    }

    if (useFullHeight) {
        frame.size.height = superviewHeight;
    } else {
        frame.size.height = superviewHeight - gCurrentTabBarHeight;
    }

    if (fabs(frame.size.height - self.view.frame.size.height) > 0.5) {
        self.view.frame = frame;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (dyyyActiveSpeedInteractionController == self) {
        AWEPlayInteractionViewController *replacementController = DYYYResolveCurrentSpeedInteractionController(nil);
        if (replacementController && replacementController != self) {
            DYYYEnsureFloatSpeedButton(replacementController);
        } else {
            dyyyActiveSpeedInteractionController = nil;
            dyyyInteractionViewVisible = NO;
            dyyyCommentViewVisible = self.isCommentVCShowing;
            updateSpeedButtonVisibility();
            dispatch_async(dispatch_get_main_queue(), ^{
              DYYYEnsureFloatSpeedButton(nil);
            });
        }
        updateClearButtonVisibility();
    }
}

%new
- (void)speedButtonTapped:(UIButton *)sender {
    [(FloatingSpeedButton *)sender resetFadeTimer];
    NSArray *speeds = getSpeedOptions();
    if (speeds.count == 0)
        return;

    NSInteger currentIndex = getCurrentSpeedIndex();
    NSInteger newIndex = (currentIndex + 1) % speeds.count;

    setCurrentSpeedIndex(newIndex);

    float newSpeed = [speeds[newIndex] floatValue];
    updateSpeedButtonUI();
    DYYYClearLongPressSpeedState();

    [UIView animateWithDuration:0.1
        delay:0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
          sender.transform = CGAffineTransformMakeScale(1.1, 1.1);
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:0.1
                                delay:0
                              options:UIViewAnimationOptionCurveEaseIn
                           animations:^{
                             sender.transform = CGAffineTransformIdentity;
                           }
                           completion:nil];
        }];

    AWEPlayInteractionViewController *currentController = DYYYResolveCurrentSpeedInteractionController(self);
    if (currentController) {
        speedButton.interactionController = currentController;
    }
    if (!DYYYApplyPlaybackSpeed(currentController, newSpeed)) {
        [DYYYUtils showToast:@"无法找到视频控制器"];
    }
}

%new
- (void)buttonTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.1
                     animations:^{
                       sender.alpha = 0.7;
                       sender.transform = CGAffineTransformMakeScale(0.95, 0.95);
                     }];
}

%new
- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.1
                     animations:^{
                       sender.alpha = 1.0;
                       sender.transform = CGAffineTransformIdentity;
                     }];
}

%end

%hook AWEAwemePlayVideoViewController

- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }

    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AWEDPlayerFeedPlayerViewController

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        UIView *contentView = self.contentView;
        if (contentView && contentView.superview) {
            CGRect frame = contentView.frame;
            CGFloat parentHeight = contentView.superview.frame.size.height;

            if (frame.size.height == parentHeight - gCurrentTabBarHeight) {
                frame.size.height = parentHeight;
                contentView.frame = frame;
            } else if (frame.size.height == parentHeight - (gCurrentTabBarHeight * 2)) {
                frame.size.height = parentHeight - gCurrentTabBarHeight;
                contentView.frame = frame;
            }
        }
    }
}

- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AWEDPlayerViewController_Merge

- (BOOL)enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        UIView *contentView = self.contentView;
        if (contentView && contentView.superview) {
            CGRect frame = contentView.frame;
            CGFloat parentHeight = contentView.superview.frame.size.height;

            if (frame.size.height == parentHeight - gCurrentTabBarHeight) {
                frame.size.height = parentHeight;
                contentView.frame = frame;
            } else if (frame.size.height == parentHeight - (gCurrentTabBarHeight * 2)) {
                frame.size.height = parentHeight - gCurrentTabBarHeight;
                contentView.frame = frame;
            }
        }
    }
}

- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
}

- (void)prepareForDisplay {
    %orig;
    if (!DYYYShouldHandleSpeedFeatures()) {
        return;
    }
    DYYYApplyPreparedPlaybackSpeedToPlayer(self);
    updateSpeedButtonUI();
}

%new
- (void)adjustPlaybackSpeed:(float)speed {
    [self setVideoControllerPlaybackRate:speed];
}

%end

%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    static char kDYFastSpeedBgKey;
    NSArray *bgViews = objc_getAssociatedObject(self, &kDYFastSpeedBgKey);
    if (!bgViews) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [tmp addObject:subview];
            }
        }
        bgViews = [tmp copy];
        objc_setAssociatedObject(self, &kDYFastSpeedBgKey, bgViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *view in bgViews) {
        view.backgroundColor = [UIColor clearColor];
    }
}
%end

%hook TTPlayerView

- (void)layoutSubviews {
    %orig;
    UIView *parent = self.superview;
    if (parent) {
        parent.backgroundColor = self.backgroundColor;
    }
}

%end

%hook AWEMixVideoPanelMoreView

- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat targetY = frame.origin.y - gCurrentTabBarHeight;
        CGFloat screenHeightMinusGDiff = [UIScreen mainScreen].bounds.size.height - gCurrentTabBarHeight;

        CGFloat tolerance = 10.0;

        if (fabs(targetY - screenHeightMinusGDiff) <= tolerance) {
            frame.origin.y = targetY;
        }
    }
    %orig(frame);
}

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        self.backgroundColor = [UIColor clearColor];
    }
}

%end

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    for (UIView *subview in self.subviews) {
        if ([subview isMemberOfClass:[UIView class]]) {
            UIColor *bgColor = subview.backgroundColor;
            if (bgColor) {
                CGFloat h, s, v, a;
                if ([bgColor getHue:&h saturation:&s brightness:&v alpha:&a]) {
                    if (v < 0.2) {
                        subview.backgroundColor = [UIColor clearColor];
                    }
                }
            }
        }
    }
}

%end
