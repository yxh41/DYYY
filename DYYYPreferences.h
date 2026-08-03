#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 偏好变更通知（写入后广播，供其他模块观察）
FOUNDATION_EXPORT NSString *const kDYYYPreferencesDidChangeNotification;

/**
 * 线程安全的偏好内存缓存层。
 *
 * 设计要点：
 * - 首次读取某 key 时回源 NSUserDefaults，之后全部走内存字典（O(1)，零 IPC）。
 * - 通过 CFNotificationCenter 监听 com.apple.UIKit.preferencesChanged，
 *   捕获所有写入路径（含直接 standardUserDefaults 直写、外部改 plist），变更即清空缓存，自愈不陈旧。
 * - 所有读写都经过同一个串行队列，线程安全。
 */
@interface DYYYPreferences : NSObject

+ (instancetype)sharedInstance;

/// 读取（命中内存缓存，未命中回源 NSUserDefaults）
+ (BOOL)boolForKey:(NSString *)key;
+ (float)floatForKey:(NSString *)key;
+ (double)doubleForKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (NSString * _Nullable)stringForKey:(NSString *)key;
+ (id _Nullable)objectForKey:(NSString *)key;

/// 写入：写存储 + 更新缓存 + 广播变更通知
+ (void)setObject:(id _Nullable)object forKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (void)setFloat:(float)value forKey:(NSString *)key;
+ (void)setDouble:(double)value forKey:(NSString *)key;
+ (void)removeObjectForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
