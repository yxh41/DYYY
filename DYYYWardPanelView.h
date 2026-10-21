#import <UIKit/UIKit.h>
#import "AwemeHeaders.h"

/// 视频插眼弹窗
@interface DYYYWardPanelView : UIView

- (instancetype)initWithAwemeModel:(AWEAwemeModel *)model;

/// 编辑已有插眼记录（历史记录无 model 时使用）
- (instancetype)initWithWard:(NSDictionary *)ward;

- (void)show;
- (void)dismiss;

@end
