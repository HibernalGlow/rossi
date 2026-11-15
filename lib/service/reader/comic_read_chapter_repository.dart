import 'dart:async';

import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';

/// 已读章节仓库。
///
/// 详情页按 `source + comicId` 批量查询已读章节 id；阅读器打开章节时写入。
/// 写入后通过 [changes] 通知当前漫画的详情页刷新置灰状态。
class ComicReadChapterRepository {
  ComicReadChapterRepository._();

  static final ComicReadChapterRepository instance =
      ComicReadChapterRepository._();

  final _changes = StreamController<String>.broadcast();

  /// 变更流：事件为 `$source:$comicId`，订阅方自行过滤当前漫画。
  Stream<String> get changes => _changes.stream;

  /// 查询某本漫画已读章节 id 集合。
  Set<String> readChapterIds({
    required String source,
    required String comicId,
  }) {
    final resolvedSource = source.trim();
    final resolvedComicId = comicId.trim();
    if (resolvedSource.isEmpty || resolvedComicId.isEmpty) {
      return const <String>{};
    }

    final query = objectbox.comicReadChapterBox
        .query(
          ComicReadChapter_.source.equals(resolvedSource) &
              ComicReadChapter_.comicId.equals(resolvedComicId),
        )
        .build();
    try {
      return query
          .find()
          .map((item) => item.chapterId)
          .where((id) => id.isNotEmpty)
          .toSet();
    } finally {
      query.close();
    }
  }

  /// 标记章节已读；同一章重复调用只刷新阅读时间。
  void markRead({
    required String source,
    required String comicId,
    required String chapterId,
    required String chapterTitle,
    required int chapterOrder,
  }) {
    final resolvedSource = source.trim();
    final resolvedComicId = comicId.trim();
    final resolvedChapterId = chapterId.trim();
    if (resolvedSource.isEmpty ||
        resolvedComicId.isEmpty ||
        resolvedChapterId.isEmpty) {
      return;
    }

    final key = comicReadChapterUniqueKey(
      resolvedSource,
      resolvedComicId,
      resolvedChapterId,
    );
    final box = objectbox.comicReadChapterBox;
    final query = box.query(ComicReadChapter_.uniqueKey.equals(key)).build();
    try {
      final now = DateTime.now().toUtc();
      final entity =
          query.findFirst() ??
          ComicReadChapter(
            uniqueKey: key,
            source: resolvedSource,
            comicId: resolvedComicId,
            chapterId: resolvedChapterId,
            chapterTitle: chapterTitle.trim(),
            chapterOrder: chapterOrder,
            readAt: now,
            updatedAt: now,
          );
      entity
        ..chapterTitle = chapterTitle.trim()
        ..chapterOrder = chapterOrder
        ..readAt = now
        ..updatedAt = now;
      box.put(entity);
    } finally {
      query.close();
    }

    _changes.add('$resolvedSource:$resolvedComicId');
  }
}
