// DYYYHighFPS.h
// 高帧率 + 实时帧率浮窗的跨文件 C 函数声明。
// 必须与 DYYYFloatSpeedButton.h 一致地使用 extern "C" 包裹，
// 否则 .xm 在 C++ 编译单元下名字修饰（mangling）不一致，链接期报
// "Undefined symbols: _DYYYApplyHighFPSSettingChange"。

#ifdef __cplusplus
extern "C" {
#endif

extern void DYYYApplyHighFPSSettingChange(BOOL enabled);
extern void DYYYApplyFPSOverlaySettingChange(void);

#ifdef __cplusplus
}
#endif
