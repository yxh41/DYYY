#import "DYYYMiniProgramRewardBypass.h"

#import "AwemeHeaders.h"
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>
#import <substrate.h>

static NSString *const kDYYYMiniProgramRewardEnabledKey = @"DYYYEnableMiniProgramJumpingAds";
static NSString *const kDYYYMiniProgramRewardControllerClassName = @"BDARewardedVideoAdBaseController";
static const NSTimeInterval kDYYYMiniProgramCloseDelay = 0.12;

typedef NS_ENUM(NSUInteger, DYYYMiniProgramRewardSessionState) {
    DYYYMiniProgramRewardSessionStateCreated = 0,
    DYYYMiniProgramRewardSessionStateAppeared,
    DYYYMiniProgramRewardSessionStateCloseScheduled,
    DYYYMiniProgramRewardSessionStateFinished,
};

@interface DYYYMiniProgramRewardSession : NSObject
@property(nonatomic, assign) DYYYMiniProgramRewardSessionState state;
@property(nonatomic, assign) BOOL diagnosticFailureLogged;
@property(nonatomic, assign) NSUInteger presentationGeneration;
@end

@implementation DYYYMiniProgramRewardSession
@end

static char kDYYYMiniProgramRewardSessionKey;

static IMP dyyyOriginalSendReward = NULL;
static IMP dyyyOriginalSendFirstReward = NULL;
static IMP dyyyOriginalDisableHostSendReward = NULL;
static IMP dyyyOriginalSetSendReward = NULL;
static IMP dyyyOriginalSetSendFirstReward = NULL;
static IMP dyyyOriginalSetDisableHostSendReward = NULL;
static IMP dyyyOriginalViewDidAppear = NULL;

static BOOL dyyyMiniProgramRewardHooksInstalled = NO;
static BOOL dyyyMiniProgramRewardRetryScheduled = NO;
static NSUInteger dyyyMiniProgramRewardRetryIndex = 0;
static id dyyyMiniProgramRewardActiveObserver = nil;
static atomic_bool dyyyMiniProgramRewardHooksInstalledAtomic = false;
static atomic_bool dyyyMiniProgramRewardImageRefreshQueued = false;

// v2.4-35：hook 安装必须离开主线程。真机崩溃日志（iPhone 13,3 / iOS 16.4.1）显示
// main queue 上调 MSHookMessageEx -> method_setImplementation 等待 ObjC runtime 写锁，
// 主线程一卡就被后台 watchdog（0x8BADF00D, failed to terminate gracefully after 5.0s）杀掉。
// 所有安装/重试/通知/dyld 回调统一走这条 serial queue，主线程不再碰 runtime 写操作。
static dispatch_queue_t DYYYMiniProgramInstallQueue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      queue = dispatch_queue_create("com.dyyy.miniprogram.install", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static BOOL DYYYMiniProgramRewardEnabled(void) {
    return DYYYGetBool(kDYYYMiniProgramRewardEnabledKey);
}

static const char *DYYYMiniProgramUnqualifiedType(const char *type) {
    if (!type) {
        return "";
    }

    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return type;
}

static BOOL DYYYMiniProgramTypeIsInteger(const char *type) {
    const char *unqualifiedType = DYYYMiniProgramUnqualifiedType(type);
    return unqualifiedType[0] != '\0' && strchr("BcCsSiIlLqQ", unqualifiedType[0]) != NULL;
}

static BOOL DYYYMiniProgramTypeIsVoid(const char *type) {
    return DYYYMiniProgramUnqualifiedType(type)[0] == 'v';
}

static NSMethodSignature *DYYYMiniProgramSignatureForMethod(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSMethodSignature signatureWithObjCTypes:encoding] : nil;
}

static BOOL DYYYMiniProgramMethodIsIntegerGetter(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 2 &&
           DYYYMiniProgramTypeIsInteger(signature.methodReturnType);
}

static BOOL DYYYMiniProgramMethodIsIntegerSetter(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 3 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType) &&
           DYYYMiniProgramTypeIsInteger([signature getArgumentTypeAtIndex:2]);
}

static BOOL DYYYMiniProgramMethodIsViewDidAppear(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 3 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType) &&
           DYYYMiniProgramTypeIsInteger([signature getArgumentTypeAtIndex:2]);
}

static BOOL DYYYMiniProgramMethodIsVoidWithoutArguments(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 2 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType);
}

static BOOL DYYYMiniProgramClassIsSubclassOfClass(Class cls, Class expectedSuperclass) {
    if (!cls || !expectedSuperclass) {
        return NO;
    }

    for (Class currentClass = cls; currentClass; currentClass = class_getSuperclass(currentClass)) {
        if (currentClass == expectedSuperclass) {
            return YES;
        }
    }
    return NO;
}

