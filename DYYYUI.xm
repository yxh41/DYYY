//
//  DYYY - 自动拆分片段（由 DYYY.xmi 通过 #include 引入，勿单独编译）
//  分类: DYYYUI
//

%hook AWEKnowledgeABTestSettings

+ (BOOL)enableHDRAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEFeedABSettings

+ (BOOL)enableHDRBrightnessOpt {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableProfilePreloadHDRBrightnessFilter {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableDynamicGaussianBlurHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)enableHDRFullModelAdaptation {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

+ (BOOL)hdrAutomaticIdentification {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEIMVideoBrowserCollectionViewCell

- (void)setEnablePlayHDR:(BOOL)enable {
    %orig(DYYYShouldDisableAllHDR() ? NO : enable);
}

%end

%hook AWEECOMIMAppSettingsService

+ (BOOL)enableVideoPreviewSupportHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook TVLSettingsManager

- (BOOL)enableMetalRenderHDR {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

%end

%hook HDRMTUIImageView

- (instancetype)initWithFrame:(CGRect)frame hdrEnabled:(BOOL)hdrEnabled {
    return %orig(frame, DYYYShouldDisableAllHDR() ? NO : hdrEnabled);
}

- (BOOL)hdrEnabled {
    if (DYYYShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (void)setHdrEnabled:(BOOL)hdrEnabled {
    %orig(DYYYShouldDisableAllHDR() ? NO : hdrEnabled);
}

- (void)setImage:(UIImage *)image {
    if (DYYYShouldDisableAllHDR()) {
        self.hdrEnabled = NO;
    }
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

%end

%hook HDRMTImageView

- (void)setMetalLayer:(CAMetalLayer *)metalLayer {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(metalLayer);
}

- (void)setUpEnv {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(self.metalLayer);
}

- (void)layoutSubviews {
    %orig;
    DYYYDisableExtendedRangeForMetalLayer(self.metalLayer);
}

%end

%hook HDRMTButton

- (void)configHDRContent {
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self.hdrmtImageView);
}

%end

%group DYYYCommentExactTimeGroup
%hook AWECommentSwiftBizUI_CommentInteractionBaseLabel

- (void)setText:(NSString *)text {
    %orig(text); // 先让系统把文本赋上去
    
    if (!DYYYGetBool(@"DYYYCommentExactTime")) {
        return;
    }

    UILabel *label = (UILabel *)self;
    if (!text || text.length == 0) return;

    // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
    if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
        CGRect currentFrame = label.frame;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        // 重新计算 X 坐标：屏幕宽度 - 100 - 标签自身宽度
        currentFrame.origin.x = screenWidth - 100.0 - currentFrame.size.width;
        label.frame = currentFrame;
        return;
    }

    // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
    UIFont *font = label.font;
    if (font) {
        CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGRect currentFrame = label.frame;
        
        // 如果当前宽度不够，并且不是尚未初始化的状态（>0），则强行修改并重新赋值
        if (currentFrame.size.width < expectedWidth && currentFrame.size.width > 0) {
            currentFrame.size.width = expectedWidth;
            label.frame = currentFrame; 
            label.clipsToBounds = NO;
        }
    }
}

- (void)setFrame:(CGRect)frame {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || ![self respondsToSelector:@selector(text)]) {
        %orig(frame);
        return;
    }

    UILabel *label = (UILabel *)self;
    NSString *text = label.text;

    if (text && text.length > 0) {
        // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
        if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            frame.origin.x = screenWidth - 100.0 - frame.size.width;
        } 
        // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
        else if ([self respondsToSelector:@selector(font)]) {
            UIFont *font = label.font;
            if (font) {
                CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
                if (frame.size.width < expectedWidth && frame.size.width > 0) {
                    frame.size.width = expectedWidth;
                    label.clipsToBounds = NO;
                }
            }
        }
    }

    %orig(frame);
}

%end
%end

%hook AWELiveGuideElement

- (BOOL)enableAutoEnterRoom {
    if (DYYYGetBool(@"DYYYDisableAutoEnterLive")) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableNewAutoEnter {
    if (DYYYGetBool(@"DYYYDisableAutoEnterLive")) {
        return NO;
    }
    return %orig;
}

%end

%hook AWELandscapeFeedViewController
- (void)viewDidLoad {
    %orig;

    // 尝试优先走属性
    gFeedCV = self.collectionView;

    // 保险起见再fallback,遍历 subviews
    if (!gFeedCV) {
        gFeedCV = [DYYYUtils findSubviewOfClass:[UICollectionView class] inContainer:self.view];
    }
}
%end

%hook UICollectionView

// 拦截手指拖动
- (void)handlePan:(UIPanGestureRecognizer *)pan {

    /* 仅处理横屏Feed列表。其余collectionView直接走系统逻辑 */
    if (self != gFeedCV || !DYYYGetBool(@"DYYYVideoGesture")) {
        %orig;
        return;
    }

    /* 取触点坐标、手势状态 */
    CGPoint loc = [pan locationInView:self];
    CGFloat w = self.bounds.size.width;
    CGFloat xPct = loc.x / w; // 0.0 ~ 1.0
    UIGestureRecognizerState st = pan.state;

    /* BEGAN：判定左右 20 % 区域 → 进入亮度 / 音量模式 */
    if (st == UIGestureRecognizerStateBegan) {

        gStartY = loc.y;

        if (xPct <= 0.20) { // 左边缘 → 亮度
            gMode = DYEdgeModeBrightness;
            gStartVal = [UIScreen mainScreen].brightness;

        } else if (xPct >= 0.80) { // 右边缘 → 音量
            gMode = DYEdgeModeVolume;
            gStartVal = [[objc_getClass("AVSystemController") sharedAVSystemController] volumeForCategory:@"Audio/Video"];

        } else {
            gMode = DYEdgeModeNone; // 中间区域走原逻辑
        }
    }

    /* 调节阶段：左右边缘时吞掉滚动、修改亮度/音量 */
    if (gMode != DYEdgeModeNone) {

        if (st == UIGestureRecognizerStateChanged) {

            CGFloat delta = (gStartY - loc.y) / self.bounds.size.height; // ↑ 为正
            const CGFloat kScale = 2.0;                                  // 灵敏度
            float newVal = gStartVal + delta * kScale;
            newVal = fminf(fmaxf(newVal, 0.0), 1.0); // Clamp 0~1

            if (gMode == DYEdgeModeBrightness) {
                [UIScreen mainScreen].brightness = newVal;
                // 弹系统亮度 HUD
                [[%c(SBHUDController) sharedInstance] presentHUDWithIcon:@"Brightness" level:newVal];

            } else { // DYEdgeModeVolume
                // iOS 18 音量控制 + 系统音量 HUD
                [[objc_getClass("AVSystemController") sharedAVSystemController] setVolumeTo:newVal forCategory:@"Audio/Video"];
            }

            // 吞掉滚动：归零 translation，防止内容位移
            [pan setTranslation:CGPointZero inView:self];
        }

        /* 结束／取消：状态复位 */
        if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled || st == UIGestureRecognizerStateFailed) {
            gMode = DYEdgeModeNone;
        }

        return; // 左右边缘：彻底阻断 %orig，避免翻页
    }

    /* 中间区域：直接执行原先翻页逻辑 */
    %orig;
}

%end

%hook AWELeftSideBarAddChildTransitionObject

- (void)handleShowSliderPanGesture:(id)gr {
    if (DYYYGetBool(@"DYYYDisableSidebarGesture")) {
        return;
    }
    %orig(gr);
}

%end

%hook AWEFeedTopBarContainer
- (void)didMoveToSuperview {
    %orig;
    applyTopBarTransparency(self);
}
- (void)setAlpha:(CGFloat)alpha {
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
            %orig(finalAlpha);
        } else {
            %orig(1.0);
        }
    } else {
        %orig(1.0);
    }
}
%end

%hook AWEHPTopTabItemTextContentView

- (void)layoutSubviews {
    %orig;
    NSDictionary<NSString *, NSString *> *titleMapping = DYYYTopTabTitleMapping();
    if (titleMapping.count == 0) {
        return;
    }

    NSString *accessibilityLabel = nil;
    if ([self.superview respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = self.superview.accessibilityLabel;
    }
    if (accessibilityLabel.length == 0) {
        return;
    }

    NSString *newTitle = titleMapping[accessibilityLabel];
    if (newTitle.length == 0) {
        return;
    }

    if ([self respondsToSelector:@selector(setContentText:)]) {
        [self setContentText:newTitle];
    } else {
        [self setValue:newTitle forKey:@"contentText"];
    }
}

%end

%hook AWEMarkView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLocation")) {
        self.hidden = YES;
        return;
    }
}

%end

%group DYYYSettingsGesture

%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    UIWindow *window = %orig(frame);
    if (window) {
        UILongPressGestureRecognizer *doubleFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleFingerLongPressGesture:)];
        doubleFingerLongPressGesture.numberOfTouchesRequired = 2;
        [window addGestureRecognizer:doubleFingerLongPressGesture];
    }
    return window;
}

%new
- (void)handleDoubleFingerLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIViewController *rootViewController = self.rootViewController;
        if (rootViewController) {
            UIViewController *settingVC = [[DYYYSettingViewController alloc] init];

            if (settingVC) {
                BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
                if (@available(iOS 15.0, *)) {
                    if (!isIPad) {
                        settingVC.modalPresentationStyle = UIModalPresentationPageSheet;
                    } else {
                        settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
                    }
                } else {
                    settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
                }

                if (settingVC.modalPresentationStyle == UIModalPresentationFullScreen) {
                    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
                    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
                    closeButton.translatesAutoresizingMaskIntoConstraints = NO;

                    [settingVC.view addSubview:closeButton];

                    [NSLayoutConstraint activateConstraints:@[
                        [closeButton.trailingAnchor constraintEqualToAnchor:settingVC.view.trailingAnchor constant:-10],
                        [closeButton.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:40], [closeButton.widthAnchor constraintEqualToConstant:80],
                        [closeButton.heightAnchor constraintEqualToConstant:40]
                    ]];

                    [closeButton addTarget:self action:@selector(closeSettings:) forControlEvents:UIControlEventTouchUpInside];
                }

                UIView *handleBar = [[UIView alloc] init];
                handleBar.backgroundColor = [UIColor whiteColor];
                handleBar.layer.cornerRadius = 2.5;
                handleBar.translatesAutoresizingMaskIntoConstraints = NO;
                [settingVC.view addSubview:handleBar];

                [NSLayoutConstraint activateConstraints:@[
                    [handleBar.centerXAnchor constraintEqualToAnchor:settingVC.view.centerXAnchor], [handleBar.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:8],
                    [handleBar.widthAnchor constraintEqualToConstant:40], [handleBar.heightAnchor constraintEqualToConstant:5]
                ]];

                [rootViewController presentViewController:settingVC animated:YES completion:nil];
            }
        }
    }
}

%new
- (void)closeSettings:(UIButton *)button {
    [button.superview.window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)makeKeyAndVisible {
    %orig;

    if (!isFloatSpeedButtonEnabled)
        return;

    if (speedButton && ![speedButton isDescendantOfView:self]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self addSubview:speedButton];
          [speedButton loadSavedPosition];
          [speedButton resetFadeTimer];
        });
    }
}
%end

%end

%hook AWEBaseListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    [self applyBlurEffectIfNeeded];
}

