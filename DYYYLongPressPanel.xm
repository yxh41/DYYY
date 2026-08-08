#import "AwemeHeaders.h"
#import <objc/runtime.h>
#import "CityManager.h"
#import "DYYYPreferences.h"
#import "DYYYBottomAlertView.h"
#import "DYYYConfirmCloseView.h"
#import "DYYYCustomInputView.h"
#import "DYYYFilterSettingsView.h"
#import "DYYYKeywordListView.h"
#import "DYYYManager.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import "DYYYPipPlayer.h"

// MARK: - 获取作品数据辅助方法
// 安全读取任意对象的属性（兼容本地头文件未声明的运行期字段，如 uid/secUid/playCount 等）。
static id DYYYVideoInfoSafeValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    @try {
        return [obj valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

// 尝试多个 key，返回第一个非空字符串值（用于 uid/secUid 等字段名不确定的场景）。
static NSString *DYYYVideoInfoStringForKeys(id obj, NSArray<NSString *> *keys) {
    if (!obj || keys.count == 0) return @"";
    for (NSString *key in keys) {
        id val = DYYYVideoInfoSafeValue(obj, key);
        if (val && ![val isKindOfClass:[NSNull class]]) {
            NSString *s = [NSString stringWithFormat:@"%@", val];
            if (s.length > 0 && ![s isEqualToString:@"(null)"]) {
                return s;
            }
        }
    }
    return @"";
}

// 解析发布属地：优先 model.ipAttribution，其次 cityCode/region 用 CityManager 转地名。
static NSString *DYYYVideoInfoResolveRegion(AWEAwemeModel *model) {
    if (!model) return @"";
    NSString *ipAttribution = model.ipAttribution;
    if (ipAttribution.length > 0) return ipAttribution;

    NSString *cityCode = model.cityCode;
    if (cityCode && cityCode.length > 0 && ![cityCode isEqualToString:@"0"] && [cityCode integerValue] != 0) {
        NSString *city = [CityManager.sharedInstance getCityNameWithCode:cityCode];
        if (city.length > 0) return city;
    }

    NSString *regionCode = DYYYVideoInfoStringForKeys(model, @[@"region"]);
    if (regionCode.length > 0) {
        NSString *country = [CityManager.sharedInstance getCountryNameWithCode:regionCode];
        if (country.length > 0) return country;
    }
    return @"";
}

// 运行期遍历对象属性，按关键词匹配取值（兜底方案，用于头文件未声明的统计字段如 playCount/downloadCount）
static NSString *DYYYVideoInfoScanProperty(id obj, NSString *keyword) {
    if (!obj || !keyword) return @"";
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *name = property_getName(props[i]);
            NSString *propName = [NSString stringWithUTF8String:name];
            if ([propName.lowercaseString containsString:keyword.lowercaseString]) {
                @try {
                    id val = [obj valueForKey:propName];
                    if (val && ![val isKindOfClass:[NSNull class]]) {
                        NSString *s = [NSString stringWithFormat:@"%@", val];
                        if (s.length > 0 && ![s isEqualToString:@"(null)"]) {
                            free(props);
                            return s;
                        }
                    }
                } @catch (NSException *e) {}
            }
        }
        free(props);
        cls = class_getSuperclass(cls);
    }
    return @"";
}

// MARK: - 作品数据卡片
@interface DYYYWorkDataCardView : UIView
+ (void)showWithAwemeModel:(AWEAwemeModel *)model;
@end

@implementation DYYYWorkDataCardView {
    AWEAwemeModel *_model;
    NSString *_copyText;
    NSString *_avatarURL;
    NSString *_videoURL;
    NSString *_workLink;
    NSString *_profileLink;
    UILabel *_playCountLabel;

    NSString *_nickname;
    NSString *_douyinId;
    NSString *_uid;
    NSString *_secUid;
    NSString *_region;
    NSString *_itemID;
    NSString *_desc;
    NSString *_publishTime;
    NSString *_fetchTime;
    NSString *_playCount;
    NSString *_diggCount;
    NSString *_commentCount;
    NSString *_collectCount;
    NSString *_shareCount;
    NSString *_downloadCount;
}

+ (void)showWithAwemeModel:(AWEAwemeModel *)model {
    if (!model) return;
    DYYYWorkDataCardView *view = [[self alloc] initWithAwemeModel:model];
    [view show];
}

- (instancetype)initWithAwemeModel:(AWEAwemeModel *)model {
    UIWindow *window = [DYYYUtils getActiveWindow];
    self = [super initWithFrame:window.bounds];
    if (self) {
        _model = model;
        [self extractData];
        [self buildUI];
    }
    return self;
}

- (void)extractData {
    AWEUserModel *author = _model.author;
    _nickname = author.nickname ?: @"未知";
    _douyinId = author.shortID ?: @"";
    _uid = DYYYVideoInfoStringForKeys(author, @[@"uid", @"userID", @"uniqueId", @"userId"]);
    _secUid = DYYYVideoInfoStringForKeys(author, @[@"secUid", @"secUID", @"sec_uid"]);
    _avatarURL = (author.avatarMedium && author.avatarMedium.originURLList.count > 0) ? author.avatarMedium.originURLList.firstObject : @"";

    _itemID = _model.itemID ?: @"";
    _desc = _model.descriptionString ?: @"";
    _region = DYYYVideoInfoResolveRegion(_model);

    _publishTime = @"";
    NSNumber *createTimeNum = _model.createTime;
    if (createTimeNum && [createTimeNum doubleValue] > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[createTimeNum doubleValue]];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        _publishTime = [fmt stringFromDate:date] ?: @"";
    }

    AWEAwemeStatisticsModel *stats = _model.statistics;
    // 播放量：先试 KVC 多 key，再运行期扫描含 "play" 的属性
    _playCount = DYYYVideoInfoStringForKeys(stats, @[@"playCount", @"play_count"]);
    if (_playCount.length == 0) _playCount = DYYYVideoInfoScanProperty(stats, @"play");
    if (_playCount.length == 0) _playCount = @"0";
    _diggCount = [NSString stringWithFormat:@"%@", stats.diggCount ?: @0];
    _commentCount = DYYYVideoInfoStringForKeys(stats, @[@"commentCount", @"comment_count"]);
    if (_commentCount.length == 0) _commentCount = DYYYVideoInfoScanProperty(stats, @"comment");
    if (_commentCount.length == 0) _commentCount = @"0";
    _collectCount = DYYYVideoInfoStringForKeys(stats, @[@"collectCount", @"collect_count", @"favoriteCount"]);
    if (_collectCount.length == 0) _collectCount = DYYYVideoInfoScanProperty(stats, @"collect");
    if (_collectCount.length == 0) _collectCount = @"0";
    _shareCount = DYYYVideoInfoStringForKeys(stats, @[@"shareCount", @"share_count"]);
    if (_shareCount.length == 0) _shareCount = DYYYVideoInfoScanProperty(stats, @"share");
    if (_shareCount.length == 0) _shareCount = @"0";
    _downloadCount = DYYYVideoInfoStringForKeys(stats, @[@"downloadCount", @"download_count"]);
    if (_downloadCount.length == 0) _downloadCount = DYYYVideoInfoScanProperty(stats, @"download");
    if (_downloadCount.length == 0) _downloadCount = @"0";

    // 作品链接：用短格式，不用 shareURL（太长）
    _workLink = [NSString stringWithFormat:@"https://www.douyin.com/video/%@", _itemID];
    // 主页链接
    if (_secUid.length > 0) {
        _profileLink = [NSString stringWithFormat:@"https://www.douyin.com/user/%@", _secUid];
    } else if (_uid.length > 0) {
        _profileLink = [NSString stringWithFormat:@"https://www.douyin.com/user/%@", _uid];
    } else {
        _profileLink = @"";
    }

    AWEVideoModel *video = _model.video;
    if (video && video.h264URL && video.h264URL.originURLList.count > 0) {
        _videoURL = video.h264URL.originURLList.firstObject;
    } else if (video && video.playURL && video.playURL.originURLList.count > 0) {
        _videoURL = video.playURL.originURLList.firstObject;
    }

    NSDateFormatter *nowFmt = [[NSDateFormatter alloc] init];
    nowFmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    _fetchTime = [nowFmt stringFromDate:[NSDate date]] ?: @"";

    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"作者：%@\n", _nickname];
    [info appendFormat:@"抖音号：%@\n", _douyinId];
    [info appendFormat:@"UID：%@\n", _uid];
    [info appendFormat:@"secUID：%@\n", _secUid];
    [info appendFormat:@"获取时间：%@\n", _fetchTime];
    [info appendFormat:@"作品ID：%@\n", _itemID];
    [info appendFormat:@"作品文案：%@\n", _desc];
    [info appendFormat:@"发布属地：%@\n", _region];
    [info appendFormat:@"发布时间：%@\n", _publishTime];
    [info appendFormat:@"播放量：%@\n", _playCount];
    [info appendFormat:@"点赞量：%@\n", _diggCount];
    [info appendFormat:@"评论量：%@\n", _commentCount];
    [info appendFormat:@"收藏量：%@\n", _collectCount];
    [info appendFormat:@"分享量：%@\n", _shareCount];
    [info appendFormat:@"下载量：%@\n", _downloadCount];
    [info appendFormat:@"作品链接：%@\n", _workLink];
    [info appendFormat:@"主页链接：%@\n", _profileLink];
    _copyText = [info copy];
}

