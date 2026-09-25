import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/local_thumbnail.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/service/video_poster_service.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

/// 缩略图内存缓存与加载服务（完全采用 mImageViewer SQLite CatalogDb 架构与 SIMD WebP 管线）。
class ReaderThumbnailService {
  ReaderThumbnailService._();

  static final ReaderThumbnailService instance = ReaderThumbnailService._();

  static const int _maxMemoryCacheEntries = 200;

  // 内存 LRU 缓存：key -> WebP 缩略图字节 (单张 ~15KB)
  final LinkedHashMap<String, Uint8List> _thumbnailBytesCache =
      LinkedHashMap<String, Uint8List>();

  // 内存直通路径缓存：key -> 文件绝对路径 (仅作散图异常时的备选兜底)
  final Map<String, String> _filePathCache = <String, String>{};

  String? _catalogCacheDir;

  /// 获取 mImageViewer SQLite 目录数据库存储目录
  Future<String> getCatalogCacheDir() async {
    if (_catalogCacheDir != null) return _catalogCacheDir!;
    final baseCache = await getCachePath();
    final dir = p.join(baseCache, 'mimage_catalog');
    final directory = Directory(dir);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    _catalogCacheDir = dir;
    return dir;
  }

  /// 获取本地漫画单页的缩略图字节（彻底使用 mImageViewer SQLite 数据库与 SIMD 缩放 WebP）
  ///
  /// 优先查 SQLite WAL (`{cache_dir}/{xx}/{sha256}.db` 的 `thumbnails` 表)；
  /// 未命中则由 Rust 后台读取原图、SIMD 缩放至指定边长并写入 SQLite。
  Future<Uint8List?> getLocalThumbnailBytes({
    required PageSource source,
    required int index,
    int maxLongSide = 320,
  }) async {
    final key = '${source.path}#$index@$maxLongSide';
    if (_thumbnailBytesCache.containsKey(key)) {
      final value = _thumbnailBytesCache.remove(key)!;
      _thumbnailBytesCache[key] = value;
      return value;
    }

    try {
      final cacheDir = await getCatalogCacheDir();
      final pages = source.pages;
      final entryName = (index >= 0 && index < pages.length)
          ? pages[index].name
          : '';

      final bytes = await getLocalThumbnail(
        cacheDir: cacheDir,
        bookPath: source.path,
        entryName: entryName,
        pageIndex: index,
        maxLongSide: maxLongSide,
      );

      if (bytes != null && bytes.isNotEmpty) {
        if (_thumbnailBytesCache.length >= _maxMemoryCacheEntries) {
          _thumbnailBytesCache.remove(_thumbnailBytesCache.keys.first);
        }
        _thumbnailBytesCache[key] = bytes;
        return bytes;
      }
    } catch (_) {
      // 容错处理：由界面呈现错误占位或转兜底
    }
    return null;
  }

  // 文件管理器缩略图在途请求去重
  final Map<String, Future<Uint8List?>> _fileManagerInFlight = {};

  /// 获取文件管理器条目 (文件夹/单张图片/漫画归档) 的缩略图字节数据。
  ///
  /// 遵循 mImageViewer SQLite 目录数据库与纯函数代表图推选逻辑。
  /// 内置内存 LRU 缓存与在途请求去重，保证列表与网格丝滑滚动。
  Future<Uint8List?> getFileManagerEntryThumbnailBytes({
    required String entryPath,
    required bool isDir,
    required bool isArchive,
    required bool isImage,
    String? sortOrder,
    int maxDepth = 8,
    int maxLongSide = 320,
  }) async {
    final key =
        'fm:$entryPath@$maxLongSide:$isDir:$isArchive:$isImage'
        ':${sortOrder ?? 'FileName'}:$maxDepth';
    if (_thumbnailBytesCache.containsKey(key)) {
      final value = _thumbnailBytesCache.remove(key)!;
      _thumbnailBytesCache[key] = value;
      return value;
    }

    if (_fileManagerInFlight.containsKey(key)) {
      return _fileManagerInFlight[key];
    }

    final future = _loadFileManagerEntryThumbnail(
      key: key,
      entryPath: entryPath,
      isDir: isDir,
      isArchive: isArchive,
      isImage: isImage,
      sortOrder: sortOrder,
      maxDepth: maxDepth,
      maxLongSide: maxLongSide,
    );
    _fileManagerInFlight[key] = future;
    try {
      return await future;
    } finally {
      _fileManagerInFlight.remove(key);
    }
  }

