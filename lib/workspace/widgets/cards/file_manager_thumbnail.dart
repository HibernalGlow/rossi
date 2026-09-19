import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/video/service/video_poster_service.dart';

/// 参考 NeoView 与 mImageViewer 设计的文件管理器条目缩略图展示组件。
///
/// 1. 针对文件夹、漫画归档、图片条目，调用 mImageViewer SQLite CatalogDb 与纯函数代表图推选；
/// 2. 具有内存 LRU 记忆与异步在途去重，快速滑动时不抖动、不发重复请求；
/// 3. 加载中或无代表图时平滑回退至对应文件类型的语义彩色图标。
class FileManagerThumbnailWidget extends StatefulWidget {
  final FileManagerEntry entry;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const FileManagerThumbnailWidget({
    super.key,
    required this.entry,
    this.width = 38,
    this.height = 38,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  State<FileManagerThumbnailWidget> createState() =>
      _FileManagerThumbnailWidgetState();
}

class _FileManagerThumbnailWidgetState
    extends State<FileManagerThumbnailWidget> {
  Uint8List? _bytes;
  bool _isLoading = false;
  String? _loadedPath;

  bool get _isEligible =>
      widget.entry.isDir ||
      widget.entry.isArchive ||
      widget.entry.isImage ||
      // 视频条目也走缩略图路：取帧由 Dart 侧的海报服务负责（B4 不许 ffmpeg 进 core）。
      widget.entry.isVideo;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant FileManagerThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.isDir != widget.entry.isDir ||
        oldWidget.entry.isArchive != widget.entry.isArchive ||
        oldWidget.entry.isImage != widget.entry.isImage ||
        oldWidget.entry.isVideo != widget.entry.isVideo) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (!_isEligible) {
      if (_bytes != null) setState(() => _bytes = null);
      return;
    }

    final path = widget.entry.path;
    _loadedPath = path;

    setState(() {
      _isLoading = true;
    });

    if (widget.entry.isVideo &&
        !widget.entry.isDir &&
        !widget.entry.isArchive &&
        !widget.entry.isImage) {
      final poster = await VideoPosterService.instance.posterForFile(path);
      if (!mounted || _loadedPath != path) return;
      setState(() {
        _bytes = poster;
        _isLoading = false;
      });
      return;
    }

    final bytes = await ReaderThumbnailService.instance
        .getFileManagerEntryThumbnailBytes(
          entryPath: path,
          isDir: widget.entry.isDir,
          isArchive: widget.entry.isArchive,
          isImage: widget.entry.isImage,
          maxLongSide:
              (widget.width > widget.height ? widget.width : widget.height) >
                  120
              ? 512
              : 320,
        );

    if (!mounted || _loadedPath != path) return;

    setState(() {
      _bytes = bytes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(6);

    Widget inner;
    if (_bytes != null && _bytes!.isNotEmpty) {
      inner = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _buildFallback(context),
      );
    } else if (_isLoading) {
      inner = _buildLoading(context);
    } else {
      inner = _buildFallback(context);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: radius,
        ),
        child: inner,
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final iconSize = (widget.height * 0.48).clamp(14.0, 24.0);
    return Center(
      child: Opacity(
        opacity: 0.45,
        child: Icon(
          _entryIcon(widget.entry),
          size: iconSize,
          color: _entryColor(context, widget.entry),
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final iconSize = (widget.height * 0.52).clamp(16.0, 26.0);
    return Center(
      child: Icon(
        _entryIcon(widget.entry),
        size: iconSize,
        color: _entryColor(context, widget.entry),
      ),
    );
  }

  IconData _entryIcon(FileManagerEntry entry) {
    if (entry.isDir) return Icons.folder_rounded;
    if (entry.isArchive) return Icons.auto_stories_rounded;
    if (entry.isImage) return Icons.image_outlined;
    if (entry.isVideo) return Icons.movie_outlined;
    if (entry.isAudio) return Icons.audio_file_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Color _entryColor(BuildContext context, FileManagerEntry entry) {
    final colors = Theme.of(context).colorScheme;
    if (entry.isDir) return colors.tertiary;
    if (entry.isArchive) return colors.primary;
    if (entry.isImage) return colors.secondary;
    if (entry.isVideo || entry.isAudio) return colors.secondary;
    return colors.outline;
  }
}
