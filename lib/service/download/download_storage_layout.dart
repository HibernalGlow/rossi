/// 一本漫画的下载目录**在哪** —— 全仓只这一处去认历史布局。
///
/// 原来这段逻辑私有在漫画详情页的资讯卡里。抽出来是因为「占用统计」与「按漫画清理」
/// 认的是同一批目录：清理是删文件，目录猜错就是删错东西，所以不允许存在第二份
/// 「哪里可能是这本漫画的目录」。
///
/// 历史布局一共四种写法，都要认（缺一个就会把已下的漫画统计成 0，
/// 或者更糟 —— 清理时以为没东西可删）：
/// 1. 当前布局 `downloadPath/hash(from)/hash(comicId)`；
/// 2. `c703e334` 那版 `downloadPath/<from>/original/hash(comicId)`；
/// 3. 更早的未编码 `downloadPath/<from>/original/<comicId>`；
/// 4. 旧库里记下的绝对 `storageRoot`。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/qjs_download_runtime.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/service/download/download_storage_summary.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/util/get_path.dart';

/// 这本漫画可能落在哪些目录（已归一、去重，Windows 下按大小写不敏感去重）。
List<String> downloadStorageRoots({
  required String downloadPath,
  required String from,
  required String comicId,
}) {
  final roots = <String, String>{};
  void addRoot(String path) {
    final normalized = p.normalize(p.absolute(path));
    final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
    roots[key] = normalized;
  }

  final trimmedComicId = comicId.trim();
  final sourceCandidates = <String>{from.trim(), normalizePluginId(from)}
    ..removeWhere((source) => source.isEmpty);

  for (final source in sourceCandidates) {
    // 当前下载布局：hash(from)/hash(cartoonId)。
    try {
      addRoot(
        p.join(
          downloadPath,
          encodePath(path: source),
          encodePath(path: trimmedComicId),
        ),
      );
    } catch (_) {
      // Rust 编码服务尚未就绪时，仍继续统计历史目录。
    }

    // c703e334 产生的旧编码目录。
    try {
      addRoot(
        p.join(
          downloadPath,
          source,
          'original',
          encodePath(path: trimmedComicId),
        ),
      );
    } catch (_) {}

    // 更早的未编码目录。
    addRoot(p.join(downloadPath, source, 'original', trimmedComicId));
  }

  // 旧数据库记录可能保存了当时实际使用的绝对 storageRoot。
  for (final source in sourceCandidates) {
    final query = objectbox.unifiedDownloadBox
        .query(
          UnifiedComicDownload_.uniqueKey.equals('$source:$trimmedComicId'),
        )
        .build();
    UnifiedComicDownload? download;
    try {
      download = query.findFirst();
    } finally {
      query.close();
    }
    final storedRoot = download?.storageRoot.trim() ?? '';
    if (storedRoot.isNotEmpty && p.isAbsolute(storedRoot)) {
      addRoot(storedRoot);
    }
  }

  return roots.values.toList();
}

/// 统计一本漫画占了多大；一个目录都找不到时返回 [DownloadStorageStat.unmeasured]。
Future<DownloadStorageStat> measureComicDownloadStorage({
  required String from,
  required String comicId,
}) async {
  try {
    final downloadPath = await getDownloadPath();
    var totalSize = 0;
    var measuredRoots = 0;

    for (final root in downloadStorageRoots(
      downloadPath: downloadPath,
      from: from,
      comicId: comicId,
    )) {
      final dir = Directory(root);
      try {
        if (!await dir.exists()) continue;
        measuredRoots++;
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              totalSize += await entity.length();
            } on FileSystemException {
              continue;
            }
          }
        }
      } on FileSystemException {
        // 某个历史目录不可访问时，继续统计其他兼容目录。
      }
    }

    if (measuredRoots == 0) return DownloadStorageStat.unmeasured;
    return DownloadStorageStat(
      bytes: totalSize,
      measured: true,
      rootCount: measuredRoots,
    );
  } catch (_) {
    return DownloadStorageStat.unmeasured;
  }
}
