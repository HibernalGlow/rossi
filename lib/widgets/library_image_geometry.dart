import 'package:material_ui/material_ui.dart';

/// 图片消费者向所在展墙报告尺寸，复用已有 ImageProvider 的解码缓存。
class LibraryImageGeometryScope extends InheritedWidget {
  const LibraryImageGeometryScope({
    super.key,
    required this.onRatio,
    required this.keepFullImage,
    this.imageScale = 1,
    required super.child,
  });
  final ValueChanged<double> onRatio;
  final bool keepFullImage;
  final double imageScale;
  static LibraryImageGeometryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryImageGeometryScope>();
  @override
  bool updateShouldNotify(LibraryImageGeometryScope oldWidget) =>
      oldWidget.keepFullImage != keepFullImage ||
      oldWidget.onRatio != onRatio ||
      oldWidget.imageScale != imageScale;
}

class LibraryImageGeometryReporter extends StatefulWidget {
  const LibraryImageGeometryReporter({
    super.key,
    required this.provider,
    required this.child,
  });
  final ImageProvider provider;
  final Widget child;
  @override
  State<LibraryImageGeometryReporter> createState() =>
      _LibraryImageGeometryReporterState();
}

class _LibraryImageGeometryReporterState
    extends State<LibraryImageGeometryReporter> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  LibraryImageGeometryScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(LibraryImageGeometryReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _listen();
  }

  void _listen() {
    _scope = LibraryImageGeometryScope.maybeOf(context);
    if (_scope == null) {
      _detach();
      return;
    }
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      final ratio = info.image.width / info.image.height;
      // ImageInfo 属于这个 listener，不能一直持有已解码图片。
      info.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stream?.key == stream.key) _scope?.onRatio(ratio);
      });
    }, onError: (_, _) {});
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
