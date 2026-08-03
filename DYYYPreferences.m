#import "DYYYPreferences.h"

NSString *const kDYYYPreferencesDidChangeNotification = @"kDYYYPreferencesDidChangeNotification";

static DYYYPreferences *_sharedInstance = nil;
static dispatch_once_t _sharedOnce;

@interface DYYYPreferences ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *cache;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

// CFNotificationCenter 回调必须是 C 函数（file-local，非全局导出）
static void DYYYPreferencesDarwinCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo);

@implementation DYYYPreferences

+ (instancetype)sharedInstance {
    dispatch_once(&_sharedOnce, ^{
        _sharedInstance = [[DYYYPreferences alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.dyyy.preferences.cache", DISPATCH_QUEUE_SERIAL);
        [self registerNotifications];
    }
    return self;
}

#pragma mark - 读取

+ (BOOL)boolForKey:(NSString *)key {
    return [[self objectForKey:key] boolValue];
}

+ (float)floatForKey:(NSString *)key {
    return [[self objectForKey:key] floatValue];
}

+ (NSInteger)integerForKey:(NSString *)key {
    return [[self objectForKey:key] integerValue];
}

+ (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (id)objectForKey:(NSString *)key {
    if (key == nil) return nil;
    DYYYPreferences *inst = [self sharedInstance];
    __block id result = nil;
    dispatch_sync(inst.queue, ^{
        id cached = inst.cache[key];
        if (cached != nil) {
            // 命中：NSNull 哨兵表示「已确认该键不存在」
            result = (cached == [NSNull null]) ? nil : cached;
        } else {
            // 未命中：回源一次并缓存
            id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
            inst.cache[key] = (stored != nil) ? stored : [NSNull null];
            result = stored;
        }
    });
    return result;
}

#pragma mark - 写入

+ (void)setObject:(id)object forKey:(NSString *)key {
    if (key == nil) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (object == nil) {
        [ud removeObjectForKey:key];
    } else {
        [ud setObject:object forKey:key];
    }
    // 同步更新缓存，保证本次写入后同进程立即可见
    DYYYPreferences *inst = [self sharedInstance];
    dispatch_sync(inst.queue, ^{
        inst.cache[key] = (object != nil) ? object : [NSNull null];
    });
    [[NSNotificationCenter defaultCenter] postNotificationName:kDYYYPreferencesDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"key": key}];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (void)setFloat:(float)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (void)removeObjectForKey:(NSString *)key {
    [self setObject:nil forKey:key];
}

#pragma mark - 变更监听（自愈）

- (void)registerNotifications {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)(self),
        DYYYPreferencesDarwinCallback,
        CFSTR("com.apple.UIKit.preferencesChanged"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
}

- (void)reloadAll {
    dispatch_sync(self.queue, ^{
        [self.cache removeAllObjects];
    });
}

static void DYYYPreferencesDarwinCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    DYYYPreferences *inst = (__bridge DYYYPreferences *)(observer);
    [inst reloadAll];
}

@end
