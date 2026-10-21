#import "DYYYWardManager.h"

static NSString *const kDYYYWardFileName = @"wards.json";
static NSString *const kDYYYWardCategoryFileName = @"wards_categories.json";

@implementation DYYYWardManager

+ (instancetype)sharedManager {
    static DYYYWardManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[DYYYWardManager alloc] init];
    });
    return manager;
}

#pragma mark - 目录与文件

+ (NSString *)wardDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        dir = [documents stringByAppendingPathComponent:@"DYYY"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

+ (NSString *)wardFilePath {
    return [[self wardDirectory] stringByAppendingPathComponent:kDYYYWardFileName];
}

+ (NSString *)wardCategoryFilePath {
    return [[self wardDirectory] stringByAppendingPathComponent:kDYYYWardCategoryFileName];
}

#pragma mark - 数据读写

- (NSArray<NSDictionary *> *)allWards {
    NSString *path = [DYYYWardManager wardFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSArray class]]) return @[];
    NSArray *wards = (NSArray *)obj;
    // 按保存时间倒序
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"saveTime" ascending:NO];
    return [wards sortedArrayUsingDescriptors:@[sort]];
}

- (NSArray<NSDictionary *> *)wardsForUserWithSecUid:(NSString *)secUid {
    if (secUid.length == 0) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *ward in [self allWards]) {
        if ([[ward objectForKey:@"secUid"] isEqualToString:secUid]) {
            [result addObject:ward];
        }
    }
    return [result copy];
}

- (NSString *)addWard:(NSDictionary *)ward {
    if (!ward) return nil;
    NSMutableDictionary *record = [ward mutableCopy];
    NSString *wardID = [record objectForKey:@"wardID"];
    if (wardID.length == 0) {
        wardID = [[NSUUID UUID] UUIDString];
        [record setObject:wardID forKey:@"wardID"];
    }
    if (![record objectForKey:@"saveTime"]) {
        [record setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"saveTime"];
    }

    NSMutableArray *wards = [[self allWards] mutableCopy];
    [wards addObject:record];
    [self writeWards:wards];
    return wardID;
}

- (void)updateWardWithID:(NSString *)wardID fields:(NSDictionary *)fields {
    if (wardID.length == 0 || !fields) return;
    NSMutableArray *wards = [[self allWards] mutableCopy];
    for (NSInteger i = 0; i < wards.count; i++) {
        NSMutableDictionary *record = [wards[i] mutableCopy];
        if ([[record objectForKey:@"wardID"] isEqualToString:wardID]) {
            [record addEntriesFromDictionary:fields];
            [wards replaceObjectAtIndex:i withObject:record];
            break;
        }
    }
    [self writeWards:wards];
}

- (void)deleteWardWithID:(NSString *)wardID {
    if (wardID.length == 0) return;
    NSMutableArray *wards = [[self allWards] mutableCopy];
    for (NSInteger i = wards.count - 1; i >= 0; i--) {
        if ([[wards[i] objectForKey:@"wardID"] isEqualToString:wardID]) {
            [wards removeObjectAtIndex:i];
            break;
        }
    }
    [self writeWards:wards];
}

- (void)writeWards:(NSArray *)wards {
    NSString *path = [DYYYWardManager wardFilePath];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:wards options:NSJSONWritingPrettyPrinted error:&error];
    if (data) {
        [data writeToFile:path atomically:YES];
    }
}

#pragma mark - 分类管理

+ (NSArray<NSString *> *)defaultCategories {
    return @[@"学习", @"音乐", @"电影", @"美食", @"旅行", @"工作", @"游戏", @"科技", @"灵感"];
}

+ (NSArray<NSString *> *)customCategories {
    NSString *path = [self wardCategoryFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if ([obj isKindOfClass:[NSArray class]]) {
        return (NSArray *)obj;
    }
    return @[];
}

+ (NSArray<NSString *> *)allCategories {
    NSMutableArray *all = [[self defaultCategories] mutableCopy];
    for (NSString *cat in [self customCategories]) {
        if (![all containsObject:cat]) {
            [all addObject:cat];
        }
    }
    return [all copy];
}

+ (void)addCustomCategory:(NSString *)category {
    if (category.length == 0) return;
    NSMutableArray *custom = [[self customCategories] mutableCopy];
    if ([custom containsObject:category]) return;
    [custom addObject:category];
    [self writeCategories:custom];
}

+ (void)removeCustomCategory:(NSString *)category {
    if (category.length == 0) return;
    NSMutableArray *custom = [[self customCategories] mutableCopy];
    [custom removeObject:category];
    [self writeCategories:custom];

    // 把引用该分类的记录重置为「未分类」，避免悬挂分类
    DYYYWardManager *mgr = [self sharedManager];
    NSMutableArray *wards = [[mgr allWards] mutableCopy];
    BOOL changed = NO;
    for (NSInteger i = 0; i < wards.count; i++) {
        NSMutableDictionary *record = [wards[i] mutableCopy];
        if ([[record objectForKey:@"category"] isEqualToString:category]) {
            [record setObject:@"未分类" forKey:@"category"];
            [wards replaceObjectAtIndex:i withObject:record];
            changed = YES;
        }
    }
    if (changed) {
        [mgr writeWards:wards];
    }
}

+ (void)writeCategories:(NSArray *)categories {
    NSString *path = [self wardCategoryFilePath];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:categories options:NSJSONWritingPrettyPrinted error:&error];
    if (data) {
        [data writeToFile:path atomically:YES];
    }
}

@end