%new
- (void)applyBlurEffectIfNeeded {
    if (DYYYGetBool(@"DYYYEnableCommentBlur") && [self isKindOfClass:NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController")]) {
        // 动态获取用户设置的透明度
        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.9;
        }

        // 应用毛玻璃效果
        [DYYYUtils applyBlurEffectToView:self.view transparency:userTransparency blurViewTag:999];
    }
}
%end

%hook AWEFeedVideoButton
- (id)touchUpInsideBlock {
    id r = %orig;

    // 只有收藏按钮才显示确认弹窗
    if (DYYYGetBool(@"DYYYCollectTips") && [self.accessibilityLabel isEqualToString:@"收藏"]) {

        dispatch_async(dispatch_get_main_queue(), ^{
          [DYYYBottomAlertView showAlertWithTitle:@"收藏确认"
                                          message:@"是否确认/取消收藏？"
                                        avatarURL:nil
                                 cancelButtonText:nil
                                confirmButtonText:nil
                                     cancelAction:nil
                                      closeAction:nil
                                    confirmAction:^{
                                      if (r && [r isKindOfClass:NSClassFromString(@"NSBlock")]) {
                                          ((void (^)(void))r)();
                                      }
                                    }];
        });

        return nil;
    }

    return r;
}
%end

%hook AWEFeedVideoButton

- (void)setImage:(id)arg1 {
    UIImage *imageToApply = arg1;
    NSString *nameString = nil;

    if ([self respondsToSelector:@selector(imageNameString)]) {
        IMP imp = [self methodForSelector:@selector(imageNameString)];
        if (imp) {
            NSString *(*func)(id, SEL) = (NSString * (*)(id, SEL)) imp;
            if (func) {
                nameString = func(self, @selector(imageNameString));
            }
        }
    }

    NSString *customFileName = DYYYCustomIconFileNameForButtonName(nameString);
    if (customFileName.length > 0) {
        UIImage *customImage = DYYYLoadCustomImage(customFileName, CGSizeMake(44.0, 44.0));
        if (customImage) {
            imageToApply = customImage;
        }
    }

    %orig(imageToApply);
}

%end

%hook AWENormalModeTabBarGeneralPlusButton
- (void)setImage:(UIImage *)image forState:(UIControlState)state {

    UIImage *imageToApply = image;
    if ([self.accessibilityLabel isEqualToString:@"拍摄"]) {
        UIImage *customImage = DYYYLoadCustomImage(@"tab_plus.png", CGSizeZero);
        if (customImage) {
            imageToApply = customImage;
        }
    }

    %orig(imageToApply, state);
}
%end

%hook AWEUserActionSheetView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableSheetBlur")) {
        [self applyBlurEffectAndWhiteText];
    }
}

%new
- (void)applyBlurEffectAndWhiteText {
    // 应用毛玻璃效果到容器视图
    if (self.containerView) {
        self.containerView.backgroundColor = [UIColor clearColor];

        // 动态获取用户设置的透明度
        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSheetBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.9; // 默认值0.9
        }

        [DYYYUtils applyBlurEffectToView:self.containerView transparency:userTransparency blurViewTag:9999];
        [DYYYUtils clearBackgroundRecursivelyInView:self.containerView];
        // 调用新的通用方法设置文本颜色，这里没有排除需求，所以传入 nil Block
        [DYYYUtils applyTextColorRecursively:[UIColor whiteColor] inView:self.containerView shouldExcludeViewBlock:nil];
    }
}

%end

%hook AWEUserTabListModel

- (NSInteger)profileLandingTab {
    if (DYYYGetBool(@"DYYYDefaultEnterWorks")) {
        return 0;
    } else {
        return %orig;
    }
}

%end

%group AutoPlay

%hook AWEAwemeDetailTableViewController

- (BOOL)hasIphoneAutoPlaySwitch {
    return YES;
}

%end

%hook AWEAwemeDetailContainerPlayControlConfig

- (BOOL)enableUserProfilePostAutoPlay {
    return YES;
}

%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)isAutoPlayOpen {
    return YES;
}

%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
    return YES;
}
%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)getFeedIphoneAutoPlayState {
    BOOL r = %orig;
    return YES;
}
%end

%end

%hook UILabel

- (void)setText:(NSString *)text {
    UIView *superview = self.superview;

    if ([superview isKindOfClass:%c(AFDFastSpeedView)] && text) {
        CGFloat displaySpeed = isGestureActive && currentLongPressSpeed > 0 ? currentLongPressSpeed : DYYYGetFloat(@"DYYYLongPressSpeed");
        if (displaySpeed == 0) {
            displaySpeed = 2.0;
        }

        NSString *speedString = [NSString stringWithFormat:@"%.2f", displaySpeed];
        if ([speedString hasSuffix:@".00"]) {
            speedString = [speedString substringToIndex:speedString.length - 3];
        } else if ([speedString hasSuffix:@"0"] && [speedString containsString:@"."]) {
            speedString = [speedString substringToIndex:speedString.length - 1];
        }

        if ([text containsString:@"2"]) {
            text = [text stringByReplacingOccurrencesOfString:@"2" withString:speedString];
        }
    }

    %orig(text);
}
%end

%hook AWEIMEmoticonPreviewV2

// 添加保存按钮
- (void)layoutSubviews {
    %orig;
    static char kHasSaveButtonKey;
    BOOL DYYYForceDownloadPreviewEmotion = DYYYGetBool(@"DYYYForceDownloadPreviewEmotion");
    if (DYYYForceDownloadPreviewEmotion) {
        if (!objc_getAssociatedObject(self, &kHasSaveButtonKey)) {
            UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *downloadIcon = [UIImage systemImageNamed:@"arrow.down.circle"];
            [saveButton setImage:downloadIcon forState:UIControlStateNormal];
            [saveButton setTintColor:[UIColor whiteColor]];
            saveButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.9 alpha:0.5];

            saveButton.layer.shadowColor = [UIColor blackColor].CGColor;
            saveButton.layer.shadowOffset = CGSizeMake(0, 2);
            saveButton.layer.shadowOpacity = 0.3;
            saveButton.layer.shadowRadius = 3;

            saveButton.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:saveButton];
            CGFloat buttonSize = 24.0;
            saveButton.layer.cornerRadius = buttonSize / 2;

            [NSLayoutConstraint activateConstraints:@[
                [saveButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-15], [saveButton.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-10],
                [saveButton.widthAnchor constraintEqualToConstant:buttonSize], [saveButton.heightAnchor constraintEqualToConstant:buttonSize]
            ]];

            saveButton.userInteractionEnabled = YES;
            [saveButton addTarget:self action:@selector(dyyy_saveButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(self, &kHasSaveButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%new
- (void)dyyy_saveButtonTapped:(UIButton *)sender {
    // 获取表情包URL
    AWEIMEmoticonModel *emoticonModel = self.model;
    if (!emoticonModel) {
        [DYYYUtils showToast:@"无法获取表情包信息"];
        return;
    }

    NSString *urlString = nil;
    MediaType mediaType = MediaTypeImage;

    // 尝试动态URL
    if ([emoticonModel valueForKey:@"animate_url"]) {
        urlString = [emoticonModel valueForKey:@"animate_url"];
    }
    // 如果没有动态URL，则使用静态URL
    else if ([emoticonModel valueForKey:@"static_url"]) {
        urlString = [emoticonModel valueForKey:@"static_url"];
    }
    // 使用animateURLModel获取URL
    else if ([emoticonModel valueForKey:@"animateURLModel"]) {
        AWEURLModel *urlModel = [emoticonModel valueForKey:@"animateURLModel"];
        if (urlModel.originURLList.count > 0) {
            urlString = urlModel.originURLList[0];
        }
    }

    if (!urlString) {
        [DYYYUtils showToast:@"无法获取表情包链接"];
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    [DYYYManager downloadMedia:url
                     mediaType:MediaTypeHeic
                         audio:nil
                    completion:^(BOOL success){
                    }];
}

%end

%hook AWEFeedTabJumpGuideView

- (void)layoutSubviews {
    %orig;
    [self removeFromSuperview];
}

%end

%hook AWEFeedLiveMarkView
- (void)setHidden:(BOOL)hidden {
    if (DYYYGetBool(@"DYYYHideAvatarLive") || DYYYGetBool(@"DYYYHideAvatarButton")) {
        hidden = YES;
    }

    %orig(hidden);
}
%end

%hook LOTAnimationView
- (void)layoutSubviews {
    %orig;
    // 旧版加号动画可能被额外容器包裹，沿父视图向上识别关注提示视图。
    if (DYYYIsLegacyAvatarFollowAnimationView(self)) {
        // 检查是否需要隐藏加号
        if (DYYYAvatarFollowOptionsEnabled()) {
            if (DYYYGetBool(@"DYYYHideFollowPromptView")) {
                DYYYRemoveAvatarView(DYYYAvatarFollowRemovalTargetForView(self, nil));
            } else {
                DYYYHideAvatarFollowLayerContents(self);
            }
            DYYYApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
            return;
        }
        // 应用透明度设置
        NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
        if (transparencyValue && transparencyValue.length > 0) {
            CGFloat alphaValue = [transparencyValue floatValue];
            self.alpha = alphaValue;
        }
    }
}
%end

%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏头像
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        self.hidden = YES;
        return;
    }

    // 应用透明度设置
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

%hook AWENearbySkyLightCapsuleView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideNearbyCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AFDCancelMuteAwemeView
- (void)layoutSubviews {
    %orig;

    UIView *superview = self.superview;

    if ([superview isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
        if (DYYYGetBool(@"DYYYHideCancelMute")) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook AWEPOIEntryAnchorView

- (void)p_addViews {
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        return;
    }
    %orig;
}

%end

%hook AWECommentGuideLunaAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }

    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        UILabel *label = nil;
        if ([self respondsToSelector:@selector(preTitleLabel)]) {
            label = [self valueForKey:@"preTitleLabel"];
        }
        if (label && [label isKindOfClass:[UILabel class]]) {
            label.text = @"";
        }
    }
}

- (void)p_didClickSong {
    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        // 通过 KVC 拿到内部的 songButton
        UIButton *btn = nil;
        if ([self respondsToSelector:@selector(songButton)]) {
            btn = (UIButton *)[self valueForKey:@"songButton"];
        }

        // 获取歌曲名并复制到剪贴板
        if (btn && [btn isKindOfClass:[UIButton class]]) {
            NSString *song = btn.currentTitle;
            if (song.length) {
                [UIPasteboard generalPasteboard].string = song;
                [DYYYToast showSuccessToastWithMessage:@"歌曲名已复制"];
            }
        }
    } else {
        %orig;
    }
}

%end

%hook AWEDiscoverFeedEntranceView
- (id)init {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        return nil;
    }
    return %orig;
}
%end

%hook AWETemplateTagsCommonView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideTemplateTags")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AFDSkylightCellBubble
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideAvatarBubble")) {
        [self removeFromSuperview];
    }
    %orig;
}
%end

%hook AWEIMMessageTabOptPushBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYHidePushBanner")) {
        return %orig(CGRectMake(frame.origin.x, frame.origin.y, 0, 0));
    }
    return %orig;
}

%end

