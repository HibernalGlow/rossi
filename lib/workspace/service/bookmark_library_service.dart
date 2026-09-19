import 'dart:io';

import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/workspace/model/bookmark_library_portable.dart';

/// 书签库的落盘与合并。
///
/// 编解码与合并决策都在 [bookmark_library_portable] 里（纯 Dart，可 `dart run`
/// 断言），这一层只负责把它翻译成 ObjectBox 的读写。
class BookmarkLibraryService {
  /// 导出用的当前书签库。软删掉的不导出 —— 那是「已经取消收藏」，
  /// 不是「暂时藏起来」。
  static List<BookmarkLibraryItem> collect() {
    final query = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.deleted.equals(false))
        .order(UnifiedComicFavorite_.updatedAt, flags: Order.descending)
        .build();
    final folders = <String, ComicFolder>{
      for (final folder in ComicFolderService.listAllFolders(
        ComicFolderType.favorite,
      ))
        folder.syncId: folder,
    };
    try {
      return [
        for (final favorite in query.find())
          _itemOf(favorite, folders: folders),
      ];
    } finally {
      query.close();
    }
  }

  static BookmarkLibraryItem _itemOf(
    UnifiedComicFavorite favorite, {
    required Map<String, ComicFolder> folders,
  }) {
    return BookmarkLibraryItem(
      uniqueKey: favorite.uniqueKey,
      source: favorite.source,
      comicId: favorite.comicId,
      title: favorite.title,
      description: favorite.description,
      cover: favorite.cover,
      creator: favorite.creator,
      titleMeta: favorite.titleMeta,
      metadata: favorite.metadata,
      createdAt: favorite.createdAt,
      updatedAt: favorite.updatedAt,
      lists: [
        for (final link in ComicLinkService.linksOfComic(
          favorite.uniqueKey,
          ComicFolderType.favorite,
        ))
          if (link.folderSyncId != null)
            _pathOf(link.folderSyncId!, folders),
      ],
    );
  }

  static String _pathOf(String syncId, Map<String, ComicFolder> folders) {
    final folder = folders[syncId];
    if (folder == null) return '';
    return ComicFolderService.folderPath(folder, syncIdMap: folders);
  }

  /// 本地库里这些键的状态：值 = 是否已被软删。不在字典里 = 没有这条。
  static Map<String, bool> localStateOf(Iterable<String> keys) {
    final result = <String, bool>{};
    for (final key in keys.toSet()) {
      final found = objectbox.unifiedFavoriteBox
          .query(UnifiedComicFavorite_.uniqueKey.equals(key))
          .build()
          .findFirst();
      if (found != null) result[key] = found.deleted;
    }
    return result;
  }

  /// 读文件并定出合并计划，**不写库**。
  ///
  /// 分成两步是为了先给用户看一眼结论（新增几条、复活几条、跳过几条为什么），
  /// 而不是点一下文件对话框就闷头改库。
  static Future<BookmarkMergePlan> planFromFile(String path) async {
    final raw = await File(path).readAsString();
    final parsed = parseBookmarkLibrary(raw);
    return planBookmarkImport(
      items: parsed.items,
      localState: localStateOf(parsed.items.map((item) => item.uniqueKey)),
      rejected: parsed.rejected,
    );
  }

  static void applyPlan(BookmarkMergePlan plan) {
    for (final decision in plan.decisions) {
      if (decision.action == BookmarkMergeAction.duplicate) continue;
      _write(decision.item);
    }
  }

  static Future<BookmarkMergePlan> importFrom(String path) async {
    final plan = await planFromFile(path);
    applyPlan(plan);
    return plan;
  }

  /// 写一条书签。字段口径照抄 `collect_comic.dart` 与
  /// `shelf_entry_actions.dart` 的两条既有路径：软删过的旧记录要**复活**
  /// （`uniqueKey` 上有 Unique 约束，另起一条会抛），并且补一条根目录链接。
  static void _write(BookmarkLibraryItem item) {
    final now = DateTime.now().toUtc();
    final existing = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(item.uniqueKey))
        .build()
        .findFirst();

    objectbox.unifiedFavoriteBox.put(
      UnifiedComicFavorite(
        id: existing?.id ?? 0,
        uniqueKey: item.uniqueKey,
        source: item.source,
        comicId: item.comicId,
        title: item.title,
        description: item.description,
        cover: item.cover,
        creator: item.creator,
        titleMeta: item.titleMeta,
        metadata: item.metadata,
        createdAt: existing?.createdAt ?? item.createdAt ?? now,
        updatedAt: now,
        deleted: false,
        schemaVersion: 2,
      ),
    );

    // 新收藏至少要有一条根目录链接，否则它出现在「全部」里却不在任何列表，
    // 面板的列表轨会把它整个跳过。
    ComicLinkService.addComic(item.uniqueKey, null, ComicFolderType.favorite);
    for (final listPath in item.lists) {
      final resolved = _ensureFolderPath(listPath);
      if (resolved != null) {
        ComicLinkService.addComic(item.uniqueKey, resolved, ComicFolderType.favorite);
      }
    }
  }

  /// 按路径把缺失的书签列表建出来（逐级）。返回最终可用的路径，
  /// 名称非法建不出来时退回上一级而不是丢掉整条归属。
  static String? _ensureFolderPath(String path) {
    final segments = path
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;

    var current = kComicFolderRootPath;
    for (final name in segments) {
      final target = current == kComicFolderRootPath ? '/$name' : '$current/$name';
      if (ComicFolderService.folderName(target, ComicFolderType.favorite) ==
          null) {
        try {
          ComicFolderService.createFolder(current, name, ComicFolderType.favorite);
        } on StateError {
          // 同名已存在（并发导入或墓碑复活），继续往下走。
        } catch (e) {
          logger.w('书签列表建不出来，挂在上一级: $target — $e');
          return current;
        }
      }
      current = target;
    }
    return current;
  }

  // ── 书签列表（ComicFolder / ComicLink） ───────────────────────────────────

  static List<ComicFolder> lists() =>
      ComicFolderService.listChildFolders(
        kComicFolderRootPath,
        ComicFolderType.favorite,
      );

  static void createList(String name) =>
      ComicFolderService.createFolder(kComicFolderRootPath, name, ComicFolderType.favorite);

  static void renameList(String path, String name) =>
      ComicFolderService.renameFolder(path, name, ComicFolderType.favorite);

  /// 删除列表本身，列表里的书签**不跟着取消收藏** —— 它们回到未分类。
  static void deleteList(String path) {
    final members = ComicLinkService.listLinks(
      path,
      ComicFolderType.favorite,
    );
    for (final member in members) {
      ComicLinkService.addComic(
        member.comicUniqueKey,
        kComicFolderRootPath,
        ComicFolderType.favorite,
      );
    }
    ComicFolderService.deleteFolder(path, ComicFolderType.favorite);
  }

  /// 某个列表的成员键。传 [kComicFolderRootPath] 即「未分类」。
  ///
  /// 「全部」不走这里：那是直接查书签表，调用方自己传 `null` 表示不过滤。
  static Set<String> membersOf(String path) {
    return {
      for (final link in ComicLinkService.listLinks(
        path,
        ComicFolderType.favorite,
      ))
        link.comicUniqueKey,
    };
  }
}
