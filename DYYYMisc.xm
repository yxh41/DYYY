//
//  DYYY - 自动拆分片段（由 DYYY.xm 通过 #include 引入，勿单独编译）
//  分类: DYYYMisc
//

%hook AWEHPChannelInvisibleWaterMarkModel

- (BOOL)isEnter {
    return NO;
}

- (BOOL)isAppear {
    return NO;
}

%end

%hook AWEProfileMentionLabel

- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYBioCopyText")) {
        return;
    }

    BOOL hasLongPressGesture = NO;
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            hasLongPressGesture = YES;
            break;
        }
    }

    if (!hasLongPressGesture) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];
        self.userInteractionEnabled = YES;
    }
}

%new
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSString *bioText = self.text;
        if (bioText && bioText.length > 0) {
            [[UIPasteboard generalPasteboard] setString:bioText];
            [DYYYToast showSuccessToastWithMessage:@"个人简介已复制"];
        }
    }
}

%end

%hook AWEProfileUserDetailComponent

- (void)reportUserDetailVisitIfNeeded:(id)user {
    if (DYYYGetBool(@"DYYYDisableProfileVisitRecordUpload")) {
        return;
    }

    %orig;
}

%end

%hook AWEProfileRecordHelper

+ (void)postProfileRecordWithParams:(id)params completionBlock:(id)completionBlock {
    if (DYYYGetBool(@"DYYYDisableProfileVisitRecordUpload")) {
        return;
    }

    %orig;
}

%end

%hook AWEVideoModel

- (AWEURLModel *)playURL {
    if (!DYYYGetBool(@"DYYYEnableVideoHighestQuality")) {
        return %orig;
    }

    // 获取比特率模型数组
    NSArray *bitrateModels = [self bitrateModels];
    if (!bitrateModels || bitrateModels.count == 0) {
        return %orig;
    }

    // 查找比特率最高的模型
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;

    for (id model in bitrateModels) {
        NSInteger bitrate = 0;
        BOOL validModel = NO;

        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = [model bitrate];
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }

        if (validModel && bitrate > highestBitrate) {
            highestBitrate = bitrate;
            highestBitrateModel = model;
        }
    }

    // 如果找到了最高比特率模型，获取其播放地址
    if (highestBitrateModel) {
        id playAddr = [highestBitrateModel valueForKey:@"playAddr"];
        if (playAddr && [playAddr isKindOfClass:%c(AWEURLModel)]) {
            return playAddr;
        }
    }

    return %orig;
}

- (NSArray *)bitrateModels {

    NSArray *originalModels = %orig;

    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(originalModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        originalModels = filteredModels;
    }

    if (!DYYYGetBool(@"DYYYEnableVideoHighestQuality")) {
        return originalModels;
    }

    if (originalModels.count == 0) {
        return originalModels;
    }

    // 查找比特率最高的模型
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;

    for (id model in originalModels) {

        NSInteger bitrate = 0;
        BOOL validModel = NO;

        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = [model bitrate];
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }

        if (validModel) {
            if (bitrate > highestBitrate) {
                highestBitrate = bitrate;
                highestBitrateModel = model;
            }
        }
    }

    if (highestBitrateModel) {
        return @[ highestBitrateModel ];
    }

    return originalModels;
}

