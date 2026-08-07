// DYYYHidePageHooks.xm
// 移植自 VexCove 的消息页/我的页元素隐藏：星光商城、我的页创作 AI 作品入口。
// 关键约束：
//  - 均为 Aweme 39.8 私有类（AWEIMMessageTabNavBarResourceSlotComponent*、
//    AWEProfileHeaderGenericOperationComponent），仅在「标准版抖音」
//    (com.ss.iphone.ugc.Aweme) 下挂载，极速版(lite)连尝试都不发生。
//  - 两个隐藏 hook 均在调用点实时读取设置键（canShowInNaviBar / buildVirtualView:），
//    切换开关后下次视图重建即生效，无需跨文件 apply 函数。
//  - 用 Logos %hook + %group，缺失类静默跳过（Logos 安全网），不使用裸 swizzle。
//  - 注：头像加号(DYYYHideMineAvatarPlus) 本地已有等价实现，本文件不重复。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DYYYConstants.h"
#import "DYYYPreferences.h"

#pragma mark - 设置键读取

static BOOL DYYYHideMessageTabStarMallEnabled(void) {
    return [DYYYPreferences boolForKey:DYYYHideMessageTabStarMall];
}

static BOOL DYYYHideMineAICreationEnabled(void) {
    return [DYYYPreferences boolForKey:DYYYHideMineAICreation];
}

#pragma mark - 隐藏辅助（视图级隐身：隐藏 + 透明 + 禁交互）

static void DYYYHideChromeView(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

%group DYYYHidePageHooksGroup

// 星光商城：消息页导航栏资源位（标准版 + V2 组件）
%hook AWEIMMessageTabNavBarResourceSlotComponent
- (BOOL)canShowInNaviBar {
    if (DYYYHideMessageTabStarMallEnabled()) {
        return NO;
    }
    return %orig;
}
%end

%hook AWEIMMessageTabNavBarResourceSlotComponentV2
- (BOOL)canShowInNaviBar {
    if (DYYYHideMessageTabStarMallEnabled()) {
        return NO;
    }
    return %orig;
}
%end

// 我的页「创作 AI 作品」入口：返回 nil 阻止虚拟视图构建，并隐藏容器节点
%hook AWEProfileHeaderGenericOperationComponent
- (id)buildVirtualView:(id)arg {
    if (DYYYHideMineAICreationEnabled()) {
        return nil;
    }
    return %orig;
}

- (void)updateComponentData:(id)arg {
    %orig;
    if (DYYYHideMineAICreationEnabled()) {
        // containerNode 为视图容器；KVC 取不到时安全跳过（buildVirtualView 已兜底返回 nil）
        // 类为前向声明，需转 (id) 才能发 KVC 消息
        id node = [(id)self valueForKey:@"containerNode"];
        if ([node isKindOfClass:[UIView class]]) {
            DYYYHideChromeView(node);
        }
    }
}
%end

%end // DYYYHidePageHooksGroup

%ctor {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    // 仅标准版抖音挂载：极速版(lite)缺失上述私有类，连尝试 hook 都不发生
    if ([bid isEqualToString:@"com.ss.iphone.ugc.Aweme"]) {
        %init(DYYYHidePageHooksGroup);
    }
}