%hook AWEIMMessageTabSideBarView
- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYHideMessageTabRedPacket")) {
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }

    NSArray<UIView *> *siblings = [parentView.subviews copy];
    if (siblings.count <= 1) {
        return;
    }

    for (UIView *subview in siblings) {
        if (subview != self) {
            [subview removeFromSuperview];
        }
    }
}
%end

%hook AWEProfileNavigationButton
- (void)setupUI {

    if (DYYYGetBool(@"DYYYHideButton")) {
        return;
    }
    %orig;
}
%end

%hook AWEFeedUnfollowFamiliarFollowAndDislikeView
- (void)showUnfollowFamiliarView {
    if (DYYYGetBool(@"DYYYHideFamiliar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEFamiliarNavView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideFamiliar")) {
        self.hidden = YES;
    }
    %orig;
}
%end

%hook AWELeftSideBarEntranceView

- (void)setRedDot:(id)redDot {
    %orig(nil);
}

- (void)setNumericalRedDot:(id)numericalRedDot {
    %orig(nil);
}

- (void)layoutSubviews {
    %orig;

    // 隐藏左侧边栏的 badge
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:%c(DUXBadge)]) {
            subview.hidden = YES;
            break;
        }
    }

    UIResponder *responder = self;
    UIViewController *parentVC = nil;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:%c(AWEFeedContainerViewController)]) {
            parentVC = (UIViewController *)responder;
            break;
        }
    }

    if (!(parentVC && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLeftSideBar"])) {
        return;
    }

    static char kDYLeftSideViewCacheKey;
    NSArray *cachedViews = objc_getAssociatedObject(self, &kDYLeftSideViewCacheKey);
    if (!cachedViews) {
        NSMutableArray *views = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBaseImageView)]) {
                [views addObject:subview];
            }
        }
        cachedViews = [views copy];
        objc_setAssociatedObject(self, &kDYLeftSideViewCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *v in cachedViews) {
        v.hidden = YES;
    }
}

%end

%hook AWEFeedVideoButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    BOOL hideBtn = NO;
    BOOL hideLabel = NO;

    if ([accessibilityLabel isEqualToString:@"点赞"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeLabel"];
    } else if ([accessibilityLabel isEqualToString:@"评论"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLabel"];
    } else if ([accessibilityLabel isEqualToString:@"分享"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareLabel"];
    } else if ([accessibilityLabel isEqualToString:@"收藏"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectLabel"];
    }

    if (!hideBtn && !hideLabel) {
        return; // 设置未启用，无需额外处理
    }

    if (hideBtn) {
        [self removeFromSuperview];
        return;
    }

    static char kDYLabelCacheKey;
    NSArray *cachedLabels = objc_getAssociatedObject(self, &kDYLabelCacheKey);
    if (!cachedLabels) {
        NSMutableArray *labels = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                [labels addObject:subview];
            }
        }
        cachedLabels = [labels copy];
        objc_setAssociatedObject(self, &kDYLabelCacheKey, cachedLabels, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UILabel *label in cachedLabels) {
        label.hidden = hideLabel;
    }
}

%end

%hook UIButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"拍照搜同款"] || [accessibilityLabel isEqualToString:@"扫一扫"]) {
        if (DYYYGetBool(@"DYYYHideScancode")) {
            [self removeFromSuperview];
        }
    }

    if ([accessibilityLabel isEqualToString:@"返回"]) {
        if (DYYYGetBool(@"DYYYHideBack")) {
            UIView *parent = self.superview;
            // 父视图是AWEBaseElementView(排除用户主页返回按钮) 按钮类不是AWENoxusHighlightButton(排除横屏返回按钮)
            if ([parent isKindOfClass:%c(AWEBaseElementView)] && ![self isKindOfClass:%c(AWENoxusHighlightButton)]) {
                [self removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEHPSearchBubbleEntranceView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideSearchBubble")) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWEFeedLiveTabTopSelectionView
- (void)setHideTimer:(id)timer {
    if (DYYYGetBool(@"DYYYDisableAutoHideLive")) {
        timer = nil;
    }
    %orig(timer);
}
%end

%hook AWEMusicCoverButton

- (void)layoutSubviews {
    %orig;
    NSString *accessibilityLabel = self.accessibilityLabel;
    if ([accessibilityLabel isEqualToString:@"音乐详情"]) {
        if (DYYYGetBool(@"DYYYHideMusicButton")) {
            UIView *parent = self.superview;
            if (parent) {
                [parent removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEGradientView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        UIView *parent = self.superview;
        if ([parent.accessibilityLabel isEqualToString:@"暂停，按钮"] || [parent.accessibilityLabel isEqualToString:@"播放，按钮"] || [parent.accessibilityLabel isEqualToString:@"“切换视角，按钮"] ||
            [parent isKindOfClass:%c(AWEStoryProgressContainerView)]) {
            self.hidden = YES;
        }
        return;
    }
    %orig;
}
%end

%hook AWEHotSpotBlurView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEHotSearchInnerBottomView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideHotSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AWELoadingAndVolumeView

- (void)layoutSubviews {
    %orig;
    self.hidden = YES;
    return;
}

%end

%hook AWEFeedRootViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) != class_getInstanceMethod([%c(AWEFeedRootViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AWELiveAudienceViewController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DYYYLiveDurationInstallFromAudienceWrapper(weakResult);
    });
    return result;
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)setAudienceViewController:(UIViewController *)audienceViewController {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)attachAudienceViewControllerDelegate:(id)delegate {
    %orig;
    DYYYLiveDurationInstallFromAudienceWrapper(self);
}

- (void)exitLiveRoomWithType:(unsigned long long)type {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook IESLiveInnerFeedLiveRoomCell

- (void)setItemModel:(id)itemModel {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setRoomAisle:(id)roomAisle {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)updateWithItemModel:(id)itemModel {
    %orig;
    DYYYLiveDurationInstallFromInnerFeedCell(self);
}

- (void)prepareForReuse {
    UIViewController *viewController = DYYYLiveDurationSafeValue(self, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DYYYLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook IESLiveAudienceViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(IESLiveAudienceViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}

- (void)viewDidLoad {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, self);
    DYYYLiveDurationUpdateView(self.view);
}

- (void)didEnterRoom:(id)room {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, room ?: self);
}

- (void)didPreloadRoom:(id)room {
    %orig;
    DYYYLiveDurationInstallOnView(self.view, room ?: self);
}

- (void)didCloseRoom:(id)room closeType:(unsigned long long)type {
    DYYYLiveDurationRemoveFromView(self.view);
    %orig;
}

- (void)dealloc {
    if (self.isViewLoaded) {
        DYYYLiveDurationRemoveFromView(self.view);
    }
    %orig;
}
%end

%hook AWEAwemeDetailTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEAwemeDetailTableViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AWEAwemeHotSpotTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEAwemeHotSpotTableViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AWEFullPageFeedNewContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEFullPageFeedNewContainerViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AFDPureModePageContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AFDPureModePageContainerViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AWESearchEntranceView

- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideSearchEntrance")) {
        self.hidden = YES;
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSearchEntranceIndicator"]) {
        static char kDYSearchIndicatorKey;
        NSArray *indicatorViews = objc_getAssociatedObject(self, &kDYSearchIndicatorKey);
        if (!indicatorViews) {
            NSMutableArray *tmp = [NSMutableArray array];
            for (UIView *subviews in self.subviews) {
                if ([subviews isKindOfClass:%c(UIImageView)] && [NSStringFromClass([((UIImageView *)subviews).image class]) isEqualToString:@"_UIResizableImage"]) {
                    [tmp addObject:subviews];
                }
            }
            indicatorViews = [tmp copy];
            objc_setAssociatedObject(self, &kDYSearchIndicatorKey, indicatorViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIImageView *imgView in indicatorViews) {
            imgView.hidden = YES;
        }
    }

    %orig;
}

%end

%hook AWEStoryProgressSlideView

- (void)layoutSubviews {
    %orig;

    BOOL shouldHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideStoryProgressSlide"];
    if (!shouldHide)
        return;

    static char kDYStoryProgressCacheKey;
    UIView *targetView = objc_getAssociatedObject(self, &kDYStoryProgressCacheKey);
    if (!targetView) {
        for (UIView *obj in self.subviews) {
            if ([obj isKindOfClass:NSClassFromString(@"UISlider")] || obj.frame.size.height < 5) {
                targetView = obj.superview;
                break;
            }
        }
        if (targetView) {
            objc_setAssociatedObject(self, &kDYStoryProgressCacheKey, targetView, OBJC_ASSOCIATION_ASSIGN);
        }
    }

    if (targetView) {
        targetView.hidden = YES;
    }
}

%end

%hook AFDNewFastReplyView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHidePrivateMessages")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWEFeedLiveTabRevisitControlView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLiveDiscovery")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveDynamicRankListEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook _TtC18IESLiveRevenueImpl34IESLiveDynamicRankListEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveMatrixEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveShortTouchActionView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveLotteryAnimationViewNew
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveConfigurableShortTouchEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveRedEnvelopeAniLynxView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTouchView")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESLiveKTVSongIndicatorView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideKTVSongIndicator")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook UILabel

static NSHashTable *processedParentViews = nil;

+ (void)load {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      processedParentViews = [NSHashTable weakObjectsHashTable];
    });
}

- (void)layoutSubviews {
    %orig;

    BOOL hideRightLabel = DYYYGetBool(@"DYYYHideRightLabel");
    if (!hideRightLabel)
        return;

    NSString *accessibilityLabel = self.accessibilityLabel;
    if (!accessibilityLabel || accessibilityLabel.length == 0)
        return;

    // 避免重复处理同一个父视图
    UIView *parentView = self.superview;
    if (!parentView)
        return;

    @synchronized(processedParentViews) {
        if ([processedParentViews containsObject:parentView]) {
            return;
        }
    }

    NSString *trimmedLabel = [accessibilityLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL shouldRemove = NO;

    if ([trimmedLabel hasSuffix:@"人共创"] && trimmedLabel.length > 3) {
        NSString *prefix = [trimmedLabel substringToIndex:trimmedLabel.length - 3];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        shouldRemove = ([prefix rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
    }

    if (!shouldRemove) {
        shouldRemove = [trimmedLabel isEqualToString:@"章节要点"] || [trimmedLabel isEqualToString:@"图集"] || [trimmedLabel isEqualToString:@"下一章"];
    }

    if (shouldRemove) {
        @synchronized(processedParentViews) {
            [processedParentViews addObject:parentView];
        }

        UIView *grandparentView = parentView.superview; // 爷爷视图

        if (grandparentView) {

            dispatch_async(dispatch_get_main_queue(), ^{
              if ([grandparentView isKindOfClass:[UIStackView class]]) {
                  UIStackView *stackView = (UIStackView *)grandparentView;
                  [stackView removeArrangedSubview:parentView];
              }

              [parentView removeFromSuperview];

              // 强制刷新爷爷视图布局
              [grandparentView setNeedsLayout];
              [grandparentView layoutIfNeeded];
            });
        }
    }
}

%end

%hook AWEFeedMultiTabSelectedContainerView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideTopBarLine")) {
        self.hidden = YES;
    }
}

%end

%hook AWEProfileMixItemCollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([self.accessibilityLabel isEqualToString:@"私密作品"]) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook AWEProfilePostEmptyPublishGuideCollectionViewCell

- (void)didMoveToSuperview {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([(UIView *)self superview]) {
            [(UIView *)self setHidden:YES];
        }
    }
}

%end

%hook AWEProfileTaskCardStyleListCollectionViewCell
- (BOOL)shouldShowPublishGuide {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return NO;
    }
    return %orig;
}
%end

%hook AWEProfileRichEmptyView

- (void)setTitle:(id)title {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(title);
}

- (void)setDetail:(id)detail {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(detail);
}
%end

%hook AWENewLiveSkylightViewController

- (void)showSkylight:(BOOL)arg0 animated:(BOOL)arg1 actionMethod:(unsigned long long)arg2 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        return;
    }
    %orig(arg0, arg1, arg2);
}

