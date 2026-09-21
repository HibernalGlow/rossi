part of '../video_control_overlay.dart';
// 进度与拖动预览：位置节流构建器、拖动条、进度条与波形、帧预览气泡


/// 播放时进度最多 10 Hz、时钟最多 1 Hz；暂停定位与操作状态改变立即更新。
/// 只在可见时订阅，避免隐藏的 MD3 Slider 动画继续占用 UI 帧。
class _PositionBuilder extends StatefulWidget {
  const _PositionBuilder({
    required this.controller,
    required this.initialSnapshot,
    required this.enabled,
    required this.builder,
    this.interval = const Duration(milliseconds: 100),
  });

  final ReaderVideoController controller;
  final ReaderVideoSnapshot initialSnapshot;
  final bool enabled;
  final Duration interval;
  final Widget Function(BuildContext, ReaderVideoSnapshot) builder;

  @override
  State<_PositionBuilder> createState() => _PositionBuilderState();
}


class _PositionBuilderState extends State<_PositionBuilder> {
  late ReaderVideoSnapshot _snapshot = widget.initialSnapshot;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(_PositionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.enabled != widget.enabled) {
      if (oldWidget.enabled) oldWidget.controller.removeListener(_update);
      if (widget.enabled) widget.controller.addListener(_update);
    }
    _snapshot = widget.initialSnapshot;
  }

  void _update() {
    final next = widget.controller.snapshot;
    final step = widget.interval.inMicroseconds;
    if (next.playing &&
        _snapshot.playing &&
        next.duration == _snapshot.duration &&
        next.currentTime.inMicroseconds ~/ step ==
            _snapshot.currentTime.inMicroseconds ~/ step) {
      return;
    }
    setState(() => _snapshot = next);
  }

  @override
  void dispose() {
    if (widget.enabled) widget.controller.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}


/// 拖动条：进度 + 已缓冲 + 章节刻度 + A–B 区间 + 悬停帧预览。
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.snapshot,
    required this.controller,
    this.framePreview,
    this.waveform = VideoWaveformStrip.empty,
  });

  final ReaderVideoSnapshot snapshot;
  final ReaderVideoController controller;
  final VideoFramePreviewProvider? framePreview;
  final VideoWaveformStrip waveform;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}


class _ScrubBarState extends State<_ScrubBar> {
  Duration? _hoverAt;
  Offset? _hoverLocal;
  VideoFramePreview? _previewFrame;

  /// 挂着的这一帧不是 [_hoverAt] 那一刻的画面（正在解 / 解不出来）。
  /// 上游为此给预览盖一个「定位中」，否则用户看到的是一张时间对不上的图。
  bool _previewStale = false;
  Timer? _previewDebounce;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  /// 指针位置 → 预览位置。**只解帧，不 seek** —— 落点归 Slider 的点击与拖动管，
  /// 悬停唯一的作用是让用户先看见他要跳到哪儿。
  void _updatePreview(Offset local, Size size) {
    final duration = widget.snapshot.duration;
    if (duration <= Duration.zero) return;
    final fraction = ((local.dx - 12) / math.max(1, size.width - 24)).clamp(
      0.0,
      1.0,
    );
    final at = duration * fraction;
    // 已经解出来的帧立刻显示：去抖窗口里先亮一个转圈，划过缓存区时会闪个不停。
    final cached = widget.framePreview?.peek(at);
    setState(() {
      _hoverAt = at;
      _hoverLocal = local;
      if (cached != null) {
        _previewFrame = cached;
        _previewStale = false;
      } else {
        // 上一帧继续挂着当占位，但标记它不是这个位置的。
        _previewStale = true;
      }
    });
    _previewDebounce?.cancel();
    // 120 ms 去抖：鼠标划过整条时间轴不该触发二十次解帧。
    _previewDebounce = Timer(const Duration(milliseconds: 120), () async {
      final frame = await widget.framePreview?.request(at);
      // 结果回来时鼠标已经划走了：这一帧对不上现在的位置，丢掉。
      if (!mounted || _hoverAt != at) return;
      setState(() {
        if (frame != null) _previewFrame = frame;
        _previewStale = frame == null;
      });
    });
  }

  void _previewFrom(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) _updatePreview(local, box.size);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final chapters = snapshot.active
        ? (widget.controller.transport?.metadata.chapters ??
              const <VideoChapter>[])
        : const <VideoChapter>[];