- (void)setBitrateModels:(NSArray *)bitrateModels {
    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(bitrateModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (void)setManualBitrateModels:(NSArray *)manualBitrateModels {
    if (DYYYShouldDisableAllHDR()) {
        NSArray *filteredModels = DYYYFilteredSDRBitrateModels(manualBitrateModels);
        DYYYStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (NSArray *)manualBitrateModels {
    NSArray *models = %orig;
    if (DYYYShouldDisableAllHDR()) {
        models = DYYYFilteredSDRBitrateModels(models);
        DYYYStripHDRHintsFromBitrateModels(models);
    }
    return models;
}

- (void)setBitrateRawData:(NSArray *)bitrateRawData {
    if (DYYYShouldDisableAllHDR()) {
        %orig(DYYYFilteredSDRRawBitrateData(bitrateRawData));
        return;
    }
    %orig;
}

- (NSArray *)bitrateRawData {
    NSArray *rawData = %orig;
    if (DYYYShouldDisableAllHDR()) {
        rawData = DYYYFilteredSDRRawBitrateData(rawData);
    }
    return rawData;
}

- (void)setHasFilterHDR:(BOOL)hasFilterHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : hasFilterHDR);
}

- (BOOL)hasFilterHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsSourceHDR:(NSInteger)isSourceHDR {
    %orig(DYYYShouldDisableAllHDR() ? 0 : isSourceHDR);
}

- (NSInteger)isSourceHDR {
    if (DYYYShouldDisableAllHDR()) {
        return 0;
    }
    return %orig;
}

%end

%hook AWEIMModuleService

- (BOOL)im_forceHDRToSDR {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

%end

%hook TVLManager

- (BOOL)shouldForbidHDR10Render {
    if (DYYYShouldDisableAllHDR()) {
        return YES;
    }
    return %orig;
}

- (void)setShouldForbidHDR10Render:(BOOL)shouldForbid {
    %orig(DYYYShouldDisableAllHDR() ? YES : shouldForbid);
}

- (void)setupVideoSDR2HDR:(id)config {
    if (!DYYYShouldDisableAllHDR()) {
        %orig;
    }
}

%end

%hook IESFiltersManager

- (void)setHDRIndensity:(double)intensity {
    %orig(DYYYShouldDisableAllHDR() ? 0.0 : intensity);
}

%end

%hook BDImageDecoderFactory

+ (BOOL)isHDRImageData:(id)data withHeifDecoderClass:(Class)decoderClass {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook BDImageDecoderImageIO

- (BOOL)isHDRCGImage:(CGImageRef)image decodedToHDR:(BOOL)decodedToHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (id)hdrOptionsFor:(id)image decodedToHDR:(BOOL *)decodedToHDR {
    if (DYYYShouldDisableAllHDR()) {
        if (decodedToHDR) {
            *decodedToHDR = NO;
        }
        return nil;
    }
    return %orig;
}

%end

%hook BDImageDecoderHeic

+ (BOOL)isHDRData:(id)data {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImageDecoderBVC2

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImageDecoderWebP

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook BDImage

- (BOOL)isHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setIsHDR:(BOOL)isHDR {
    %orig(DYYYShouldDisableAllHDR() ? NO : isHDR);
}

%end

%hook CAMetalLayer

- (void)setWantsExtendedDynamicRangeContent:(BOOL)wantsExtendedDynamicRangeContent {
    %orig(DYYYShouldDisableAllHDR() ? NO : wantsExtendedDynamicRangeContent);
}

- (BOOL)wantsExtendedDynamicRangeContent {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setEDRMetadata:(CAEDRMetadata *)EDRMetadata {
    %orig(DYYYShouldDisableAllHDR() ? nil : EDRMetadata);
}

- (CAEDRMetadata *)EDRMetadata {
    if (DYYYShouldDisableAllHDR()) {
        return nil;
    }
    return %orig;
}

%end

%hook CALayer

- (void)setHidden:(BOOL)hidden {
    %orig(DYYYShouldForceHideAvatarActionLayer(self) ? YES : hidden);
}

- (void)setContents:(id)contents {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? nil : contents);
}

- (void)setBackgroundColor:(CGColorRef)backgroundColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : backgroundColor);
}

- (void)setOpaque:(BOOL)opaque {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? NO : opaque);
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? 0.0 : borderWidth);
}

- (void)setBorderColor:(CGColorRef)borderColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : borderColor);
}

- (void)setShadowOpacity:(float)shadowOpacity {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? 0.0f : shadowOpacity);
}

- (void)setShadowColor:(CGColorRef)shadowColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : shadowColor);
}

- (void)addSublayer:(CALayer *)layer {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer);
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned int)index {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, index);
}

- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, sibling);
}

- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling {
    DYYYPrepareAvatarActionSublayer(self, layer);
    %orig(layer, sibling);
}

- (void)setSublayers:(NSArray<CALayer *> *)sublayers {
    for (CALayer *layer in sublayers) {
        DYYYPrepareAvatarActionSublayer(self, layer);
    }
    %orig(sublayers);
}

- (void)setWantsExtendedDynamicRangeContent:(BOOL)wantsExtendedDynamicRangeContent {
    %orig(DYYYShouldDisableAllHDR() ? NO : wantsExtendedDynamicRangeContent);
}