- (void)updateIsSkylightShowing:(BOOL)arg0 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        %orig(NO);
    } else {
        %orig(arg0);
    }
}

%end

%hook AWELiveSkylightViewModel

- (id)dataSource {
	BOOL DYYYHideConcernCapsuleView = DYYYGetBool(@"DYYYHideConcernCapsuleView");
	if (DYYYHideConcernCapsuleView) {
		return nil;
	}
	return %orig;
}

- (void)setDataSource:(id)dataSource {
	BOOL DYYYHideConcernCapsuleView = DYYYGetBool(@"DYYYHideConcernCapsuleView");
	if (DYYYHideConcernCapsuleView) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWELiveAutoEnterStyleAView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLiveView")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWENearbyFullScreenViewModel

- (void)setShowSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

- (void)setHaveSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

%end

%hook AWEHPDiscoverFeedEntranceView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDiscover")) {
        UIView *firstSubview = self.subviews.firstObject;
        if ([firstSubview isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)firstSubview).image = nil;
        }
    }
}

%end

%hook AWEIMCellLiveStatusContainerView

- (void)p_initUI {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideGroupLiveIndicator"])
        %orig;
}
%end

%hook AWELiveStatusIndicatorView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupLiveIndicator")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWELiveFeedLabelTagView
- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideLiveCapsuleView")) {
        UIView *parentView = self.superview;
        if (parentView) {
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

%hook AWEHPTopTabItemBadgeContentView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideConcernCapsuleView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEIMFansGroupTopDynamicDomainTemplateView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupShop")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEIMInputActionBarInteractor

- (void)p_setupUI {
    if (DYYYGetBool(@"DYYYHideGroupInputActionBar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWETemplateCommonView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCameraLocation")) {
        [self removeFromSuperview];
    }
}
%end

%hook AWEHPTopBarCTAItemView

- (void)showRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)hideCountRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSidebarDot"]) {
        return;
    }

    static char kDYSidebarBadgeCacheKey;
    NSArray *cachedBadges = objc_getAssociatedObject(self, &kDYSidebarBadgeCacheKey);
    if (!cachedBadges) {
        NSMutableArray *badges = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBadge)]) {
                [badges addObject:subview];
            }
        }
        cachedBadges = [badges copy];
        objc_setAssociatedObject(self, &kDYSidebarBadgeCacheKey, cachedBadges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *badge in cachedBadges) {
        badge.hidden = YES;
    }
}
%end

%hook ACCStickerContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideSearchSame")) {
        [self removeFromSuperview];
    }
}
%end

%hook BDXWebView
- (void)layoutSubviews {
    %orig;

    BOOL enabled = DYYYGetBool(@"DYYYHideGiftPavilion");
    if (!enabled)
        return;

    NSString *title = [self valueForKey:@"title"];

    if ([title containsString:@"任务Banner"] || [title containsString:@"活动Banner"]) {
        self.hidden = YES;
    }
}
%end

%hook AWEVideoTypeTagView

- (void)setupUI {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideLiveGIF"])
        %orig;
}
%end

%hook IESLiveFeedDrawerEntranceView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLivePlayground")) {
        self.hidden = YES;
    }
}

%end

%hook IESLiveButton

- (void)layoutSubviews {
    %orig;
    BOOL hideClear = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomClear"];
    BOOL hideMirror = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomMirroring"];
    BOOL hideFull = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomFullscreen"];
    BOOL hideClose = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomClose"];

    if (!(hideClear || hideMirror || hideFull)) {
        return;
    }

    NSString *label = self.accessibilityLabel;
    if (hideClear && [label isEqualToString:@"退出清屏"] && self.superview) {
        [self.superview removeFromSuperview];
        return;
    } else if (hideMirror && [label isEqualToString:@"投屏"] && self.superview) {
        self.superview.hidden = YES;
        return;
    } else if (hideFull && [label isEqualToString:@"横屏"] && self.superview) {
        static char kDYLiveButtonCacheKey;
        NSArray *cached = objc_getAssociatedObject(self, &kDYLiveButtonCacheKey);
        if (!cached) {
            cached = [self.subviews copy];
            objc_setAssociatedObject(self, &kDYLiveButtonCacheKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *subview in cached) {
            subview.hidden = YES;
        }
        return;
    } else if (hideClose && [self.superview isKindOfClass:%c(HTSLive4LayerContainerView)]) {
        self.hidden = YES;
        return;
    }
}

%end

%hook IESLiveLayoutPlaceholderView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveRoomClose")) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWELiveFlowAlertView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCellularAlert")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook IESECLivePluginLayoutView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESECLiveGoodsCardView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveBottomRightCardView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEPOILivePurchaseAtmosphereView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg") && self.superview) {
        self.superview.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveActivityBannnerView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook HTSLiveDiggView
- (void)setIconImageView:(UIImageView *)arg1 {
    if (DYYYGetBool(@"DYYYHideLiveLikeAnimation")) {
        %orig(nil);
    } else {
        %orig(arg1);
    }
}
%end

%hook IESLiveStickerView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideStickerView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook IESLiveGroupLiveComponentView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGroupComponent")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook IESLiveDynamicUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook _TtC18IESLiveRevenueImpl32IESLiveSwiftDynamicUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook PlatformCanvasView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        UIView *pview = self.superview;
        UIView *gpview = pview.superview;
        // 基于accessibilitylabel的判断
        BOOL isLynxView = [pview isKindOfClass:%c(UILynxView)] && [gpview isKindOfClass:%c(LynxView)] && [gpview.accessibilityLabel isEqualToString:@"lynxview"];
        // 基于最近的视图控制器IESLiveAudienceViewController的判断
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        BOOL isLiveAudienceVC = [vc isKindOfClass:%c(IESLiveAudienceViewController)];
        if (isLynxView && isLiveAudienceVC) {
            self.hidden = YES;
        }
    }
    return;
}
%end

%hook _TtC18IESLiveRevenueImpl35IESLiveSwiftVideoLayerUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveDanmakuVariousView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}

%end

%hook IESLiveDanmakuSupremeView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLiveHotMessageView
- (void)layoutSubviews {

    if (DYYYGetBool(@"DYYYHideLiveHotMessage")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AFDFriendRecommendTagView

- (void)layoutSubviews {
	if (DYYYGetBool(@"DYYYHideFriendRecommend")) {
		self.hidden = YES;
		return;
	}
	%orig;
}

%end

%hook AWEAwesomeSplashFeedCellOldAccessoryView

// 在方法入口处添加控制逻辑
- (id)ddExtraView {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return NULL; // 返回空视图
	}

	// 正常模式调用原始方法
	return %orig;
}

%end

%hook AWETeenModeAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end

%hook AWETeenModeSimpleAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end

%hook MTKView

- (void)layoutSubviews {
    %orig;
    DYYYDisableExtendedRangeForLayer(self.layer);
    UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
    Class playVCClass = NSClassFromString(@"AWEPlayVideoViewController");
    if (vc && playVCClass && [vc isKindOfClass:playVCClass]) {
        NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYVideoBGColor"];
        if (colorHex && colorHex.length > 0) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            UIColor *customColor = [DYYYUtils colorFromSchemeHexString:colorHex targetWidth:screenWidth];
            if (customColor)
                self.backgroundColor = customColor;
        }
    }
}

%end

%hook AFDPrivacyHalfScreenViewController

%new
- (void)updateDarkModeAppearance {
    BOOL isDarkMode = [DYYYUtils isDarkMode];

    UIView *contentView = self.view.subviews.count > 1 ? self.view.subviews[1] : nil;
    if (contentView) {
        if (isDarkMode) {
            contentView.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.13 alpha:1.0];
        } else {
            contentView.backgroundColor = [UIColor whiteColor];
        }
    }

    // 修改标题文本颜色
    if (self.titleLabel) {
        if (isDarkMode) {
            self.titleLabel.textColor = [UIColor whiteColor];
        } else {
            self.titleLabel.textColor = [UIColor blackColor];
        }
    }

    // 修改内容文本颜色
    if (self.contentLabel) {
        if (isDarkMode) {
            self.contentLabel.textColor = [UIColor lightGrayColor];
        } else {
            self.contentLabel.textColor = [UIColor darkGrayColor];
        }
    }

    // 修改左侧按钮颜色和文字颜色
    if (self.leftCancelButton) {
        if (isDarkMode) {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.25 green:0.25 blue:0.25 alpha:1.0]]; // 暗色模式按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];          // 暗色模式文字颜色
        } else {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]]; // 默认按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];        // 默认文字颜色
        }
    }
}

- (void)viewDidLoad {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)configWithImageView:(UIImageView *)imageView
                  lockImage:(UIImage *)lockImage
           defaultLockState:(BOOL)defaultLockState
             titleLabelText:(NSString *)titleText
           contentLabelText:(NSString *)contentText
       leftCancelButtonText:(NSString *)leftButtonText
     rightConfirmButtonText:(NSString *)rightButtonText
       rightBtnClickedBlock:(void (^)(void))rightBtnBlock
     leftButtonClickedBlock:(void (^)(void))leftBtnBlock {

    %orig;
    [self updateDarkModeAppearance];
}

%end

%hook UITextField

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook UITextView

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook AWENormalModeTabBarPlusButton

- (void)setHidden:(BOOL)hidden {
    BOOL hidePlus = DYYYGetBool(@"DYYYHidePlusButton");
    %orig(hidePlus ? YES : hidden);

    if (hidePlus) {
        self.userInteractionEnabled = NO;
    }
}