- (void)buildUI {
    // 背景遮罩（点空白处关闭）
    UIView *dimView = [[UIView alloc] initWithFrame:self.bounds];
    dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [dimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
    [self addSubview:dimView];

    CGFloat cardW = MIN(self.bounds.size.width - 36, 340);
    CGFloat cardH = MIN(self.bounds.size.height - 80, 540);
    CGFloat cardX = (self.bounds.size.width - cardW) / 2;
    CGFloat cardY = (self.bounds.size.height - cardH) / 2;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardH)];
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = 18;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    card.layer.shadowOpacity = 0.25;
    card.layer.shadowRadius = 16;
    [self addSubview:card];

    CGFloat topH = 52;
    CGFloat bottomH = 56;
    CGFloat margin = 16;

    // 顶部栏
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardW, topH)];
    [card addSubview:topBar];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(10, 8, 36, 36);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    [closeBtn setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 11, cardW - 100, 30)];
    titleLabel.text = @"作品数据";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor blackColor];
    [topBar addSubview:titleLabel];

    UIButton *copyTopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyTopBtn.frame = CGRectMake(cardW - 78, 10, 68, 32);
    copyTopBtn.layer.cornerRadius = 14;
    copyTopBtn.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    copyTopBtn.layer.borderColor = [UIColor colorWithRed:0.15 green:0.68 blue:0.38 alpha:1].CGColor;
    [copyTopBtn setTitle:@"复制信息" forState:UIControlStateNormal];
    [copyTopBtn setTitleColor:[UIColor colorWithRed:0.15 green:0.68 blue:0.38 alpha:1] forState:UIControlStateNormal];
    copyTopBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [copyTopBtn addTarget:self action:@selector(copyInfo:) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:copyTopBtn];

    // 底部栏
    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, cardH - bottomH, cardW, bottomH)];
    [card addSubview:bottomBar];

    NSArray *bottomTitles = @[@"下载原画", @"复制信息", @"保存头像"];
    NSArray *bottomActions = @[NSStringFromSelector(@selector(downloadOriginal:)),
                               NSStringFromSelector(@selector(copyInfo:)),
                               NSStringFromSelector(@selector(saveAvatar:))];
    CGFloat btnW = (cardW - margin * 2 - 16) / 3;
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(margin + i * (btnW + 8), 8, btnW, 40);
        btn.layer.cornerRadius = 8;
        btn.titleLabel.font = [UIFont systemFontOfSize:14];
        [btn setTitle:bottomTitles[i] forState:UIControlStateNormal];
        if (i == 0) {
            btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.68 blue:0.38 alpha:1];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
            [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        }
        [btn addTarget:self action:NSSelectorFromString(bottomActions[i]) forControlEvents:UIControlEventTouchUpInside];
        [bottomBar addSubview:btn];
    }

    // 内容滚动区
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, topH, cardW, cardH - topH - bottomH)];
    scroll.alwaysBounceVertical = YES;
    [card addSubview:scroll];

    CGFloat y = margin;
    CGFloat contentW = cardW - margin * 2;

    // 作者区（头像 + 信息）
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake(margin, y, 54, 54)];
    avatar.layer.cornerRadius = 27;
    avatar.clipsToBounds = YES;
    avatar.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    [scroll addSubview:avatar];
    if (_avatarURL.length > 0) {
        [self loadImageWithURL:_avatarURL intoImageView:avatar];
    }

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + 66, y, contentW - 66, 22)];
    nameLabel.text = _nickname;
    nameLabel.font = [UIFont boldSystemFontOfSize:17];
    nameLabel.textColor = [UIColor blackColor];
    [scroll addSubview:nameLabel];

    y += 26;
    UILabel *idLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + 66, y, contentW - 66, 18)];
    idLabel.text = [NSString stringWithFormat:@"抖音号：%@", _douyinId];
    idLabel.font = [UIFont systemFontOfSize:13];
    idLabel.textColor = [UIColor grayColor];
    [scroll addSubview:idLabel];

    y += 22;
    UILabel *uidLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + 66, y, contentW - 66, 18)];
    uidLabel.text = [NSString stringWithFormat:@"UID：%@", _uid];
    uidLabel.font = [UIFont systemFontOfSize:12];
    uidLabel.textColor = [UIColor grayColor];
    uidLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [scroll addSubview:uidLabel];

    y += 34;
    [self addLineIn:scroll atY:y - 8 width:contentW margin:margin];

    // 获取时间
    UILabel *fetchLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, contentW, 18)];
    fetchLabel.text = [NSString stringWithFormat:@"获取时间：%@", _fetchTime];
    fetchLabel.font = [UIFont systemFontOfSize:12];
    fetchLabel.textColor = [UIColor grayColor];
    [scroll addSubview:fetchLabel];
    y += 26;

    // 作品信息
    y = [self addSectionTitle:@"【作品信息】" in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"作品ID" value:_itemID in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"作品文案" value:_desc in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"发布属地" value:_region in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"发布时间" value:_publishTime in:scroll atY:y width:contentW margin:margin];

    // 统计数据
    y += 4;
    y = [self addSectionTitle:@"【统计数据】" in:scroll atY:y width:contentW margin:margin];
    // 播放量：特殊处理，本地可能为 0，需调 tikhub.io API 异步补值
    {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, contentW, 0)];
        lbl.text = [NSString stringWithFormat:@"播放量：%@", _playCount];
        lbl.font = [UIFont systemFontOfSize:14];
        lbl.textColor = [UIColor blackColor];
        lbl.numberOfLines = 0;
        CGSize sz = [lbl.text boundingRectWithSize:CGSizeMake(contentW, CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:@{NSFontAttributeName: lbl.font}
                                           context:nil].size;
        lbl.frame = CGRectMake(margin, y, contentW, ceil(sz.height) + 4);
        [scroll addSubview:lbl];
        _playCountLabel = lbl;
        y += CGRectGetHeight(lbl.frame) + 2;
    }
    y = [self addRowWithKey:@"点赞量" value:_diggCount in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"评论量" value:_commentCount in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"收藏量" value:_collectCount in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"分享量" value:_shareCount in:scroll atY:y width:contentW margin:margin];
    y = [self addRowWithKey:@"下载量" value:_downloadCount in:scroll atY:y width:contentW margin:margin];

    // 作品链接
    y += 4;
    y = [self addSectionTitle:@"【作品链接】" in:scroll atY:y width:contentW margin:margin];
    UILabel *linkLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, contentW, 0)];
    linkLabel.text = _workLink;
    linkLabel.font = [UIFont systemFontOfSize:12];
    linkLabel.textColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1];
    linkLabel.numberOfLines = 0;
    linkLabel.userInteractionEnabled = YES;
    [linkLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyLink:)]];
    CGSize linkSize = [_workLink boundingRectWithSize:CGSizeMake(contentW, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:@{NSFontAttributeName: linkLabel.font}
                                              context:nil].size;
    linkLabel.frame = CGRectMake(margin, y, contentW, ceil(linkSize.height) + 4);
    [scroll addSubview:linkLabel];
    y += CGRectGetHeight(linkLabel.frame) + 10;

    // 主页链接
    if (_profileLink.length > 0) {
        y = [self addSectionTitle:@"【主页链接】" in:scroll atY:y width:contentW margin:margin];
        UILabel *profileLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, contentW, 0)];
        profileLabel.text = _profileLink;
        profileLabel.font = [UIFont systemFontOfSize:12];
        profileLabel.textColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1];
        profileLabel.numberOfLines = 0;
        profileLabel.userInteractionEnabled = YES;
        [profileLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyProfileLink:)]];
        CGSize profileSize = [_profileLink boundingRectWithSize:CGSizeMake(contentW, CGFLOAT_MAX)
                                                       options:NSStringDrawingUsesLineFragmentOrigin
                                                    attributes:@{NSFontAttributeName: profileLabel.font}
                                                       context:nil].size;
        profileLabel.frame = CGRectMake(margin, y, contentW, ceil(profileSize.height) + 4);
        [scroll addSubview:profileLabel];
        y += CGRectGetHeight(profileLabel.frame) + 10;
    }

    scroll.contentSize = CGSizeMake(cardW, y + margin);
}

- (CGFloat)addSectionTitle:(NSString *)title in:(UIView *)container atY:(CGFloat)y width:(CGFloat)w margin:(CGFloat)margin {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w, 22)];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:15];
    label.textColor = [UIColor blackColor];
    [container addSubview:label];
    return y + 26;
}

- (CGFloat)addRowWithKey:(NSString *)key value:(NSString *)value in:(UIView *)container atY:(CGFloat)y width:(CGFloat)w margin:(CGFloat)margin {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w, 0)];
    label.text = [NSString stringWithFormat:@"%@：%@", key, value];
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [UIColor blackColor];
    label.numberOfLines = 0;
    CGSize size = [label.text boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:@{NSFontAttributeName: label.font}
                                             context:nil].size;
    label.frame = CGRectMake(margin, y, w, ceil(size.height) + 4);
    [container addSubview:label];
    return y + CGRectGetHeight(label.frame) + 2;
}

- (void)addLineIn:(UIView *)container atY:(CGFloat)y width:(CGFloat)w margin:(CGFloat)margin {
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(margin, y, w, 1.0 / [UIScreen mainScreen].scale)];
    line.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
    [container addSubview:line];
}

- (void)loadImageWithURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            UIImage *img = [UIImage imageWithData:data];
            if (img) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    imageView.image = img;
                });
            }
        }
    }];
    [task resume];
}

- (void)show {
    UIWindow *window = [DYYYUtils getActiveWindow];
    [window addSubview:self];
    self.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1; }];
    [self fetchPlayCountFromAPI];
}

