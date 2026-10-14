import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/online_image_processing.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';

/// 已解析的原图先显示；处理结果到位、模型或参数变化后切换，不再覆写下载文件。
class EnhancedOnlinePage extends StatefulWidget {
  const EnhancedOnlinePage({
    super.key,
    required this.sourcePath,
    this.bookKey,
    required this.builder,
  });
  final String sourcePath;
  final String? bookKey;
  final Widget Function(BuildContext, String) builder;
  @override
  State<EnhancedOnlinePage> createState() => _EnhancedOnlinePageState();
}

class _EnhancedOnlinePageState extends State<EnhancedOnlinePage> {
  String? _processedPath;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ImageDenoiseSettings.changes.addListener(_reload);
    RealSrBookScope.changes.addListener(_reload);
    RealSrSettings.modelChanges.addListener(_reload);
    unawaited(_process());
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _processedPath = null);
    unawaited(_process());
  }

  Future<void> _process() async {
    final generation = ++_generation;
    final source = widget.sourcePath;
    final book = widget.bookKey;
    try {
      final path = await OnlineImageProcessing.process(source, bookKey: book);
      if (!mounted ||
          generation != _generation ||
          widget.sourcePath != source ||
          widget.bookKey != book) {
        return;
      }
      setState(() => _processedPath = path);
    } catch (e, s) {
      logger.w('在线图像处理失败，继续显示原图', error: e, stackTrace: s);
    }
  }

  @override
  void didUpdateWidget(covariant EnhancedOnlinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.bookKey != widget.bookKey) {
      _processedPath = null;
      unawaited(_process());
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: OnlineImageProcessing.originalPreview,
    builder: (context, _, _) => widget.builder(
      context,
      OnlineImageProcessing.previewsOriginal(widget.bookKey)
          ? widget.sourcePath
          : _processedPath ?? widget.sourcePath,
    ),
  );

  @override
  void dispose() {
    _generation++;
    ImageDenoiseSettings.changes.removeListener(_reload);
    RealSrBookScope.changes.removeListener(_reload);
    RealSrSettings.modelChanges.removeListener(_reload);
    super.dispose();
  }
}