- (BOOL)wantsExtendedDynamicRangeContent {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setPreferredDynamicRange:(id)preferredDynamicRange {
    id standardDynamicRange = DYYYStandardCADynamicRange();
    %orig(DYYYShouldDisableAllHDR() && standardDynamicRange ? standardDynamicRange : preferredDynamicRange);
}

- (id)preferredDynamicRange {
    id preferredDynamicRange = %orig;
    if (DYYYShouldDisableAllHDR()) {
        id standardDynamicRange = DYYYStandardCADynamicRange();
        if (standardDynamicRange) {
            return standardDynamicRange;
        }
    }
    return preferredDynamicRange;
}

%end

%hook CAShapeLayer

- (void)setFillColor:(CGColorRef)fillColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : fillColor);
}

- (void)setStrokeColor:(CGColorRef)strokeColor {
    %orig(DYYYShouldClearAvatarActionLayer(self) ? UIColor.clearColor.CGColor : strokeColor);
}

%end

%hook AWEDateTimeFormatter

+ (id)formattedDateForTimestamp:(double)timestamp {
    if (!DYYYGetBool(@"DYYYCommentExactTime")) return %orig(timestamp);
    return [NSString stringWithFormat:@"%.0f ", timestamp];
}

%end

%hook AWERLVirtualLabel

- (void)setText:(NSString *)text {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !text || text.length == 0) {
        %orig(text);
        return;
    }

    if ([text isEqualToString:@"回复"]) {
        %orig(@"");
        return;
    }

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})([\\s\\S]*)" options:0 error:&error];
    
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];

    if (match) {
        NSString *rawTs = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *suffix = [text substringWithRange:[match rangeAtIndex:2]];
        
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSString *newText = [NSString stringWithFormat:@"%@%@", formattedDate, suffix];
        %orig(newText);
    } else {
        %orig(text);
    }
}

%end

%hook YYLabel

// 1. Hook 富文本赋值方法 (核心)
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !attributedText || attributedText.length == 0) {
        %orig(attributedText);
        return;
    }

    NSString *plainText = [attributedText string];

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})" options:0 error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:plainText options:0 range:NSMakeRange(0, plainText.length)];

    if (match) {
        NSString *rawTs = [plainText substringWithRange:[match rangeAtIndex:1]];
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSMutableAttributedString *newAttrStr = [attributedText mutableCopy];
        [newAttrStr replaceCharactersInRange:[match rangeAtIndex:1] withString:formattedDate];
        
        %orig(newAttrStr);
    } else {
        %orig(attributedText);
    }
}

%end

%hook AWEDanmakuContentLabel
- (void)setTextColor:(UIColor *)textColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        NSString *danmuColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDanmuColor"];
        if (DYYYGetBool(@"DYYYDanmuRainbowRotating")) {
            danmuColor = @"rainbow_rotating";
        }
        [DYYYUtils applyColorSettingsToLabel:self colorHexString:danmuColor];
    } else {
        %orig(textColor);
    }
}

- (void)setStrokeWidth:(double)strokeWidth {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(FLT_MIN);
    } else {
        %orig(strokeWidth);
    }
}

- (void)setStrokeColor:(UIColor *)strokeColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(nil);
    } else {
        %orig(strokeColor);
    }
}

%end

%hook AWEDProgressCoreContainer

