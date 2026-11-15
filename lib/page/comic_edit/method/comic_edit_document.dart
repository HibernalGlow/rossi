import 'dart:convert';

/// 已下载漫画的可编辑文档。
///
/// 下载记录里章节与图片全部存在两份 JSON 中：
/// - `chapters`：权威数据，含每章 `images` 列表；
/// - `detailJson`：详情页/阅读器展示用，含 `comicInfo`、`eps`，以及
///   `extern.downloadChapters` 镜像。
///
/// 本类只做纯数据变换，不碰 ObjectBox、不碰文件系统，方便单测。
/// 所有方法返回新实例，原实例不变。
class ComicEditDocument {
  ComicEditDocument._(this.detail, this.chapters);

  factory ComicEditDocument.fromJson({
    required String chaptersJson,
    required String detailJson,
  }) {
    return ComicEditDocument._(
      _decodeMap(detailJson, name: 'detailJson'),
      _decodeMapList(chaptersJson, name: 'chapters'),
    );
  }

  factory ComicEditDocument.fromMaps({
    required Map<String, dynamic> detail,
    required List<Map<String, dynamic>> chapters,
  }) {
    return ComicEditDocument._(_deepCopyMap(detail), _deepCopyList(chapters));
  }

  /// 完整详情 JSON（`NormalComicAllInfo`）。
  final Map<String, dynamic> detail;

  /// 权威章节列表（`UnifiedComicDownloadStoredChapter`）。
  final List<Map<String, dynamic>> chapters;

  Map<String, dynamic> get _comicInfo => _asMap(detail['comicInfo']);

  String get title => _string(_comicInfo['title']);

  Map<String, dynamic> get comicInfo => _deepCopyMap(_comicInfo);

  Map<String, dynamic> get cover => _deepCopyMap(_asMap(_comicInfo['cover']));

  List<Map<String, dynamic>> get eps => _deepCopyList(_asList(detail['eps']));

  List<Map<String, dynamic>> get chapterMaps => _deepCopyList(chapters);

  ComicEditDocument setTitle(String value) {
    final nextDetail = _deepCopyMap(detail);
    final comicInfo = _asMap(nextDetail['comicInfo']);
    comicInfo['title'] = value.trim();
    nextDetail['comicInfo'] = comicInfo;
    return ComicEditDocument._(nextDetail, _deepCopyList(chapters));
  }

  ComicEditDocument setCover(Map<String, dynamic> value) {
    final nextDetail = _deepCopyMap(detail);
    final comicInfo = _asMap(nextDetail['comicInfo']);
    comicInfo['cover'] = _deepCopyMap(value);
    nextDetail['comicInfo'] = comicInfo;
    return ComicEditDocument._(nextDetail, _deepCopyList(chapters));
  }

