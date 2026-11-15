import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_document.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart'
    show detectImageExtension;
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/type/enum.dart';

/// 该漫画还有未完成的下载任务，按当前策略禁止编辑。
class ComicEditLockedException implements Exception {
  const ComicEditLockedException();

  @override
  String toString() => 'comic has incomplete download tasks';
}

/// 已下载漫画的编辑入口。
///
/// 只改元数据与文件位置，不做任何图片重编码。所有写操作都先检查
/// “该漫画没有未完成下载任务”，避免和下载保存互相覆盖。
class ComicEditService {
  const ComicEditService();

  UnifiedComicDownload? findRecord(String from, String comicId) {
    return const DownloadTaskRepository().findDownloadRecord(from, comicId);
  }

  bool hasIncompleteDownload(String from, String comicId) {
    return const DownloadTaskRepository()
        .findIncompleteByComic(from: from, comicId: comicId)
        .isNotEmpty;
  }

  ComicEditDocument loadDocument(UnifiedComicDownload record) {
    return ComicEditDocument.fromJson(
      chaptersJson: record.chapters,
      detailJson: record.detailJson,
    );
  }

  Future<ComicEditDocument> updateTitle({
    required String from,
    required String comicId,
    required String title,
  }) async {
    final record = _requireEditable(from, comicId);
    final value = title.trim();
    if (value.isEmpty) {
      throw ArgumentError('title is empty');
    }
    final doc = loadDocument(record).setTitle(value);
    _persist(record, doc, titleOverride: value);
    return doc;
  }

  Future<ComicEditDocument> updateCover({
    required String from,
    required String comicId,
    required File source,
  }) async {
    final record = _requireEditable(from, comicId);
    if (!await source.exists()) {
      throw StateError('cover source not found: ${source.path}');
    }
    return _saveCoverFromFile(
      record: record,
      doc: loadDocument(record),
      source: source,
    );
  }

  /// 把某一章里的任意一张图片复制为封面。
  Future<ComicEditDocument> updateCoverFromImage({
    required String from,
    required String comicId,
    required String chapterId,
    required String imagePath,
  }) async {
    final record = _requireEditable(from, comicId);
    final doc = loadDocument(record);
    final chapter = _findChapter(doc.chapterMaps, chapterId);
    if (chapter == null) {
      throw StateError('chapter not found: $chapterId');
    }
    final store = DownloadAssetStore(
      from: from,
      path: imagePath,
      cartoonId: comicId,
      chapterId: '',
      storageChapterId: comicEditChapterStorageId(chapter),
      pictureType: PictureType.page,
    );
    final existing = await store.findExistingDownload();
    if (existing == null) {
      throw StateError('image not found: $imagePath');
    }
    return _saveCoverFromFile(
      record: record,
      doc: doc,
      source: File(existing.path),
    );
  }

  Future<ComicEditDocument> _saveCoverFromFile({
    required UnifiedComicDownload record,
    required ComicEditDocument doc,
    required File source,
  }) async {
    final from = record.source;
    final comicId = record.comicId;
    final oldCover = doc.cover;
    final extension = await detectImageExtension(source);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final fileName = 'cover_$timestamp$extension';
    final store = DownloadAssetStore(
      from: from,
      path: fileName,
      cartoonId: comicId,
      chapterId: '',
      storageChapterId: '',
      pictureType: PictureType.cover,
    );
    final targetPath = await store.canonicalDownloadPath();
    await store.copyFileAtomically(
      sourcePath: source.path,
      finalPath: targetPath,
    );

    final oldExtern = Map<String, dynamic>.from(
      oldCover['extern'] as Map? ?? const <String, dynamic>{},
    );
    final cover = <String, dynamic>{
      'id': 'local_cover_$timestamp',
      'url': '',
      'name': fileName,
      'path': fileName,
      'extern': <String, dynamic>{
        ...oldExtern,
        'path': fileName,
        'local': true,
      },
    };

    final next = doc.setCover(cover);
    try {
      _persist(record, next, coverOverride: jsonEncode(cover));
    } catch (_) {
      await _deleteIfExists(File(targetPath));
      rethrow;
    }

    await _deleteOldCover(
      from: from,
      comicId: comicId,
      oldCover: oldCover,
      keepPath: targetPath,
    );
    return next;
  }

  Future<ComicEditDocument> renameChapter({
    required String from,
    required String comicId,
    required String chapterId,
    required String name,
  }) async {
    final record = _requireEditable(from, comicId);
    final value = name.trim();
    if (value.isEmpty) {
      throw ArgumentError('chapter name is empty');
    }
    final doc = loadDocument(record).renameChapter(chapterId, value);
    _persist(record, doc);
    return doc;
  }