- (void)didMoveToWindow {
    %orig;

    if (self.window && DYYYGetBool(@"DYYYHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

%end

%hook AWENormalModeTabBar

static Class barBackgroundClass = nil;
static Class generalButtonClass = nil;
static Class plusContainerButtonClass = nil;
static Class plusButtonClass = nil;
static Class plusInnerButtonClass = nil;
static Class tabBarButtonClass = nil;

+ (void)initialize {
    if (self == [%c(AWENormalModeTabBar) class]) {
        barBackgroundClass = NSClassFromString(@"_UIBarBackground");
        generalButtonClass = %c(AWENormalModeTabBarGeneralButton);
        plusContainerButtonClass = %c(AWENormalModeTabBarPlusButton);
        plusButtonClass = %c(AWENormalModeTabBarGeneralPlusButton);
        plusInnerButtonClass = %c(AWENormalModeTabBarGeneralPlusInnerButton);
        tabBarButtonClass = %c(UITabBarButton);
    }
}

%new
- (void)initializeOriginalTabBarHeight {
    if (originalTabBarHeight != kInvalidHeight) {
        if (gCurrentTabBarHeight == kInvalidHeight) {
            gCurrentTabBarHeight = originalTabBarHeight;
        }
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Skipped! originalTabBarHeight already initialized as %.1f.", originalTabBarHeight);
        return;
    }

    UIWindow *targetWindow = self.window ?: [DYYYUtils getActiveWindow];
    if (self.frame.size.height >= 30) {
        originalTabBarHeight = self.frame.size.height;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Success! originalTabBarHeight set to %.1f (from self.frame.size.height)", originalTabBarHeight);
    } else if (targetWindow) {
        CGFloat bottomInset = targetWindow.safeAreaInsets.bottom;
        originalTabBarHeight = 49 + bottomInset;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Success! originalTabBarHeight set to %.1f (fallback calculation: 49.0 + %.1f)", originalTabBarHeight, bottomInset);
    } else {
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: Failed! No window available.");
    }
    if (originalTabBarHeight != kInvalidHeight) {
        gCurrentTabBarHeight = originalTabBarHeight;
        NSLog(@"[DYYY] initializeOriginalTabBarHeight: gCurrentTabBarHeight synced to %.1f.", gCurrentTabBarHeight);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self initializeOriginalTabBarHeight];
    }
}

- (void)layoutSubviews {
    %orig;

    if (originalTabBarHeight == kInvalidHeight) {
        NSLog(@"[DYYY] layoutSubviews: Fallback! originalTabBarHeight initialization triggered.");
        [self initializeOriginalTabBarHeight];
    }

    if (gCurrentTabBarHeight == kInvalidHeight) {
        gCurrentTabBarHeight = originalTabBarHeight;
        NSLog(@"[DYYY] layoutSubviews: gCurrentTabBarHeight fallback synced to %.1f.", gCurrentTabBarHeight);
    }

    BOOL hideShop = DYYYGetBool(@"DYYYHideShopButton");
    BOOL hideMsg = DYYYGetBool(@"DYYYHideMessageButton");
    BOOL hideFri = DYYYGetBool(@"DYYYHideFriendsButton");
    BOOL hideMe = DYYYGetBool(@"DYYYHideMyButton");
    BOOL hidePlus = DYYYGetBool(@"DYYYHidePlusButton");
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);

    NSMutableArray *visibleButtons = [NSMutableArray array];
    UIView *ipadContainerView = nil;

    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
            [subview isKindOfClass:plusInnerButtonClass]) {
            NSString *label = subview.accessibilityLabel;
            BOOL isPlusButton = [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] || [subview isKindOfClass:plusInnerButtonClass] ||
                                [label isEqualToString:@"拍摄"];
            BOOL shouldHide = (isPlusButton && hidePlus) || ([label containsString:@"商城"] && hideShop) || ([label containsString:@"消息"] && hideMsg) || ([label containsString:@"朋友"] && hideFri) ||
                              ([label isEqualToString:@"我"] && hideMe);

            subview.userInteractionEnabled = !shouldHide;
            subview.hidden = shouldHide;

            if (!shouldHide) {
                [visibleButtons addObject:subview];
            }
        } else if ([subview isKindOfClass:tabBarButtonClass]) {
            subview.userInteractionEnabled = NO;
            subview.hidden = YES;
        } else if (isPad && !ipadContainerView && [subview isMemberOfClass:UIView.class] && fabs(subview.frame.size.width - self.bounds.size.width) > 0.1) {
            ipadContainerView = subview;
        }
    }

    [visibleButtons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
      return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];

    CGFloat offsetX, totalWidth;
    if (ipadContainerView) {
        offsetX = ipadContainerView.frame.origin.x;
        totalWidth = ipadContainerView.bounds.size.width;
    } else {
        offsetX = 0;
        totalWidth = self.bounds.size.width;
    }
    CGFloat buttonWidth = (visibleButtons.count > 0) ? (totalWidth / visibleButtons.count) : 0;

    // 均匀布局按钮
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIView *button = visibleButtons[i];
        button.frame = CGRectMake(offsetX + i * buttonWidth, button.frame.origin.y, buttonWidth, button.frame.size.height);
    }

    // 禁用首页刷新功能
    if (DYYYGetBool(@"DYYYDisableHomeRefresh")) {
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:generalButtonClass]) {
                AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;
                if ([button.accessibilityLabel isEqualToString:@"首页"]) {
                    // status == 2 表示选中状态
                    button.userInteractionEnabled = (button.status != 2);
                }
            }
        }
    }

    // 背景和分隔线处理
    BOOL hideBottomBg = DYYYGetBool(@"DYYYHideBottomBg");
    BOOL enableFullScreen = DYYYGetBool(@"DYYYEnableFullScreen");

    if (hideBottomBg || enableFullScreen) {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = YES;
        }

        BOOL isHomeSelected = NO;
        BOOL isFriendsSelected = NO;

        if (enableFullScreen && !hideBottomBg) {
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:generalButtonClass]) {
                    AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;
                    if (button.status == 2) {
                        if ([button.accessibilityLabel isEqualToString:@"首页"])
                            isHomeSelected = YES;
                        else if ([button.accessibilityLabel containsString:@"朋友"])
                            isFriendsSelected = YES;
                    }
                }
            }
        }

        BOOL hideFriendsButton = DYYYGetBool(@"DYYYHideFriendsButton");
        BOOL shouldHideBackgrounds = hideBottomBg || (enableFullScreen && (isHomeSelected || (isFriendsSelected && !hideFriendsButton)));

        // 单次遍历处理所有背景和分割线
        for (UIView *subview in self.subviews) {
            // 跳过底栏按钮
            if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
                [subview isKindOfClass:plusInnerButtonClass]) {
                continue;
            }
            // 隐藏底栏背景
            if ([subview isKindOfClass:barBackgroundClass] || ([subview isMemberOfClass:[UIView class]] && originalTabBarHeight > 0 && fabs(subview.frame.size.height - gCurrentTabBarHeight) < 0.1)) {
                subview.hidden = shouldHideBackgrounds;
            }
            // 隐藏细分割线
            if (subview.frame.size.height > 0 && subview.frame.size.height < 1 && subview.frame.size.width > 300) {
                subview.hidden = enableFullScreen;
            }
        }
    } else {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = NO;
        }

        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:barBackgroundClass] || [subview isMemberOfClass:[UIView class]]) {
                subview.hidden = NO;
            }
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    BOOL disableHomeRefresh = DYYYGetBool(@"DYYYDisableHomeRefresh");
    BOOL enableFullScreen = DYYYGetBool(@"DYYYEnableFullScreen");
    BOOL hideBottomBg = DYYYGetBool(@"DYYYHideBottomBg");
    BOOL hideFriendsButton = DYYYGetBool(@"DYYYHideFriendsButton");

    BOOL isHomeSelected = NO;
    BOOL isFriendsSelected = NO;

    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:generalButtonClass]) {
            AWENormalModeTabBarGeneralButton *button = (AWENormalModeTabBarGeneralButton *)subview;

            // 禁用首页刷新功能
            if (disableHomeRefresh && [button.accessibilityLabel isEqualToString:@"首页"]) {
                button.userInteractionEnabled = (button.status != 2);
            }

            // 检查当前选中的页
            if (enableFullScreen && button.status == 2) {
                if ([button.accessibilityLabel isEqualToString:@"首页"]) {
                    isHomeSelected = YES;
                } else if ([button.accessibilityLabel containsString:@"朋友"]) {
                    isFriendsSelected = YES;
                }
            }
        }
    }

    if (hideBottomBg || enableFullScreen) {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = YES;
        }

        BOOL shouldHideBackgrounds = NO;
        if (hideBottomBg) {
            shouldHideBackgrounds = YES;
        } else if (enableFullScreen) {
            shouldHideBackgrounds = isHomeSelected || (isFriendsSelected && !hideFriendsButton);
        }

        // 处理所有背景和分割线
        for (UIView *subview in self.subviews) {
            CGFloat subviewHeight = subview.frame.size.height;
            // 跳过底栏按钮
            if ([subview isKindOfClass:generalButtonClass] || [subview isKindOfClass:plusContainerButtonClass] || [subview isKindOfClass:plusButtonClass] ||
                [subview isKindOfClass:plusInnerButtonClass]) {
                continue;
            }
            // 隐藏底栏背景
            if ([subview isKindOfClass:barBackgroundClass] || ([subview isMemberOfClass:[UIView class]] && originalTabBarHeight > 0 && fabs(subviewHeight - gCurrentTabBarHeight) < 0.1)) {
                subview.hidden = shouldHideBackgrounds;
            }
            // 隐藏细分割线
            if (subviewHeight > 0 && subviewHeight < 1 && subview.frame.size.width > 300) {
                subview.hidden = enableFullScreen;
            }
        }
    } else {
        if (self.skinContainerView) {
            self.skinContainerView.hidden = NO;
        }
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:barBackgroundClass] || [subview isMemberOfClass:[UIView class]]) {
                subview.hidden = NO;
            }
        }
    }
}

%end

%hook AWETabBarElementContainerView

- (void)setHidden:(BOOL)hidden {
    if (DYYYGetBool(@"DYYYHidePadTabBarElements")) {
        %orig(YES);
        return;
    }

    %orig(hidden);
}

%end

%hook AWENormalModeTabBarBadgeContainerView

- (void)layoutSubviews {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideBottomDot"]) {
        return;
    }

    static char kDYBadgeCacheKey;
    NSArray *badges = objc_getAssociatedObject(self, &kDYBadgeCacheKey);
    if (!badges) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in [self subviews]) {
            if ([subview isKindOfClass:NSClassFromString(@"DUXBadge")]) {
                [tmp addObject:subview];
            }
        }
        badges = [tmp copy];
        objc_setAssociatedObject(self, &kDYBadgeCacheKey, badges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *badge in badges) {
        badge.hidden = YES;
    }
}

%end

%hook AWENormalModeTabBarGeneralButton

- (BOOL)enableRefresh {
    if ([self.accessibilityLabel isEqualToString:@"首页"]) {
        if (DYYYGetBool(@"DYYYDisableHomeRefresh")) {
            return NO;
        }
    }
    return %orig;
}

%end

%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    @try {
        %orig;

        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYIndexTitle"];
        NSString *friendsTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFriendsTitle"];
        NSString *msgTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYMsgTitle"];
        NSString *selfTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSelfTitle"];

        if (!(indexTitle.length || friendsTitle.length || msgTitle.length || selfTitle.length)) {
            return;
        }

        static char kDYTabTextLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDYTabTextLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }

            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }

            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }

            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDYTabTextLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }

            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }

            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"朋友"] && friendsTitle.length > 0) {
                label.text = friendsTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"消息"] && msgTitle.length > 0) {
                label.text = msgTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"我"] && selfTitle.length > 0) {
                label.text = selfTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }

    } @catch (NSException *exception) {
        return;
    }
}
%end

%hook AWENormalModeTabBarFeedView

- (void)layoutSubviews {
    @try {
        %orig;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDoubleColumnEntry"]) {
            return;
        }

        static char kDYDoubleColumnCacheKey;
        static char kDYDoubleColumnCountKey;
        NSArray *cachedViews = objc_getAssociatedObject(self, &kDYDoubleColumnCacheKey);
        NSNumber *cachedCount = objc_getAssociatedObject(self, &kDYDoubleColumnCountKey);
        if (!cachedViews || cachedCount.unsignedIntegerValue != self.subviews.count) {
            NSMutableArray *views = [NSMutableArray array];
            for (UIView *subview in self.subviews) {
                if (![subview isKindOfClass:[UILabel class]]) {
                    [views addObject:subview];
                }
            }
            cachedViews = [views copy];
            objc_setAssociatedObject(self, &kDYDoubleColumnCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, &kDYDoubleColumnCountKey, @(self.subviews.count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIView *v in cachedViews) {
            v.hidden = YES;
        }

        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYIndexTitle"];

        if (!(indexTitle.length)) {
            return;
        }

        static char kDYTabFeedLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDYTabFeedLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }

            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }

            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }

            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDYTabFeedLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }

            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }

            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }

    } @catch (NSException *exception) {
        return;
    }
}
%end