static DYYYMiniProgramRewardSession *DYYYMiniProgramSessionForController(id controller, BOOL createIfNeeded) {
    if (!controller) {
        return nil;
    }

    DYYYMiniProgramRewardSession *session = objc_getAssociatedObject(controller, &kDYYYMiniProgramRewardSessionKey);
    if (!session && createIfNeeded) {
        session = [DYYYMiniProgramRewardSession new];
        session.state = DYYYMiniProgramRewardSessionStateCreated;
        objc_setAssociatedObject(controller,
                                 &kDYYYMiniProgramRewardSessionKey,
                                 session,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}

static BOOL DYYYMiniProgramReadIntegerGetter(id object, SEL selector, NSInteger *value) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return NO;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!DYYYMiniProgramMethodIsIntegerGetter(method)) {
        return NO;
    }

    if (value) {
        *value = ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return YES;
}

static BOOL DYYYMiniProgramWriteIntegerSetter(id object, SEL selector, NSInteger value) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return NO;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!DYYYMiniProgramMethodIsIntegerSetter(method)) {
        return NO;
    }

    ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, value);
    return YES;
}

static BOOL DYYYMiniProgramPrepareLocalRewardState(id controller) {
    @try {
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setDisableHostSendReward:"), 0);
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setSendReward:"), 1);
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setSendFirstReward:"), 1);

        NSInteger sendReward = 0;
        NSInteger sendFirstReward = 0;
        if (!DYYYMiniProgramReadIntegerGetter(controller, NSSelectorFromString(@"sendReward"), &sendReward) ||
            !DYYYMiniProgramReadIntegerGetter(controller, NSSelectorFromString(@"sendFirstReward"), &sendFirstReward)) {
            return NO;
        }

        NSInteger disableHostSendReward = 0;
        BOOL hasDisableHostSendReward =
            DYYYMiniProgramReadIntegerGetter(controller,
                                             NSSelectorFromString(@"disableHostSendReward"),
                                             &disableHostSendReward);
        return sendReward != 0 &&
               sendFirstReward != 0 &&
               (!hasDisableHostSendReward || disableHostSendReward == 0);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 奖励状态校验异常：%@", exception.reason);
        return NO;
    }
}

static BOOL DYYYMiniProgramControllerIsVisible(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) {
        return NO;
    }

    UIViewController *viewController = controller;
    return viewController.isViewLoaded && viewController.view.window != nil;
}

static BOOL DYYYMiniProgramCloseController(id controller) {
    SEL closeSelector = NSSelectorFromString(@"close");
    if (!controller || ![controller respondsToSelector:closeSelector]) {
        return NO;
    }

    Method closeMethod = class_getInstanceMethod(object_getClass(controller), closeSelector);
    if (!DYYYMiniProgramMethodIsVoidWithoutArguments(closeMethod)) {
        return NO;
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(controller, closeSelector);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 关闭广告控制器异常：%@", exception.reason);
        return NO;
    }
}

