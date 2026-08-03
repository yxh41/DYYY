//
//  DYYY - 自动拆分片段（由 DYYY.xm 通过 #include 引入，勿单独编译）
//  分类: DYYYFeed
//

%hook AWEFeedABTestServiceObjc

+ (BOOL)enableProfilePreloadHDRBrightnessFilter {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook IESLiveAudienceHDRController

+ (BOOL)currentHDRStatusForRoomID:(id)roomID {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isCurrentRoomSupportHDR:(id)roomID roomModel:(id)roomModel {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isFeedCanEnableHDRFeature {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isInnerFeedCanEnableHDRFeature {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)isUserEnableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)p_isHDRFeatureEnable {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (void)setUserEnableHDR:(BOOL)enableHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

+ (BOOL)shouldShowHDRSwitchForRoom:(id)room {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook IESLiveUserSeqlistFragment

- (void)refreshVerticalUserCount:(id)arg1 horizontalUserCount:(id)arg2 trueValue:(NSInteger)trueValue {
    if ( trueValue > 0 && DYYYGetBool(@"DYYYEnableLiveRealCount") ) {
        NSString *realStr = [NSString stringWithFormat:@"%ld", (long)trueValue];
        %orig(realStr, realStr, trueValue);
    } else {
        %orig;
    }
}

%end

%hook AWEFeedChannelManager

- (void)reloadChannelWithChannelModels:(id)arg1 currentChannelIDList:(id)arg2 reloadType:(id)arg3 selectedChannelID:(id)arg4 {
    NSArray *channelModels = arg1;
    NSMutableArray *newChannelModels = [NSMutableArray array];
    NSArray *currentChannelIDList = arg2;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *newCurrentChannelIDList = [NSMutableArray arrayWithArray:currentChannelIDList];

    if (!arg1 || !arg2) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    if (![channelModels isKindOfClass:[NSArray class]] || ![currentChannelIDList isKindOfClass:[NSArray class]]) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    if (channelModels.count == 0) {
        %orig(arg1, arg2, arg3, arg4);
        return;
    }

    for (AWEHPTopTabItemModel *tabItemModel in channelModels) {
        NSString *channelID = tabItemModel.channelID;
        BOOL isHideChannel = NO;

        if ([channelID isEqualToString:@"homepage_hot_container"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideHotContainer"];
        } else if ([channelID isEqualToString:@"homepage_follow"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFollow"];
        } else if ([channelID isEqualToString:@"homepage_mall"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMall"];
        } else if ([channelID isEqualToString:@"homepage_nearby"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideNearby"];
        } else if ([channelID isEqualToString:@"homepage_groupon"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideGroupon"];
        } else if ([channelID isEqualToString:@"homepage_tablive"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideTabLive"];
        } else if ([channelID isEqualToString:@"homepage_pad_hot"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHidePadHot"];
        } else if ([channelID isEqualToString:@"homepage_hangout"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideHangout"];
        } else if ([channelID isEqualToString:@"homepage_familiar"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFriend"];
        } else if ([channelID isEqualToString:@"homepage_playlet_stream"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHidePlaylet"];
        } else if ([channelID isEqualToString:@"homepage_pad_cinema"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideCinema"];
        } else if ([channelID isEqualToString:@"homepage_pad_kids_v2"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideKidsV2"];
        } else if ([channelID isEqualToString:@"homepage_pad_game"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideGame"];
        } else if ([channelID isEqualToString:@"homepage_mediumvideo"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMediumVideo"];
        }

        if (!isHideChannel) {
            [newChannelModels addObject:tabItemModel];
        } else {
            [newCurrentChannelIDList removeObject:channelID];
        }
    }

    %orig(newChannelModels, newCurrentChannelIDList, arg3, arg4);
}

%end

%hook AWEFeedProgressSlider

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);
}

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        if (DYYYGetBool(@"DYYYHideVideoProgress")) {
            %orig(0);
        } else {
            %orig(1.0);
        }
    } else {
        %orig;
    }
}

%new
- (NSString *)dyyy_formatTimeFromSeconds:(CGFloat)seconds {
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

%new
- (CGFloat)dyyy_modelDurationInSeconds {
    id delegate = self.progressSliderDelegate;
    if (!delegate || ![delegate respondsToSelector:@selector(model)]) {
        return 0;
    }

    id model = [delegate valueForKey:@"model"];
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) {
        return 0;
    }

    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) {
        return 0;
    }
    return videoDurationMs / 1000.0;
}

%new
- (CGFloat)dyyy_scheduleVerticalOffset {
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

%new
- (void)dyyy_removeScheduleLabels {
    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];
    [[parentView viewWithTag:10001] removeFromSuperview];
    [[parentView viewWithTag:10002] removeFromSuperview];
}

%new
- (void)dyyy_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        [self dyyy_removeScheduleLabels];
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
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

    CGFloat modelDuration = [self dyyy_modelDurationInSeconds];
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
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyyy_scheduleVerticalOffset];
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
            newLeftText = [self dyyy_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyyy_formatTimeFromSeconds:effectiveCurrentTime], [self dyyy_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyyy_formatTimeFromSeconds:effectiveCurrentTime];
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
            newRightText = [self dyyy_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyyy_formatTimeFromSeconds:effectiveCurrentTime], [self dyyy_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyyy_formatTimeFromSeconds:effectiveTotalDuration];
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

- (void)setLimitUpperActionArea:(BOOL)arg1 {
    %orig;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf dyyy_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
    });
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    BOOL hideVideoProgress = DYYYGetBool(@"DYYYHideVideoProgress");
    BOOL showScheduleDisplay = DYYYGetBool(@"DYYYShowScheduleDisplay");
    if (hideVideoProgress && showScheduleDisplay && !hidden) {
        self.alpha = 0;
    }
}

%end

%hook HTSLiveStreamPcdnManager

+ (void)start {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (!disablePCDN) {
        %orig;
    } else {
        NSLog(@"[DYYY] HTSLiveStreamPcdnManager start blocked");
    }
}

+ (void)configAndStartLiveIO {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (!disablePCDN) {
        %orig;
    } else {
        NSLog(@"[DYYY] HTSLiveStreamPcdnManager configAndStartLiveIO blocked");
    }
}

%end

%hook IESLiveLaunchTaskPcdn

- (void)excute {
    BOOL disablePCDN = DYYYGetBool(@"DYYYDisableLivePCDN");
    if (disablePCDN) {
        NSLog(@"[DYYY] IESLiveLaunchTaskPcdn excute blocked");
        return;
    }
    %orig;
}

%end

%hook HTSLiveStreamQualityFragment

- (void)setupStreamQuality:(id)arg1 {
    %orig;

    NSString *preferredQuality = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLiveQuality"];
    if (!preferredQuality || [preferredQuality isEqualToString:@"自动"]) {
        NSLog(@"[DYYY] Live quality auto - skipping hook");
        return;
    }

    BOOL preferLower = YES;
    NSLog(@"[DYYY] preferredQuality=%@ preferLower=%@", preferredQuality, @(preferLower));

    NSArray *qualities = self.streamQualityArray;
    if (!qualities || qualities.count == 0) {
        qualities = [self getQualities];
    }
    if (!qualities || qualities.count == 0) {
        return;
    }

    if (!dyyy_qualityRank) {
        dyyy_qualityRank = @[ @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清" ];
    }
    NSArray *orderedNames = dyyy_qualityRank;

    // Map available names to their indices in the provided order
    NSMutableDictionary<NSString *, NSNumber *> *nameToIndex = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *availableNames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rankArray = [NSMutableArray array];
    for (NSInteger i = 0; i < qualities.count; i++) {
        id q = qualities[i];
        NSString *name = nil;
        if ([q respondsToSelector:@selector(name)]) {
            name = [q name];
        } else {
            name = [q valueForKey:@"name"];
        }
        if (name) {
            [availableNames addObject:name];
            nameToIndex[name] = @(i);
            NSInteger rank = [orderedNames indexOfObject:name];
            if (rank != NSNotFound) {
                [rankArray addObject:@(rank)];
            }
        }
    }
    NSLog(@"[DYYY] available qualities: %@", availableNames);

    BOOL qualityDesc = YES; // ranks ascending -> high to low
    BOOL qualityAsc = YES;  // ranks descending -> low to high
    for (NSInteger i = 1; i < rankArray.count; i++) {
        NSInteger prev = rankArray[i - 1].integerValue;
        NSInteger curr = rankArray[i].integerValue;
        if (curr < prev) {
            qualityDesc = NO;
        }
        if (curr > prev) {
            qualityAsc = NO;
        }
    }

    NSInteger count = availableNames.count;
    NSInteger (^convertIndex)(NSInteger) = ^NSInteger(NSInteger idx) {
      if (qualityAsc && !qualityDesc) {
          return count - 1 - idx;
      }
      return idx;
    };

    NSArray *searchOrder = orderedNames;

    NSNumber *indexToUse = nameToIndex[preferredQuality];
    if (indexToUse) {
        NSInteger finalIdx = convertIndex(indexToUse.integerValue);
        NSLog(@"[DYYY] exact quality %@ found at index %ld", preferredQuality, (long)finalIdx);
        [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
        return;
    }

    NSInteger targetPos = [orderedNames indexOfObject:preferredQuality];
    if (targetPos == NSNotFound) {
        NSLog(@"[DYYY] preferred quality %@ not in list", preferredQuality);
        return;
    }

    NSInteger step = preferLower ? 1 : -1;
    BOOL applied = NO;
    for (NSInteger pos = targetPos + step; pos >= 0 && pos < searchOrder.count; pos += step) {
        NSString *candidate = searchOrder[pos];
        NSNumber *idx = nameToIndex[candidate];
        if (idx) {
            NSInteger finalIdx = convertIndex(idx.integerValue);
            NSLog(@"[DYYY] fallback quality %@ at index %ld", candidate, (long)finalIdx);
            [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
            applied = YES;
            break;
        }
    }
    if (!applied) {
        NSLog(@"[DYYY] no suitable fallback quality found");
    }
}

%end

%hook AWECommentImageModel
- (id)downloadUrl {
    if (DYYYGetBool(@"DYYYCommentNotWaterMark")) {
        return self.originUrl;
    }
    return %orig;
}
%end

%hook AWESearchAnchorListModel

- (BOOL)hideWords {
    return DYYYGetBool(@"DYYYHideCommentViews");
}

%end

%hook AWELiveAudienceContainerController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel config:(id)config {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)createAudienceViewController:(id)arg beginTime:(double)beginTime {
    %orig;
    __weak id weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakSelf);
    });
}

- (id)audienceControllerWithRoom:(id)room beginTime:(double)beginTime {
    id result = %orig;
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromContainer(weakSelf);
    });
    return result;
}

- (void)updateWithRoomModel:(id)roomModel config:(id)config {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    %orig;
    DYYYLiveDurationInstallFromContainer(self);
}

- (void)clearAudience {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)prepareForReuse {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DYYYLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook AWEFeedPauseRelatedWordComponent

- (id)updateViewWithModel:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (id)pauseContentWithModel:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (id)recommendsWords {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return nil;
    }
    return %orig;
}

- (void)showRelatedRecommendPanelControllerWithSelectedText:(id)arg0 {
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        return;
    }
    %orig;
}

- (void)setupUI {
    %orig;
    if (DYYYGetBool(@"DYYYHidePauseVideoRelatedWord")) {
        if (self.relatedView) {
            self.relatedView.hidden = YES;
        }
    }
}

%end

%hook AFDRecommendToFriendEntranceLabel
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendTips")) {
        if (self.accessibilityLabel) {
            [self removeFromSuperview];
        }
    }
}

%end

%hook AWELiveFeedStatusLabel
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideEnterLive")) {
        UIView *parentView = self.superview;
        UIView *grandparentView = parentView.superview;

        if (grandparentView) {
            grandparentView.hidden = YES;
            return;
        } else if (parentView) {
            parentView.hidden = YES;
            return;
        } else {
            self.hidden = YES;
            return;
        }
    }
    %orig;
}
%end

%hook IESECLiveCardSizeComponent
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveGameCPExplainCardContainerImpl
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook AWEAwemeModel

- (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = %orig;
    if (orig) {
        BOOL shouldDisableHDR = DYYYShouldDisableAllHDR();
        BOOL shouldFilterOnlyHDRSource = NO;
        if (shouldDisableHDR && ![self dyyy_shouldExcludeFromGlobalHDRFilter]) {
            shouldFilterOnlyHDRSource = DYYYAwemeModelHasOnlyHDRBitrateModels(self);
            if (!shouldFilterOnlyHDRSource) {
                shouldFilterOnlyHDRSource = DYYYRawObjectHasOnlyHDRBitrateModels(arg1);
                if (shouldFilterOnlyHDRSource) {
                    objc_setAssociatedObject(self, &kDYYYHDROnlyAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        BOOL shouldFilter = DYYYGetBool(@"DYYYNoAds") &&
                            ([DYYYUtils isAdvertisementAwemeModel:self] || [DYYYUtils isAdvertisementRawData:arg1]);
        if (!shouldFilter) {
            shouldFilter = [self contentFilter];
        }
        if (!shouldFilter && shouldFilterOnlyHDRSource) {
            shouldFilter = YES;
        }
        if (!shouldFilter && DYYYShouldFilterGlobalHDR() &&
            ![self dyyy_shouldExcludeFromGlobalHDRFilter] &&
            [self dyyy_containsHDRMetadataInObject:arg1 depth:0]) {
            shouldFilter = YES;
        }
        if (shouldFilter) {
            return nil;
        }
        if (shouldDisableHDR) {
            DYYYStripHDRHintsFromAwemeModel(self);
        }
    }
    return orig;
}

- (void)setVideo:(AWEVideoModel *)video {
    DYYYStripHDRHintsFromVideoModel(video);
    %orig;
}

- (AWEVideoModel *)video {
    return %orig;
}

- (void)setAlbumImages:(NSArray<AWEImageAlbumImageModel *> *)albumImages {
    if (DYYYShouldDisableAllHDR()) {
        for (AWEImageAlbumImageModel *imageModel in albumImages) {
            DYYYStripHDRHintsFromVideoModel(DYYYValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
    %orig;
}

- (NSArray<AWEImageAlbumImageModel *> *)albumImages {
    return %orig;
}

- (BOOL)awe_enableHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (id)awe_HDRValueFor:(long long)value enableHDR:(BOOL)enableHDR {
    return %orig(value, DYYYShouldDisableAllHDR() ? NO : enableHDR);
}

%new
- (BOOL)dyyy_shouldExcludeFromGlobalHDRFilter {
    NSString *referString = [self.referString lowercaseString];
    if (referString.length == 0) {
        return NO;
    }

    return [referString isEqualToString:@"chat"] ||
           [referString containsString:@"chat_room"] ||
           [referString containsString:@"message"] ||
           [referString containsString:@"forward"] ||
           [referString containsString:@"private"] ||
           [referString containsString:@"share"] ||
           [referString hasPrefix:@"im_"] ||
           [referString containsString:@"_im_"];
}

%new
- (BOOL)dyyy_containsHDRMetadataInObject:(id)object depth:(NSUInteger)depth {
    if (!object || depth > 8) {
        return NO;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [[rawKey description] lowercaseString];
            NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;

            if (([key isEqualToString:@"is_source_hdr"] || [key isEqualToString:@"has_filter_hdr"]) && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_type"] && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_bit"] && numericValue >= 10) {
                return YES;
            }
            if (([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) &&
                [self dyyy_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            if ([self dyyy_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    }

    return NO;
}

%new
- (BOOL)contentFilter {
    BOOL noAds = DYYYGetBool(@"DYYYNoAds");
    BOOL skipAllLive = DYYYGetBool(@"DYYYSkipAllLive");
    BOOL skipHotSpot = DYYYGetBool(@"DYYYSkipHotSpot");
    BOOL skipPhoto = DYYYGetBool(@"DYYYSkipPhoto");
    BOOL skipPhotoText = DYYYGetBool(@"DYYYSkipPhotoText");
    BOOL skipMusic = DYYYGetBool(@"DYYYSkipMusic");
    BOOL skipAIInteraction = DYYYGetBool(@"DYYYSkipAIInteraction");
    BOOL filterHDR = DYYYShouldFilterGlobalHDR();

    BOOL shouldFilterAds = noAds && [DYYYUtils isAdvertisementAwemeModel:self];
    BOOL shouldFilterHotSpot = skipHotSpot && self.hotSpotLynxCardModel;
    BOOL shouldFilterAllLive = skipAllLive && [self.videoFeedTag isEqualToString:@"直播中"];
    BOOL isRecommendFeed = [self.referString isEqualToString:@"homepage_hot"];
    BOOL shouldskipPhoto = skipPhoto && (self.awemeType == 68) && isRecommendFeed;
    BOOL shouldskipPhotoText = skipPhotoText && self.isNewTextMode && isRecommendFeed;
    BOOL shouldFilterMusic = skipMusic && self.musicCard && isRecommendFeed;
    BOOL shouldFilterAIInteraction = skipAIInteraction && (self.awemeType == 162) && isRecommendFeed;
    BOOL shouldFilterHDR = NO;
    BOOL shouldFilterLowLikes = NO;
    BOOL shouldFilterKeywords = NO;
    BOOL shouldFilterProp = NO;
    BOOL shouldFilterTime = NO;
    BOOL shouldFilterUser = NO;

    // 获取用户设置的需要过滤的关键词
    NSString *filterKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterKeywords"];
    NSArray *keywordsList = nil;

    if (filterKeywords.length > 0) {
        keywordsList = [filterKeywords componentsSeparatedByString:@","];
    }

    // 过滤包含指定拍同款的视频
    NSString *filterProp = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterProp"];
    NSArray *propKeywordsList = nil;

    if (filterProp.length > 0) {
        propKeywordsList = [filterProp componentsSeparatedByString:@","];
    }

    // 获取需要过滤的用户列表
    NSString *filterUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFilterUsers"];
    BOOL disableHDR = DYYYShouldDisableAllHDR();

    // 检查是否需要过滤特定用户
    if (isRecommendFeed && filterUsers.length > 0 && self.author) {
        NSArray *usersList = [filterUsers componentsSeparatedByString:@","];
        NSString *currentShortID = self.author.shortID;
        NSString *currentNickname = self.author.nickname;

        if (currentShortID.length > 0) {
            for (NSString *userInfo in usersList) {
                // 解析"昵称-id"格式
                NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                if (components.count >= 2) {
                    NSString *userId = [components lastObject];
                    NSString *userNickname = [[components subarrayWithRange:NSMakeRange(0, components.count - 1)] componentsJoinedByString:@"-"];

                    if ([userId isEqualToString:currentShortID]) {
                        shouldFilterUser = YES;
                        break;
                    }
                }
            }
        }
    }

    // 仅在推荐页过滤关键词和道具
    if (isRecommendFeed) {
        // 过滤包含特定关键词的视频
        if (keywordsList.count > 0) {
            // 检查视频标题
            if (self.descriptionString.length > 0) {
                for (NSString *keyword in keywordsList) {
                    NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedKeyword.length > 0 && [self.descriptionString containsString:trimmedKeyword]) {
                        shouldFilterKeywords = YES;
                        break;
                    }
                }
            }
        }

        // 过滤包含特定道具的视频
        if (propKeywordsList.count > 0 && self.propGuideV2) {
            NSString *propName = self.propGuideV2.propName;
            if (propName.length > 0) {
                for (NSString *propKeyword in propKeywordsList) {
                    NSString *trimmedKeyword = [propKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedKeyword.length > 0 && [propName containsString:trimmedKeyword]) {
                        shouldFilterProp = YES;
                        break;
                    }
                }
            }
        }
    }

    // 全局屏蔽 HDR 时，仍允许有 SDR 档的作品降档播放；纯 HDR 档作品直接过滤，避免黑屏或 HDR 漏出。
    if (disableHDR &&
        ![self dyyy_shouldExcludeFromGlobalHDRFilter] &&
        DYYYAwemeModelHasOnlyHDRBitrateModels(self)) {
        shouldFilterHDR = YES;
    }

    // 全场景过滤 HDR 作品，但保留私信、消息详情和转发链路。
    if (filterHDR && ![self dyyy_shouldExcludeFromGlobalHDRFilter] && self.video) {
        AWEVideoModel *video = self.video;
        if ([video respondsToSelector:@selector(isSourceHDR)] && video.isSourceHDR > 0) {
            shouldFilterHDR = YES;
        } else if ([video respondsToSelector:@selector(hasFilterHDR)] && video.hasFilterHDR) {
            shouldFilterHDR = YES;
        }

        if (!shouldFilterHDR) {
            for (id bitrateModel in video.bitrateModels) {
                @try {
                    NSNumber *hdrType = [bitrateModel valueForKey:@"hdrType"];
                    NSNumber *hdrBit = [bitrateModel valueForKey:@"hdrBit"];

                    // hdrType 覆盖 HDR10、HLG、HDR Vivid 等类型；无类型字段时保留 10bit 兜底。
                    if ((hdrType && [hdrType integerValue] > 0) ||
                        (!hdrType && hdrBit && [hdrBit integerValue] >= 10)) {
                        shouldFilterHDR = YES;
                        break;
                    }
                } @catch (__unused NSException *exception) {
                }
            }
        }
    }

    return shouldFilterAds || shouldFilterAllLive || shouldFilterHotSpot || shouldFilterMusic || shouldFilterHDR || shouldFilterKeywords || shouldFilterProp ||
           shouldFilterTime || shouldFilterUser;
}

- (AWEECommerceLabel *)ecommerceBelowLabel {
    if (DYYYGetBool(@"DYYYHideHisShop")) {
        return nil;
    }
    return %orig;
}

- (void)setEcommerceBelowLabel:(id)label {
	if (DYYYGetBool(@"DYYYHideHisShop")) {
		%orig(nil);
		return;
	}
	%orig;
}

- (void)setDescriptionString:(NSString *)desc {
    NSString *labelStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelStyle"];
    BOOL hideLabel = [labelStyle isEqualToString:@"文案标签隐藏"];
    if (hideLabel) {
        // 过滤掉所有以 # 开头的标签
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"#\\S+" options:0 error:nil];
        NSString *filtered = [regex stringByReplacingMatchesInString:desc options:0 range:NSMakeRange(0, desc.length) withTemplate:@""];
        // 去除首尾空白字符
        filtered = [filtered stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 为空则赋nil，避免显示空行
        desc = filtered.length > 0 ? filtered : nil;
    }
    %orig(desc);
}

- (void)setTextExtras:(NSArray *)extras {
    NSString *labelStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelStyle"];
    BOOL disableLabelSearch = [labelStyle isEqualToString:@"文案标签禁止跳转搜索"] || [labelStyle isEqualToString:@"文案标签隐藏"];
    if (disableLabelSearch && [extras isKindOfClass:[NSArray class]]) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (AWEAwemeTextExtraModel *model in extras) {
            if (model.userID.length > 0) {
                [filtered addObject:model];
            }
        }
        extras = [filtered copy];
    }
    %orig(extras);
}

// 固定设置为 1，启用自定义背景色
- (NSUInteger)awe_playerBackgroundViewShowType {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"]) {
        return 1;
    }
    return %orig;
}

- (UIColor *)awe_smartBackgroundColor {
    NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"];
    if (colorHex && colorHex.length > 0) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        UIColor *customColor = [DYYYUtils colorFromSchemeHexString:colorHex targetWidth:screenWidth];
        if (customColor)
            return customColor;
    }
    return %orig;
}

//屏蔽章节要点数据
- (NSArray *)chapterList {
	BOOL hideChapterList = DYYYGetBool(@"DYYYHideChapterProgress");
	if (hideChapterList) {
		return @[]; // 返回空数组
	}
	return %orig;
}

// 屏蔽共创数据
- (id)acceptedCoCreators {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return @[]; // 永远为空
	}
	return %orig;
}

- (id)unAcceptedCoCreators {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return @[];
	}
	return %orig;
}

- (NSInteger)acceptedCoCreatorsNums {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return 0;
	}
	return %orig;
}

- (id)awe_coCreatorPoster {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}

- (id)awe_coCreatorFromAuthor {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}

- (id)awe_userModelWithCoCreator:(id)creator {
	BOOL DYYYHideGongChuang = DYYYGetBool(@"DYYYHideGongChuang");
	if (DYYYHideGongChuang) {
		return nil;
	}
	return %orig;
}


// 屏蔽相关视频推荐
- (id)relatedVideoExtra {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

- (id)relatedVideo {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

- (id)playletRelatedVideoInfoModel {
	BOOL DYYYHideBottomRelated = DYYYGetBool(@"DYYYHideBottomRelated");
	if (DYYYHideBottomRelated) {
		return nil;
	}
	return %orig;
}

// 屏蔽评论搜索锚点
- (id)commonSearchAnchor {
	BOOL DYYYHideCommentLongPressSearch = DYYYGetBool(@"DYYYHideCommentLongPressSearch");
	if (DYYYHideCommentLongPressSearch) {
		return nil;
	}
	return %orig;
}

- (void)setCommonSearchAnchor:(id)arg {
	BOOL DYYYHideCommentLongPressSearch = DYYYGetBool(@"DYYYHideCommentLongPressSearch");
	if (DYYYHideCommentLongPressSearch) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽汽水音乐锚点
- (id)relatedMusicAnchor {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (void)setRelatedMusicAnchor:(id)anchor {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽底栏热点
- (id)hotSpotRawData {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (void)setHotSpotRawData:(id)data {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)hotSpotListModel {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (void)setHotSpotListModel:(id)model {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(nil);
		return;
	}
	%orig;
}

- (NSString *)templateBarsString {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (void)setTemplateBarsString:(NSString *)string {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		%orig(@"");
		return;
	}
	%orig;
}

// 屏蔽底部合集（只对推荐页生效）
- (id)mixInfo {
	BOOL DYYYHideTemplateVideo = DYYYGetBool(@"DYYYHideTemplateVideo");
	if (DYYYHideTemplateVideo && [self.referString isEqualToString:@"homepage_hot"]) {
		return nil;
	}
	return %orig;
}

// 屏蔽短剧信息（复用屏蔽合集开关，只对推荐页生效）
- (id)playletInfoModel {
	BOOL DYYYHideTemplatePlaylet = DYYYGetBool(@"DYYYHideTemplatePlaylet");
	if (DYYYHideTemplatePlaylet && [self.referString isEqualToString:@"homepage_hot"]) {
		return nil;
	}
	return %orig;
}

// 屏蔽锚点信息
- (id)anchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)localLifeAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setLocalLifeAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)nearbyFeedDualAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setNearbyFeedDualAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)minorAnchorInfo {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		return nil;
	}
	return %orig;
}

- (void)setMinorAnchorInfo:(id)info {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽通用锚点（合并到锚点信息）
- (id)commonAnchor {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) { 
		return nil;
	}
	return %orig;
}

- (void)setCommonAnchor:(id)anchor {
	BOOL DYYYHideFeedAnchorContainer = DYYYGetBool(@"DYYYHideFeedAnchorContainer");
	if (DYYYHideFeedAnchorContainer) {
		%orig(nil);
		return;
	}
	%orig;
}

// 屏蔽作者声明及风险提示
- (id)riskInfoModel {
	BOOL DYYYHideAntiAddictedNotice = DYYYGetBool(@"DYYYHideAntiAddictedNotice");
	if (DYYYHideAntiAddictedNotice) {
		return nil;
	}
	return %orig;
}

- (void)setRiskInfoModel:(id)model {
	BOOL DYYYHideAntiAddictedNotice = DYYYGetBool(@"DYYYHideAntiAddictedNotice");
	if (DYYYHideAntiAddictedNotice) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWEGeneralSearchModel
- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	id orig = %orig;
	
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (!noAds || !orig) {
		return orig;
	}
	
	if ([DYYYUtils isAdvertisementContainerModel:orig] || [DYYYUtils isAdvertisementRawData:dict]) {
		return nil;
	}
	
	return orig;
}
%end

%hook AWEFeedCommentConfigModel
- (void)setCommentInputConfigText:(NSString *)text {
    NSString *customText = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentContent"];
    if (customText && customText.length > 0) {
        text = customText;
    }
    %orig(text);
}
%end

%hook AWEAwemeStatusModel
- (void)setListenVideoStatus:(NSInteger)status {
    if (status == 1 && DYYYGetBool(@"DYYYEnableBackgroundListen")) {
        status = 2;
    }
    %orig(status);
}
%end