- (void)fetchPlayCountFromAPI {
    NSString *token = DYYYGetString(@"DYYYWorkDataAPIToken");
    if (token.length == 0 || _itemID.length == 0) return;
    // 正确端点：V3 fetch_video_statistics，参数 aweme_ids（逗号分隔），大陆用 api.tikhub.dev
    NSString *urlString = [NSString stringWithFormat:@"https://api.tikhub.dev/api/v1/douyin/app/v3/fetch_video_statistics?aweme_ids=%@", _itemID];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_playCountLabel) {
            _playCountLabel.text = [NSString stringWithFormat:@"播放量：%@（API获取中...）", _playCount];
        }
    });

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    req.timeoutInterval = 10;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_playCountLabel) _playCountLabel.text = [NSString stringWithFormat:@"播放量：%@（API失败:%@）", _playCount, error.localizedDescription];
            });
            return;
        }
        // 先把原始响应转成字符串，方便调试
        NSString *rawStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        // 解析外层 JSON
        id outerJson = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];

        // 递归搜索：在整个 JSON 树里找包含指定 key 的值
        NSString * (^searchKey)(id, NSString *) = ^NSString *(id node, NSString *targetKey) {
            if (!node) return (NSString *)nil;
            if ([node isKindOfClass:[NSDictionary class]]) {
                // 先检查当前层有没有目标 key
                for (NSString *k in [(NSDictionary *)node allKeys]) {
                    if ([k.lowercaseString containsString:targetKey.lowercaseString]) {
                        id v = [(NSDictionary *)node objectForKey:k];
                        if (v && ![v isKindOfClass:[NSNull class]]) {
                            NSString *s = [NSString stringWithFormat:@"%@", v];
                            if (s.length > 0 && ![s isEqualToString:@"(null)"]) return s;
                        }
                    }
                }
                // 递归搜索子节点
                for (id v in [(NSDictionary *)node allValues]) {
                    NSString *r = searchKey(v, targetKey);
                    if (r) return r;
                }
            } else if ([node isKindOfClass:[NSArray class]]) {
                for (id v in (NSArray *)node) {
                    NSString *r = searchKey(v, targetKey);
                    if (r) return r;
                }
            } else if ([node isKindOfClass:[NSString class]]) {
                // 字符串可能是嵌套 JSON，尝试二次解析
                NSData *innerData = [(NSString *)node dataUsingEncoding:NSUTF8StringEncoding];
                if (innerData) {
                    id innerJson = [NSJSONSerialization JSONObjectWithData:innerData options:NSJSONReadingAllowFragments error:nil];
                    if (innerJson && innerJson != node) {
                        NSString *r = searchKey(innerJson, targetKey);
                        if (r) return r;
                    }
                }
            }
            return (NSString *)nil;
        };

        // 如果外层解析失败，尝试直接把整个 rawStr 当 JSON 解析
        if (!outerJson) {
            outerJson = rawStr;
        }

        NSString *playCountStr = searchKey(outerJson, @"play_count");
        NSString *downloadCountStr = searchKey(outerJson, @"download_count");
        NSString *shareCountStr = searchKey(outerJson, @"share_count");
        NSString *diggCountStr = searchKey(outerJson, @"digg_count");

        if (playCountStr.length == 0 || [playCountStr isEqualToString:@"(null)"]) {
            // 找不到 play_count，显示原始响应前 80 字符方便调试
            NSString *preview = rawStr;
            if (preview.length > 80) preview = [preview substringToIndex:80];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_playCountLabel) _playCountLabel.text = [NSString stringWithFormat:@"播放量：%@（未找到,响应:%@...）", _playCount, preview];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            _playCount = playCountStr;
            if (_playCountLabel) _playCountLabel.text = [NSString stringWithFormat:@"播放量：%@", _playCount];
            // 也更新下载量/分享量/点赞量（API 返回了的话）
            if (downloadCountStr.length > 0 && ![downloadCountStr isEqualToString:@"(null)"]) {
                _downloadCount = downloadCountStr;
            }
            if (shareCountStr.length > 0 && ![shareCountStr isEqualToString:@"(null)"]) {
                _shareCount = shareCountStr;
            }
            if (diggCountStr.length > 0 && ![diggCountStr isEqualToString:@"(null)"]) {
                _diggCount = diggCountStr;
            }
            [self refreshCopyText];
        });
    }];
    [task resume];
}

- (void)refreshCopyText {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"作者：%@\n", _nickname];
    [info appendFormat:@"抖音号：%@\n", _douyinId];
    [info appendFormat:@"UID：%@\n", _uid];
    [info appendFormat:@"secUID：%@\n", _secUid];
    [info appendFormat:@"获取时间：%@\n", _fetchTime];
    [info appendFormat:@"作品ID：%@\n", _itemID];
    [info appendFormat:@"作品文案：%@\n", _desc];
    [info appendFormat:@"发布属地：%@\n", _region];
    [info appendFormat:@"发布时间：%@\n", _publishTime];
    [info appendFormat:@"播放量：%@\n", _playCount];
    [info appendFormat:@"点赞量：%@\n", _diggCount];
    [info appendFormat:@"评论量：%@\n", _commentCount];
    [info appendFormat:@"收藏量：%@\n", _collectCount];
    [info appendFormat:@"分享量：%@\n", _shareCount];
    [info appendFormat:@"下载量：%@\n", _downloadCount];
    [info appendFormat:@"作品链接：%@\n", _workLink];
    [info appendFormat:@"主页链接：%@\n", _profileLink];
    _copyText = [info copy];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)copyInfo:(id)sender {
    [[UIPasteboard generalPasteboard] setString:_copyText];
    [DYYYToast showSuccessToastWithMessage:@"作品数据已复制"];
}

- (void)copyLink:(UITapGestureRecognizer *)gesture {
    [[UIPasteboard generalPasteboard] setString:_workLink];
    [DYYYToast showSuccessToastWithMessage:@"作品链接已复制"];
}

- (void)copyProfileLink:(UITapGestureRecognizer *)gesture {
    [[UIPasteboard generalPasteboard] setString:_profileLink];
    [DYYYToast showSuccessToastWithMessage:@"主页链接已复制"];
}

- (void)saveAvatar:(id)sender {
    if (_avatarURL.length == 0) {
        [DYYYUtils showToast:@"没有头像地址"];
        return;
    }
    NSURL *url = [NSURL URLWithString:_avatarURL];
    if (url) {
        [DYYYManager downloadMedia:url mediaType:MediaTypeImage audio:nil completion:^(BOOL success){}];
    }
}

- (void)downloadOriginal:(id)sender {
    if (_videoURL.length == 0) {
        [DYYYUtils showToast:@"没有原画地址"];
        return;
    }
    NSURL *url = [NSURL URLWithString:_videoURL];
    if (url) {
        [DYYYManager downloadMedia:url mediaType:MediaTypeVideo audio:nil completion:^(BOOL success){}];
    }
}

@end

%hook AWELongPressPanelViewGroupModel
%property(nonatomic, assign) BOOL isDYYYCustomGroup;
%end

