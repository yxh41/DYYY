#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 插眼记录数据管理器（本地 JSON 持久化）
@interface DYYYWardManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - 插眼记录读写

/// 全部插眼记录（按保存时间倒序）
- (NSArray<NSDictionary *> *)allWards;

/// 指定用户（按 secUid）的全部插眼记录
- (NSArray<NSDictionary *> *)wardsForUserWithSecUid:(NSString *)secUid;

/// 新增一条插眼记录，返回生成的 wardID（失败返回 nil）
- (NSString * _Nullable)addWard:(NSDictionary *)ward;

/// 更新指定 wardID 的字段
- (void)updateWardWithID:(NSString *)wardID fields:(NSDictionary *)fields;

/// 删除指定 wardID 的记录
- (void)deleteWardWithID:(NSString *)wardID;

#pragma mark - 分类管理

/// 预置分类（不可删除）
+ (NSArray<NSString *> *)defaultCategories;

/// 用户自定义分类
+ (NSArray<NSString *> *)customCategories;

/// 全部分类（预置 + 自定义）
+ (NSArray<NSString *> *)allCategories;

/// 新增自定义分类（去重）
+ (void)addCustomCategory:(NSString *)category;

/// 删除自定义分类（同时把引用该分类的记录重置为「未分类」）
+ (void)removeCustomCategory:(NSString *)category;

@end

NS_ASSUME_NONNULL_END