  /// 按章节身份改名。
  ///
  /// [chapterId] 可以是 `logicalKey` / `id` / `taskChapterId` / `requestId`
  /// 中的任意一个；不按数组下标匹配。
  ComicEditDocument renameChapter(String chapterId, String name) {
    final key = chapterId.trim();
    final index = _findChapterIndex(chapters, key);
    if (index < 0) {
      throw StateError('chapter not found: $chapterId');
    }

    final nextChapters = _deepCopyList(chapters);
    nextChapters[index]['name'] = name.trim();

    final nextDetail = _deepCopyMap(detail);
    final nextEps = _asList(nextDetail['eps']);
    final epIndex = _findEpIndex(nextEps, key);
    if (epIndex >= 0) {
      nextEps[epIndex]['name'] = name.trim();
    } else {
      nextEps.add(_epFromChapter(nextChapters[index]));
    }
    nextDetail['eps'] = nextEps;
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 新增一个本地空章节。
  ///
  /// 章节身份用调用方生成的 [id]（约定 `local:<uuid>`），同时写入
  /// `logicalKey` 与 `storageChapterId`，保证详情页、阅读器、导出都能识别。
  /// 顺序固定追加到末尾，避免改动既有 `order` 破坏阅读历史。
  ComicEditDocument addChapter({required String id, required String name}) {
    final key = id.trim();
    if (key.isEmpty) {
      throw ArgumentError('chapter id is empty');
    }
    if (_findChapterIndex(chapters, key) >= 0) {
      throw StateError('chapter already exists: $key');
    }

    final chapter = <String, dynamic>{
      'id': key,
      'name': name.trim(),
      'order': _nextOrder(chapters),
      'logicalKey': key,
      'taskChapterId': '',
      'storageChapterId': key,
      'groupTitle': '',
      'images': <Map<String, dynamic>>[],
    };

    final nextChapters = _deepCopyList(chapters)..add(chapter);
    final nextDetail = _deepCopyMap(detail);
    final nextEps = _asList(nextDetail['eps'])..add(_epFromChapter(chapter));
    nextDetail['eps'] = nextEps;
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 按给定章节 id 顺序重排，并重新编号 1..N。
  ///
  /// `order` 同时是阅读器的 `epsId`，重排后必须保持 1..N 连续且唯一。
  ComicEditDocument reorderChapters(List<String> orderedChapterIds) {
    final remaining = _deepCopyList(chapters);
    final nextChapters = <Map<String, dynamic>>[];
    for (final id in orderedChapterIds) {
      final index = remaining.indexWhere(
        (chapter) => comicEditChapterId(chapter) == id,
      );
      if (index >= 0) nextChapters.add(remaining.removeAt(index));
    }
    nextChapters.addAll(remaining);
    for (var i = 0; i < nextChapters.length; i++) {
      nextChapters[i]['order'] = i + 1;
    }

    final nextDetail = _deepCopyMap(detail);
    final oldEps = _asList(nextDetail['eps']);
    final nextEps = <Map<String, dynamic>>[];
    for (final chapter in nextChapters) {
      final id = comicEditChapterId(chapter);
      final epIndex = _findEpIndex(oldEps, id);
      final ep = epIndex >= 0
          ? _deepCopyMap(oldEps[epIndex])
          : _epFromChapter(chapter);
      ep['order'] = chapter['order'];
      ep['name'] = chapter['name'];
      nextEps.add(ep);
    }
    nextDetail['eps'] = nextEps;
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 按图片 `path` 删除某一章的图片。
  ComicEditDocument removeImages(String chapterId, List<String> imagePaths) {
    final key = chapterId.trim();
    final index = _findChapterIndex(chapters, key);
    if (index < 0) {
      throw StateError('chapter not found: $chapterId');
    }

    final nextChapters = _deepCopyList(chapters);
    final images = _asList(nextChapters[index]['images']);
    for (final path in imagePaths) {
      final imageIndex = images.indexWhere(
        (image) => _string(image['path']) == path,
      );
      if (imageIndex >= 0) images.removeAt(imageIndex);
    }
    nextChapters[index]['images'] = images;

    final nextDetail = _deepCopyMap(detail);
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 按图片 `path` 列表重排某一章。
  ///
  /// 未出现在 [orderedPaths] 里的图片会按原顺序追加到末尾，避免 UI 漏传
  /// 导致图片丢失。
  ComicEditDocument reorderImages(String chapterId, List<String> orderedPaths) {
    final key = chapterId.trim();
    final index = _findChapterIndex(chapters, key);
    if (index < 0) {
      throw StateError('chapter not found: $chapterId');
    }

    final nextChapters = _deepCopyList(chapters);
    final images = _asList(nextChapters[index]['images']);
    nextChapters[index]['images'] = _reorderImages(images, orderedPaths);

    final nextDetail = _deepCopyMap(detail);
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 修改某张图片的 `path`。
  ///
  /// 跨章移动遇到目标章已有同名文件时，IO 层会生成新文件名并先调用本方法，
  /// 再调用 [moveImages]。
  ComicEditDocument replaceImagePath(
    String chapterId,
    String oldPath,
    String newPath,
  ) {
    final key = chapterId.trim();
    final index = _findChapterIndex(chapters, key);
    if (index < 0) {
      throw StateError('chapter not found: $chapterId');
    }

    final nextChapters = _deepCopyList(chapters);
    final images = _asList(nextChapters[index]['images']);
    var changed = false;
    for (final image in images) {
      if (_string(image['path']) == oldPath) {
        image['path'] = newPath;
        changed = true;
        break;
      }
    }
    if (!changed) return this;

    nextChapters[index]['images'] = images;
    final nextDetail = _deepCopyMap(detail);
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  /// 把图片从一章移动到另一章。
  ///
  /// 只改 JSON；磁盘文件搬移由 IO 层负责。`imagePaths` 按目标顺序排列，
  /// [targetIndex] 为空时追加到目标章末尾。
  ComicEditDocument moveImages({
    required String sourceChapterId,
    required String targetChapterId,
    required List<String> imagePaths,
    int? targetIndex,
  }) {
    final sourceIndex = _findChapterIndex(chapters, sourceChapterId.trim());
    final targetListIndex = _findChapterIndex(chapters, targetChapterId.trim());
    if (sourceIndex < 0) {
      throw StateError('source chapter not found: $sourceChapterId');
    }
    if (targetListIndex < 0) {
      throw StateError('target chapter not found: $targetChapterId');
    }

    final nextChapters = _deepCopyList(chapters);

    if (sourceIndex == targetListIndex) {
      final images = _asList(nextChapters[sourceIndex]['images']);
      final moved = _takeImages(images, imagePaths);
      if (moved.isEmpty) {
        return this;
      }
      final insertAt = (targetIndex ?? images.length).clamp(0, images.length);
      images.insertAll(insertAt, moved);
      nextChapters[sourceIndex]['images'] = images;

      final nextDetail = _deepCopyMap(detail);
      _syncMirror(nextDetail, nextChapters);
      return ComicEditDocument._(nextDetail, nextChapters);
    }

    final sourceImages = _asList(nextChapters[sourceIndex]['images']);
    final targetImages = _asList(nextChapters[targetListIndex]['images']);
    final moved = _takeImages(sourceImages, imagePaths);
    if (moved.isEmpty) {
      return this;
    }

    final insertAt = (targetIndex ?? targetImages.length).clamp(
      0,
      targetImages.length,
    );
    targetImages.insertAll(insertAt, moved);
    nextChapters[sourceIndex]['images'] = sourceImages;
    nextChapters[targetListIndex]['images'] = targetImages;

    final nextDetail = _deepCopyMap(detail);
    _syncMirror(nextDetail, nextChapters);
    return ComicEditDocument._(nextDetail, nextChapters);
  }

  String toChaptersJson() => jsonEncode(chapters);

  String toDetailJson() {
    final nextDetail = _deepCopyMap(detail);
    _syncMirror(nextDetail, chapters);
    return jsonEncode(nextDetail);
  }
}

Map<String, dynamic> _decodeMap(String raw, {required String name}) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('$name is not a JSON object');
  }
  return _deepCopyMap(Map<String, dynamic>.from(decoded));
}

List<Map<String, dynamic>> _decodeMapList(String raw, {required String name}) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw FormatException('$name is not a JSON array');
  }
  return decoded
      .whereType<Map>()
      .map((entry) => _deepCopyMap(Map<String, dynamic>.from(entry)))
      .toList();
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) {
    return <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

List<Map<String, dynamic>> _deepCopyList(List<Map<String, dynamic>> value) {
  return value.map((entry) => _deepCopyMap(entry)).toList(growable: true);
}

String _string(Object? value) => value?.toString().trim() ?? '';

/// 章节的宿主匹配 key（`logicalKey` 优先，回退 `id`）。
String comicEditChapterId(Map<String, dynamic> chapter) {
  final logical = _string(chapter['logicalKey']);
  if (logical.isNotEmpty) return logical;
  return _string(chapter['id']);
}

/// 章节的本地存储目录 key（`storageChapterId` 优先，回退宿主 key）。
String comicEditChapterStorageId(Map<String, dynamic> chapter) {
  final storage = _string(chapter['storageChapterId']);
  if (storage.isNotEmpty) return storage;
  return comicEditChapterId(chapter);
}

int _toInt(Object? value, int fallback) {
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Set<String> _chapterKeys(Map<String, dynamic> chapter) {
  return <String>{
    _string(chapter['logicalKey']),
    _string(chapter['id']),
    _string(chapter['taskChapterId']),
    _string(chapter['requestId']),
  }..remove('');
}

Set<String> _epKeys(Map<String, dynamic> ep) {
  return <String>{
    _string(ep['logicalKey']),
    _string(ep['id']),
    _string(ep['requestId']),
  }..remove('');
}

int _findChapterIndex(List<Map<String, dynamic>> chapters, String key) {
  if (key.isEmpty) return -1;
  for (var i = 0; i < chapters.length; i++) {
    if (_chapterKeys(chapters[i]).contains(key)) return i;
  }
  return -1;
}

int _findEpIndex(List<Map<String, dynamic>> eps, String key) {
  if (key.isEmpty) return -1;
  for (var i = 0; i < eps.length; i++) {
    if (_epKeys(eps[i]).contains(key)) return i;
  }
  return -1;
}

int _nextOrder(List<Map<String, dynamic>> chapters) {
  var maxOrder = 0;
  for (final chapter in chapters) {
    final order = _toInt(chapter['order'], 0);
    if (order > maxOrder) maxOrder = order;
  }
  return maxOrder + 1;
}

Map<String, dynamic> _epFromChapter(Map<String, dynamic> chapter) {
  final logicalKey = _string(chapter['logicalKey']);
  final id = logicalKey.isNotEmpty ? logicalKey : _string(chapter['id']);
  return <String, dynamic>{
    'id': id,
    'name': _string(chapter['name']),
    'order': _toInt(chapter['order'], 1),
    'requestId': _string(chapter['taskChapterId']),
    'storageChapterId': _string(chapter['storageChapterId']),
    'logicalKey': logicalKey,
    'groupTitle': _string(chapter['groupTitle']),
    'extern': _asMap(chapter['extern']),
  };
}

void _syncMirror(
  Map<String, dynamic> detail,
  List<Map<String, dynamic>> chapters,
) {
  final extern = _asMap(detail['extern']);
  extern['downloadChapters'] = _deepCopyList(chapters);
  detail['extern'] = extern;
}

List<Map<String, dynamic>> _reorderImages(
  List<Map<String, dynamic>> images,
  List<String> orderedPaths,
) {
  final remaining = _deepCopyList(images);
  final ordered = <Map<String, dynamic>>[];
  for (final path in orderedPaths) {
    final index = remaining.indexWhere(
      (image) => _string(image['path']) == path,
    );
    if (index >= 0) {
      ordered.add(remaining.removeAt(index));
    }
  }
  ordered.addAll(remaining);
  return ordered;
}

List<Map<String, dynamic>> _takeImages(
  List<Map<String, dynamic>> images,
  List<String> paths,
) {
  final taken = <Map<String, dynamic>>[];
  for (final path in paths) {
    final index = images.indexWhere((image) => _string(image['path']) == path);
    if (index >= 0) {
      taken.add(images.removeAt(index));
    }
  }
  return taken;
}