// Modern风格长按面板（新版UI）
%hook AWEModernLongPressPanelTableViewController
- (NSArray *)dataArray {
    // 检查是否开启精简模式
    BOOL simplifyPanel = DYYYGetBool(@"DYYYSimplifyLongPressPanel");

    NSArray *originalArray = %orig;
    if (!originalArray) {
        originalArray = @[];
    }

    // 如果开启精简模式，直接跳过原始面板处理，只返回自定义选项
    if (simplifyPanel) {
        originalArray = @[]; // 清空原始数组
    } else {
        // 获取需要隐藏的按钮设置（从文本输入框读取，逗号分隔）
        NSString *hidePanelItems = DYYYGetString(@"DYYYHidePanelItems");
        NSMutableSet<NSString *> *hideItemsLowerSet = [NSMutableSet set];

        if (hidePanelItems && hidePanelItems.length > 0) {
            // 支持中英文逗号分隔
            NSString *normalizedItems = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
            NSArray *items = [normalizedItems componentsSeparatedByString:@","];
            for (NSString *item in items) {
                NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedItem.length > 0) {
                    [hideItemsLowerSet addObject:[trimmedItem lowercaseString]];
                }
            }
        }

        // 如果有需要隐藏的项目，才进行过滤
        if (hideItemsLowerSet.count > 0) {
            NSMutableArray *modifiedOriginalGroups = [NSMutableArray array];

            for (id group in originalArray) {
                if ([group isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                    AWELongPressPanelViewGroupModel *groupModel = (AWELongPressPanelViewGroupModel *)group;
                    NSMutableArray *filteredGroupArr = [NSMutableArray array];

                    for (id item in groupModel.groupArr) {
                        if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                            AWELongPressPanelBaseViewModel *viewModel = (AWELongPressPanelBaseViewModel *)item;
                            NSString *descString = viewModel.describeString;

                            BOOL shouldHide = NO;
                            if (descString && descString.length > 0) {
                                NSString *descLower = [descString lowercaseString];

                                // 精确匹配
                                if ([hideItemsLowerSet containsObject:descLower]) {
                                    shouldHide = YES;
                                } else {
                                    // 部分匹配
                                    for (NSString *hideItemLower in hideItemsLowerSet) {
                                        if ([descLower containsString:hideItemLower] || [hideItemLower containsString:descLower]) {
                                            shouldHide = YES;
                                            break;
                                        }
                                    }
                                }
                            }

                            if (!shouldHide) {
                                [filteredGroupArr addObject:item];
                            }
                        } else {
                            [filteredGroupArr addObject:item];
                        }
                    }

                    if (filteredGroupArr.count > 0) {
                        AWELongPressPanelViewGroupModel *filteredGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
                        filteredGroup.groupType = groupModel.groupType;
                        filteredGroup.isModern = groupModel.isModern;
                        filteredGroup.groupArr = filteredGroupArr;
                        [modifiedOriginalGroups addObject:filteredGroup];
                    }
                } else {
                    [modifiedOriginalGroups addObject:group];
                }
            }
            originalArray = modifiedOriginalGroups;
        }
    }

    // 检查是否启用了任意长按功能
    BOOL hasAnyFeatureEnabled = NO;
    // 检查各个单独的功能开关
    BOOL enableSaveVideo = DYYYGetBool(@"DYYYLongPressSaveVideo");
    BOOL enableSaveCover = DYYYGetBool(@"DYYYLongPressSaveCover");
    BOOL enableSaveAudio = DYYYGetBool(@"DYYYLongPressSaveAudio");
    BOOL enableSaveCurrentImage = DYYYGetBool(@"DYYYLongPressSaveCurrentImage");
    BOOL enableSaveAllImages = DYYYGetBool(@"DYYYLongPressSaveAllImages");
    BOOL enableCopyText = DYYYGetBool(@"DYYYLongPressCopyText");
    BOOL enableCopyLink = DYYYGetBool(@"DYYYLongPressCopyLink");
    BOOL enableApiDownload = DYYYGetBool(@"DYYYLongPressApiDownload");
    BOOL enableFilterUser = DYYYGetBool(@"DYYYLongPressFilterUser");
    BOOL enableFilterKeyword = DYYYGetBool(@"DYYYLongPressFilterTitle");
    BOOL enableTimerClose = DYYYGetBool(@"DYYYLongPressTimerClose");
    BOOL enableCreateVideo = DYYYGetBool(@"DYYYLongPressCreateVideo");
    BOOL enablePip = DYYYGetBool(@"DYYYLongPressPip");

    // 检查是否有任何功能启用
    hasAnyFeatureEnabled = enableSaveVideo || enableSaveCover || enableSaveAudio || enableSaveCurrentImage || enableSaveAllImages || enableCopyText || enableCopyLink || enableApiDownload ||
                           enableFilterUser || enableFilterKeyword || enableTimerClose || enableCreateVideo || enablePip;

    // 如果没有任何功能启用，仅使用官方按钮
    if (!hasAnyFeatureEnabled) {
        return originalArray;
    }

    // 创建自定义功能按钮
    NSMutableArray *viewModels = [NSMutableArray array];

    BOOL isNewLivePhoto = (self.awemeModel.video && self.awemeModel.animatedImageVideoInfo != nil);

    // 视频下载功能 (非实况照片才显示)
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && !isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        downloadViewModel.awemeModel = self.awemeModel;
        downloadViewModel.actionType = 666;
        downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        downloadViewModel.describeString = @"保存视频";
        downloadViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          AWEMusicModel *musicModel = awemeModel.music;
          NSURL *audioURL = nil;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
          }

                  if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                      NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                      [DYYYManager downloadMedia:url
                                       mediaType:MediaTypeVideo
                                           audio:audioURL
                                      completion:^(BOOL success){
                                      }];
                  }
              
          
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:downloadViewModel];
    }

    //  新版实况照片保存
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *livePhotoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        livePhotoViewModel.awemeModel = self.awemeModel;
        livePhotoViewModel.actionType = 679;
        livePhotoViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        livePhotoViewModel.describeString = @"保存实况";
        livePhotoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;

          // 使用封面URL作为图片URL
          NSURL *imageURL = nil;
          if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
          }

          // 视频URL从视频模型获取
          NSURL *videoURL = nil;
          if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
          } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
          }

          // 下载实况照片
          if (imageURL && videoURL) {
              [DYYYManager downloadLivePhoto:imageURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:livePhotoViewModel];
    }

    // 当前图片/实况下载功能
    if (enableSaveCurrentImage && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
        AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imageViewModel.awemeModel = self.awemeModel;
        imageViewModel.actionType = 669;
        imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";

        if (self.awemeModel.albumImages.count == 1) {
            imageViewModel.describeString = @"保存图片";
        } else {
            imageViewModel.describeString = @"保存当前图片";
        }

        AWEImageAlbumImageModel *currimge = self.awemeModel.albumImages[self.awemeModel.currentImageIndex - 1];
        if (currimge.clipVideo != nil || self.awemeModel.isLivePhoto) {
            if (self.awemeModel.albumImages.count == 1) {
                imageViewModel.describeString = @"保存实况";
            } else {
                imageViewModel.describeString = @"保存当前实况";
            }
        }
        imageViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEImageAlbumImageModel *currentImageModel = nil;
          if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
              currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
          } else {
              currentImageModel = awemeModel.albumImages.firstObject;
          }
          // 如果是实况的话
          // 查找非.image后缀的URL
          NSURL *downloadURL = nil;
          for (NSString *urlString in currentImageModel.urlList) {
              NSURL *url = [NSURL URLWithString:urlString];
              NSString *pathExtension = [url.path.lowercaseString pathExtension];
              if (![pathExtension isEqualToString:@"image"]) {
                  downloadURL = url;
                  break;
              }
          }

          if (currentImageModel.clipVideo != nil) {
              NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
              [DYYYManager downloadLivePhoto:downloadURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          } else if (currentImageModel && currentImageModel.urlList.count > 0) {
              if (downloadURL) {
                  [DYYYManager downloadMedia:downloadURL
                                   mediaType:MediaTypeImage
                                       audio:nil
                                  completion:^(BOOL success) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:@"图片保存已取消"];
                                    }
                                  }];
              } else {
                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
              }
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imageViewModel];
    }

    // 保存所有图片/实况功能
    if (enableSaveAllImages && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 1) {
        AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        allImagesViewModel.awemeModel = self.awemeModel;
        allImagesViewModel.actionType = 670;
        allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        allImagesViewModel.describeString = @"保存所有图片";
        // 检查是否有实况照片并更改按钮文字
        BOOL hasLivePhoto = NO;
        for (AWEImageAlbumImageModel *imageModel in self.awemeModel.albumImages) {
            if (imageModel.clipVideo != nil) {
                hasLivePhoto = YES;
                break;
            }
        }
        if (hasLivePhoto) {
            allImagesViewModel.describeString = @"保存所有实况";
        }
        allImagesViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSMutableArray *imageURLs = [NSMutableArray array];
          NSMutableArray *livePhotos = [NSMutableArray array];

          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSURL *downloadURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          downloadURL = url;
                          break;
                      }
                  }

                  if (!downloadURL && imageModel.urlList.count > 0) {
                      downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                  }

                  // 检查是否是实况照片
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                  } else {
                      [imageURLs addObject:downloadURL.absoluteString];
                  }
              }
          }

          // 分别处理普通图片和实况照片
          if (livePhotos.count > 0) {
              [DYYYManager downloadAllLivePhotos:livePhotos];
          }

          if (imageURLs.count > 0) {
              [DYYYManager downloadAllImages:imageURLs];
          }

          if (livePhotos.count == 0 && imageURLs.count == 0) {
              [DYYYUtils showToast:@"没有找到合适格式的图片"];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:allImagesViewModel];
    }

    // 接口保存功能
    NSString *apiKey = [DYYYPreferences objectForKey:@"DYYYInterfaceDownload"];
    if (enableApiDownload && apiKey.length > 0) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存";
        apiDownload.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          if (shareLink.length == 0) {
              [DYYYUtils showToast:@"无法获取分享链接"];
              return;
          }
          // 使用封装的方法进行解析下载
          [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:apiDownload];
    }

    // 封面下载功能
    if (enableSaveCover && self.awemeModel.awemeType != 68) {
        AWELongPressPanelBaseViewModel *coverViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        coverViewModel.awemeModel = self.awemeModel;
        coverViewModel.actionType = 667;
        coverViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        coverViewModel.describeString = @"保存封面";
        coverViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          if (videoModel && videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                if (success) {
                                } else {
                                    [DYYYUtils showToast:@"封面保存已取消"];
                                }
                              }];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:coverViewModel];
    }

    // 音频下载功能
    if (enableSaveAudio) {
        AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioViewModel.awemeModel = self.awemeModel;
        audioViewModel.actionType = 668;
        audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        audioViewModel.describeString = @"保存音频";
        audioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEMusicModel *musicModel = awemeModel.music;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioViewModel];
    }

    // 创建视频功能
    if (enableCreateVideo && self.awemeModel.awemeType == 68) {
        AWELongPressPanelBaseViewModel *createVideoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        createVideoViewModel.awemeModel = self.awemeModel;
        createVideoViewModel.actionType = 677;
        createVideoViewModel.duxIconName = @"ic_videosearch_outlined_20";
        createVideoViewModel.describeString = @"制作视频";
        createVideoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;

          // 收集普通图片URL
          NSMutableArray *imageURLs = [NSMutableArray array];
          // 收集实况照片信息（图片URL+视频URL）
          NSMutableArray *livePhotos = [NSMutableArray array];

          // 获取背景音乐URL
          NSString *bgmURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              bgmURL = awemeModel.music.playURL.originURLList.firstObject;
          }

          // 处理所有图片和实况
          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSString *bestURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          bestURL = urlString;
                          break;
                      }
                  }

                  if (!bestURL && imageModel.urlList.count > 0) {
                      bestURL = imageModel.urlList.firstObject;
                  }

                  // 如果是实况照片，需要收集图片和视频URL
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      if (videoURL) {
                          [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                      }
                  } else {
                      // 普通图片
                      [imageURLs addObject:bestURL];
                  }
              }
          }

          // 调用视频创建API
          [DYYYManager createVideoFromMedia:imageURLs
              livePhotos:livePhotos
              bgmURL:bgmURL
              progress:^(NSInteger current, NSInteger total, NSString *status) {
              }
              completion:^(BOOL success, NSString *message) {
                if (success) {
                } else {
                    [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                }
              }];

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:createVideoViewModel];
    }

    // 复制文案功能
    if (enableCopyText) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";
        copyText.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          [[UIPasteboard generalPasteboard] setString:descText];
          [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyText];
    }

    // 复制分享链接功能
    if (enableCopyLink) {
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制链接";
        copyShareLink.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          NSString *cleanedURL = cleanShareURL(shareLink);
          [[UIPasteboard generalPasteboard] setString:cleanedURL];
          [DYYYToast showSuccessToastWithMessage:@"分享链接已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyShareLink];
    }

    // 过滤用户功能
    if (enableFilterUser) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 674;
        filterKeywords.duxIconName = @"ic_userban_outlined_20";
        filterKeywords.describeString = @"过滤用户";
        filterKeywords.action = ^{
          AWEUserModel *author = self.awemeModel.author;
          NSString *nickname = author.nickname ?: @"未知用户";
          NSString *shortId = author.shortID ?: @"";
          // 创建当前用户的过滤格式 "nickname-shortid"
          NSString *currentUserFilter = [NSString stringWithFormat:@"%@-%@", nickname, shortId];
          // 获取保存的过滤用户列表
          NSString *savedUsers = [DYYYPreferences objectForKey:@"DYYYFilterUsers"] ?: @"";
          NSArray *userArray = [savedUsers length] > 0 ? [savedUsers componentsSeparatedByString:@","] : @[];
          BOOL userExists = NO;
          for (NSString *userInfo in userArray) {
              NSArray *components = [userInfo componentsSeparatedByString:@"-"];
              if (components.count >= 2) {
                  NSString *userId = [components lastObject];
                  if ([userId isEqualToString:shortId] && shortId.length > 0) {
                      userExists = YES;
                      break;
                  }
              }
          }
          NSString *actionButtonText = userExists ? @"取消过滤" : @"添加过滤";
          [DYYYBottomAlertView showAlertWithTitle:@"过滤用户视频"
              message:[NSString stringWithFormat:@"用户: %@ (ID: %@)", nickname, shortId]
              avatarURL:nil
              cancelButtonText:@"管理过滤列表"
              confirmButtonText:actionButtonText
              cancelAction:^{
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:userArray];
                keywordListView.onConfirm = ^(NSArray *users) {
                  NSString *userString = [users componentsJoinedByString:@","];
                  [DYYYPreferences setObject:userString forKey:@"DYYYFilterUsers"];
                  [DYYYUtils showToast:@"过滤用户列表已更新"];
                };
                [keywordListView show];
              }
              closeAction:nil
              confirmAction:^{
                // 添加或移除用户过滤
                NSMutableArray *updatedUsers = [NSMutableArray arrayWithArray:userArray];
                if (userExists) {
                    // 移除用户
                    NSMutableArray *toRemove = [NSMutableArray array];
                    for (NSString *userInfo in updatedUsers) {
                        NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                        if (components.count >= 2) {
                            NSString *userId = [components lastObject];
                            if ([userId isEqualToString:shortId]) {
                                [toRemove addObject:userInfo];
                            }
                        }
                    }
                    [updatedUsers removeObjectsInArray:toRemove];
                    [DYYYUtils showToast:@"已从过滤列表中移除此用户"];
                } else {
                    // 添加用户
                    [updatedUsers addObject:currentUserFilter];
                    [DYYYUtils showToast:@"已添加此用户到过滤列表"];
                }
                // 保存更新后的列表
                NSString *updatedUserString = [updatedUsers componentsJoinedByString:@","];
                [DYYYPreferences setObject:updatedUserString forKey:@"DYYYFilterUsers"];
              }];
        };
        [viewModels addObject:filterKeywords];
    }

    // 过滤文案功能
    if (enableFilterKeyword) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 675;
        filterKeywords.duxIconName = @"ic_funnel_outlined_20";
        filterKeywords.describeString = @"过滤文案";
        filterKeywords.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          NSString *propName = nil;
          if (self.awemeModel.propGuideV2) {
              propName = self.awemeModel.propGuideV2.propName;
          }
          DYYYFilterSettingsView *filterView = [[DYYYFilterSettingsView alloc] initWithTitle:@"过滤关键词调整" text:descText propName:propName];
          filterView.onConfirm = ^(NSString *selectedText) {
            if (selectedText.length > 0) {
                NSString *currentKeywords = [DYYYPreferences objectForKey:@"DYYYFilterKeywords"] ?: @"";
                NSString *newKeywords;
                if (currentKeywords.length > 0) {
                    newKeywords = [NSString stringWithFormat:@"%@,%@", currentKeywords, selectedText];
                } else {
                    newKeywords = selectedText;
                }
                [DYYYPreferences setObject:newKeywords forKey:@"DYYYFilterKeywords"];
                [DYYYUtils showToast:[NSString stringWithFormat:@"已添加过滤词: %@", selectedText]];
            }
          };
          // 设置过滤关键词按钮回调
          filterView.onKeywordFilterTap = ^{
            // 获取保存的关键词
            NSString *savedKeywords = [DYYYPreferences objectForKey:@"DYYYFilterKeywords"] ?: @"";
            NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
            // 创建并显示关键词列表视图
            DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];
            // 设置确认回调
            keywordListView.onConfirm = ^(NSArray *keywords) {
              // 将关键词数组转换为逗号分隔的字符串
              NSString *keywordString = [keywords componentsJoinedByString:@","];
              // 保存到用户默认设置
              [DYYYPreferences setObject:keywordString forKey:@"DYYYFilterKeywords"];
              // 显示提示
              [DYYYUtils showToast:@"过滤关键词已更新"];
            };
            // 显示关键词列表视图
            [keywordListView show];
          };
          [filterView show];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:filterKeywords];
    }

    if (enableTimerClose) {
        AWELongPressPanelBaseViewModel *timerCloseViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        timerCloseViewModel.awemeModel = self.awemeModel;
        timerCloseViewModel.actionType = 676;
        timerCloseViewModel.duxIconName = @"ic_c_alarm_outlined";
        // 检查是否已有定时任务在运行
        NSNumber *shutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
        BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
        timerCloseViewModel.describeString = hasActiveTimer ? @"取消定时" : @"定时关闭";
        timerCloseViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          NSNumber *shutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
          BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
          if (hasActiveTimer) {
              [DYYYPreferences removeObjectForKey:@"DYYYTimerShutdownTime"];
              [DYYYUtils showToast:@"已取消定时关闭任务"];
              return;
          }
          // 读取上次设置的时间
          NSInteger defaultMinutes = [DYYYPreferences integerForKey:@"DYYYTimerCloseMinutes"];
          if (defaultMinutes <= 0) {
              defaultMinutes = 5;
          }
          NSString *defaultText = [NSString stringWithFormat:@"%ld", (long)defaultMinutes];
          DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"设置定时关闭时间" defaultText:defaultText placeholder:@"请输入关闭时间(单位:分钟)"];
          inputView.onConfirm = ^(NSString *inputText) {
            NSInteger minutes = [inputText integerValue];
            if (minutes <= 0) {
                minutes = 5;
            }
            // 保存用户设置的时间以供下次使用
            [DYYYPreferences setInteger:minutes forKey:@"DYYYTimerCloseMinutes"];
            NSInteger seconds = minutes * 60;
            NSTimeInterval shutdownTimeValue = [[NSDate date] timeIntervalSince1970] + seconds;
            [DYYYPreferences setObject:@(shutdownTimeValue) forKey:@"DYYYTimerShutdownTime"];
            [DYYYUtils showToast:[NSString stringWithFormat:@"抖音将在%ld分钟后关闭...", (long)minutes]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              NSNumber *currentShutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
              if (currentShutdownTime != nil && [currentShutdownTime doubleValue] <= [[NSDate date] timeIntervalSince1970]) {
                  [DYYYPreferences removeObjectForKey:@"DYYYTimerShutdownTime"];
                  // 显示确认关闭弹窗，而不是直接退出
                  DYYYConfirmCloseView *confirmView = [[DYYYConfirmCloseView alloc] initWithTitle:@"定时关闭" message:@"定时关闭时间已到，是否关闭抖音？"];
                  [confirmView show];
              }
            });
          };
          [inputView show];
        };
        [viewModels addObject:timerCloseViewModel];
    }

    // 画中画功能
    if (enablePip) {
        AWELongPressPanelBaseViewModel *pipViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        pipViewModel.awemeModel = self.awemeModel;
        pipViewModel.actionType = 690;
        pipViewModel.duxIconName = @"ic_rectangleonrectangleup_outlined_20";
        pipViewModel.describeString = @"画中画";
        pipViewModel.action = ^{
          [[DYYYPipManager sharedManager] createPipWithAwemeModel:self.awemeModel];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:pipViewModel];
    }

    // 获取作品数据功能（插入到原始面板"听抖音"所在组的后面）
    BOOL enableWorkData = DYYYGetBool(@"DYYYLongPressWorkData");
    if (enableWorkData) {
        AWELongPressPanelBaseViewModel *workDataViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        workDataViewModel.awemeModel = self.awemeModel;
        workDataViewModel.actionType = 691;
        workDataViewModel.duxIconName = @"ic_tag_outlined_20";
        workDataViewModel.describeString = @"获取作品数据";
        AWEAwemeModel *wdModel = self.awemeModel;
        workDataViewModel.action = ^{
            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:^{
                [DYYYWorkDataCardView showWithAwemeModel:wdModel];
            }];
        };
        // 遍历原始组，找到"听抖音"所在组，在该组末尾插入
        BOOL injected = NO;
        for (NSInteger gi = 0; gi < (NSInteger)originalArray.count && !injected; gi++) {
            AWELongPressPanelViewGroupModel *grp = originalArray[gi];
            if (![grp isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) continue;
            NSArray *arr = grp.groupArr;
            // 先检查是否已注入过（防止 dataArray 多次调用导致重复）
            BOOL alreadyExists = NO;
            for (id item in arr) {
                if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                    AWELongPressPanelBaseViewModel *vm = (AWELongPressPanelBaseViewModel *)item;
                    if ([vm.describeString containsString:@"获取作品数据"]) {
                        alreadyExists = YES;
                        break;
                    }
                }
            }
            if (alreadyExists) { injected = YES; break; }
            for (id item in arr) {
                if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                    AWELongPressPanelBaseViewModel *vm = (AWELongPressPanelBaseViewModel *)item;
                    if ([vm.describeString containsString:@"听抖音"] || [vm.describeString containsString:@"听音乐"]) {
                        NSMutableArray *mutArr = [arr mutableCopy];
                        [mutArr addObject:workDataViewModel];
                        grp.groupArr = [mutArr copy];
                        injected = YES;
                        break;
                    }
                }
            }
        }
        // 如果没找到听抖音组，插入到最后一个原始组
        if (!injected && originalArray.count > 0) {
            AWELongPressPanelViewGroupModel *lastGrp = originalArray.lastObject;
            if ([lastGrp isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                NSMutableArray *mutArr = [lastGrp.groupArr mutableCopy];
                [mutArr addObject:workDataViewModel];
                lastGrp.groupArr = [mutArr copy];
            }
        }
    }

    // 创建自定义组
    NSMutableArray *customGroups = [NSMutableArray array];
    NSInteger totalButtons = viewModels.count;

    // 根据按钮总数确定每行的按钮数
    NSInteger firstRowCount = 0;
    NSInteger secondRowCount = 0;

    // 确定分配方式与原代码相同
    if (totalButtons <= 2) {
        firstRowCount = totalButtons;
    } else if (totalButtons <= 4) {
        firstRowCount = totalButtons / 2;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 5) {
        firstRowCount = 3;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 6) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 8) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else {
        firstRowCount = 5;
        secondRowCount = totalButtons - firstRowCount;
    }

    // 创建第一行
    if (firstRowCount > 0) {
        NSArray<AWELongPressPanelBaseViewModel *> *firstRowButtons = [viewModels subarrayWithRange:NSMakeRange(0, firstRowCount)];
        AWELongPressPanelViewGroupModel *firstRowGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
        firstRowGroup.isDYYYCustomGroup = YES;
        firstRowGroup.groupType = (firstRowCount <= 3) ? 11 : 12;
        firstRowGroup.isModern = YES;
        firstRowGroup.groupArr = firstRowButtons;
        [customGroups addObject:firstRowGroup];
    }

    // 创建第二行
    if (secondRowCount > 0) {
        NSArray<AWELongPressPanelBaseViewModel *> *secondRowButtons = [viewModels subarrayWithRange:NSMakeRange(firstRowCount, secondRowCount)];
        AWELongPressPanelViewGroupModel *secondRowGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
        secondRowGroup.isDYYYCustomGroup = YES;
        secondRowGroup.groupType = (secondRowCount <= 3) ? 11 : 12;
        secondRowGroup.isModern = YES;
        secondRowGroup.groupArr = secondRowButtons;
        [customGroups addObject:secondRowGroup];
    }

    NSMutableArray *resultGroups = [NSMutableArray array];
    [resultGroups addObjectsFromArray:customGroups];
    [resultGroups addObjectsFromArray:originalArray];
    return [resultGroups copy];
}
%end