  Future<ComicEditDocument> addChapter({
    required String from,
    required String comicId,
    required String name,
  }) async {
    final record = _requireEditable(from, comicId);
    final value = name.trim();
    if (value.isEmpty) {
      throw ArgumentError('chapter name is empty');
    }
    final id = 'local:${const Uuid().v4()}';
    final doc = loadDocument(record).addChapter(id: id, name: value);
    _persist(record, doc);
    return doc;
  }

  Future<ComicEditDocument> reorderChapters({
    required String from,
    required String comicId,
    required List<String> orderedChapterIds,
  }) async {
    final record = _requireEditable(from, comicId);
    final doc = loadDocument(record).reorderChapters(orderedChapterIds);
    _persist(record, doc);
    return doc;
  }

  Future<ComicEditDocument> deleteImages({
    required String from,
    required String comicId,
    required String chapterId,
    required List<String> imagePaths,
  }) async {
    final record = _requireEditable(from, comicId);
    final doc = loadDocument(record);
    final chapter = _findChapter(doc.chapterMaps, chapterId);
    if (chapter == null) {
      throw StateError('chapter not found: $chapterId');
    }
    final storageId = comicEditChapterStorageId(chapter);
    final existingPaths = ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => image['path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
    final removed = imagePaths.where(existingPaths.contains).toList();
    if (removed.isEmpty) return doc;

    final next = doc.removeImages(chapterId, removed);
    _persist(record, next);

    for (final path in removed) {
      final store = DownloadAssetStore(
        from: from,
        path: path,
        cartoonId: comicId,
        chapterId: '',
        storageChapterId: storageId,
        pictureType: PictureType.page,
      );
      final existing = await store.findExistingDownload();
      if (existing != null) {
        await _deleteIfExists(File(existing.path));
      }
    }
    return next;
  }

  Future<ComicEditDocument> reorderImages({
    required String from,
    required String comicId,
    required String chapterId,
    required List<String> orderedPaths,
  }) async {
    final record = _requireEditable(from, comicId);
    final doc = loadDocument(record).reorderImages(chapterId, orderedPaths);
    _persist(record, doc);
    return doc;
  }

  Future<ComicEditDocument> moveImages({
    required String from,
    required String comicId,
    required String sourceChapterId,
    required String targetChapterId,
    required List<String> imagePaths,
    int? targetIndex,
  }) async {
    final record = _requireEditable(from, comicId);
    var doc = loadDocument(record);
    final chapters = doc.chapterMaps;
    final source = _findChapter(chapters, sourceChapterId);
    final target = _findChapter(chapters, targetChapterId);
    if (source == null) {
      throw StateError('source chapter not found: $sourceChapterId');
    }
    if (target == null) {
      throw StateError('target chapter not found: $targetChapterId');
    }

    final sourceStorageId = comicEditChapterStorageId(source);
    final targetStorageId = comicEditChapterStorageId(target);
    final sameChapter = sourceStorageId == targetStorageId;
    final createdTargets = <String>[];
    final sourceFiles = <String>[];
    final pathOverrides = <String, String>{};
    final usedTargetPaths = <String>{
      ...((target['images'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((image) => image['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty),
    };

    try {
      if (!sameChapter) {
        for (final path in imagePaths) {
          if (_findImage(source, path) == null) continue;
          final sourceStore = DownloadAssetStore(
            from: from,
            path: path,
            cartoonId: comicId,
            chapterId: '',
            storageChapterId: sourceStorageId,
            pictureType: PictureType.page,
          );
          final sourceCandidate = await sourceStore.findExistingDownload();
          if (sourceCandidate == null) continue;
          final canonicalSource = await sourceStore.migrateDownload(
            sourceCandidate,
          );

          var targetPathName = path;
          if (usedTargetPaths.contains(targetPathName)) {
            targetPathName = _uniquePath(path, usedTargetPaths);
            pathOverrides[path] = targetPathName;
          }
          usedTargetPaths.add(targetPathName);

          var targetStore = DownloadAssetStore(
            from: from,
            path: targetPathName,
            cartoonId: comicId,
            chapterId: '',
            storageChapterId: targetStorageId,
            pictureType: PictureType.page,
          );
          var targetPath = await targetStore.canonicalDownloadPath();
          while (await File(targetPath).exists()) {
            targetPathName = _uniquePath(targetPathName, usedTargetPaths);
            pathOverrides[path] = targetPathName;
            usedTargetPaths.add(targetPathName);
            targetStore = DownloadAssetStore(
              from: from,
              path: targetPathName,
              cartoonId: comicId,
              chapterId: '',
              storageChapterId: targetStorageId,
              pictureType: PictureType.page,
            );
            targetPath = await targetStore.canonicalDownloadPath();
          }

          await targetStore.copyFileAtomically(
            sourcePath: canonicalSource,
            finalPath: targetPath,
          );
          createdTargets.add(targetPath);
          sourceFiles.add(canonicalSource);
        }
      }

      for (final entry in pathOverrides.entries) {
        doc = doc.replaceImagePath(sourceChapterId, entry.key, entry.value);
      }
      final finalPaths = imagePaths
          .map((path) => pathOverrides[path] ?? path)
          .toList();
      doc = doc.moveImages(
        sourceChapterId: sourceChapterId,
        targetChapterId: targetChapterId,
        imagePaths: finalPaths,
        targetIndex: targetIndex,
      );
      _persist(record, doc);
    } catch (_) {
      for (final path in createdTargets) {
        await _deleteIfExists(File(path));
      }
      rethrow;
    }

    for (final path in sourceFiles) {
      await _deleteIfExists(File(path));
    }
    return doc;
  }

  UnifiedComicDownload _requireEditable(String from, String comicId) {
    final record = findRecord(from, comicId);
    if (record == null) {
      throw StateError('download record not found: $from:$comicId');
    }
    if (hasIncompleteDownload(from, comicId)) {
      throw const ComicEditLockedException();
    }
    return record;
  }

  void _persist(
    UnifiedComicDownload record,
    ComicEditDocument doc, {
    String? titleOverride,
    String? coverOverride,
  }) {
    record
      ..chapters = doc.toChaptersJson()
      ..detailJson = doc.toDetailJson()
      ..updatedAt = DateTime.now().toUtc();
    if (titleOverride != null) {
      record
        ..title = doc.title
        ..titleOverride = titleOverride;
    }
    if (coverOverride != null) {
      record
        ..cover = jsonEncode(doc.cover)
        ..coverOverride = coverOverride;
    }
    objectbox.unifiedDownloadBox.put(record);
    if (titleOverride != null || coverOverride != null) {
      _syncLinkedRecords(record, doc);
    }
  }

  /// 自定义标题/封面同步到历史与本地收藏，避免书架各页各显示一套。
  void _syncLinkedRecords(UnifiedComicDownload record, ComicEditDocument doc) {
    final now = DateTime.now().toUtc();
    final title = doc.title;
    final cover = jsonEncode(doc.cover);

    final historyQuery = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(record.uniqueKey))
        .build();
    try {
      final history = historyQuery.findFirst();
      if (history != null && !history.deleted) {
        history
          ..title = title
          ..cover = cover
          ..updatedAt = now;
        objectbox.unifiedHistoryBox.put(history);
      }
    } finally {
      historyQuery.close();
    }

    final favoriteQuery = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(record.uniqueKey))
        .build();
    try {
      final favorite = favoriteQuery.findFirst();
      if (favorite != null && !favorite.deleted) {
        favorite
          ..title = title
          ..cover = cover
          ..updatedAt = now;
        objectbox.unifiedFavoriteBox.put(favorite);
      }
    } finally {
      favoriteQuery.close();
    }
  }

  Future<void> _deleteOldCover({
    required String from,
    required String comicId,
    required Map<String, dynamic> oldCover,
    required String keepPath,
  }) async {
    final path = _coverPathOf(oldCover);
    if (path.isEmpty) return;
    final store = DownloadAssetStore(
      from: from,
      path: path,
      cartoonId: comicId,
      chapterId: '',
      storageChapterId: '',
      pictureType: PictureType.cover,
    );
    final existing = await store.findCanonicalDownload();
    if (existing == null || existing.path == keepPath) return;
    await _deleteIfExists(File(existing.path));
  }

  String _coverPathOf(Map<String, dynamic> cover) {
    final path = cover['path']?.toString().trim() ?? '';
    if (path.isNotEmpty) return path;
    final extern = cover['extern'];
    if (extern is Map) {
      return extern['path']?.toString().trim() ?? '';
    }
    return '';
  }

  Map<String, dynamic>? _findChapter(
    List<Map<String, dynamic>> chapters,
    String key,
  ) {
    final target = key.trim();
    if (target.isEmpty) return null;
    for (final chapter in chapters) {
      final keys = <String>{
        chapter['logicalKey']?.toString().trim() ?? '',
        chapter['id']?.toString().trim() ?? '',
        chapter['taskChapterId']?.toString().trim() ?? '',
        chapter['requestId']?.toString().trim() ?? '',
      }..remove('');
      if (keys.contains(target)) return chapter;
    }
    return null;
  }

  Map<String, dynamic>? _findImage(Map<String, dynamic> chapter, String path) {
    final images = (chapter['images'] as List?) ?? const <dynamic>[];
    for (final image in images.whereType<Map>()) {
      if (image['path']?.toString() == path) {
        return Map<String, dynamic>.from(image);
      }
    }
    return null;
  }

  String _uniquePath(String path, Set<String> used) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var candidate = '${path}_m$stamp';
    var counter = 1;
    while (used.contains(candidate)) {
      candidate = '${path}_m${stamp}_$counter';
      counter++;
    }
    return candidate;
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.w('删除文件失败: ${file.path}', error: e);
    }
  }
}