    return MouseRegion(
      key: const ValueKey('video-progress-bar'),
      onHover: (e) => _previewFrom(e.localPosition),
      onExit: (_) {
        _previewDebounce?.cancel();
        setState(() {
          _hoverAt = null;
          _previewFrame = null;
          _previewStale = false;
        });
      },
      // 按下期间只有 move 事件（`MouseRegion.onHover` 收不到 PointerMoveEvent），
      // 所以拖进度条时预览要靠这一路才跟手。触摸不参与：手指盖住的预览没有意义。
      child: Listener(
        onPointerMove: (e) {
          if (e.kind != PointerDeviceKind.mouse &&
              e.kind != PointerDeviceKind.stylus) {
            return;
          }
          _previewFrom(e.localPosition);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            return SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: _ProgressBar(
                      snapshot: snapshot,
                      chapters: chapters,
                      waveform: widget.waveform,
                      onChanged: widget.controller.seekFraction,
                    ),
                  ),
                  if (_hoverAt != null && snapshot.duration > Duration.zero)
                    Positioned(
                      left: (_hoverLocal!.dx - 80).clamp(
                        0.0,
                        math.max(0, width - 160),
                      ),
                      bottom: 36,
                      child: _FramePreviewBubble(
                        at: _hoverAt!,
                        frame: _previewFrame,
                        stale: _previewStale,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


/// 使用 MD3 Slider 提供拖动、键盘操作和进度语义，波形与章节仅作底纹。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.snapshot,
    required this.chapters,
    required this.onChanged,
    this.waveform = VideoWaveformStrip.empty,
  });

  final ReaderVideoSnapshot snapshot;
  final List<VideoChapter> chapters;
  final ValueChanged<double> onChanged;
  final VideoWaveformStrip waveform;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final durationMs = math.max(1, snapshot.duration.inMilliseconds);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          left: 12,
          right: 12,
          top: 8,
          bottom: 8,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double x(Duration at) =>
                  (at.inMilliseconds / durationMs * width).clamp(0, width);
              final ab = snapshot.abLoop;
              return Stack(
                children: <Widget>[
                  if (!waveform.isEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          waveform,
                          colors.onSurfaceVariant.withValues(alpha: 0.24),
                        ),
                      ),
                    ),
                  if (ab != null)
                    Positioned(
                      left: x(ab.a),
                      width: math.max(0, x(ab.b) - x(ab.a)),
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(color: colors.tertiaryContainer),
                    ),
                  for (final chapter in chapters)
                    if (chapter.at > Duration.zero)
                      Positioned(
                        left: x(chapter.at),
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: colors.outlineVariant,
                          child: const SizedBox(width: 2),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        Slider(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          value: snapshot.progress,
          onChanged: snapshot.duration > Duration.zero ? onChanged : null,
          semanticFormatterCallback: (value) =>
              formatVideoTime(snapshot.duration * value),
        ),
      ],
    );
  }
}


/// 波形条绘制：一格一根竖条，居中对称。
///
/// 刻意不用 `ui.Path` 描轮廓 —— 180 根竖条在 300 px 宽度上读起来才像 mimage
/// 那种「响度柱」，折线在小尺寸上会糊成一团。
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.strip, this.color);

  final VideoWaveformStrip strip;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = strip.samples;
    if (samples.isEmpty || size.width <= 0) return;
    final paint = Paint()..color = color;
    final slot = size.width / samples.length;
    // 柱子至少 1 px 宽，否则 180 格在窄栏里会画成一条灰带。
    final barWidth = math.max(1.0, slot * 0.62);
    final midY = size.height / 2;
    for (var i = 0; i < samples.length; i++) {
      final amplitude = samples[i].clamp(0.04, 1.0);
      final half = amplitude * (size.height / 2);
      final left = i * slot + (slot - barWidth) / 2;
      canvas.drawRect(
        Rect.fromLTWH(left, midY - half, barWidth, half * 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.strip != strip || old.color != color;
}


class _FramePreviewBubble extends StatelessWidget {
  const _FramePreviewBubble({
    required this.at,
    required this.frame,
    required this.stale,
  });

  final Duration at;
  final VideoFramePreview? frame;

  /// 挂着的这一帧不是 [at] 那一刻的画面：还没有帧就给空框 + 转圈，
  /// 有旧帧就让它继续挂着但盖一个角标 —— 不能让用户以为这就是那一刻。
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = frame;
    return Material(
      color: colors.surfaceContainerHighest,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 160,
            height: 90,
            child: preview == null
                ? const Center(child: _PreviewBusyChip())
                : Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.file(File(preview.filePath), fit: BoxFit.contain),
                      if (stale)
                        const Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: _PreviewBusyChip(),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              formatVideoTime(at),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}


/// 「定位中」角标：解帧没回来 / 回来的不是这一格。
class _PreviewBusyChip extends StatelessWidget {
  const _PreviewBusyChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('video-preview-busy'),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.86),
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
      ),
    );
  }
}
