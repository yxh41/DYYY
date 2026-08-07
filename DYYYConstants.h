#ifndef DYYYConstants_h
#define DYYYConstants_h

#define DYYY_NAME @"DYYY"
#define DYYY_SETTINGS_NAME @"DYYY设置"

#define DYYY_VERSION @"2.2-9"

// 默认的远程 ABTest 配置地址
#define DYYY_DEFAULT_ABTEST_URL @"https://github.com/Nathalie-Annis/AWEABTestDataPatch/releases/latest/download/ABTestDataPatch_A.json"

// 是否使用远程配置的偏好键
#define DYYY_REMOTE_CONFIG_FLAG_KEY @"DYYYUseRemoteConfig"

// 远程配置状态改变的通知名
#define DYYY_REMOTE_CONFIG_CHANGED_NOTIFICATION @"DYYYRemoteConfigStateChanged"

// 配置应用方式中的远程模式名称
#define DYYY_REMOTE_MODE_STRING @"远程模式：启动时自动检查更新"

#define DYYYGeonamesErrorDomain @"com.dyyy.geonames.api.error"
#define DYYYGeonamesStatusUserInfoKey @"com.dyyy.geonames.api.status"

// 高帧率与实时帧率浮窗设置键（移植自 VexCove，默认关闭）
#define DYYYEnableHighFPS @"DYYYEnableHighFPS"
#define DYYYEnableFPSOverlay @"DYYYEnableFPSOverlay"

// 消息页/我的页元素隐藏设置键（移植自 VexCove，默认关闭）
// 注：头像加号(DYYYHideMineAvatarPlus) 本地已有等价实现，不在此重复。
#define DYYYHideMessageTabStarMall @"DYYYHideMessageTabStarMall"
#define DYYYHideMineAICreation @"DYYYHideMineAICreation"

#endif