%new
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (progressSlider && [progressSlider respondsToSelector:@selector(dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    id model = nil;
    if ([self respondsToSelector:@selector(model)]) {
        model = [self valueForKey:@"model"];
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

%hook AWEUserNameLabel

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    // 添加垂直偏移支持
    NSString *verticalOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (verticalOffsetValue.length > 0) {
        verticalOffset = [verticalOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    // 检查祖父视图是否为 AWEBaseElementView 类型
    if (grandParentView && [grandParentView.superview isKindOfClass:%c(AWEBaseElementView)]) {
        CGRect scaledFrame = grandParentView.frame;
        CGFloat translationX = -scaledFrame.origin.x;

        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(translationX, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}

%end

%hook AWEURLModel
%new - (NSURL *)getDYYYSrcURLDownload {
    NSURL *bestURL;
    for (NSString *url in self.originURLList) {
        if ([url containsString:@"video_mp4"] || [url containsString:@".jpeg"] || [url containsString:@".mp3"]) {
            bestURL = [NSURL URLWithString:url];
        }
    }

    if (bestURL == nil) {
        bestURL = [NSURL URLWithString:[self.originURLList firstObject]];
    }

    return bestURL;
}
%end

%hook AWEVersionUpdateManager

- (void)startVersionUpdateWorkflow:(id)arg1 completion:(id)arg2 {
    if (DYYYGetBool(@"DYYYNoUpdates")) {
        if (arg2) {
            void (^completionBlock)(void) = arg2;
            completionBlock();
        }
    } else {
        %orig;
    }
}

- (id)workflow {
    return DYYYGetBool(@"DYYYNoUpdates") ? nil : %orig;
}

- (id)badgeModule {
    return DYYYGetBool(@"DYYYNoUpdates") ? nil : %orig;
}

%end

%hook AWEInnerNotificationWindow

- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"]) {
        [self setupBlurEffectForNotificationView];
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window && DYYYGetBool(@"DYYYEnableNotificationTransparency")) {
        [self setupBlurEffectForNotificationView];
    }
}

%new
- (void)setupBlurEffectForNotificationView {
    for (UIView *subview in self.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"AWEInnerNotificationContainerView"]) {
            [self applyBlurEffectToView:subview];
            break;
        }
    }
}

%new
- (void)applyBlurEffectToView:(UIView *)containerView {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!containerView) {
          return;
      }

      containerView.backgroundColor = [UIColor clearColor];

      float userRadius = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNotificationCornerRadius"] floatValue];
      if (!userRadius || userRadius < 0 || userRadius > 50) {
          userRadius = 12;
      }

      containerView.layer.cornerRadius = userRadius;
      containerView.layer.masksToBounds = YES;

      for (UIView *subview in containerView.subviews) {
          if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999) {
              [subview removeFromSuperview];
          }
      }

      BOOL isDarkMode = [DYYYUtils isDarkMode];
      UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
      UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
      UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];

      blurView.frame = containerView.bounds;
      blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      blurView.tag = 999;
      blurView.layer.cornerRadius = userRadius;
      blurView.layer.masksToBounds = YES;

      float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
      if (userTransparency <= 0 || userTransparency > 1) {
          userTransparency = 0.5;
      }

      blurView.alpha = userTransparency;

      [containerView insertSubview:blurView atIndex:0];

      [self clearBackgroundRecursivelyInView:containerView];

      [self setLabelsColorWhiteInView:containerView];
    });
}

%new
- (void)setLabelsColorWhiteInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            NSString *text = label.text;

            if (![text isEqualToString:@"回复"] && ![text isEqualToString:@"查看"] && ![text isEqualToString:@"续火花"]) {
                label.textColor = [UIColor whiteColor];
            }
        }
        [self setLabelsColorWhiteInView:subview];
    }
}

%new
- (void)clearBackgroundRecursivelyInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999 && [subview isKindOfClass:[UIButton class]]) {
            continue;
        }
        subview.backgroundColor = [UIColor clearColor];
        [self clearBackgroundRecursivelyInView:subview];
    }
}

%end

%hook AWEIMPhotoPickerFunctionModel

- (void)setUseShadowIcon:(BOOL)arg1 {
    BOOL enabled = DYYYGetBool(@"DYYYAutoSelectOriginalPhoto");
    if (enabled) {
        %orig(YES);
    } else {
        %orig(arg1);
    }
}

- (BOOL)isSelected {
    BOOL enabled = DYYYGetBool(@"DYYYAutoSelectOriginalPhoto");
    if (enabled) {
        return YES;
    }
    return %orig;
}

%end

%hook BDByteCastUtils

+ (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastNetUtilities

- (BOOL)getVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastMonitorManager

- (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setNetVPNStatus:(BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(netVPNStatus);
}

%end

%hook BDByteCastEnvInfo

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

%hook BDByteScreenCastContext

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

%hook AFDProfileAvatarFunctionManager
- (BOOL)shouldShowSaveAvatarItem {
    BOOL shouldEnable = DYYYGetBool(@"DYYYEnableSaveAvatar");
    if (shouldEnable) {
        return YES;
    }
    return %orig;
}
%end

%group DYYYIMMenuLegacyGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuTapLocationGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, menuPanelOptions, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuHighLowGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame highLocationInScreen:(CGPoint)highLocation lowLocationInScreen:(CGPoint)lowLocation tryHighLocationFirst:(BOOL)tryHighLocationFirst menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, highLocation, lowLocation, tryHighLocationFirst, updatedMenuItems, menuPanelOptions, cell, extra);
}
%end
%end