static void DYYYMiniProgramScheduleClose(id controller) {
    if (!controller || !DYYYMiniProgramRewardEnabled()) {
        return;
    }

    DYYYMiniProgramRewardSession *session = DYYYMiniProgramSessionForController(controller, YES);
    NSUInteger presentationGeneration = 0;
    BOOL reusedController = NO;
    @synchronized(session) {
        if (session.state == DYYYMiniProgramRewardSessionStateCloseScheduled) {
            return;
        }

        if (session.state == DYYYMiniProgramRewardSessionStateFinished) {
            session.state = DYYYMiniProgramRewardSessionStateCreated;
            session.diagnosticFailureLogged = NO;
            session.presentationGeneration++;
            reusedController = YES;
        } else if (session.presentationGeneration == 0) {
            session.presentationGeneration = 1;
        }

        presentationGeneration = session.presentationGeneration;
        session.state = DYYYMiniProgramRewardSessionStateAppeared;
    }

    if (reusedController) {
        NSLog(@"[DYYY][小程序跳广告] 检测到控制器复用，开始第 %lu 轮广告：%@",
              (unsigned long)presentationGeneration,
              NSStringFromClass([controller class]));
    }

    if (!DYYYMiniProgramPrepareLocalRewardState(controller)) {
        @synchronized(session) {
            if (session.presentationGeneration == presentationGeneration &&
                !session.diagnosticFailureLogged) {
                session.diagnosticFailureLogged = YES;
                NSLog(@"[DYYY][小程序跳广告] 本地奖励状态未确认，保留原广告流程：%@",
                      NSStringFromClass([controller class]));
            }
        }
        return;
    }

    @synchronized(session) {
        if (session.presentationGeneration != presentationGeneration ||
            session.state == DYYYMiniProgramRewardSessionStateFinished) {
            return;
        }
        session.state = DYYYMiniProgramRewardSessionStateCloseScheduled;
    }

    __weak id weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kDYYYMiniProgramCloseDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      id strongController = weakController;
      if (!strongController) {
          return;
      }

      DYYYMiniProgramRewardSession *strongSession =
          DYYYMiniProgramSessionForController(strongController, NO);
      if (!strongSession) {
          return;
      }

      @synchronized(strongSession) {
          if (strongSession.presentationGeneration != presentationGeneration ||
              strongSession.state != DYYYMiniProgramRewardSessionStateCloseScheduled) {
              return;
          }
          if (!DYYYMiniProgramRewardEnabled()) {
              strongSession.state = DYYYMiniProgramRewardSessionStateAppeared;
              return;
          }
      }

      if (!DYYYMiniProgramControllerIsVisible(strongController) ||
          !DYYYMiniProgramPrepareLocalRewardState(strongController)) {
          @synchronized(strongSession) {
              if (strongSession.presentationGeneration == presentationGeneration) {
                  strongSession.state = DYYYMiniProgramRewardSessionStateAppeared;
              }
          }
          return;
      }

      BOOL closed = DYYYMiniProgramCloseController(strongController);
      @synchronized(strongSession) {
          if (strongSession.presentationGeneration == presentationGeneration) {
              strongSession.state = closed
                                        ? DYYYMiniProgramRewardSessionStateFinished
                                        : DYYYMiniProgramRewardSessionStateAppeared;
          }
      }
      if (closed) {
          NSLog(@"[DYYY][小程序跳广告] 第 %lu 轮已确认本地奖励状态并关闭广告控制器：%@",
                (unsigned long)presentationGeneration,
                NSStringFromClass([strongController class]));
      }
    });
}

static NSInteger DYYYMiniProgramSendReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 1;
    }
    return dyyyOriginalSendReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalSendReward)(self, _cmd)
               : 0;
}

static NSInteger DYYYMiniProgramSendFirstReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 1;
    }
    return dyyyOriginalSendFirstReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalSendFirstReward)(self, _cmd)
               : 0;
}

static NSInteger DYYYMiniProgramDisableHostSendReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 0;
    }
    return dyyyOriginalDisableHostSendReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalDisableHostSendReward)(self, _cmd)
               : 0;
}

static void DYYYMiniProgramSetSendReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 1;
    }
    if (dyyyOriginalSetSendReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetSendReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramSetSendFirstReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 1;
    }
    if (dyyyOriginalSetSendFirstReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetSendFirstReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramSetDisableHostSendReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 0;
    }
    if (dyyyOriginalSetDisableHostSendReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetDisableHostSendReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (dyyyOriginalViewDidAppear) {
        ((void (*)(id, SEL, BOOL))dyyyOriginalViewDidAppear)(self, _cmd, animated);
    }

    if (!DYYYMiniProgramRewardEnabled()) {
        return;
    }

    @try {
        DYYYMiniProgramScheduleClose(self);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 广告生命周期处理异常：%@", exception.reason);
    }
}

typedef BOOL (*DYYYMiniProgramMethodValidator)(Method method);

static void DYYYMiniProgramPrefetchIMP(Class cls, SEL selector, IMP *slot, IMP replacement) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    IMP current = method ? method_getImplementation(method) : NULL;
    // 跳过尚未就绪的方法，以及已经装过 replacement 的情况，避免把替换后的 IMP 当成原 IMP 存下来。
    if (current && current != replacement) {
        *slot = current;
    }
}

static BOOL DYYYMiniProgramInstallHook(Class cls,
                                       SEL selector,
                                       IMP replacement,
                                       IMP *original,
                                       DYYYMiniProgramMethodValidator validator,
                                       BOOL required) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) {
        if (required) {
            NSLog(@"[DYYY][小程序跳广告] 缺少必要方法：%@ %@",
                  NSStringFromClass(cls),
                  NSStringFromSelector(selector));
        }
        return NO;
    }

    if (!validator(method)) {
        NSLog(@"[DYYY][小程序跳广告] 方法签名不兼容，跳过 Hook：%@ %@ (%s)",
              NSStringFromClass(cls),
              NSStringFromSelector(selector),
              method_getTypeEncoding(method));
        return NO;
    }

    IMP currentImplementation = method_getImplementation(method);
    if (currentImplementation == replacement) {
        return original && *original != NULL;
    }

    IMP previousImplementation = NULL;
    MSHookMessageEx(cls, selector, replacement, &previousImplementation);
    if (!previousImplementation || previousImplementation == replacement) {
        NSLog(@"[DYYY][小程序跳广告] 无法保存原 IMP，停止使用：%@ %@",
              NSStringFromClass(cls),
              NSStringFromSelector(selector));
        return NO;
    }

    *original = previousImplementation;
    return YES;
}

