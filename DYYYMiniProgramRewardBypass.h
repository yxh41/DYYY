#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 小程序激励视频奖励绕过安装入口（设置 key: `DYYYEnableMiniProgramJumpingAds`）。
/// Hook `BDARewardedVideoAdBaseController`，开启后强制标记奖励已发放并在 0.12s 后自动关闭广告控制器。
/// 类缺失（极速版/未加载广告 SDK）时静默跳过，安全。
FOUNDATION_EXPORT void DYYYStartMiniProgramRewardBypassInstaller(void);

NS_ASSUME_NONNULL_END