// 修复Modern风格长按面板水平设置单元格的大小计算
%hook AWEModernLongPressHorizontalSettingCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDYYYCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            CGFloat totalWidth = collectionView.bounds.size.width;
            NSInteger itemCount = self.dataArray.count;
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 修复Modern风格长按面板交互单元格的大小计算
%hook AWEModernLongPressInteractiveCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDYYYCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            NSInteger itemCount = self.dataArray.count;
            CGFloat totalWidth = collectionView.bounds.size.width - 12 * (itemCount - 1);
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 经典风格长按面板
%hook AWELongPressPanelTableViewController
- (NSArray *)dataArray {
    NSArray *originalArray = %orig;
    if (!originalArray) {
        originalArray = @[];
    }
    if (!self.awemeModel.author.nickname) {
        return originalArray;
    }

    // 检查是否开启精简模式
    BOOL simplifyPanel = DYYYGetBool(@"DYYYSimplifyLongPressPanel");

    // 如果开启精简模式，直接跳过原始面板处理，只返回自定义选项
    if (simplifyPanel) {
        originalArray = @[]; // 清空原始数组
    } else {
        // 获取需要隐藏的按钮设置（从文本输入框读取，逗号分隔）
        NSString *hidePanelItems = DYYYGetString(@"DYYYHidePanelItems");
        NSMutableSet<NSString *> *hideItemsLowerSet = [NSMutableSet set];

        if (hidePanelItems && hidePanelItems.length > 0) {
            // 支持中英文逗号分隔
            NSString *normalizedItems = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
            NSArray *items = [normalizedItems componentsSeparatedByString:@","];
            for (NSString *item in items) {
                NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedItem.length > 0) {
                    [hideItemsLowerSet addObject:[trimmedItem lowercaseString]];
                }
            }
        }

        // 如果有需要隐藏的项目，才进行过滤
        if (hideItemsLowerSet.count > 0) {
            NSMutableArray *modifiedOriginalGroups = [NSMutableArray array];

            for (id group in originalArray) {
                if ([group isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                    AWELongPressPanelViewGroupModel *groupModel = (AWELongPressPanelViewGroupModel *)group;
                    NSMutableArray *filteredGroupArr = [NSMutableArray array];

                    for (id item in groupModel.groupArr) {
                        if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                            AWELongPressPanelBaseViewModel *viewModel = (AWELongPressPanelBaseViewModel *)item;
                            NSString *descString = viewModel.describeString;

                            BOOL shouldHide = NO;
                            if (descString && descString.length > 0) {
                                NSString *descLower = [descString lowercaseString];

                                // 精确匹配
                                if ([hideItemsLowerSet containsObject:descLower]) {
                                    shouldHide = YES;
                                } else {
                                    // 部分匹配
                                    for (NSString *hideItemLower in hideItemsLowerSet) {
                                        if ([descLower containsString:hideItemLower] || [hideItemLower containsString:descLower]) {
                                            shouldHide = YES;
                                            break;
                                        }
                                    }
                                }
                            }

                            if (!shouldHide) {
                                [filteredGroupArr addObject:item];
                            }
                        } else {
                            [filteredGroupArr addObject:item];
                        }
                    }

                    if (filteredGroupArr.count > 0) {
                        AWELongPressPanelViewGroupModel *filteredGroup = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
                        filteredGroup.groupType = groupModel.groupType;
                        filteredGroup.groupArr = filteredGroupArr;
                        [modifiedOriginalGroups addObject:filteredGroup];
                    }
                } else {
                    [modifiedOriginalGroups addObject:group];
                }
            }
            originalArray = modifiedOriginalGroups;
        }
    }

    // 检查是否启用了任意长按功能
    BOOL hasAnyFeatureEnabled = NO;

    // 检查各个单独的功能开关
    BOOL enableSaveVideo = DYYYGetBool(@"DYYYLongPressSaveVideo");
    BOOL enableSaveCover = DYYYGetBool(@"DYYYLongPressSaveCover");
    BOOL enableSaveAudio = DYYYGetBool(@"DYYYLongPressSaveAudio");
    BOOL enableSaveCurrentImage = DYYYGetBool(@"DYYYLongPressSaveCurrentImage");
    BOOL enableSaveAllImages = DYYYGetBool(@"DYYYLongPressSaveAllImages");
    BOOL enableCopyText = DYYYGetBool(@"DYYYLongPressCopyText");
    BOOL enableCopyLink = DYYYGetBool(@"DYYYLongPressCopyLink");
    BOOL enableApiDownload = DYYYGetBool(@"DYYYLongPressApiDownload");
    BOOL enableFilterUser = DYYYGetBool(@"DYYYLongPressFilterUser");
    BOOL enableFilterKeyword = DYYYGetBool(@"DYYYLongPressFilterTitle");
    BOOL enableTimerClose = DYYYGetBool(@"DYYYLongPressTimerClose");
    BOOL enableCreateVideo = DYYYGetBool(@"DYYYLongPressCreateVideo");
    BOOL enablePip = DYYYGetBool(@"DYYYLongPressPip");
    BOOL enableWorkData = DYYYGetBool(@"DYYYLongPressWorkData");

    // 检查是否有任何功能启用
    hasAnyFeatureEnabled = enableSaveVideo || enableSaveCover || enableSaveAudio || enableSaveCurrentImage || enableSaveAllImages || enableCopyText || enableCopyLink || enableApiDownload ||
                           enableFilterUser || enableFilterKeyword || enableTimerClose || enableCreateVideo || enablePip || enableWorkData;

    if (!hasAnyFeatureEnabled) {
        return originalArray;
    }

    // 创建自定义功能组
    AWELongPressPanelViewGroupModel *newGroupModel = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
    newGroupModel.groupType = 0;
    NSMutableArray *viewModels = [NSMutableArray array];

    BOOL isNewLivePhoto = (self.awemeModel.video && self.awemeModel.animatedImageVideoInfo != nil);

    // 视频下载功能 (非实况照片才显示)
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && !isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        downloadViewModel.awemeModel = self.awemeModel;
        downloadViewModel.actionType = 666;
        downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        downloadViewModel.describeString = @"保存视频";
        downloadViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          AWEMusicModel *musicModel = awemeModel.music;
          NSURL *audioURL = nil;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              audioURL = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
          }

                  // 备用方法：直接使用h264URL
                  if (videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                      NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                      [DYYYManager downloadMedia:url
                                       mediaType:MediaTypeVideo
                                           audio:audioURL
                                      completion:^(BOOL success){
                                      }];
                  }
              
          
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:downloadViewModel];
    }

    //  新版实况照片保存
    if (enableSaveVideo && self.awemeModel.awemeType != 68 && isNewLivePhoto) {
        AWELongPressPanelBaseViewModel *livePhotoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        livePhotoViewModel.awemeModel = self.awemeModel;
        livePhotoViewModel.actionType = 679;
        livePhotoViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        livePhotoViewModel.describeString = @"保存实况";
        livePhotoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;

          // 使用封面URL作为图片URL
          NSURL *imageURL = nil;
          if (videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              imageURL = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
          }

          // 视频URL从视频模型获取
          NSURL *videoURL = nil;
          if (videoModel && videoModel.playURL && videoModel.playURL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.playURL.originURLList.firstObject];
          } else if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
              videoURL = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
          }

          // 下载实况照片
          if (imageURL && videoURL) {
              [DYYYManager downloadLivePhoto:imageURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:livePhotoViewModel];
    }

    // 当前图片/实况下载功能
    if (enableSaveCurrentImage && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
        AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        imageViewModel.awemeModel = self.awemeModel;
        imageViewModel.actionType = 669;
        imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";

        if (self.awemeModel.albumImages.count == 1) {
            imageViewModel.describeString = @"保存图片";
        } else {
            imageViewModel.describeString = @"保存当前图片";
        }

        AWEImageAlbumImageModel *currimge = self.awemeModel.albumImages[self.awemeModel.currentImageIndex - 1];
        if (currimge.clipVideo != nil || self.awemeModel.isLivePhoto) {
            if (self.awemeModel.albumImages.count == 1) {
                imageViewModel.describeString = @"保存实况";
            } else {
                imageViewModel.describeString = @"保存当前实况";
            }
        }

        imageViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEImageAlbumImageModel *currentImageModel = nil;
          if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
              currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
          } else {
              currentImageModel = awemeModel.albumImages.firstObject;
          }
          // 如果是实况的话
          // 查找非.image后缀的URL
          NSURL *downloadURL = nil;
          for (NSString *urlString in currentImageModel.urlList) {
              NSURL *url = [NSURL URLWithString:urlString];
              NSString *pathExtension = [url.path.lowercaseString pathExtension];
              if (![pathExtension isEqualToString:@"image"]) {
                  downloadURL = url;
                  break;
              }
          }

          if (currentImageModel.clipVideo != nil) {
              NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];
              [DYYYManager downloadLivePhoto:downloadURL
                                    videoURL:videoURL
                                  completion:^{
                                  }];
          } else if (currentImageModel && currentImageModel.urlList.count > 0) {
              if (downloadURL) {
                  [DYYYManager downloadMedia:downloadURL
                                   mediaType:MediaTypeImage
                                       audio:nil
                                  completion:^(BOOL success) {
                                    if (success) {
                                    } else {
                                        [DYYYUtils showToast:@"图片保存已取消"];
                                    }
                                  }];
              } else {
                  [DYYYUtils showToast:@"没有找到合适格式的图片"];
              }
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:imageViewModel];
    }

    // 保存所有图片/实况功能
    if (enableSaveAllImages && self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 1) {
        AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        allImagesViewModel.awemeModel = self.awemeModel;
        allImagesViewModel.actionType = 670;
        allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        allImagesViewModel.describeString = @"保存所有图片";
        // 检查是否有实况照片并更改按钮文字
        BOOL hasLivePhoto = NO;
        for (AWEImageAlbumImageModel *imageModel in self.awemeModel.albumImages) {
            if (imageModel.clipVideo != nil) {
                hasLivePhoto = YES;
                break;
            }
        }
        if (hasLivePhoto) {
            allImagesViewModel.describeString = @"保存所有实况";
        }
        allImagesViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          NSMutableArray *imageURLs = [NSMutableArray array];
          NSMutableArray *livePhotos = [NSMutableArray array];

          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSURL *downloadURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          downloadURL = url;
                          break;
                      }
                  }

                  if (!downloadURL && imageModel.urlList.count > 0) {
                      downloadURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                  }

                  // 检查是否是实况照片
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      [livePhotos addObject:@{@"imageURL" : downloadURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                  } else {
                      [imageURLs addObject:downloadURL.absoluteString];
                  }
              }
          }

          // 分别处理普通图片和实况照片
          if (livePhotos.count > 0) {
              [DYYYManager downloadAllLivePhotos:livePhotos];
          }

          if (imageURLs.count > 0) {
              [DYYYManager downloadAllImages:imageURLs];
          }

          if (livePhotos.count == 0 && imageURLs.count == 0) {
              [DYYYUtils showToast:@"没有找到合适格式的图片"];
          }

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:allImagesViewModel];
    }

    // 接口保存功能
    NSString *apiKey = [DYYYPreferences objectForKey:@"DYYYInterfaceDownload"];
    if (enableApiDownload && apiKey.length > 0) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存";
        apiDownload.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          if (shareLink.length == 0) {
              [DYYYUtils showToast:@"无法获取分享链接"];
              return;
          }
          // 使用封装的方法进行解析下载
          [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:apiDownload];
    }

    // 封面下载功能
    if (enableSaveCover && self.awemeModel.awemeType != 68) {
        AWELongPressPanelBaseViewModel *coverViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        coverViewModel.awemeModel = self.awemeModel;
        coverViewModel.actionType = 667;
        coverViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        coverViewModel.describeString = @"保存封面";
        coverViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEVideoModel *videoModel = awemeModel.video;
          if (videoModel && videoModel.coverURL && videoModel.coverURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url
                               mediaType:MediaTypeImage
                                   audio:nil
                              completion:^(BOOL success) {
                                if (success) {
                                } else {
                                    [DYYYUtils showToast:@"封面保存已取消"];
                                }
                              }];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:coverViewModel];
    }

    // 音频下载功能
    if (enableSaveAudio) {
        AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        audioViewModel.awemeModel = self.awemeModel;
        audioViewModel.actionType = 668;
        audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
        audioViewModel.describeString = @"保存音频";
        audioViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;
          AWEMusicModel *musicModel = awemeModel.music;
          if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
              NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
              [DYYYManager downloadMedia:url mediaType:MediaTypeAudio audio:nil completion:nil];
          }
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:audioViewModel];
    }

    // 创建视频功能
    if (enableCreateVideo && self.awemeModel.awemeType == 68) {
        AWELongPressPanelBaseViewModel *createVideoViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        createVideoViewModel.awemeModel = self.awemeModel;
        createVideoViewModel.actionType = 677;
        createVideoViewModel.duxIconName = @"ic_videosearch_outlined_20";
        createVideoViewModel.describeString = @"制作视频";
        createVideoViewModel.action = ^{
          AWEAwemeModel *awemeModel = self.awemeModel;

          // 收集普通图片URL
          NSMutableArray *imageURLs = [NSMutableArray array];
          // 收集实况照片信息（图片URL+视频URL）
          NSMutableArray *livePhotos = [NSMutableArray array];

          // 获取背景音乐URL
          NSString *bgmURL = nil;
          if (awemeModel.music && awemeModel.music.playURL && awemeModel.music.playURL.originURLList.count > 0) {
              bgmURL = awemeModel.music.playURL.originURLList.firstObject;
          }

          // 处理所有图片和实况
          for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
              if (imageModel.urlList.count > 0) {
                  // 查找非.image后缀的URL
                  NSString *bestURL = nil;
                  for (NSString *urlString in imageModel.urlList) {
                      NSURL *url = [NSURL URLWithString:urlString];
                      NSString *pathExtension = [url.path.lowercaseString pathExtension];
                      if (![pathExtension isEqualToString:@"image"]) {
                          bestURL = urlString;
                          break;
                      }
                  }

                  if (!bestURL && imageModel.urlList.count > 0) {
                      bestURL = imageModel.urlList.firstObject;
                  }

                  // 如果是实况照片，需要收集图片和视频URL
                  if (imageModel.clipVideo != nil) {
                      NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];
                      if (videoURL) {
                          [livePhotos addObject:@{@"imageURL" : bestURL, @"videoURL" : videoURL.absoluteString}];
                      }
                  } else {
                      // 普通图片
                      [imageURLs addObject:bestURL];
                  }
              }
          }

          // 调用视频创建API
          [DYYYManager createVideoFromMedia:imageURLs
              livePhotos:livePhotos
              bgmURL:bgmURL
              progress:^(NSInteger current, NSInteger total, NSString *status) {
              }
              completion:^(BOOL success, NSString *message) {
                if (success) {
                } else {
                    [DYYYUtils showToast:[NSString stringWithFormat:@"视频制作失败: %@", message]];
                }
              }];

          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:createVideoViewModel];
    }

    // 复制文案功能
    if (enableCopyText) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";
        copyText.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          [[UIPasteboard generalPasteboard] setString:descText];
          [DYYYToast showSuccessToastWithMessage:@"文案已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyText];
    }

    // 复制分享链接功能
    if (enableCopyLink) {
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制链接";
        copyShareLink.action = ^{
          NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
          NSString *cleanedURL = cleanShareURL(shareLink);
          [[UIPasteboard generalPasteboard] setString:cleanedURL];
          [DYYYToast showSuccessToastWithMessage:@"分享链接已复制"];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:copyShareLink];
    }

    // 过滤用户功能
    if (enableFilterUser) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 674;
        filterKeywords.duxIconName = @"ic_userban_outlined_20";
        filterKeywords.describeString = @"过滤用户";
        filterKeywords.action = ^{
          AWEUserModel *author = self.awemeModel.author;
          NSString *nickname = author.nickname ?: @"未知用户";
          NSString *shortId = author.shortID ?: @"";
          // 创建当前用户的过滤格式 "nickname-shortid"
          NSString *currentUserFilter = [NSString stringWithFormat:@"%@-%@", nickname, shortId];
          // 获取保存的过滤用户列表
          NSString *savedUsers = [DYYYPreferences objectForKey:@"DYYYFilterUsers"] ?: @"";
          NSArray *userArray = [savedUsers length] > 0 ? [savedUsers componentsSeparatedByString:@","] : @[];
          BOOL userExists = NO;
          for (NSString *userInfo in userArray) {
              NSArray *components = [userInfo componentsSeparatedByString:@"-"];
              if (components.count >= 2) {
                  NSString *userId = [components lastObject];
                  if ([userId isEqualToString:shortId] && shortId.length > 0) {
                      userExists = YES;
                      break;
                  }
              }
          }
          NSString *actionButtonText = userExists ? @"取消过滤" : @"添加过滤";
          [DYYYBottomAlertView showAlertWithTitle:@"过滤用户视频"
              message:[NSString stringWithFormat:@"用户: %@ (ID: %@)", nickname, shortId]
              avatarURL:nil
              cancelButtonText:@"管理过滤列表"
              confirmButtonText:actionButtonText
              cancelAction:^{
                DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:userArray];
                keywordListView.onConfirm = ^(NSArray *users) {
                  NSString *userString = [users componentsJoinedByString:@","];
                  [DYYYPreferences setObject:userString forKey:@"DYYYFilterUsers"];
                  [DYYYUtils showToast:@"过滤用户列表已更新"];
                };
                [keywordListView show];
              }
              closeAction:nil
              confirmAction:^{
                // 添加或移除用户过滤
                NSMutableArray *updatedUsers = [NSMutableArray arrayWithArray:userArray];
                if (userExists) {
                    // 移除用户
                    NSMutableArray *toRemove = [NSMutableArray array];
                    for (NSString *userInfo in updatedUsers) {
                        NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                        if (components.count >= 2) {
                            NSString *userId = [components lastObject];
                            if ([userId isEqualToString:shortId]) {
                                [toRemove addObject:userInfo];
                            }
                        }
                    }
                    [updatedUsers removeObjectsInArray:toRemove];
                    [DYYYUtils showToast:@"已从过滤列表中移除此用户"];
                } else {
                    // 添加用户
                    [updatedUsers addObject:currentUserFilter];
                    [DYYYUtils showToast:@"已添加此用户到过滤列表"];
                }
                // 保存更新后的列表
                NSString *updatedUserString = [updatedUsers componentsJoinedByString:@","];
                [DYYYPreferences setObject:updatedUserString forKey:@"DYYYFilterUsers"];
              }];
        };
        [viewModels addObject:filterKeywords];
    }

    // 过滤文案功能
    if (enableFilterKeyword) {
        AWELongPressPanelBaseViewModel *filterKeywords = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        filterKeywords.awemeModel = self.awemeModel;
        filterKeywords.actionType = 675;
        filterKeywords.duxIconName = @"ic_funnel_outlined_20";
        filterKeywords.describeString = @"过滤文案";
        filterKeywords.action = ^{
          NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
          NSString *propName = nil;
          if (self.awemeModel.propGuideV2) {
              propName = self.awemeModel.propGuideV2.propName;
          }
          DYYYFilterSettingsView *filterView = [[DYYYFilterSettingsView alloc] initWithTitle:@"过滤关键词调整" text:descText propName:propName];
          filterView.onConfirm = ^(NSString *selectedText) {
            if (selectedText.length > 0) {
                NSString *currentKeywords = [DYYYPreferences objectForKey:@"DYYYFilterKeywords"] ?: @"";
                NSString *newKeywords;
                if (currentKeywords.length > 0) {
                    newKeywords = [NSString stringWithFormat:@"%@,%@", currentKeywords, selectedText];
                } else {
                    newKeywords = selectedText;
                }
                [DYYYPreferences setObject:newKeywords forKey:@"DYYYFilterKeywords"];
                [DYYYUtils showToast:[NSString stringWithFormat:@"已添加过滤词: %@", selectedText]];
            }
          };
          // 设置过滤关键词按钮回调
          filterView.onKeywordFilterTap = ^{
            // 获取保存的关键词
            NSString *savedKeywords = [DYYYPreferences objectForKey:@"DYYYFilterKeywords"] ?: @"";
            NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];
            // 创建并显示关键词列表视图
            DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];
            // 设置确认回调
            keywordListView.onConfirm = ^(NSArray *keywords) {
              // 将关键词数组转换为逗号分隔的字符串
              NSString *keywordString = [keywords componentsJoinedByString:@","];
              // 保存到用户默认设置
              [DYYYPreferences setObject:keywordString forKey:@"DYYYFilterKeywords"];
              // 显示提示
              [DYYYUtils showToast:@"过滤关键词已更新"];
            };
            // 显示关键词列表视图
            [keywordListView show];
          };
          [filterView show];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:filterKeywords];
    }

    if (enableTimerClose) {
        AWELongPressPanelBaseViewModel *timerCloseViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        timerCloseViewModel.awemeModel = self.awemeModel;
        timerCloseViewModel.actionType = 676;
        timerCloseViewModel.duxIconName = @"ic_c_alarm_outlined";
        // 检查是否已有定时任务在运行
        NSNumber *shutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
        BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
        timerCloseViewModel.describeString = hasActiveTimer ? @"取消定时" : @"定时关闭";
        timerCloseViewModel.action = ^{
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
          NSNumber *shutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
          BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
          if (hasActiveTimer) {
              [DYYYPreferences removeObjectForKey:@"DYYYTimerShutdownTime"];
              [DYYYUtils showToast:@"已取消定时关闭任务"];
              return;
          }
          // 读取上次设置的时间
          NSInteger defaultMinutes = [DYYYPreferences integerForKey:@"DYYYTimerCloseMinutes"];
          if (defaultMinutes <= 0) {
              defaultMinutes = 5;
          }
          NSString *defaultText = [NSString stringWithFormat:@"%ld", (long)defaultMinutes];
          DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"设置定时关闭时间" defaultText:defaultText placeholder:@"请输入关闭时间(单位:分钟)"];
          inputView.onConfirm = ^(NSString *inputText) {
            NSInteger minutes = [inputText integerValue];
            if (minutes <= 0) {
                minutes = 5;
            }
            // 保存用户设置的时间以供下次使用
            [DYYYPreferences setInteger:minutes forKey:@"DYYYTimerCloseMinutes"];
            NSInteger seconds = minutes * 60;
            NSTimeInterval shutdownTimeValue = [[NSDate date] timeIntervalSince1970] + seconds;
            [DYYYPreferences setObject:@(shutdownTimeValue) forKey:@"DYYYTimerShutdownTime"];
            [DYYYUtils showToast:[NSString stringWithFormat:@"抖音将在%ld分钟后关闭...", (long)minutes]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              NSNumber *currentShutdownTime = [DYYYPreferences objectForKey:@"DYYYTimerShutdownTime"];
              if (currentShutdownTime != nil && [currentShutdownTime doubleValue] <= [[NSDate date] timeIntervalSince1970]) {
                  [DYYYPreferences removeObjectForKey:@"DYYYTimerShutdownTime"];
                  // 显示确认关闭弹窗，而不是直接退出
                  DYYYConfirmCloseView *confirmView = [[DYYYConfirmCloseView alloc] initWithTitle:@"定时关闭" message:@"定时关闭时间已到，是否关闭抖音？"];
                  [confirmView show];
              }
            });
          };
          [inputView show];
        };
        [viewModels addObject:timerCloseViewModel];
    }

    // 画中画功能
    if (enablePip) {
        AWELongPressPanelBaseViewModel *pipViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        pipViewModel.awemeModel = self.awemeModel;
        pipViewModel.actionType = 690;
        pipViewModel.duxIconName = @"ic_rectangleonrectangleup_outlined_20";
        pipViewModel.describeString = @"画中画";
        pipViewModel.action = ^{
          [[DYYYPipManager sharedManager] createPipWithAwemeModel:self.awemeModel];
          AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
          [panelManager dismissWithAnimation:YES completion:nil];
        };
        [viewModels addObject:pipViewModel];
    }

    // 获取作品数据功能（插入到原始面板"听抖音"所在组的后面）
    if (enableWorkData) {
        AWELongPressPanelBaseViewModel *workDataViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        workDataViewModel.awemeModel = self.awemeModel;
        workDataViewModel.actionType = 692;
        workDataViewModel.duxIconName = @"ic_tag_outlined_20";
        workDataViewModel.describeString = @"获取作品数据";
        AWEAwemeModel *wdModel = self.awemeModel;
        workDataViewModel.action = ^{
            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:^{
                [DYYYWorkDataCardView showWithAwemeModel:wdModel];
            }];
        };
        // 遍历原始组，找到"听抖音"所在组，在该组末尾插入
        BOOL injected = NO;
        for (NSInteger gi = 0; gi < (NSInteger)originalArray.count && !injected; gi++) {
            AWELongPressPanelViewGroupModel *grp = originalArray[gi];
            if (![grp isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) continue;
            NSArray *arr = grp.groupArr;
            // 先检查是否已注入过（防止 dataArray 多次调用导致重复）
            BOOL alreadyExists = NO;
            for (id item in arr) {
                if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                    AWELongPressPanelBaseViewModel *vm = (AWELongPressPanelBaseViewModel *)item;
                    if ([vm.describeString containsString:@"获取作品数据"]) {
                        alreadyExists = YES;
                        break;
                    }
                }
            }
            if (alreadyExists) { injected = YES; break; }
            for (id item in arr) {
                if ([item isKindOfClass:%c(AWELongPressPanelBaseViewModel)]) {
                    AWELongPressPanelBaseViewModel *vm = (AWELongPressPanelBaseViewModel *)item;
                    if ([vm.describeString containsString:@"听抖音"] || [vm.describeString containsString:@"听音乐"]) {
                        NSMutableArray *mutArr = [arr mutableCopy];
                        [mutArr addObject:workDataViewModel];
                        grp.groupArr = [mutArr copy];
                        injected = YES;
                        break;
                    }
                }
            }
        }
        // 如果没找到听抖音组，插入到最后一个原始组
        if (!injected && originalArray.count > 0) {
            AWELongPressPanelViewGroupModel *lastGrp = originalArray.lastObject;
            if ([lastGrp isKindOfClass:%c(AWELongPressPanelViewGroupModel)]) {
                NSMutableArray *mutArr = [lastGrp.groupArr mutableCopy];
                [mutArr addObject:workDataViewModel];
                lastGrp.groupArr = [mutArr copy];
            }
        }
    }

    newGroupModel.groupArr = viewModels;

    // 返回：原始组（含获取作品数据） + 自定义组（顶部）
    NSMutableArray *resultArray = [NSMutableArray array];
    [resultArray addObjectsFromArray:originalArray];
    if (viewModels.count > 0) {
        [resultArray addObject:newGroupModel];
    }
    return [resultArray copy];
}
%end