%hook AWECorrelationItemTag

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideItemTag")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWEListDataController

- (void)setDataSource:(NSMutableArray *)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (NSMutableArray *)dataSource {
    NSMutableArray *dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return [filtered mutableCopy];
    }
    return dataSource;
}

- (void)setFilteredDataSource:(NSMutableArray *)filteredDataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    %orig(filtered);
}

- (NSMutableArray *)filteredDataSource {
    NSMutableArray *filteredDataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    if (filtered != filteredDataSource && [filteredDataSource isKindOfClass:[NSMutableArray class]]) {
        [filteredDataSource setArray:filtered];
    } else if (filtered != filteredDataSource) {
        return [filtered mutableCopy];
    }
    return filteredDataSource;
}

%end

%hook AWEMixVideoListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWEMixVideoRelatedListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWEHotListDataController

%new
- (NSNumber *)dyyy_numberValueForLowLikesFilter:(id)rawValue {
    if (!rawValue || rawValue == [NSNull null]) {
        return nil;
    }

    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return (NSNumber *)rawValue;
    }

    if ([rawValue isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            return nil;
        }

        NSString *normalized = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"," withString:@""];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"+" withString:@""];
        if ([normalized hasSuffix:@"赞"]) {
            normalized = [normalized substringToIndex:normalized.length - 1];
        }

        double multiplier = 1.0;
        NSString *lowercaseValue = [normalized lowercaseString];
        if ([normalized hasSuffix:@"亿"]) {
            multiplier = 100000000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        } else if ([normalized hasSuffix:@"万"] || [lowercaseValue hasSuffix:@"w"]) {
            multiplier = 10000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        } else if ([normalized hasSuffix:@"千"] || [lowercaseValue hasSuffix:@"k"]) {
            multiplier = 1000.0;
            normalized = [normalized substringToIndex:normalized.length - 1];
        }

        NSScanner *doubleScanner = [NSScanner scannerWithString:normalized];
        double doubleValue = 0.0;
        if ([doubleScanner scanDouble:&doubleValue] && doubleScanner.isAtEnd) {
            return @((long long)llround(doubleValue * multiplier));
        }
    }

    return nil;
}

%new
- (NSNumber *)dyyy_resolvedDiggCountForAweme:(AWEAwemeModel *)aweme {
    if (!aweme) {
        return nil;
    }

    static NSArray<NSString *> *diggKeyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diggKeyPaths = @[
            @"statistics.diggCount",
            @"statistics.digg_count",
            @"diggCount",
            @"digg_count",
            @"feedSequenceExtendFeature.digg_count",
            @"feedSequenceExtendFeature.diggCount",
            @"recommendFeedExtendFeature.digg_count",
            @"recommendFeedExtendFeature.diggCount"
        ];
    });

    for (NSString *keyPath in diggKeyPaths) {
        id rawValue = nil;
        @try {
            rawValue = [aweme valueForKeyPath:keyPath];
        } @catch (__unused NSException *exception) {
            rawValue = nil;
        }

        NSNumber *resolved = [self dyyy_numberValueForLowLikesFilter:rawValue];
        if (resolved) {
            return resolved;
        }
    }

    return nil;
}