%hook AWEConcernCellLastView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen") && gCurrentTabBarHeight > 0) {
        for (UIView *subview in self.subviews) {
            CGRect frame = subview.frame;
            frame.origin.y -= gCurrentTabBarHeight;
            subview.frame = frame;
        }
    }
}
%end

%hook AWECommentInputBackgroundView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideComment")) {
        [self removeFromSuperview];
        return;
    }

    CGAffineTransform newTransform = CGAffineTransformMakeTranslation(0, originalTabBarHeight - gCurrentTabBarHeight);

    if (!CGAffineTransformEqualToTransform(self.transform, newTransform)) {
        self.transform = newTransform;
    }
}
%end

%hook AWECommentContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = YES;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {

            UIView *parentView = self.view.superview;
            if (parentView) {
                for (UIView *subview in parentView.subviews) {
                    if ([subview.accessibilityLabel isEqualToString:@"搜索"]) {
                        CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
                        subview.alpha = finalAlpha;
                    }
                }
            }
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = NO;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYEnableCommentBlur"))
        return;

    Class containerViewClass = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    NSArray<UIView *> *containerViews = [DYYYUtils findAllSubviewsOfClass:containerViewClass inContainer:self.view];
    for (UIView *containerView in containerViews) {
        for (UIView *subview in containerView.subviews) {
            if (subview.hidden == NO && subview.backgroundColor && CGColorGetAlpha(subview.backgroundColor.CGColor) == 1) {
                float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
                if (userTransparency <= 0 || userTransparency > 1) {
                    userTransparency = 0.8;
                }
                [DYYYUtils applyBlurEffectToView:subview transparency:userTransparency blurViewTag:999];
            }
        }
    }

    Class middleContainerClass = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputViewMiddleContainer");
    NSArray<UIView *> *middleContainers = [DYYYUtils findAllSubviewsOfClass:middleContainerClass inContainer:self.view];
    for (UIView *middleContainer in middleContainers) {
        BOOL containsDanmu = NO;
        for (UIView *innerSubviewCheck in middleContainer.subviews) {
            if ([innerSubviewCheck isKindOfClass:[UILabel class]] && [((UILabel *)innerSubviewCheck).text containsString:@"弹幕"]) {
                containsDanmu = YES;
                break;
            }
        }

        if (containsDanmu) {
            UIView *parentView = middleContainer.superview;
            for (UIView *innerSubview in parentView.subviews) {
                if ([innerSubview isKindOfClass:[UIView class]]) {
                    if (innerSubview.subviews.count > 0) {
                        innerSubview.subviews[0].hidden = YES;
                    }

                    UIView *whiteBackgroundView = [[UIView alloc] initWithFrame:innerSubview.bounds];
                    whiteBackgroundView.backgroundColor = [UIColor whiteColor];
                    whiteBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    [innerSubview addSubview:whiteBackgroundView];
                    break;
                }
            }
        } else {
            for (UIView *subview in middleContainer.subviews) {
                if (subview.hidden == NO && subview.backgroundColor && CGColorGetAlpha(subview.backgroundColor.CGColor) == 1) {
                    [DYYYUtils applyBlurEffectToView:subview transparency:0.2f blurViewTag:999];
                }
            }
        }
    }
}

%end

%hook AWEListKitMagicCollectionView

- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYEnableCommentBlur")) {
        return;
    }

    UICollectionView *collectionView = (UICollectionView *)self;

    UIView *superview = collectionView.superview;
    CGRect targetFrame = superview.bounds;
    if (superview == nil || CGSizeEqualToSize(targetFrame.size, CGSizeZero) || CGRectEqualToRect(collectionView.frame, targetFrame)) {
        return;
    }

    collectionView.frame = targetFrame;

    CGFloat commentOffset = 166.0;

    UIEdgeInsets inset = collectionView.contentInset;
    inset.bottom = commentOffset;
    collectionView.contentInset = inset;
    collectionView.scrollIndicatorInsets = inset;
}

%end

%hook UIView

- (void)setHidden:(BOOL)hidden {
    BOOL shouldForceHidden = DYYYShouldForceAvatarActionViewHidden(self) || DYYYShouldForceAvatarSurroundingViewHidden(self);
    %orig(shouldForceHidden ? YES : hidden);
}

- (void)didAddSubview:(UIView *)subview {
    %orig(subview);

    if (!subview) {
        return;
    }

    BOOL hasSuppressedChrome = objc_getAssociatedObject(self, &kDYYYAvatarActionChromeViewKey) != nil;
    BOOL isAvatarFollowScope = objc_getAssociatedObject(self, &kDYYYAvatarFollowScopeViewKey) != nil;
    if ((!hasSuppressedChrome && !isAvatarFollowScope) || !DYYYAvatarFollowOptionsEnabled()) {
        return;
    }

    if (hasSuppressedChrome) {
        DYYYClearAvatarActionSubviewChrome(subview);
        DYYYHideAvatarAuxiliaryActionVisualsInView(subview);
    }

    if (isAvatarFollowScope) {
        DYYYApplyAvatarFollowSettingsInView(subview, self);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (!hideButton || !hideButton.isElementsHidden) {
        DYYYRestoreClearTargetViewStateIfNeeded(self);
    }
}

- (id)initWithFrame:(CGRect)frame {
    UIView *view = %orig;
    if (hideButton && hideButton.isElementsHidden) {
        for (NSString *className in targetClassNames) {
            if ([view isKindOfClass:NSClassFromString(className)]) {
                if ([view isKindOfClass:NSClassFromString(@"AWELeftSideBarEntranceView")]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      UIViewController *controller = [hideButton findViewController:view];
                      if ([controller isKindOfClass:NSClassFromString(@"AWEFeedContainerViewController")]) {
                          DYYYApplyClearTargetViewHiddenState(view);
                      }
                    });
                    break;
                }
                DYYYApplyClearTargetViewHiddenState(view);
                break;
            }
        }
    }
    return view;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setBackgroundColor:backgroundColor];
        });
        return;
    }

    if (DYYYShouldClearAvatarActionViewChrome(self)) {
        %orig([UIColor clearColor]);
        return;
    }

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        if ([vc isKindOfClass:%c(AWEAwemeDetailTableViewController)] ||
            [vc isKindOfClass:%c(AWEAwemeDetailCellViewController)]) {
            %orig([UIColor clearColor]);
            return;
        }
    }

    %orig(backgroundColor);
}

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        if (self.frame.size.height == originalTabBarHeight && originalTabBarHeight > 0) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
            if ([vc isKindOfClass:NSClassFromString(@"AWEMixVideoPanelDetailTableViewController")] || [vc isKindOfClass:NSClassFromString(@"AWECommentInputViewController")] ||
                [vc isKindOfClass:NSClassFromString(@"AWEAwemeDetailTableViewController")]) {
                self.backgroundColor = [UIColor clearColor];
            }
        }
    }

    if (DYYYGetBool(@"DYYYEnableFullScreen") || DYYYGetBool(@"DYYYEnableCommentBlur")) {
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        if ([vc isKindOfClass:%c(AWEPlayInteractionViewController)]) {
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:[UIView class]] && subview.backgroundColor && CGColorEqualToColor(subview.backgroundColor.CGColor, [UIColor blackColor].CGColor)) {
                    subview.hidden = YES;
                }
            }
        }
    }
}

- (void)setFrame:(CGRect)frame {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setFrame:frame];
        });
        return;
    }

    BOOL enableBlur = DYYYGetBool(@"DYYYEnableCommentBlur");
    BOOL enableFS = DYYYGetBool(@"DYYYEnableFullScreen");

    UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
    Class DetailVCClass = NSClassFromString(@"AWEMixVideoPanelDetailTableViewController");
    Class PlayVCClass1 = NSClassFromString(@"AWEAwemePlayVideoViewController");
    Class PlayVCClass2 = NSClassFromString(@"AWEDPlayerFeedPlayerViewController");
    Class PlayVCClass3 = NSClassFromString(@"AWEDPlayerViewController_Merge");

    BOOL isDetailVC = (DetailVCClass && [vc isKindOfClass:DetailVCClass]);
    BOOL isPlayVC = ((PlayVCClass1 && [vc isKindOfClass:PlayVCClass1]) ||
                     (PlayVCClass2 && [vc isKindOfClass:PlayVCClass2]) ||
                     (PlayVCClass3 && [vc isKindOfClass:PlayVCClass3]));

    if (isPlayVC && enableBlur) {
        if (frame.origin.x != 0) {
            return;
        }
    }

    if (isPlayVC && enableFS) {
        if (frame.origin.x != 0 && frame.origin.y != 0) {
            %orig(frame);
            return;
        }
        CGRect superF = self.superview.frame;
        if (CGRectGetHeight(superF) > 0 && CGRectGetHeight(frame) > 0 && CGRectGetHeight(frame) < CGRectGetHeight(superF)) {
            CGFloat diff = CGRectGetHeight(superF) - CGRectGetHeight(frame);
            if (fabs(diff - gCurrentTabBarHeight) < 1.0) {
                frame.size.height = CGRectGetHeight(superF);
            }
        }

        %orig(frame);
        return;
    }
    %orig(frame);
}

%new
- (void)dyyy_applyGlobalTransparency {
    if ([NSThread isMainThread]) {
        if (self.window && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG) {
            NSNumber *stored = objc_getAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey);
            CGFloat baseAlpha = stored ? stored.floatValue : self.alpha;
            if (!stored) {
                objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGFloat finalAlpha = baseAlpha;
            if (gGlobalTransparency != kInvalidAlpha) {
                CGFloat clampedAlpha = MIN(MAX(baseAlpha, 0.0), 1.0);
                finalAlpha = clampedAlpha * gGlobalTransparency;
            }
            if (fabs(self.alpha - finalAlpha) >= 0.01) {
                [UIView animateWithDuration:0.2
                                 animations:^{
                                   dyyyGlobalTransparencyMutationDepth++;
                                   self.alpha = finalAlpha;
                                   if (dyyyGlobalTransparencyMutationDepth > 0) {
                                       dyyyGlobalTransparencyMutationDepth--;
                                   }
                                 }];
            }
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self dyyy_applyGlobalTransparency];
        });
    }
}

%end

%hook AWEIMSkylightListView
- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYHideAvatarList")) {
        CGFloat scale = [UIScreen mainScreen].scale ?: 2.0;
        CGFloat minH = MAX(1.0 / scale, 0.5);
        frame.size.height = minH;
    }
    %orig(frame);
}
%end

%hook AWEFeedTableView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGRect frame = self.frame;
        frame.size.height = self.superview.frame.size.height;
        self.frame = frame;
    } else if (gCurrentTabBarHeight > 0) {
        UIWindow *keyWindow = [DYYYUtils getActiveWindow];
        if (keyWindow && keyWindow.safeAreaInsets.bottom == 0) {
            return;
        }

        CGRect frame = self.frame;
        frame.size.height = self.superview.frame.size.height - gCurrentTabBarHeight;
        self.frame = frame;
    }
}
%end

