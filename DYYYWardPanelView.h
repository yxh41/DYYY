#import <UIKit/UIKit.h>
#import "AwemeHeaders.h"

/// 视频插眼弹窗
@interface DYYYWardPanelView : UIView

- (instancetype)initWithAwemeModel:(AWEAwemeModel *)model;

/// 通用插眼（主页/评论等无 awemeModel 场景）
/// data 支持字段：type(主页/评论/视频)、nickname、uid、secUid、avatarURL、awemeID、commentID、desc、createTime、shareURL
- (instancetype)initWithWardData:(NSDictionary *)data;

/// 编辑已有插眼记录（历史记录无 model 时使用）
- (instancetype)initWithWard:(NSDictionary *)ward;

- (void)show;
- (void)dismiss;

@end