// 隐藏评论分享功能

%hook AWEIMCommentShareUserHorizontalCollectionViewCell

- (void)layoutSubviews {
    %orig;

    if ([DYYYPreferences boolForKey:@"DYYYHideCommentShareToFriends"]) {
        self.hidden = YES;
    } else {
        self.hidden = NO;
    }
}

%end

%hook AWEIMCommentShareUserHorizontalSectionController

- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size {
    if ([DYYYPreferences boolForKey:@"DYYYHideCommentShareToFriends"]) {
        return CGSizeZero;
    }
    return %orig;
}

- (void)configCell:(id)cell index:(NSInteger)index model:(id)model {
    if ([DYYYPreferences boolForKey:@"DYYYHideCommentShareToFriends"]) {
        return;
    }
    %orig;
}

%end

%ctor {
    if ([DYYYPreferences boolForKey:@"DYYYUserAgreementAccepted"]) {
        %init;
    }
}

%group DYYYFilterSetterGroup

%hook HOOK_TARGET_OWNER_CLASS

- (void)setModelsArray:(id)arg1 {
    if (![arg1 isKindOfClass:[NSArray class]]) {
        %orig(arg1);
        return;
    }

    NSArray *inputArray = (NSArray *)arg1;
    NSMutableArray *filteredArray = nil;

    for (id item in inputArray) {
        NSString *className = NSStringFromClass([item class]);

        BOOL shouldFilter = ([className isEqualToString:@"AWECommentIMSwiftImpl.CommentLongPressPanelForwardElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressDaily"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCopyElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressCopy"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSaveImageElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressSaveImage"]) ||

                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelReportElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressReport"]) ||

                            ([className isEqualToString:@"AWECommentStudioSwiftImpl.CommentLongPressPanelVideoReplyElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressVideoReply"]) ||

                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelPictureSearchElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressPictureSearch"]) ||

                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelSearchElement"] &&
                             [DYYYPreferences boolForKey:@"DYYYHideCommentLongPressSearch"]);

        if (shouldFilter) {
            if (!filteredArray) {
                filteredArray = [NSMutableArray arrayWithCapacity:inputArray.count];
                for (id keepItem in inputArray) {
                    if (keepItem == item)
                        break;
                    [filteredArray addObject:keepItem];
                }
            }
            continue;
        }

        if (filteredArray) {
            [filteredArray addObject:item];
        }
    }

    if (filteredArray) {
        %orig([filteredArray copy]);
    } else {
        %orig(arg1);
    }
}

%end
%end

%ctor {
    Class ownerClass = objc_getClass("AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionViewModel");
    if (ownerClass) {
        %init(DYYYFilterSetterGroup, HOOK_TARGET_OWNER_CLASS = ownerClass);
    }
}