static BOOL DYYYMiniProgramValidateControllerClass(Class cls) {
    if (!DYYYMiniProgramClassIsSubclassOfClass(cls, UIViewController.class)) {
        NSLog(@"[DYYY][小程序跳广告] 目标类不是 UIViewController 子类：%@",
              NSStringFromClass(cls));
        return NO;
    }

    Method sendRewardMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"sendReward"));
    Method sendFirstRewardMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"sendFirstReward"));
    Method viewDidAppearMethod = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    Method closeMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"close"));
    return DYYYMiniProgramMethodIsIntegerGetter(sendRewardMethod) &&
           DYYYMiniProgramMethodIsIntegerGetter(sendFirstRewardMethod) &&
           DYYYMiniProgramMethodIsViewDidAppear(viewDidAppearMethod) &&
           DYYYMiniProgramMethodIsVoidWithoutArguments(closeMethod);
}

// 安装改到 serial queue 后，主线程可能在"逐个替换 IMP"的中途调用到已替换的方法。
// 先把全部原 IMP 读进全局变量，保证任意 hook 一被触发就能拿到有效 original，
// 消除跨线程下 original 还是 NULL 的窗口。validate 已保证方法存在且签名匹配。
static void DYYYPrefetchMiniProgramOriginals(Class cls) {
    if (!cls) return;
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"sendReward"),
                               &dyyyOriginalSendReward, (IMP)DYYYMiniProgramSendReward);
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"sendFirstReward"),
                               &dyyyOriginalSendFirstReward, (IMP)DYYYMiniProgramSendFirstReward);
    DYYYMiniProgramPrefetchIMP(cls, @selector(viewDidAppear:),
                               &dyyyOriginalViewDidAppear, (IMP)DYYYMiniProgramViewDidAppear);
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"disableHostSendReward"),
                               &dyyyOriginalDisableHostSendReward, (IMP)DYYYMiniProgramDisableHostSendReward);
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"setSendReward:"),
                               &dyyyOriginalSetSendReward, (IMP)DYYYMiniProgramSetSendReward);
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"setSendFirstReward:"),
                               &dyyyOriginalSetSendFirstReward, (IMP)DYYYMiniProgramSetSendFirstReward);
    DYYYMiniProgramPrefetchIMP(cls, NSSelectorFromString(@"setDisableHostSendReward:"),
                               &dyyyOriginalSetDisableHostSendReward, (IMP)DYYYMiniProgramSetDisableHostSendReward);
}

static BOOL DYYYMiniProgramInstallControllerHooks(Class cls) {
    if (!DYYYMiniProgramValidateControllerClass(cls)) {
        NSLog(@"[DYYY][小程序跳广告] 核心方法不完整或签名不匹配，保持原流程：%@",
              NSStringFromClass(cls));
        return NO;
    }
    DYYYPrefetchMiniProgramOriginals(cls);

    BOOL sendRewardInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   NSSelectorFromString(@"sendReward"),
                                   (IMP)DYYYMiniProgramSendReward,
                                   &dyyyOriginalSendReward,
                                   DYYYMiniProgramMethodIsIntegerGetter,
                                   YES);
    BOOL sendFirstRewardInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   NSSelectorFromString(@"sendFirstReward"),
                                   (IMP)DYYYMiniProgramSendFirstReward,
                                   &dyyyOriginalSendFirstReward,
                                   DYYYMiniProgramMethodIsIntegerGetter,
                                   YES);
    BOOL viewDidAppearInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   @selector(viewDidAppear:),
                                   (IMP)DYYYMiniProgramViewDidAppear,
                                   &dyyyOriginalViewDidAppear,
                                   DYYYMiniProgramMethodIsViewDidAppear,
                                   YES);
    if (!sendRewardInstalled || !sendFirstRewardInstalled || !viewDidAppearInstalled) {
        return NO;
    }

    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"disableHostSendReward"),
                               (IMP)DYYYMiniProgramDisableHostSendReward,
                               &dyyyOriginalDisableHostSendReward,
                               DYYYMiniProgramMethodIsIntegerGetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setSendReward:"),
                               (IMP)DYYYMiniProgramSetSendReward,
                               &dyyyOriginalSetSendReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setSendFirstReward:"),
                               (IMP)DYYYMiniProgramSetSendFirstReward,
                               &dyyyOriginalSetSendFirstReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setDisableHostSendReward:"),
                               (IMP)DYYYMiniProgramSetDisableHostSendReward,
                               &dyyyOriginalSetDisableHostSendReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);

    NSLog(@"[DYYY][小程序跳广告] 已安装窄核心：%@", NSStringFromClass(cls));
    return YES;
}