%hook AWEFeedTableViewCell
- (void)prepareForReuse {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
}
%end

%hook AWEFeedViewCell
- (void)layoutSubviews {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)setModel:(id)model {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}
%end

%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      isAppInTransition = NO;
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      isAppInTransition = NO;
    });
}
%end

%hook AFDPureModePageContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    isPureViewVisible = YES;
    updateClearButtonVisibility();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    isPureViewVisible = NO;
    updateClearButtonVisibility();
}
%end

%hook AWEFeedContainerViewController
- (void)aweme:(id)arg1 currentIndexWillChange:(NSInteger)arg2 {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)aweme:(id)arg1 currentIndexDidChange:(NSInteger)arg2 {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
    DYYYHandleCurrentSpeedAwemeChanged(arg1);
}

- (void)viewWillLayoutSubviews {
    %orig;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
}
%end

%hook AWEElementStackView

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 纯净模式功能
    static AWMSafeDispatchTimer *pureModeTimer = nil;
    static int attempts = 0;
    static BOOL pureModeSet = NO;
    if (DYYYGetBool(@"DYYYEnablePure")) {
        %orig(0.0);
        if (pureModeSet) {
            return;
        }
        if (!pureModeTimer) {
            pureModeTimer = [[AWMSafeDispatchTimer alloc] init];
        }
        if (!pureModeTimer.isRunning) {
            attempts = 0;
            __weak AWMSafeDispatchTimer *weakTimer = pureModeTimer;
            [pureModeTimer startWithInterval:0.5
                                      leeway:0.1
                                       queue:dispatch_get_main_queue()
                                     repeats:YES
                                     handler:^{
                                       AWMSafeDispatchTimer *strongTimer = weakTimer;
                                       UIWindow *keyWindow = [DYYYUtils getActiveWindow];
                                       if (keyWindow && keyWindow.rootViewController) {
                                           UIViewController *feedVC = [DYYYUtils findViewControllerOfClass:NSClassFromString(@"AWEFeedTableViewController")
                                                                                          inViewController:keyWindow.rootViewController];
                                           if (feedVC) {
                                               [feedVC setValue:@YES forKey:@"pureMode"];
                                               pureModeSet = YES;
                                               [strongTimer cancel];
                                               pureModeTimer = nil;
                                               attempts = 0;
                                               return;
                                           }
                                       }
                                       attempts++;
                                       if (attempts >= 10) {
                                           [strongTimer cancel];
                                           pureModeTimer = nil;
                                           attempts = 0;
                                       }
                                     }];
        }
        return;
    }

    // 清理纯净模式的残留状态
    if (pureModeTimer) {
        [pureModeTimer cancel];
        pureModeTimer = nil;
    }
    attempts = 0;
    pureModeSet = NO;

    // 倍速和清屏按钮的状态控制
    BOOL hasFloatingButtons = (speedButton && isFloatSpeedButtonEnabled) || hideButton;
    if (!isApplyingGlobal && hasFloatingButtons && !dyyyIsPerformingFloatClearOperation) {
        const CGFloat threshold = 0.01f;
        if (alpha <= threshold) {
            dyyyCommentViewVisible = YES;
        } else if (alpha >= (1.0f - threshold)) {
            dyyyCommentViewVisible = NO;
        }
        updateSpeedButtonVisibility();
        updateClearButtonVisibility();
    }

    // 值守全局透明度
    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    // 统一应用透明度
    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

+ (void)initialize {
    GuideViewClass = NSClassFromString(@"AWELivePrestreamGuideView");
    MuteViewClass = NSClassFromString(@"AFDCancelMuteAwemeView");
    TagViewClass = NSClassFromString(@"AWELiveFeedLabelTagView");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = NO;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    dyyyCommentViewVisible = YES;
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:self];

    if ([viewController isKindOfClass:%c(AWELiveNewPreStreamViewController)]) {
        const BOOL shouldShiftUp = DYYYGetBool(@"DYYYEnableFullScreen");
        const CGFloat labelScaleValue = DYYYGetFloat(@"DYYYNicknameScale");
        const CGFloat targetLabelScale = (labelScaleValue != 0.0) ? MAX(0.01, labelScaleValue) : 1.0;
        const CGFloat elementScaleValue = DYYYGetFloat(@"DYYYElementScale");
        const CGFloat targetElementScale = (elementScaleValue != 0.0) ? MAX(0.01, elementScaleValue) : 1.0;

        CGAffineTransform targetTransform = CGAffineTransformIdentity;
        CGFloat boundsWidth = self.bounds.size.width;
        CGFloat currentScale = 1.0;
        CGFloat targetHeight, tx, ty = 0;
        UIWindow *keyWindow = [DYYYUtils getActiveWindow];
        if (keyWindow && keyWindow.safeAreaInsets.bottom == 0) {
            targetHeight = gCurrentTabBarHeight - originalTabBarHeight;
        } else {
            targetHeight = gCurrentTabBarHeight;
        }

        if ([DYYYUtils containsSubviewOfClass:GuideViewClass inContainer:self]) {
            currentScale = targetLabelScale;
            tx = 0; // 中对齐
        } else if ([DYYYUtils containsSubviewOfClass:MuteViewClass inContainer:self]) {
            currentScale = targetElementScale;
            tx = (boundsWidth - boundsWidth * currentScale) / 2; // 右对齐
        } else if ([DYYYUtils containsSubviewOfClass:TagViewClass inContainer:self]) {
            currentScale = targetLabelScale;
            tx = (boundsWidth - boundsWidth * currentScale) / -2; // 左对齐
        }

        NSArray *subviews = [self.subviews copy];
        for (UIView *view in subviews) {
            CGFloat viewHeight = view.bounds.size.height;
            ty += (viewHeight - viewHeight * currentScale) / 2;
        }

        if (shouldShiftUp) {
            ty -= targetHeight;
        }

        targetTransform = CGAffineTransformMake(currentScale, 0, 0, currentScale, tx, ty);

        if (!CGAffineTransformEqualToTransform(self.transform, targetTransform)) {
            self.transform = targetTransform;
        }
    }

    if ([viewController isKindOfClass:%c(AWEPlayInteractionViewController)]) {
        NSString *label = self.accessibilityLabel ?: @"";
        BOOL hasAnchor = [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEFeedAnchorContainerView") inContainer:self];
        BOOL hasAvatar = [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEPlayInteractionUserAvatarView") inContainer:self];

        BOOL isRightStack = ([label isEqualToString:@"right"] || hasAvatar);
        if (!isRightStack) {
            NSArray *subviews = [self.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) {
                        isRightStack = YES;
                        break;
                    }
                }
            }
        }

        BOOL isLeftStack = ([label isEqualToString:@"left"] || hasAnchor);
        if (!isLeftStack) {
            NSArray *subviews = [self.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionDescriptionElement"]) {
                        isLeftStack = YES;
                        break;
                    }
                }
            }
        }

        // 右侧元素的处理逻辑
        if (isRightStack) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYElementScale"];
            self.transform = CGAffineTransformIdentity;
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat right_tx = (frameWidth - frameWidth * scale) / 2;
                    self.transform = CGAffineTransformMake(scale, 0, 0, scale, right_tx, ty);
                } else {
                    self.transform = CGAffineTransformIdentity;
                }
            }
        }
        // 左侧元素的处理逻辑
        else if (isLeftStack) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                self.transform = CGAffineTransformIdentity;
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                    CGAffineTransform newTransform = CGAffineTransformMakeScale(scale, scale);
                    newTransform = CGAffineTransformTranslate(newTransform, left_tx / scale, ty / scale);
                    self.transform = newTransform;
                }
            }
        }
    }
}

- (NSArray<__kindof UIView *> *)arrangedSubviews {

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:self];
    if ([viewController isKindOfClass:%c(AWEPlayInteractionViewController)]) {

        if ([self.accessibilityLabel isEqualToString:@"left"] || [DYYYUtils containsSubviewOfClass:NSClassFromString(@"AWEFeedAnchorContainerView") inContainer:self]) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                self.transform = CGAffineTransformIdentity;
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                    CGAffineTransform newTransform = CGAffineTransformMakeScale(scale, scale);
                    newTransform = CGAffineTransformTranslate(newTransform, left_tx / scale, ty / scale);
                    self.transform = newTransform;
                }
            }
        }
    }

    NSArray *originalSubviews = %orig;
    return originalSubviews;
}

%end

%hook IESLiveStackView

+ (void)initialize {
    GuideViewClass = NSClassFromString(@"AWELivePrestreamGuideView");
    MuteViewClass = NSClassFromString(@"AFDCancelMuteAwemeView");
    TagViewClass = NSClassFromString(@"AWELiveFeedLabelTagView");
}

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!isApplyingGlobal && speedButton && isFloatSpeedButtonEnabled) {
        if (alpha == 0) {
            dyyyCommentViewVisible = YES;
        } else if (alpha == 1) {
            dyyyCommentViewVisible = NO;
        }
        updateSpeedButtonVisibility();
        updateClearButtonVisibility();
    }

    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:self];

    if ([viewController isKindOfClass:%c(AWELiveNewPreStreamViewController)]) {
        const BOOL shouldShiftUp = DYYYGetBool(@"DYYYEnableFullScreen");
        const CGFloat labelScaleValue = DYYYGetFloat(@"DYYYNicknameScale");
        const CGFloat targetLabelScale = (labelScaleValue != 0.0) ? MAX(0.01, labelScaleValue) : 1.0;
        const CGFloat elementScaleValue = DYYYGetFloat(@"DYYYElementScale");
        const CGFloat targetElementScale = (elementScaleValue != 0.0) ? MAX(0.01, elementScaleValue) : 1.0;

        CGAffineTransform targetTransform = CGAffineTransformIdentity;
        CGFloat boundsWidth = self.bounds.size.width;
        CGFloat currentScale = 1.0;
        CGFloat targetHeight, tx, ty = 0;
        UIWindow *keyWindow = [DYYYUtils getActiveWindow];
        if (keyWindow && keyWindow.safeAreaInsets.bottom == 0) {
            targetHeight = gCurrentTabBarHeight - originalTabBarHeight;
        } else {
            targetHeight = gCurrentTabBarHeight;
        }

        if ([DYYYUtils containsSubviewOfClass:GuideViewClass inContainer:self]) {
            currentScale = targetLabelScale;
            tx = 0; // 中对齐
        } else if ([DYYYUtils containsSubviewOfClass:MuteViewClass inContainer:self]) {
            currentScale = targetElementScale;
            tx = (boundsWidth - boundsWidth * currentScale) / 2; // 右对齐
        } else if ([DYYYUtils containsSubviewOfClass:TagViewClass inContainer:self]) {
            currentScale = targetLabelScale;
            tx = (boundsWidth - boundsWidth * currentScale) / -2; // 左对齐
        }

        NSArray *subviews = [self.subviews copy];
        for (UIView *view in subviews) {
            CGFloat viewHeight = view.bounds.size.height;
            ty += (viewHeight - viewHeight * currentScale) / 2;
        }

        if (shouldShiftUp) {
            ty -= targetHeight;
        }
        targetTransform = CGAffineTransformMakeTranslation(0, -20);

        if (!CGAffineTransformEqualToTransform(self.transform, targetTransform)) {
            self.transform = targetTransform;
        }
    }
}

