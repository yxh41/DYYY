//
//  DYYYHideCommentAIAnalysisHooks.h
//  移植自 VexCove/DYYY 的「评论区扩展 Tab 隐藏」模块
//
//  机制：手写 runtime swizzling（非 Logos %hook），所有涉及类均通过
//  NSClassFromString 动态获取 + Swift mangled 名回退，类不存在时静默跳过，
//  因此对缺少这些 Swift 类的抖音极速版完全安全（不会崩溃，仅不生效）。
//
//  入口 DYYYStartHideCommentAIAnalysisHooks() 在 DYYY.xm 的 %ctor 中调用一次，
//  内部用 dispatch_once 防止重复安装。
//

#ifndef DYYYHideCommentAIAnalysisHooks_h
#define DYYYHideCommentAIAnalysisHooks_h

#ifdef __cplusplus
extern "C" {
#endif

void DYYYStartHideCommentAIAnalysisHooks(void);

#ifdef __cplusplus
}
#endif

#endif /* DYYYHideCommentAIAnalysisHooks_h */