  Future<Uint8List?> _loadFileManagerEntryThumbnail({
    required String key,
    required String entryPath,
    required bool isDir,
    required bool isArchive,
    required bool isImage,
    String? sortOrder,
    required int maxDepth,
    required int maxLongSide,
  }) async {
    try {
      final cacheDir = await getCatalogCacheDir();
      final bytes = await getFileManagerEntryThumbnail(
        cacheDir: cacheDir,
        entryPath: entryPath,
        isDir: isDir,
        isArchive: isArchive,
        isImage: isImage,
        sortOrder: sortOrder,
        maxDepth: maxDepth,
        maxLongSide: maxLongSide,
      );

      if (bytes != null && bytes.isNotEmpty) {
        if (_thumbnailBytesCache.length >= _maxMemoryCacheEntries) {
          _thumbnailBytesCache.remove(_thumbnailBytesCache.keys.first);
        }
        _thumbnailBytesCache[key] = bytes;
        return bytes;
      }
    } catch (_) {
      // 容错处理：由界面呈现语义图标占位或兜底
    }
    return null;
  }

  /// 获取整本漫画已缓存页面的原图真实尺寸映射 (entryName -> (w, h))。
  /// 从 SQLite 直接返回，无需解压原图。
  Future<Map<String, (int, int)>> getBookPageDimensions({
    required String bookPath,
  }) async {
    try {
      final cacheDir = await getCatalogCacheDir();
      return await getCachedBookPageDimensions(
        cacheDir: cacheDir,
        bookPath: bookPath,
      );
    } catch (_) {
      return const {};
    }
  }

  /// 兼容接口：向后兼容原调用方，直接复用 SQLite WebP 缩略图
  Future<Uint8List?> getLocalArchivePageBytes({
    required PageSource source,
    required int index,
  }) async {
    return getLocalThumbnailBytes(source: source, index: index);
  }

  /// 获取本地散图的直接文件路径（带内存记忆，仅作异常时的备选兜底）
  Future<String?> getLocalPageFilePath({
    required PageSource source,
    required int index,
  }) async {
    final key = '${source.path}#$index';
    final cached = _filePathCache[key];
    if (cached != null) return cached;

    final directPath = await source.getPageFilePath(index);
    if (directPath != null && directPath.isNotEmpty) {
      _filePathCache[key] = directPath;
      return directPath;
    }
    return null;
  }

  /// 清除缓存
  void clear() {
    _thumbnailBytesCache.clear();
    _filePathCache.clear();
  }
}