static NSArray<NSNumber *> *DYYYMiniProgramRewardRetryDelays(void) {
    static NSArray<NSNumber *> *delays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      delays = @[ @0.5, @1.0, @2.0, @4.0, @8.0, @15.0 ];
    });
    return delays;
}

static void DYYYMiniProgramAttemptInstall(void);
static void DYYYMiniProgramAttemptInstallOnQueue(void);

static void DYYYMiniProgramScheduleRetryIfNeeded(void) {
    if (dyyyMiniProgramRewardHooksInstalled || dyyyMiniProgramRewardRetryScheduled) {
        return;
    }

    NSArray<NSNumber *> *delays = DYYYMiniProgramRewardRetryDelays();
    if (dyyyMiniProgramRewardRetryIndex >= delays.count) {
        return;
    }

    NSTimeInterval delay = delays[dyyyMiniProgramRewardRetryIndex++].doubleValue;
    dyyyMiniProgramRewardRetryScheduled = YES;
    // v2.4-35：重试不再投递到 main queue，避免主线程触碰 runtime 写锁。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   DYYYMiniProgramInstallQueue(), ^{
      dyyyMiniProgramRewardRetryScheduled = NO;
      DYYYMiniProgramAttemptInstallOnQueue();
    });
}

// v2.4-35：真身只在专用 serial queue 上执行，主线程绝不跑 MSHookMessageEx。
static void DYYYMiniProgramAttemptInstallOnQueue(void) {
    if (dyyyMiniProgramRewardHooksInstalled) {
        return;
    }

    Class controllerClass = NSClassFromString(kDYYYMiniProgramRewardControllerClassName);
    if (controllerClass) {
        dyyyMiniProgramRewardHooksInstalled =
            DYYYMiniProgramInstallControllerHooks(controllerClass);
        if (dyyyMiniProgramRewardHooksInstalled) {
            atomic_store_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                                  true,
                                  memory_order_release);
        }
    }
    if (!dyyyMiniProgramRewardHooksInstalled) {
        DYYYMiniProgramScheduleRetryIfNeeded();
    }
}

// v2.4-35：所有外部调用点统一经这个 wrapper 改投 install queue。
// 同队列内重复投递只是多排一个串行任务，不会并发，也不会死锁。
static void DYYYMiniProgramAttemptInstall(void) {
    dispatch_async(DYYYMiniProgramInstallQueue(), ^{
      DYYYMiniProgramAttemptInstallOnQueue();
    });
}

static void DYYYMiniProgramPerformDeferredImageRefresh(__unused void *context) {
    atomic_store_explicit(&dyyyMiniProgramRewardImageRefreshQueued, false, memory_order_release);
    DYYYMiniProgramAttemptInstallOnQueue();
}

static void DYYYMiniProgramImageAdded(__unused const struct mach_header *header,
                                      __unused intptr_t slide) {
    if (atomic_load_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                             memory_order_acquire)) {
        return;
    }

    if (!atomic_exchange_explicit(&dyyyMiniProgramRewardImageRefreshQueued,
                                  true,
                                  memory_order_acq_rel)) {
        // v2.4-35：dyld image 回调改投 install queue，不再借 main queue 装 hook。
        dispatch_async_f(DYYYMiniProgramInstallQueue(), NULL, DYYYMiniProgramPerformDeferredImageRefresh);
    }
}

void DYYYStartMiniProgramRewardBypassInstaller(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      void (^startInstaller)(void) = ^{
        DYYYMiniProgramAttemptInstall();
        dyyyMiniProgramRewardActiveObserver =
            [NSNotificationCenter.defaultCenter
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:nil
                        usingBlock:^(__unused NSNotification *notification) {
                          dyyyMiniProgramRewardRetryIndex = 0;
                          DYYYMiniProgramAttemptInstall();
                        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
          if (!atomic_load_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                                    memory_order_acquire)) {
              _dyld_register_func_for_add_image(DYYYMiniProgramImageAdded);
          }
        });
      };

      if (NSThread.isMainThread) {
          startInstaller();
      } else {
          dispatch_async(dispatch_get_main_queue(), startInstaller);
      }
    });
}
