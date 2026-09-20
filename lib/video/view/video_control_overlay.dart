/// 视频控制条：MD3 主题颜色、标准按钮/滑杆与 MenuAnchor 弹层。
/// 播放交互语义参考 neoview `features/video/ReaderVideoControlOverlay.tsx`。
///
/// 借过来的三条硬规则（都是上游踩过之后定下来的）：
/// 1. **自动隐藏 3 s，但暂停或钉住时常显** —— 暂停时收起等于把进度条藏起来，
///    用户下一步一定是「先让它出来」。
/// 2. **弹层打开期间不隐藏**（`shown = visible || anyPanelOpen`）。
/// 3. 拖动条上的**悬停帧预览**是 160×90、夹在 ±80 px 内，配一个 `formatVideoTime` 气泡。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:zephyr/i18n/strings.g.dart';

import 'package:flutter/material.dart';

import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';

/// 控制条文案。由上层从 i18n 构造，控件本身不碰 `context.t` ——
/// 这样这块 UI 可以脱离 App 的本地化管线被测试和预览。
@immutable
class VideoLabels {
  const VideoLabels({
    required this.play,
    required this.pause,
    required this.backward,
    required this.forward,
    required this.loop,
    required this.loopSingle,
    required this.loopOff,
    required this.speed,
    required this.volume,
    required this.subtitles,
    required this.subtitleOff,
    required this.filters,
    required this.resetFilters,
    required this.abLoop,
    required this.abClear,
    required this.screenshot,
    required this.audioOnly,
    required this.seekMode,
    required this.fullscreen,
    required this.pin,
    required this.info,
    required this.frameStepForward,
    required this.frameStepBackward,
    required this.pip,
    this.audio = '音轨',
    this.audioOff = '关闭音轨',
  });

  final String play;
  final String pause;
  final String backward;
  final String forward;
  final String loop;
  final String loopSingle;
  final String loopOff;
  final String speed;
  final String volume;
  final String subtitles;
  final String subtitleOff;
  final String filters;
  final String resetFilters;
  final String abLoop;
  final String abClear;
  final String screenshot;
  final String audioOnly;
  final String seekMode;
  final String fullscreen;
  final String pin;
  final String info;
  final String frameStepForward;
  final String frameStepBackward;
  final String pip;

  /// 音轨面板文案（多音轨片源用得上，见 `_TrackPanel`）。
  final String audio;
  final String audioOff;
}

/// 轨道选择面板（字幕与音轨共用）：`null` = 关闭这条输出。
class _TrackPanel extends StatelessWidget {
  const _TrackPanel({
    required this.tracks,
    required this.offLabel,
    required this.onSelected,
  });

