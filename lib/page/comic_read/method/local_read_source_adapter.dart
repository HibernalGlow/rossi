import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/util/get_path.dart';

export 'package:zephyr/util/path_util.dart' show isLocalComicSource;

/// 管理当前活跃的本地 GPU 呈现阅读会话。
class LocalReadSession {
  LocalReadSession._();

  static final LocalReadSession instance = LocalReadSession._();

  PageSource? _currentSource;
  GpuPresentController? _presenter;

  PageSource? get currentSource => _currentSource;
  GpuPresentController? get presenter => _presenter;

  /// 初始化或获取当前 GPU 呈现控制器
  GpuPresentController getOrCreatePresenter() {
    if (_presenter == null) {
      final presenter = GpuPresentController();
      presenter.start();
      _presenter = presenter;
    }
    return _presenter!;
  }

  /// 设置当前打开的来源
  void setSource(PageSource source) {
    if (!identical(_currentSource, source)) {
      unawaited(_currentSource?.close());
      _currentSource = source;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _currentSource?.close();
    _currentSource = null;
    _presenter?.dispose();
    _presenter = null;
  }
}

/// 将本地漫画归档/文件夹解析为 Breeze 阅读器所需的 [NormalComicEpInfo]
Future<NormalComicEpInfo> getLocalComicEpInfo(String path) async {
  final PageSourceOpen result = await LocalPageSource.open(path);

  switch (result) {
    case PageSourceRejected(:final message):
      throw StateError('无法打开本地漫画: $message');

    case PageSourceOpened(:final source):
      LocalReadSession.instance.setSource(source);
      LocalReadSession.instance.getOrCreatePresenter();

      final String name = p.basename(path);
      final docs = <Doc>[];

      for (int i = 0; i < source.pageCount; i++) {
        final pageRef = source.pages[i];
        docs.add(
          Doc(
            originalName: pageRef.name,
            path: i.toString(),
            fileServer: path,
            id: i.toString(),
            storageChapterId: path,
            extern: <String, dynamic>{
              'localIndex': i,
              'localPath': path,
              'isLocalGpu': true,
            },
          ),
        );
      }

      return NormalComicEpInfo(
        length: docs.length,
        epPages: docs.length.toString(),
        docs: docs,
        epId: path,
        epName: name,
      );
  }
}

/// 路径归一化（统一消除尾随斜杠与相对路径符号，确保历史键值唯一）
String normalizeLocalComicPath(String rawPath) {
  var normalized = p.normalize(rawPath.trim());
  if (normalized.length > 1 &&
      (normalized.endsWith('/') || normalized.endsWith(r'\'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// 确保本地漫画有可展示的封面图片，并返回其本地绝对文件路径。
///
/// 若为目录且首项为图片文件，直接返回其磁盘绝对路径。
/// 若为归档包（ZIP/RAR/CBZ/CBR 等），提取首页字节并缓存至本地缓存目录中。
Future<String?> ensureLocalComicCover(String comicPath) async {
  try {
    final normalized = normalizeLocalComicPath(comicPath);
    final file = File(normalized);
    final isDir = Directory(normalized).existsSync();
    final isFile = file.existsSync();

    if (!isDir && !isFile) {
      return null;
    }

    final cachePath = await getCachePath();
    final coversDir = Directory(p.join(cachePath, 'local_covers'));
    if (!coversDir.existsSync()) {
      await coversDir.create(recursive: true);
    }
    final keyHash = md5.convert(utf8.encode(normalized)).toString();
    final cachedCoverFile = File(p.join(coversDir.path, '$keyHash.jpg'));
    if (cachedCoverFile.existsSync()) {
      return cachedCoverFile.path;
    }

    // 检查当前阅读会话是否正好持有此漫画
    final currentSource = LocalReadSession.instance.currentSource;
    if (currentSource != null &&
        normalizeLocalComicPath(currentSource.path) == normalized) {
      final directPath = await currentSource.getPageFilePath(0);
      if (directPath != null && File(directPath).existsSync()) {
        return directPath;
      }
      final bytes = await currentSource.getPageBytes(0);
      if (bytes != null && bytes.isNotEmpty) {
        await cachedCoverFile.writeAsBytes(bytes, flush: true);
        return cachedCoverFile.path;
      }
    }

    // 独立打开并提取首页
    final openRes = await LocalPageSource.open(normalized);
    if (openRes is PageSourceOpened) {
      try {
        final directPath = await openRes.source.getPageFilePath(0);
        if (directPath != null && File(directPath).existsSync()) {
          return directPath;
        }
        final bytes = await openRes.source.getPageBytes(0);
        if (bytes != null && bytes.isNotEmpty) {
          await cachedCoverFile.writeAsBytes(bytes, flush: true);
          return cachedCoverFile.path;
        }
      } finally {
        await openRes.source.close();
      }
    }
  } catch (e, st) {
    logger.w('获取或生成本地漫画封面失败: $comicPath', error: e, stackTrace: st);
  }
  return null;
}
