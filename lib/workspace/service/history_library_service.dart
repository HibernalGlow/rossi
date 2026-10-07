import 'dart:io';

import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/workspace/model/history_library_portable.dart';

/// 阅读历史库的落盘与合并。
///
/// 编解码与合并决策都在 [history_library_portable] 里（纯 Dart，可 `dart run`
/// 断言），这一层只负责把它翻译成 ObjectBox 的读写。
///
/// 与 [BookmarkLibraryService] 同一套 API 形状（`collect` / `localStateOf` /
/// `planFromFile` / `applyPlan`），书架两个面板的接线方式因此对称；差别只在
/// 合并语义 —— 历史按 `lastReadAt` 裁决，见 `planHistoryImport`。
class HistoryLibraryService {
  /// 导出用的当前历史库。软删掉的不导出 —— 那是「已经从历史上移除」，
  /// 不是「暂时藏起来」。
  ///
  /// 排序照抄 `history_shelf_card.dart:130-132`：`lastReadAt` 倒序，
  /// 导出文件翻开就是「最近在读的在最前面」。
  static List<HistoryLibraryItem> collect() {
    final query = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending)
        .build();
    try {
      return [for (final history in query.find()) _itemOf(history)];
    } finally {
      query.close();
    }
  }

  static HistoryLibraryItem _itemOf(UnifiedComicHistory history) {
    return HistoryLibraryItem(
      uniqueKey: history.uniqueKey,
      source: history.source,
      comicId: history.comicId,
      title: history.title,
      description: history.description,
      cover: history.cover,
      creator: history.creator,
      titleMeta: history.titleMeta,
      metadata: history.metadata,
      chapterId: history.chapterId,
      chapterTitle: history.chapterTitle,
      chapterOrder: history.chapterOrder,
      pageIndex: history.pageIndex,
      createdAt: history.createdAt,
      lastReadAt: history.lastReadAt,
      updatedAt: history.updatedAt,
    );
  }

  /// 本地库里这些键的现状。不在字典里 = 本地根本没有。
  ///
  /// 与书签的 `Map<String, bool>` 多带一个 `lastReadAt`：历史要比时间，
  /// 光知道「有没有」不够。软删的记录也算「有」—— 复活时得复用它的行。
  static Map<String, HistoryLocalState?> localStateOf(Iterable<String> keys) {
    final result = <String, HistoryLocalState?>{};
    for (final key in keys.toSet()) {
      final query = objectbox.unifiedHistoryBox
          .query(UnifiedComicHistory_.uniqueKey.equals(key))
          .build();
      try {
        final found = query.findFirst();
        if (found != null) {
          result[key] = HistoryLocalState(
            deleted: found.deleted,
            lastReadAt: found.lastReadAt,
          );
        }
      } finally {
        query.close();
      }
    }
    return result;
  }

  /// 读文件并定出合并计划，**不写库**。
  ///
  /// 分成两步是为了先给用户看一眼结论（新增几条、进度刷新几条、为什么保留
  /// 本地），而不是点一下文件对话框就闷头改库。
  static Future<HistoryMergePlan> planFromFile(String path) async {
    final raw = await File(path).readAsString();
    final parsed = parseHistoryLibrary(raw);
    return planHistoryImport(
      items: parsed.items,
      localState: localStateOf(parsed.items.map((item) => item.uniqueKey)),
      rejected: parsed.rejected,
    );
  }

  /// 落库。**只写该写的，一条也不删** —— 被判定 `stale`/`duplicate` 的条目
  /// 就地丢弃，本地那条原样留着。
  static void applyPlan(HistoryMergePlan plan) {
    for (final decision in plan.decisions) {
      switch (decision.action) {
        case HistoryMergeAction.add:
        case HistoryMergeAction.revive:
        case HistoryMergeAction.overwrite:
          _write(decision.item);
        case HistoryMergeAction.stale:
        case HistoryMergeAction.duplicate:
          break;
      }
    }
  }

  static Future<HistoryMergePlan> importFrom(String path) async {
    final plan = await planFromFile(path);
    applyPlan(plan);
    return plan;
  }

  /// 写一条历史。字段口径照抄 `reader_history_service.dart:301` 那条既有写入
  /// 路径：键是 `source:comicId`、`schemaVersion` 是 2、软删的旧记录要**复活**
  /// （`uniqueKey` 上有 `@Unique()`，另起一条会抛）。
  static void _write(HistoryLibraryItem item) {
    final now = DateTime.now().toUtc();
    final query = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(item.uniqueKey))
        .build();
    final UnifiedComicHistory? existing;
    try {
      existing = query.findFirst();
    } finally {
      query.close();
    }

    // 复活而不是新起一条：复用 existing 的 id 让 ObjectBox 覆盖同一行，
    // 顺带保住它的 createdAt（第一次读到的时间比导入时间更有解释力）。
    final entity =
        existing ??
        UnifiedComicHistory(
          uniqueKey: item.uniqueKey,
          source: item.source,
          comicId: item.comicId,
          title: item.title,
          description: item.description,
          cover: item.cover,
          creator: item.creator,
          titleMeta: item.titleMeta,
          metadata: item.metadata,
          chapterId: item.chapterId,
          chapterTitle: item.chapterTitle,
          chapterOrder: item.chapterOrder,
          pageIndex: item.pageIndex,
          // 新建才用 createdAt：已存在的那条走下面的 cascade，不碰它。
          createdAt: item.createdAt ?? now,
          lastReadAt: item.lastReadAt ?? now,
          updatedAt: now,
          deleted: false,
          schemaVersion: 2,
        );

    entity
      ..source = item.source
      ..comicId = item.comicId
      ..title = item.title
      ..description = item.description
      ..cover = item.cover
      ..creator = item.creator
      ..titleMeta = item.titleMeta
      ..metadata = item.metadata
      ..chapterId = item.chapterId
      ..chapterTitle = item.chapterTitle
      ..chapterOrder = item.chapterOrder
      ..pageIndex = item.pageIndex
      ..lastReadAt = item.lastReadAt ?? now
      ..updatedAt = now
      ..deleted = false;

    objectbox.unifiedHistoryBox.put(entity);
  }
}
