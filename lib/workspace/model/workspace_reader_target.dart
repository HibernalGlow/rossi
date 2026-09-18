import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/type/enum.dart';

/// 工作区**阅读器泳道**当前打开的目标。
///
/// 这是「中央泳道放什么」的唯一答案：泳道只认这个值，不认任何导航栈。
/// 值是**不可变**的 —— 换一本漫画就是换一个值，阅读器的内部状态由
/// `identityKey` 决定的 widget key 重建。
@immutable
class WorkspaceReaderTarget {
  final String comicId;
  final String from;
  final int order;
  final int epsNumber;
  final String chapterId;
  final String requestId;
  final String storageChapterId;
  final String logicalKey;
  final ChapterExtern chapterExtern;
  final ComicEntryType type;
  final dynamic comicInfo;

  /// 上游页面推入 `ComicReadRoute` 时自带的选中态 Cubit。
  /// 由工作区持有（跟随目标一起被替换），不额外新建。
  final StringSelectCubit stringSelectCubit;

  const WorkspaceReaderTarget({
    required this.comicId,
    required this.from,
    this.order = 0,
    this.epsNumber = 1,
    this.chapterId = '',
    this.requestId = '',
    this.storageChapterId = '',
    this.logicalKey = '',
    this.chapterExtern = const <String, dynamic>{},
    this.type = ComicEntryType.normal,
    this.comicInfo,
    required this.stringSelectCubit,
  });

  /// 从被拦截的 `ComicReadRoute` 还原目标 —— 上游页面推什么，泳道就开什么。
  factory WorkspaceReaderTarget.fromRouteArgs(ComicReadRouteArgs args) {
    return WorkspaceReaderTarget(
      comicId: args.comicId,
      from: args.from,
      order: args.order,
      epsNumber: args.epsNumber,
      chapterId: args.chapterId,
      requestId: args.requestId,
      storageChapterId: args.storageChapterId,
      logicalKey: args.logicalKey,
      chapterExtern: args.chapterExtern,
      type: args.type,
      comicInfo: args.comicInfo,
      stringSelectCubit: args.stringSelectCubit,
    );
  }

  /// 阅读器页面实例的身份。同一本书同一章 → 同一个 key（不重建）；
  /// 换书 / 换章 / 换跳转来源 → 换 key（阅读器状态整体重建）。
  String get identityKey =>
      '$from\u0001$comicId\u0001$order\u0001$chapterId\u0001$requestId\u0001$logicalKey';

  /// 泳道标题栏显示的书名。真实书名由阅读器自己的 breadcrumb 负责，
  /// 这里只求「一眼能认出是哪一本」。
  String get displayTitle {
    final info = comicInfo;
    if (info is Map) {
      for (final key in const ['title', 'name', 'comicName']) {
        final value = info[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    if (comicId.isEmpty) return '未命名';
    return p.basename(comicId);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceReaderTarget &&
          runtimeType == other.runtimeType &&
          identityKey == other.identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}