- (id)transferAwemeListIfNeededWithArray:(id)arg1 isInitFetch:(BOOL)arg2 {
    NSArray *orig = %orig;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) {
        return orig;
    }

    // --- 配置读取 ---
    NSInteger daysThreshold = DYYYGetInteger(@"DYYYFilterTimeLimit");
    BOOL skipLive = DYYYGetBool(@"DYYYSkipLive"); // 读取直播过滤开关
    NSInteger minLikesThreshold = DYYYGetInteger(@"DYYYFilterLowLikes"); // 读取低赞过滤阈值 (例如: 1000)
    BOOL skipPhotoText = DYYYGetBool(@"DYYYSkipPhotoText"); // 图文过滤
    BOOL skipPhoto = DYYYGetBool(@"DYYYSkipPhoto"); // 图集过滤
    BOOL skipMusic = DYYYGetBool(@"DYYYSkipMusic"); // 音乐过滤
    BOOL shouldDisableHDR = DYYYShouldDisableAllHDR();
    BOOL noAds = DYYYGetBool(@"DYYYNoAds");

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval thresholdInSeconds = MAX(daysThreshold, 0) * 86400.0;

    // 第一阶段：先做稳定字段过滤（直播/时间/类型）
    NSMutableArray *baseFiltered = [NSMutableArray arrayWithCapacity:orig.count];

    for (id obj in orig) {
        if (![obj isKindOfClass:%c(AWEAwemeModel)]) {
            [baseFiltered addObject:obj];
            continue;
        }

        AWEAwemeModel *m = (AWEAwemeModel *)obj;

        // 1. 广告过滤：合集、搜索内流、分页追加等旁路也会进入此共享转换。
        if (noAds && [DYYYUtils isAdvertisementAwemeModel:m]) {
            continue;
        }

        // 2. 直播过滤逻辑 (仅依赖 cellRoom)
        if (skipLive && [m respondsToSelector:@selector(cellRoom)] && m.cellRoom != nil) {
            continue; // 命中直播过滤，跳过
        }

        // 2.1 图文模式过滤逻辑（推荐页）
        if (skipPhotoText &&
            [m respondsToSelector:@selector(isNewTextMode)] &&
            m.isNewTextMode &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"]) {
            continue; // 图文模式且来自推荐页，跳过
        }

        // 2.2 图集过滤逻辑（推荐页）
        if (skipPhoto &&
            [m respondsToSelector:@selector(awemeType)] &&
            m.awemeType == 68 &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"]) {
            continue; // 图集且来自推荐页，跳过
        }

        // 2.3 音乐过滤逻辑（推荐页）
        if (skipMusic &&
            [m respondsToSelector:@selector(referString)] &&
            [m.referString isEqualToString:@"homepage_hot"] &&
            [m respondsToSelector:@selector(musicCard)] &&
            m.musicCard) {
            continue; // 音乐卡片且来自推荐页，跳过
        }

        // 3. 时间限制过滤
        if (daysThreshold > 0 && [m respondsToSelector:@selector(createTime)]) {
            NSTimeInterval vTs = [m.createTime doubleValue];
            if (vTs > 1e12) {
                vTs /= 1000.0; // 毫秒转秒
            }

            if (vTs > 0 && (now - vTs) > thresholdInSeconds) {
                continue; // 超过设定时限，跳过
            }
        }

        // 4. 全局屏蔽 HDR 时，若作品没有 SDR 码率档，直接过滤，避免强播纯 HDR 源导致黑屏或 HDR 漏出。
        if (shouldDisableHDR &&
            ![m dyyy_shouldExcludeFromGlobalHDRFilter] &&
            DYYYAwemeModelHasOnlyHDRBitrateModels(m)) {
            continue;
        }

        if (shouldDisableHDR) {
            DYYYStripHDRHintsFromAwemeModel(m);
        }

        [baseFiltered addObject:obj];
    }

    if (minLikesThreshold <= 0 || baseFiltered.count == 0) {
        return [baseFiltered copy];
    }

    // 第二阶段：低赞过滤。字段缺失时放行；只要能解析到数值，就严格按阈值过滤。
    NSMutableArray *lowLikesFiltered = [NSMutableArray arrayWithCapacity:baseFiltered.count];

    for (id obj in baseFiltered) {
        if (![obj isKindOfClass:%c(AWEAwemeModel)]) {
            [lowLikesFiltered addObject:obj];
            continue;
        }

        AWEAwemeModel *m = (AWEAwemeModel *)obj;
        NSNumber *diggCountValue = [self dyyy_resolvedDiggCountForAweme:m];

        if (!diggCountValue) {
            [lowLikesFiltered addObject:obj];
            continue;
        }

        if (diggCountValue.integerValue < minLikesThreshold) {
            continue;
        }

        [lowLikesFiltered addObject:obj];
    }

    return [lowLikesFiltered copy];
}

%end

%hook AWEUserModel

- (NSNumber *)roomID {
	BOOL DYYYHideAvatarLive = DYYYGetBool(@"DYYYHideAvatarLive") || DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarLive) {
		return @(0);
	}
	return %orig;
}

%end

%hook AWEUserModel

- (id)storyRing {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		return nil;
	}
	return %orig;
}

- (void)setStoryRing:(id)ring {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWECodeGenStoryRingInfoModel

- (NSArray *)storyRingsModelArray {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		return @[];
	}
	return %orig;
}

