import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/src/rust/api/simple.dart';

/// 下载目录里的元数据文件名，与导出包用的是同一组名字（导入端认这组名字）。
const String downloadOriginalComicInfoFile = 'original_comic_info.json';
const String downloadProcessedComicInfoFile = 'processed_comic_info.json';

/// 把已下载漫画的信息写成元数据文件，落在下载目录的漫画根目录下。
///
/// 下载目录是「hash 目录 + hash 文件名」，离开 ObjectBox 没人认得；这两份 JSON
/// 让目录自身可被识别。[downloadProcessedComicInfoFile] 里的章节目录名与图片文件名
/// 写的是**磁盘上的真实名字**而不是展示名，否则照着 JSON 找不到文件。
Future<void> writeDownloadComicMetadata(String uniqueKey) async {
  final download = objectbox.unifiedDownloadBox
      .query(UnifiedComicDownload_.uniqueKey.equals(uniqueKey))
      .build()
      .findFirst();
  if (download == null) {
    throw StateError('找不到下载记录: $uniqueKey');
  }
  final comicDir = download.storageRoot.trim();
  if (comicDir.isEmpty) {
    throw StateError('下载记录缺少 storageRoot，无法写入元数据: $uniqueKey');
  }

  final original = _originalDetail(download);
  final processed = _processedDetail(
    original,
    resolveDownloadChapters(download),
  );
  final dir = Directory(comicDir);
  await dir.create(recursive: true);
  await File(
    p.join(comicDir, downloadOriginalComicInfoFile),
  ).writeAsString(jsonEncode(original));
  await File(
    p.join(comicDir, downloadProcessedComicInfoFile),
  ).writeAsString(jsonEncode(processed));
}

/// 原始信息：数据库里的 `detailJson` 加上导入端要看的版本与图源。
Map<String, dynamic> _originalDetail(UnifiedComicDownload download) {
  final detail = Map<String, dynamic>.from(
    jsonDecode(download.detailJson) as Map<String, dynamic>,
  );
  final extern = Map<String, dynamic>.from(
    detail['extern'] as Map? ?? const {},
  );
  extern['version'] = mainVersion;
  extern['source'] = download.source;
  detail['extern'] = extern;
  return detail;
}

Map<String, dynamic> _processedDetail(
  Map<String, dynamic> original,
  List<DownloadChapter> chapters,
) {
  final processed = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(original)) as Map<String, dynamic>,
  );
  final extern = Map<String, dynamic>.from(
    processed['extern'] as Map? ?? const {},
  );
  final storedChapters = ((extern['downloadChapters'] as List?) ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final storedEps = ((processed['eps'] as List?) ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  final rewrittenChapters = <Map<String, dynamic>>[];
  final rewrittenEps = <Map<String, dynamic>>[];
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final chapterDir = _storedChapterDir(chapter);

    final chapterBase = i < storedChapters.length
        ? Map<String, dynamic>.from(storedChapters[i])
        : <String, dynamic>{};
    final storedImages = ((chapterBase['images'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final images = <Map<String, dynamic>>[];
    for (var j = 0; j < chapter.images.length; j++) {
      final fileName = _storedImageFileName(chapter.images[j]);
      if (fileName.isEmpty) continue;
      final imageBase = j < storedImages.length
          ? storedImages[j]
          : <String, dynamic>{};
      images.add({...imageBase, 'name': fileName, 'path': fileName});
    }
    chapterBase['name'] = chapterDir;
    chapterBase['order'] = i + 1;
    chapterBase['images'] = images;
    rewrittenChapters.add(chapterBase);

    final epBase = i < storedEps.length
        ? Map<String, dynamic>.from(storedEps[i])
        : <String, dynamic>{};
    epBase['name'] = chapterDir;
    epBase['order'] = i + 1;
    rewrittenEps.add(epBase);
  }

  if (rewrittenChapters.isNotEmpty) {
    extern['downloadChapters'] = rewrittenChapters;
    processed['extern'] = extern;
  }
  if (rewrittenEps.isNotEmpty) {
    processed['eps'] = rewrittenEps;
  }
  return processed;
}

/// 目录名与文件名口径来自 [DownloadAssetStore] 的 canonical 布局，改一处要改两处。
String _storedChapterDir(DownloadChapter chapter) =>
    encodePath(path: chapter.effectiveStorageId);

String _storedImageFileName(DownloadImage image) {
  final path = image.path.trim();
  if (path.isEmpty) return '';
  return encodePath(path: normalizeStoredAssetPath(path));
}