  final List<VideoMediaTrack> tracks;
  final String offLabel;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedId = tracks.where((t) => t.selected).firstOrNull?.id;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              dense: true,
              title: Text(offLabel),
              leading: Icon(
                selectedId == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => onSelected(null),
            ),
            for (final track in tracks)
              ListTile(
                dense: true,
                title: Text(track.title),
                subtitle: track.language == null ? null : Text(track.language!),
                leading: Icon(
                  track.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => onSelected(track.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// 倍速档：neo 的滑杆区间 + 0.5/1/1.5/2 预设。
const List<double> kPlaybackRatePresets = <double>[0.5, 1.0, 1.5, 2.0];

/// 多个菜单共享可见性：关闭其中一个不能把其它仍打开的菜单算作已关闭。
class VideoPanelController extends ValueNotifier<bool> {
  VideoPanelController() : super(false);

  final Set<Object> _owners = <Object>{};
  bool _disposed = false;

  void setOpen(Object owner, bool open) {
    if (_disposed) return;
    if (open) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    value = _owners.isNotEmpty;
  }

  @override
  void dispose() {
    _disposed = true;
    _owners.clear();
    super.dispose();
  }
}

class VideoControlOverlay extends StatelessWidget {
  const VideoControlOverlay({
    super.key,
    required this.snapshot,
    required this.controller,
    required this.labels,
    required this.onTogglePin,
    required this.pinned,
    required this.panelsOpen,
    this.waveform = VideoWaveformStrip.empty,
    this.framePreview,
    this.filter,
    this.onFilterChanged,
    this.subtitleStyle,
    this.onSubtitleStyleChanged,
    this.onScreenshot,
    this.onFullscreen,
    this.onTogglePip,
    this.onOpenInfo,
    this.onSubtitleSelected,
    this.extraSubtitleTracks = const <VideoMediaTrack>[],
    this.audioOnlyAvailable = true,
    this.progressUpdates = true,
    this.controlUpdates,
  });

  final ReaderVideoSnapshot snapshot;
  final ReaderVideoController controller;
  final VideoLabels labels;
  final VoidCallback onTogglePin;
  final bool pinned;

  /// 任一弹层开着 —— 控制条的自动隐藏要让路给它（neo `shown = visible || anyPanelOpen`）。
  final VideoPanelController panelsOpen;

  /// 声音轮廓（mimage 的 seek strip wave）。空则进度条后面什么都不画。
  final VideoWaveformStrip waveform;
  final VideoFramePreviewProvider? framePreview;
  final VideoFilterState? filter;
  final ValueChanged<VideoFilterState>? onFilterChanged;
  final VideoSubtitleStyle? subtitleStyle;
  final ValueChanged<VideoSubtitleStyle>? onSubtitleStyleChanged;
  final Future<void> Function()? onScreenshot;
  final VoidCallback? onFullscreen;
  final VoidCallback? onTogglePip;
  final VoidCallback? onOpenInfo;
  final void Function(String? trackId)? onSubtitleSelected;

  /// 引擎不知道的外挂字幕轨（由宿主发现并登记，选中后由宿主的回调负责挂上）。
  final List<VideoMediaTrack> extraSubtitleTracks;
  final bool audioOnlyAvailable;

  /// 隐藏时停止进度 UI 订阅，视频纹理继续独立播放。
  final bool progressUpdates;

  /// 非进度状态的通知，打开倍速/音量面板时也不随位置反复刷新。
  final Listenable? controlUpdates;

  @override
  Widget build(BuildContext context) {
    final transport = controller.transport;
    final engineTracks = transport?.subtitleTracks ?? const <VideoMediaTrack>[];
    // 外挂字幕（同目录 / 同归档里的 srt/ass）也要能在同一个弹层里选：
    // neoview 的字幕弹层列的就是「服务端匹配到的轨 + 容器内轨」。
    final tracks = <VideoMediaTrack>[...engineTracks, ...extraSubtitleTracks];
    final audioTracks = transport?.audioTracks ?? const <VideoMediaTrack>[];
    final filterState = filter;
    final loops = <ReaderVideoLoopMode, (IconData, String)>{
      ReaderVideoLoopMode.list: (Icons.repeat, labels.loop),
      ReaderVideoLoopMode.single: (Icons.repeat_one, labels.loopSingle),
      ReaderVideoLoopMode.none: (Icons.repeat_on, labels.loopOff),
    };
    final loop = loops[snapshot.loopMode]!;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget menuAction(
      IconData icon,
      String label,
      VoidCallback? action, {
      bool selected = false,
    }) => MenuItemButton(
      leadingIcon: Icon(icon),
      trailingIcon: selected ? const Icon(Icons.check, size: 20) : null,
      onPressed: action,
      child: Text(label),
    );

    return Theme(
      data: theme.copyWith(
        sliderTheme: theme.sliderTheme.copyWith(
          trackHeight: 8,
          trackShape: const GappedSliderTrackShape(),
          thumbShape: const HandleThumbShape(),
          thumbSize: const WidgetStatePropertyAll(Size(4, 28)),
          trackGap: 4,
          activeTrackColor: colors.primary,
          inactiveTrackColor: colors.secondaryContainer,
        ),
      ),
      child: Material(
        key: const ValueKey('video-controls-surface'),
        color: colors.surfaceContainerHigh,
        elevation: 3,
        shadowColor: colors.shadow.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(24),
        textStyle: theme.textTheme.bodyMedium!.copyWith(
          color: colors.onSurface,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PositionBuilder(
                controller: controller,
                initialSnapshot: snapshot,
                enabled: progressUpdates,
                builder: (context, current) => RepaintBoundary(
                  child: _ScrubBar(
                    snapshot: current,
                    controller: controller,
                    framePreview: framePreview,
                    waveform: waveform,
                  ),
                ),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  IconButton.filled(
                    tooltip: snapshot.playing ? labels.pause : labels.play,
                    icon: Icon(
                      snapshot.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => controller.togglePlay(),
                  ),
                  _IconButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: labels.backward,
                    onPressed: () => controller.seekBackward(),
                  ),
                  _IconButton(
                    icon: Icons.forward_10_rounded,
                    tooltip: labels.forward,
                    onPressed: () => controller.seekForward(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _PositionBuilder(
                      controller: controller,
                      initialSnapshot: snapshot,
                      enabled: progressUpdates,
                      interval: const Duration(seconds: 1),
                      builder: (context, current) => RepaintBoundary(
                        child: Text(
                          '${formatVideoTime(current.currentTime)} / ${formatVideoTime(current.duration)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _TextButton(
                    label: '${_rateText(snapshot.playbackRate)}×',
                    tooltip: labels.speed,
                    active: snapshot.playbackRate != 1.0,
                    panelsOpen: panelsOpen,
                    builder: (context) => ListenableBuilder(
                      listenable: controlUpdates ?? controller,
                      builder: (context, _) => _RatePanel(
                        snapshot: controller.snapshot,
                        controller: controller,
                        labels: labels,
                      ),
                    ),
                  ),
                  _TextButton(
                    label: snapshot.muted
                        ? t.video.muted
                        : '${(snapshot.volume * 100).round()}%',
                    tooltip: labels.volume,
                    active: snapshot.muted,
                    panelsOpen: panelsOpen,
                    builder: (context) => ListenableBuilder(
                      listenable: controlUpdates ?? controller,
                      builder: (context, _) =>
                          _VolumePanel(controller: controller),
                    ),
                  ),
                  _TextButton(
                    label: labels.subtitles,
                    tooltip: labels.subtitles,
                    active: tracks.any((track) => track.selected),
                    panelsOpen: panelsOpen,
                    builder: (context) => _SubtitlePanel(
                      tracks: tracks,
                      labels: labels,
                      style: subtitleStyle ?? const VideoSubtitleStyle(),
                      onStyleChanged: onSubtitleStyleChanged,
                      onSelected: (id) {
                        final chosen = onSubtitleSelected;
                        if (chosen != null) {
                          chosen(id);
                        } else {
                          controller.transport?.selectSubtitleTrack(id);
                        }
                      },
                    ),
                  ),
                  if (audioTracks.length > 1)
                    _TextButton(
                      label: labels.audio,
                      tooltip: labels.audio,
                      panelsOpen: panelsOpen,
                      builder: (context) => _TrackPanel(
                        tracks: audioTracks,
                        offLabel: labels.audioOff,
                        onSelected: (id) => transport?.selectAudioTrack(id),
                      ),
                    ),
                  if (filterState != null && onFilterChanged != null)
                    _TextButton(
                      label: labels.filters,
                      tooltip: labels.filters,
                      active: !filterState.isDefault,
                      panelsOpen: panelsOpen,
                      builder: (context) => _FilterPanel(
                        filter: filterState,
                        labels: labels,
                        onChanged: onFilterChanged!,
                      ),
                    ),
                  _IconButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: labels.fullscreen,
                    onPressed: onFullscreen,
                  ),
                  _IconButton(
                    buttonKey: const ValueKey('video-pin-controls'),
                    icon: Icons.push_pin_outlined,
                    selectedIcon: Icons.push_pin_rounded,
                    tooltip: pinned ? t.reader.unpinBottomBar : labels.pin,
                    active: pinned,
                    onPressed: onTogglePin,
                  ),
                  _TextButton(
                    label: t.common.more,
                    tooltip: t.common.more,
                    icon: Icons.more_horiz_rounded,
                    panelsOpen: panelsOpen,
                    builder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        menuAction(
                          Icons.skip_previous_rounded,
                          labels.frameStepBackward,
                          () => controller.stepFrame(-1),
                        ),
                        menuAction(
                          Icons.skip_next_rounded,
                          labels.frameStepForward,
                          () => controller.stepFrame(1),
                        ),
                        menuAction(
                          loop.$1,
                          loop.$2,
                          controller.cycleLoopMode,
                          selected:
                              snapshot.loopMode != ReaderVideoLoopMode.none,
                        ),
                        menuAction(
                          Icons.repeat_rounded,
                          labels.abLoop,
                          controller.tapAbLoop,
                          selected:
                              snapshot.abLoop != null ||
                              controller.markedPointA != null,
                        ),
                        if (snapshot.abLoop != null ||
                            controller.markedPointA != null)
                          menuAction(
                            Icons.clear,
                            labels.abClear,
                            controller.clearAbLoop,
                          ),
                        const Divider(),
                        menuAction(
                          Icons.photo_camera_outlined,
                          labels.screenshot,
                          onScreenshot == null ? null : () => onScreenshot!(),
                        ),
                        menuAction(
                          Icons.fast_forward_rounded,
                          labels.seekMode,
                          controller.toggleSeekMode,
                          selected: snapshot.seekMode,
                        ),
                        if (audioOnlyAvailable)
                          menuAction(
                            Icons.music_note_rounded,
                            labels.audioOnly,
                            () => controller.setAudioOnly(!snapshot.audioOnly),
                            selected: snapshot.audioOnly,
                          ),
                        menuAction(
                          Icons.picture_in_picture_alt_rounded,
                          labels.pip,
                          onTogglePip,
                        ),
                        menuAction(
                          Icons.info_outline_rounded,
                          labels.info,
                          onOpenInfo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  Timer? _previewDebounce;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  void _onHover(PointerEvent event, Size size) {
    final duration = widget.snapshot.duration;
    if (duration <= Duration.zero) return;
    final fraction =
        ((event.localPosition.dx - 12) / math.max(1, size.width - 24)).clamp(
          0.0,
          1.0,
        );
    final at = duration * fraction;
    // 已经解出来的帧立刻显示：去抖窗口里先亮一个转圈，划过缓存区时会闪个不停。
    final cached = widget.framePreview?.peek(at);
    setState(() {
      _hoverAt = at;
      _hoverLocal = event.localPosition;
      if (cached != null) _previewFrame = cached;
    });
    _previewDebounce?.cancel();
    // 120 ms 去抖：鼠标划过整条时间轴不该触发二十次解帧。
    _previewDebounce = Timer(const Duration(milliseconds: 120), () async {
      final frame = await widget.framePreview?.request(at);
      if (mounted) setState(() => _previewFrame = frame);
    });
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
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _onHover(e, box.size);
      },
      onExit: (_) {
        _previewDebounce?.cancel();
        setState(() {
          _hoverAt = null;
          _previewFrame = null;
        });
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
                    ),
                  ),
              ],
            ),
          );
        },
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

String _rateText(double rate) => rate == rate.roundToDouble()
    ? rate.toStringAsFixed(0)
    : rate.toStringAsFixed(2);

class _FramePreviewBubble extends StatelessWidget {
  const _FramePreviewBubble({required this.at, required this.frame});

  final Duration at;
  final VideoFramePreview? frame;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (frame != null)
            Image.file(
              File(frame!.filePath),
              width: 160,
              height: 90,
              fit: BoxFit.contain,
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

class _RatePanel extends StatelessWidget {
  const _RatePanel({
    required this.snapshot,
    required this.controller,
    required this.labels,
  });

  final ReaderVideoSnapshot snapshot;
  final ReaderVideoController controller;
  final VideoLabels labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Slider(
              min: snapshot.minimumPlaybackRate,
              max: snapshot.maximumPlaybackRate,
              divisions:
                  ((snapshot.maximumPlaybackRate -
                              snapshot.minimumPlaybackRate) /
                          snapshot.playbackRateStep)
                      .round()
                      .clamp(1, 200),
              value: snapshot.playbackRate.clamp(
                snapshot.minimumPlaybackRate,
                snapshot.maximumPlaybackRate,
              ),
              onChanged: (v) => controller.setPlaybackRate(v),
            ),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final preset in kPlaybackRatePresets)
                  ChoiceChip(
                    label: Text('${preset}x'),
                    selected: snapshot.playbackRate == preset,
                    onSelected: (_) => controller.setPlaybackRate(preset),
                  ),
                TextButton(
                  onPressed: controller.toggleSpeed,
                  child: const Text('1x ⇄'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.controller});

  final ReaderVideoController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 200,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: Icon(snapshot.muted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => controller.toggleMute(),
            ),
            Expanded(
              // 步长 5%：上游的 0.05，一格一个可感知的音量变化。
              child: Slider(
                value: snapshot.volume,
                divisions: 20,
                onChanged: (v) => controller.setVolume(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitlePanel extends StatelessWidget {
  const _SubtitlePanel({
    required this.tracks,
    required this.labels,
    required this.style,
    required this.onStyleChanged,
    required this.onSelected,
  });

  final List<VideoMediaTrack> tracks;
  final VideoLabels labels;
  final VideoSubtitleStyle style;
  final ValueChanged<VideoSubtitleStyle>? onStyleChanged;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedId = tracks.where((t) => t.selected).firstOrNull?.id;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              dense: true,
              title: Text(labels.subtitleOff),
              leading: Icon(
                selectedId == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => onSelected(null),
            ),
            for (final track in tracks)
              ListTile(
                dense: true,
                title: Text(track.title),
                subtitle: track.language == null ? null : Text(track.language!),
                leading: Icon(
                  track.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => onSelected(track.id),
              ),
            if (onStyleChanged != null) ...<Widget>[
              const Divider(height: 16),
              _LabeledSlider(
                label: t.video.subSize,
                value: style.sizeEm,
                min: 0.5,
                max: 3,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: v,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: style.backgroundOpacityPercent,
                    bottomPercent: style.bottomPercent,
                  ),
                ),
              ),
              _LabeledSlider(
                label: t.video.subBg,
                value: style.backgroundOpacityPercent.toDouble(),
                min: 0,
                max: 100,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: style.sizeEm,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: v.round(),
                    bottomPercent: style.bottomPercent,
                  ),
                ),
              ),
              _LabeledSlider(
                label: t.video.subBottom,
                value: style.bottomPercent.toDouble(),
                min: 0,
                max: 30,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: style.sizeEm,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: style.backgroundOpacityPercent,
                    bottomPercent: v.round(),
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final color in const <String>[
                    'ffffff',
                    'ffe066',
                    '7cc4ff',
                    'ff8a8a',
                    'a6e3a1',
                  ])
                    _ColorDot(
                      hex: color,
                      selected: style.colorHex == color,
                      onTap: () => onStyleChanged!(
                        VideoSubtitleStyle(
                          sizeEm: style.sizeEm,
                          colorHex: color,
                          backgroundOpacityPercent:
                              style.backgroundOpacityPercent,
                          bottomPercent: style.bottomPercent,
                        ),
                      ),
                    ),
                  TextButton(
                    // 「大号黄色」预设：上游把它作为一个一键项保留，因为
                    // 白底黑框的老式字幕在浅色页面上几乎读不出来。
                    onPressed: () => onStyleChanged!(
                      const VideoSubtitleStyle(
                        sizeEm: 1.6,
                        colorHex: 'ffe066',
                        backgroundOpacityPercent: 70,
                        bottomPercent: 5,
                      ),
                    ),
                    child: Text(t.video.subLargeYellow),
                  ),
                  TextButton(
                    onPressed: () =>
                        onStyleChanged!(const VideoSubtitleStyle()),
                    child: Text(t.video.reset),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    final color = Color(0xFF000000 | parsed);
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '#$hex',
      isSelected: selected,
      onPressed: onTap,
      style: IconButton.styleFrom(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      icon: CircleAvatar(radius: 12, backgroundColor: color),
      selectedIcon: CircleAvatar(
        radius: 12,
        backgroundColor: color,
        child: Icon(
          Icons.check,
          size: 18,
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.light
              ? Colors.black
              : Colors.white,
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filter,
    required this.labels,
    required this.onChanged,
  });

  final VideoFilterState filter;
  final VideoLabels labels;
  final ValueChanged<VideoFilterState> onChanged;

  @override
  Widget build(BuildContext context) {
    // 0–200%：100 = 原样。上限 200 而不是 100 是 neo 的口径 ——
    // 「增强」需要往上一半的空间，往下只需要一半。
    Widget row(String label, int value, void Function(int) set) =>
        _LabeledSlider(
          label: label,
          value: value.toDouble(),
          min: 0,
          max: 200,
          onChanged: (v) => set(v.round()),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            row(
              t.video.brightness,
              filter.brightness,
              (v) => onChanged(filter.copyWith(brightness: v)),
            ),
            row(
              t.video.contrast,
              filter.contrast,
              (v) => onChanged(filter.copyWith(contrast: v)),
            ),
            row(
              t.video.saturation,
              filter.saturation,
              (v) => onChanged(filter.copyWith(saturation: v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onChanged(VideoFilterState.neutral),
                child: Text(labels.resetFilters),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                value == value.roundToDouble()
                    ? '${value.round()}'
                    : value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.selectedIcon,
    this.buttonKey,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    if (selectedIcon != null) {
      return IconButton.filledTonal(
        key: buttonKey,
        tooltip: tooltip,
        isSelected: active,
        icon: Icon(icon),
        selectedIcon: Icon(selectedIcon),
        onPressed: onPressed,
      );
    }
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _TextButton extends StatefulWidget {
  const _TextButton({
    required this.label,
    required this.tooltip,
    required this.builder,
    required this.panelsOpen,
    this.active = false,
    this.icon,
  });

  final String label;
  final String tooltip;
  final WidgetBuilder builder;
  final VideoPanelController panelsOpen;
  final bool active;
  final IconData? icon;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  final MenuController _menu = MenuController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    // 菜单随页面销毁时不保证触发 onClose；延后通知，避开 widget 树的销毁阶段。
    final panels = widget.panelsOpen;
    scheduleMicrotask(() => panels.setOpen(this, false));
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      onOpen: () => widget.panelsOpen.setOpen(this, true),
      onClose: () => widget.panelsOpen.setOpen(this, false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(
              328,
              math.max(0, MediaQuery.sizeOf(context).width - 32),
            ),
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SingleChildScrollView(
            primary: false,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.onSurface,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      widget.tooltip,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Builder(builder: widget.builder),
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, menu, _) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        if (widget.icon != null) {
          return IconButton(
            focusNode: _focus,
            tooltip: widget.tooltip,
            icon: Icon(widget.icon),
            onPressed: toggle,
          );
        }
        return TextButton(
          focusNode: _focus,
          onPressed: toggle,
          style: TextButton.styleFrom(
            foregroundColor: widget.active || menu.isOpen
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
            backgroundColor: widget.active || menu.isOpen
                ? colors.secondaryContainer
                : Colors.transparent,
            minimumSize: const Size(48, 40),
          ),
          child: Tooltip(message: widget.tooltip, child: Text(widget.label)),
        );
      },
    );
  }
}
