import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/video/model/animated_video_mode.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/service/video_poster_service.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

export 'package:zephyr/util/path_util.dart'
    show isLocalComicSource, isLocalPictureRequest;

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
      // 「动图当视频播」是用户开关（默认关），关掉时下面这条判定恒为 false，
      // 行为与改造前逐字一致 —— 所以在这里读一次设置是安全的。
      final videoSettings = await VideoSettingsStore.instance.load();
      // 视频页要找「同归档里的同名字幕」，所以整本条目名要先备好。
      final List<String> allEntryNames = <String>[
        for (final page in source.pages) page.name,
      ];

      for (int i = 0; i < source.pageCount; i++) {
        final pageRef = source.pages[i];
        final bool isVideo =
            mediaKindOf(pageRef.name) == RossiMediaKind.video ||
                shouldOpenAnimatedImageAsVideo(
                  pageRef.name,
                  enabled: videoSettings.animatedVideoEnabled,
                  keywords: videoSettings.animatedVideoKeywords,
                );
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
              // 「这一页是视频」必须在建页表时定下来：GPU 上屏那条路是按
              // 「一页 = 一张位图」设计的，走到那一步才发现是视频就晚了。
              'isVideo': isVideo,
              'videoEntryName': pageRef.name,
              if (isVideo) 'videoSiblings': allEntryNames,
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

/// 封面用的页下标：**页序现在含视频条目**，直接取第 0 页可能把一个 mp4 的字节
/// 当 jpg 写进封面缓存（症状是封面永久白图，且因为按路径哈希缓存了，改不回来）。
int firstImagePageIndex(PageSource source) {
  final pages = source.pages;
  for (var i = 0; i < pages.length; i++) {
    if (!isVideoName(pages[i].name)) return i;
  }
  return 0;
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
      final cover = await _coverFromSource(currentSource, cachedCoverFile);
      if (cover != null) return cover;
    }

    // 独立打开并提取首页
    final openRes = await LocalPageSource.open(normalized);
    if (openRes is PageSourceOpened) {
      try {
        final cover = await _coverFromSource(openRes.source, cachedCoverFile);
        if (cover != null) return cover;
      } finally {
        await openRes.source.close();
      }
    }
  } catch (e, st) {
    logger.w('获取或生成本地漫画封面失败: $comicPath', error: e, stackTrace: st);
  }
  return null;
}

/// 从来源取一张**能当封面的图**，必要时落盘到 [cachedCoverFile]；拿不到返回 null。
///
/// 三条路，顺序即优先级：
/// 1. 第一个非视频页就在磁盘上（文件夹来源）→ 路径直接用，零成本；
/// 2. 有非视频页但只在归档里 → 取字节写进封面缓存；
/// 3. 整本都只有视频条目 → 取海报帧。
///
/// 第 3 条不能省成「拿第 0 页的字节当 jpg」：那是把一个 mp4 的头几十字节写进
/// **按路径哈希**的封面缓存，症状是封面永久白图、重开也不恢复。
Future<String?> _coverFromSource(
  PageSource source,
  File cachedCoverFile,
) async {
  final index = firstImagePageIndex(source);
  final hasImagePage = source.pages.any((page) => !isVideoName(page.name));
  if (hasImagePage) {
    final directPath = await source.getPageFilePath(index);
    if (directPath != null && File(directPath).existsSync()) return directPath;
    final bytes = await source.getPageBytes(index);
    if (bytes == null || bytes.isEmpty) return null;
    await cachedCoverFile.writeAsBytes(bytes, flush: true);
    return cachedCoverFile.path;
  }

  final direct = await source.getPageFilePath(index);
  final Uint8List? poster;
  if (direct != null && File(direct).existsSync()) {
    poster = await VideoPosterService.instance.posterForFile(direct);
  } else {
    final bytes = await source.getPageBytes(index);
    if (bytes == null || bytes.isEmpty) return null;
    final name = index < source.pages.length ? source.pages[index].name : '';
    poster = await VideoPosterService.instance.posterForBytes(
      identityKey: sha1ish('${source.path}|$name|${bytes.lengthInBytes}'),
      readBytes: () async => bytes,
    );
  }
  if (poster == null || poster.isEmpty) return null;
  await cachedCoverFile.writeAsBytes(poster, flush: true);
  return cachedCoverFile.path;
}