/// 统一的漫画缩略图展示组件。
///
/// 能够自适应本地归档/文件夹（完全基于 mImageViewer SQLite WAL 缓存），
/// 以及在线/插件图源，保证列表与胶卷栏以最小开销丝滑滚动。
class ReaderThumbnailWidget extends StatefulWidget {
  final int index;
  final Doc? doc;
  final PageSource? localSource;
  final String comicId;
  final String from;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ReaderThumbnailWidget({
    super.key,
    required this.index,
    this.doc,
    this.localSource,
    required this.comicId,
    required this.from,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<ReaderThumbnailWidget> createState() => _ReaderThumbnailWidgetState();
}

class _ReaderThumbnailWidgetState extends State<ReaderThumbnailWidget> {
  String? _localDirectPath;
  Uint8List? _archiveBytes;
  bool _isLoadingLocal = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  @override
  void didUpdateWidget(covariant ReaderThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.localSource != widget.localSource ||
        oldWidget.doc != widget.doc) {
      _checkAndLoad();
    }
  }

  Future<void> _checkAndLoad() async {
    final source = widget.localSource;
    if (source != null) {
      setState(() {
        _isLoadingLocal = true;
      });

      // 0. 视频页：图像缩略图那条路（SQLite catalog / Image.file）对它必然失败，
      //    先分流到海报服务。不分流的症状是页列表里每个视频格都是「加载失败」占位。
      final pages = source.pages;
      final isVideoPage =
          widget.index >= 0 &&
          widget.index < pages.length &&
          isVideoName(pages[widget.index].name);
      if (isVideoPage) {
        final direct = await ReaderThumbnailService.instance
            .getLocalPageFilePath(source: source, index: widget.index);
        Uint8List? poster;
        if (direct != null && File(direct).existsSync()) {
          poster = await VideoPosterService.instance.posterForFile(direct);
        } else {
          final bytes = await source.getPageBytes(widget.index);
          if (bytes != null && bytes.isNotEmpty) {
            poster = await VideoPosterService.instance.posterForBytes(
              identityKey: sha1ish(
                '${source.path}|${pages[widget.index].name}|${bytes.lengthInBytes}',
              ),
              readBytes: () async => bytes,
            );
          }
        }
        if (!mounted) return;
        setState(() {
          _archiveBytes = poster;
          _localDirectPath = null;
          _isLoadingLocal = false;
        });
        return;
      }

      // 1. 优先使用 mImageViewer SQLite WAL 缓存的 WebP 缩略图
      final bytes = await ReaderThumbnailService.instance
          .getLocalThumbnailBytes(source: source, index: widget.index);

      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _archiveBytes = bytes;
          _localDirectPath = null;
          _isLoadingLocal = false;
        });
        return;
      }

      // 2. 兜底策略：如果缩略图生成失败且为本地散图，尝试直接读取原图文件
      final directPath = await ReaderThumbnailService.instance
          .getLocalPageFilePath(source: source, index: widget.index);

      if (!mounted) return;
      if (directPath != null && File(directPath).existsSync()) {
        setState(() {
          _localDirectPath = directPath;
          _archiveBytes = null;
          _isLoadingLocal = false;
        });
        return;
      }

      setState(() {
        _isLoadingLocal = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(4);
    final theme = Theme.of(context);

    Widget content;

    if (widget.localSource != null) {
      if (_isLoadingLocal) {
        content = _buildPlaceholder(theme);
      } else if (_archiveBytes != null) {
        content = Image.memory(
          _archiveBytes!,
          fit: widget.fit,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _buildError(theme),
        );
      } else if (_localDirectPath != null) {
        content = Image.file(
          File(_localDirectPath!),
          fit: widget.fit,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _buildError(theme),
        );
      } else {
        content = _buildError(theme);
      }
    } else if (widget.doc != null) {
      // 在线或插件漫画
      final doc = widget.doc!;
      final pictureInfo = PictureInfo(
        from: widget.from,
        url: doc.fileServer,
        path: doc.path,
        cartoonId: widget.comicId,
        chapterId: doc.storageChapterId.isNotEmpty
            ? doc.storageChapterId
            : widget.comicId,
        storageChapterId: doc.storageChapterId,
        pictureType: PictureType.page,
        extern: doc.extern,
      );

      content = BlocProvider(
        create: (_) => PictureBloc()..add(GetPicture(pictureInfo)),
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return _buildPlaceholder(theme);
              case PictureLoadStatus.success:
                final imagePath = state.imagePath;
                if (imagePath != null && File(imagePath).existsSync()) {
                  return Image.file(
                    File(imagePath),
                    fit: widget.fit,
                    cacheWidth: 320,
                    errorBuilder: (_, _, _) => _buildError(theme),
                  );
                }
                return _buildError(theme);
              case PictureLoadStatus.failure:
                return _buildError(theme);
            }
          },
        ),
      );
    } else {
      content = _buildPlaceholder(theme);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Center(
        child: Text(
          '#${widget.index + 1}',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          size: 16,
          color: theme.colorScheme.error.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