%end

%hook AWEStoryContainerCollectionView
- (void)layoutSubviews {
    %orig;
    if ([self.subviews count] == 2)
        return;

    // 获取 enableEnterProfile 属性来判断是否是主页
    id enableEnterProfile = [self valueForKey:@"enableEnterProfile"];
    BOOL isHome = (enableEnterProfile != nil && [enableEnterProfile boolValue]);

    // 检查是否在作者主页
    BOOL isAuthorProfile = NO;
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([NSStringFromClass([responder class]) containsString:@"UserHomeViewController"] || [NSStringFromClass([responder class]) containsString:@"ProfileViewController"]) {
            isAuthorProfile = YES;
            break;
        }
    }

    // 如果不是主页也不是作者主页，直接返回
    if (!isHome && !isAuthorProfile)
        return;

    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:[UIView class]]) {
            UIView *nextResponder = (UIView *)subview.nextResponder;

            // 处理主页的情况
            if (isHome && [nextResponder isKindOfClass:%c(AWEPlayInteractionViewController)]) {
                UIViewController *awemeBaseViewController = [nextResponder valueForKey:@"awemeBaseViewController"];
                if (![awemeBaseViewController isKindOfClass:%c(AWEFeedCellViewController)]) {
                    continue;
                }

                CGRect frame = subview.frame;
                if (DYYYGetBool(@"DYYYEnableFullScreen")) {
                    frame.size.height = subview.superview.frame.size.height - gCurrentTabBarHeight;
                    subview.frame = frame;
                }
            }
            // 处理作者主页的情况
            else if (isAuthorProfile) {
                // 检查是否是作品图片
                BOOL isWorkImage = NO;

                // 可以通过检查子视图、标签或其他特性来确定是否是作品图片
                for (UIView *childView in subview.subviews) {
                    if ([NSStringFromClass([childView class]) containsString:@"ImageView"] || [NSStringFromClass([childView class]) containsString:@"ThumbnailView"]) {
                        isWorkImage = YES;
                        break;
                    }
                }

                if (isWorkImage) {
                    // 修复作者主页作品图片上移问题
                    CGRect frame = subview.frame;
                    frame.origin.y += gCurrentTabBarHeight;
                    subview.frame = frame;
                }
            }
        }
    }
}
%end

%hook TTMetalView
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        if (viewWidth + 0.5f >= screenWidth) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = gCurrentTabBarHeight > 0 ? gCurrentTabBarHeight : originalTabBarHeight;
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook TTMetalViewNew
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        if (viewWidth + 0.5f >= screenWidth) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = gCurrentTabBarHeight > 0 ? gCurrentTabBarHeight : originalTabBarHeight;
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook TTMetalViewVP
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        if (viewWidth + 0.5f >= screenWidth) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = gCurrentTabBarHeight > 0 ? gCurrentTabBarHeight : originalTabBarHeight;
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook AWEStoryProgressContainerView
- (void)setCenter:(CGPoint)center {
    UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
    if ([vc isKindOfClass:NSClassFromString(@"AWEFeedPlayControlImpl.PureModePageCellViewController")] && DYYYGetBool(@"DYYYEnableFullScreen")) {
        center.y -= gCurrentTabBarHeight;
    }
    %orig(center);
}

- (BOOL)isHidden {
    BOOL originalValue = %orig;
    BOOL customHide = DYYYGetBool(@"DYYYHideDotsIndicator");
    return originalValue || customHide;
}

- (void)setHidden:(BOOL)hidden {
    BOOL forceHide = DYYYGetBool(@"DYYYHideDotsIndicator");
    %orig(forceHide ? YES : hidden);
}
%end

%hook AWELandscapeFeedEntryView

- (void)setAlpha:(CGFloat)alpha {
    BOOL isApplyingGlobal = (dyyyGlobalTransparencyMutationDepth > 0);
    if (!isApplyingGlobal) {
        objc_setAssociatedObject(self, &kDYYYGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat finalAlpha = alpha;
    if (!isApplyingGlobal && self.tag != DYYY_IGNORE_GLOBAL_ALPHA_TAG && gGlobalTransparency != kInvalidAlpha) {
        CGFloat clampedAlpha = MIN(MAX(alpha, 0.0), 1.0);
        finalAlpha = clampedAlpha * gGlobalTransparency;
    }

    if (fabs(self.alpha - finalAlpha) >= 0.01) {
        %orig(finalAlpha);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self dyyy_applyGlobalTransparency];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dyyy_applyGlobalTransparency) name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kDYYYGlobalTransparencyDidChangeNotification object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYRemoveEntry")) {
        [self removeFromSuperview];
        return;
    }
    if (DYYYGetBool(@"DYYYHideEntry")) {
        for (UIView *subview in self.subviews) {
            subview.hidden = YES;
        }
        return;
    }

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }

    NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];
    CGFloat scale = scaleValue.length > 0 ? [scaleValue floatValue] : 1.0;
    if (scale > 0 && scale != 1.0) {
        self.transform = CGAffineTransformMakeScale(scale, scale);
    } else {
        self.transform = CGAffineTransformIdentity;
    }
}

%end

%hook AWEAwemeDetailTableView

- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

        CGFloat remainder = fmod(frame.size.height, screenHeight);
        if (remainder != 0) {
            frame.size.height += (screenHeight - remainder);
        }
    }
    %orig(frame);
}

%end

%hook CommentInputContainerView

- (void)layoutSubviews {
    %orig;
    UIViewController *parentVC = nil;
    if ([self respondsToSelector:@selector(viewController)]) {
        id viewController = [self performSelector:@selector(viewController)];
        if ([viewController respondsToSelector:@selector(parentViewController)]) {
            parentVC = [viewController parentViewController];
        }
    }

    if (parentVC && ([parentVC isKindOfClass:%c(AWEAwemeDetailTableViewController)] || [parentVC isKindOfClass:%c(AWEAwemeDetailCellViewController)])) {
        static char kDYCommentHideCacheKey;
        UIView *target = objc_getAssociatedObject(self, &kDYCommentHideCacheKey);
        if (!target) {
            for (UIView *subview in [self subviews]) {
                if ([subview class] == [UIView class]) {
                    target = subview;
                    objc_setAssociatedObject(self, &kDYCommentHideCacheKey, target, OBJC_ASSOCIATION_ASSIGN);
                    break;
                }
            }
        }
        if (target) {
            target.hidden = ([(UIView *)self frame].size.height == gCurrentTabBarHeight);
        }
    }
}

%end

%hook AWEIMFeedBottomQuickEmojiInputBar

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        UIView *parentView = self.superview;
        while (parentView) {
            if ([NSStringFromClass([parentView class]) isEqualToString:@"UIView"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  parentView.backgroundColor = [UIColor clearColor];
                  parentView.layer.backgroundColor = [UIColor clearColor].CGColor;
                  parentView.opaque = NO;
                });
                break;
            }
            parentView = parentView.superview;
        }
    }
}

%end

%hook _TtC21AWEIncentiveSwiftImpl29IncentivePendantContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePendantGroup")) {
        [self removeFromSuperview];
    }
}
%end

%hook UIImageView
- (void)setImage:(UIImage *)image {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setHighlightedImage:(UIImage *)highlightedImage {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setAnimationImages:(NSArray<UIImage *> *)animationImages {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)setHighlightedAnimationImages:(NSArray<UIImage *> *)highlightedAnimationImages {
    DYYYApplySDRDynamicRangeToImageView(self);
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
}

- (void)layoutSubviews {
    %orig;
    DYYYApplySDRDynamicRangeToImageView(self);
    if (DYYYGetBool(@"DYYYHideCommentDiscover")) {
        if (!self.accessibilityLabel) {
            UIView *parentView = self.superview;

            if (parentView && [parentView class] == [UIView class] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            }

            else if (parentView && [NSStringFromClass([parentView class]) isEqualToString:@"AWESearchEntryHalfScreenElement"] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            }
        }
    }
    return;
}
%end

%hook AWELuckyCatBannerView
- (id)initWithFrame:(CGRect)frame {
    return nil;
}

- (id)init {
    return nil;
}
%end

%hook AWELeftSideBarModel

- (NSArray *)moduleModels {
    NSArray *originalModels = %orig;

    BOOL shouldHideRecentApps = DYYYGetBool(kHideRecentAppsKey);
    BOOL shouldHideRecentUsers = DYYYGetBool(kHideRecentUsersKey);

    if (!shouldHideRecentApps && !shouldHideRecentUsers) {
        return originalModels;
    }

    NSMutableArray *filteredModels = [NSMutableArray arrayWithCapacity:originalModels.count];

    for (id moduleModel in originalModels) {
        if ([moduleModel respondsToSelector:@selector(moduleID)]) {
            NSString *moduleID = [moduleModel moduleID];

            if (shouldHideRecentApps && [moduleID isEqualToString:@"recently_apps_module"]) {
                continue;
            }

            if (shouldHideRecentUsers && [moduleID isEqualToString:@"recently_users_module"]) {
                continue;
            }
        }

        id filteredModule = [self filterModuleItems:moduleModel];
        if (filteredModule) {
            [filteredModels addObject:filteredModule];
        }
    }

    return [filteredModels copy];
}

%new
- (id)filterModuleItems:(id)moduleModel {
    if (![moduleModel respondsToSelector:@selector(items)] || ![moduleModel respondsToSelector:@selector(moduleID)]) {
        return moduleModel;
    }

    NSString *moduleID = [moduleModel moduleID];
    NSArray *originalItems = [moduleModel items];

    if ([moduleID isEqualToString:@"top_area"]) {
        // 只保留天气、设置、扫一扫
        NSMutableArray *filteredItems = [NSMutableArray array];

        for (id item in originalItems) {
            if ([item respondsToSelector:@selector(businessType)]) {
                NSString *businessType = [item businessType];

                // 保留需要的组件
                if ([businessType isEqualToString:@"weather_time_tip_component"] || [businessType isEqualToString:@"setting_page_component"] ||
                    [businessType isEqualToString:@"top_area_vertical_cell"]) {
                    [filteredItems addObject:item];
                }
            }
        }

        // 创建新的模块对象，保持原有属性但更新items
        if ([moduleModel respondsToSelector:@selector(copy)]) {
            id newModule = [moduleModel copy];
            if ([newModule respondsToSelector:@selector(setItems:)]) {
                [newModule setItems:[filteredItems copy]];
            }
            return newModule;
        }
    }

    return moduleModel;
}

%end

%hook AFDViewedBottomView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {

        self.backgroundColor = [UIColor clearColor];

        self.effectView.hidden = YES;
    }
}
%end

%group IncentivePendantGroup
%hook AWEIncentiveSwiftImplDOUYINLite_IncentivePendantContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePendantGroup")) {
        [self removeFromSuperview];
    }
}
%end
%end

%group BDMultiContentImageViewGroup
%hook BDMultiContentContainer_ImageContentView

- (void)setTransform:(CGAffineTransform)transform {
    if (DYYYGetBool(@"DYYYEnableCommentBlur")) {
        return;
    }
    %orig(transform);
}

%end
%end

%hook AWEStoryContainerCollectionView

- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYEnableCommentBlur")) {
        if (frame.origin.y != 0) {
            return;
        }
    }
    %orig(frame);
}

%end