- (void)setStoryRingsModelArray:(NSArray *)array {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

%hook AWEInteractionHashtagStickerModel

- (id)hashtagInfo {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (void)setHashtagInfo:(id)info {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)hashtagId {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (id)hashtagName {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

%end

%hook AWEInteractionEditTagStickerModel

- (id)editTagInfo {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		return nil;
	}
	return %orig;
}

- (void)setEditTagInfo:(id)info {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWEHotSpotListModel

- (BOOL)disableDisplay {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return YES;
	}
	return %orig;
}

- (BOOL)disableDisplayInner {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return YES;
	}
	return %orig;
}

- (NSString *)hotSpotTipTitleHeader {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotSpotTipTitle {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotSpotTipTitleFooter {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)hotInfoWord {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)i18NTipTitle {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @"";
	}
	return %orig;
}

- (NSString *)tipSchema {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return nil;
	}
	return %orig;
}

- (NSDictionary *)extraDictionary {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @{};
	}
	return %orig;
}

- (NSDictionary *)relativityExtra {
	BOOL DYYYHideHotspot = DYYYGetBool(@"DYYYHideHotspot");
	if (DYYYHideHotspot) {
		return @{};
	}
	return %orig;
}

%end

%hook AWETemplateStaticLabelInfoModel

- (NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		return @[];
	}
	return %orig;
}

- (void)setContainers:(NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

%hook AWERelatedMusicAnchorModel

- (instancetype)init {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

%end

%hook AWEMusicExtraModel

- (id)commentTopBarInfo {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (void)setCommentTopBarInfo:(id)info {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook TTAdSplashModel

+ (id)alloc {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return nil;  // 直接返回 nil，阻止对象创建
	}
	return %orig;
}

%end

%hook AWEOriginalAdModel
- (instancetype)init {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}
%end

%hook AFDPureModePageTapController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = DYYYGetBool(@"DYYYDisableDoubleTapLike");
    if (!isSwitchOn) {
        %orig;
    }
}

%end

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    initTargetClassNames();

    updateGlobalTransparencyCache();

    [[NSUserDefaults standardUserDefaults] addObserver:(NSObject *)self forKeyPath:kDYYYGlobalTransparencyKey options:NSKeyValueObservingOptionNew context:DYYYGlobalTransparencyContext];

    reloadClearButtonConfiguration();
    DYYYRemoveAppLifecycleObservers();

    dyyyWindowKeyObserverToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification
                                                                                   object:nil
                                                                                    queue:[NSOperationQueue mainQueue]
                                                                               usingBlock:^(NSNotification *_Nonnull notification) {
                                                                                 reloadClearButtonConfiguration();
                                                                               }];

    dyyyDidBecomeActiveToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                                 object:nil
                                                                                  queue:[NSOperationQueue mainQueue]
                                                                             usingBlock:^(NSNotification *_Nonnull notification) {
                                                                               isAppActive = YES;
                                                                               reloadClearButtonConfiguration();
                                                                             }];

    dyyyWillResignActiveToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                                                  object:nil
                                                                                   queue:[NSOperationQueue mainQueue]
                                                                              usingBlock:^(NSNotification *_Nonnull notification) {
                                                                                isAppActive = NO;
                                                                                updateClearButtonVisibility();
                                                                              }];

    return result;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    DYYYRemoveAppLifecycleObservers();
    DYYYRemoveKeyboardObserver();
    %orig;
}

- (void)dealloc {
    DYYYRemoveAppLifecycleObservers();
    DYYYRemoveKeyboardObserver();
    @try {
        [[NSUserDefaults standardUserDefaults] removeObserver:(NSObject *)self forKeyPath:kDYYYGlobalTransparencyKey context:DYYYGlobalTransparencyContext];
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] KVO removeObserver failed: %@", exception);
    } 
    %orig;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == DYYYGlobalTransparencyContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
          updateGlobalTransparencyCache();
          [[NSNotificationCenter defaultCenter] postNotificationName:kDYYYGlobalTransparencyDidChangeNotification object:nil];
        });
    } else {
        %orig(keyPath, object, change, context);
    }
}

%end

%hook DUXPopover
- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYHidePopover")) {
        return;
    }

    id rawContent = nil;
    @try {
        rawContent = [self valueForKey:@"content"];
    } @catch (__unused NSException *e) {
        return;
    }

    NSString *text = [rawContent isKindOfClass:NSString.class] ? (NSString *)rawContent : [rawContent description];

    if ([text containsString:@"上次看到"]) {
        self.hidden = YES;
        return;
    }
}
%end
