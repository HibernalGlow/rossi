import 'package:flutter/foundation.dart';

/// 发现页标签的封面数据描述。
@immutable
class DiscoverCoverData {
  const DiscoverCoverData({
    required this.url,
    this.path,
    this.from,
    this.cartoonId,
  });

  /// 封面图片的 URL 或远程地址。
  final String url;

  /// 本地已缓存路径（如果有）。
  final String? path;

  /// 插件来源 uuid（如果有）。
  final String? from;

  /// 漫画 ID（用于缓存键构建，如果有）。
  final String? cartoonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoverCoverData &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          path == other.path &&
          from == other.from &&
          cartoonId == other.cartoonId;

  @override
  int get hashCode => Object.hash(url, path, from, cartoonId);
}
