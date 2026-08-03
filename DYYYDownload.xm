//
//  DYYY - 自动拆分片段（由 DYYY.xm 通过 #include 引入，勿单独编译）
//  分类: DYYYDownload
//

%hook AWECommentMediaDownloadConfigLivePhoto

BOOL commentLivePhotoNotWaterMark = DYYYGetBool(@"DYYYCommentLivePhotoNotWaterMark");

- (BOOL)needClientWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (BOOL)needClientEndWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (id)watermarkConfig {
    return commentLivePhotoNotWaterMark ? nil : %orig;
}

%end
