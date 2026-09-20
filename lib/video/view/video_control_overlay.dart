/// 视频控制条 —— 布局、显隐节奏与弹层内容照 neoview
/// `features/video/ReaderVideoControlOverlay.tsx:44-359`。
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
                subtitle: track.language == null
                    ? null
                    : Text(track.language!),
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
  });

  final ReaderVideoSnapshot snapshot;
  final ReaderVideoController controller;
  final VideoLabels labels;
  final VoidCallback onTogglePin;
  final bool pinned;

  /// 任一弹层开着 —— 控制条的自动隐藏要让路给它（neo `shown = visible || anyPanelOpen`）。
  final ValueNotifier<bool> panelsOpen;

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ScrubBar(
          snapshot: snapshot,
          controller: controller,
          framePreview: framePreview,
          waveform: waveform,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.start,
            children: <Widget>[
              _IconButton(
                icon: snapshot.playing ? Icons.pause : Icons.play_arrow,
                tooltip: snapshot.playing ? labels.pause : labels.play,
                onPressed: () => controller.togglePlay(),
              ),
              _IconButton(
                icon: Icons.replay_10,
                tooltip: labels.backward,
                onPressed: () => controller.seekBackward(),
              ),
              _IconButton(
                icon: Icons.forward_10,
                tooltip: labels.forward,
                onPressed: () => controller.seekForward(),
              ),
              _IconButton(
                icon: Icons.skip_previous,
                tooltip: labels.frameStepBackward,
                onPressed: () => controller.stepFrame(-1),
              ),
              _IconButton(
                icon: Icons.skip_next,
                tooltip: labels.frameStepForward,
                onPressed: () => controller.stepFrame(1),
              ),
              _IconButton(
                icon: loop.$1,
                tooltip: loop.$2,
                active: snapshot.loopMode != ReaderVideoLoopMode.none,
                onPressed: controller.cycleLoopMode,
              ),
              _TextButton(
                label: '${_rateText(snapshot.playbackRate)}x',
                tooltip: labels.speed,
                active: snapshot.playbackRate != 1.0,
                panelsOpen: panelsOpen,
                builder: (context) => _RatePanel(
                  snapshot: snapshot,
                  controller: controller,
                  labels: labels,
                ),
              ),
              _TextButton(
                label: snapshot.muted ? t.video.muted : '${(snapshot.volume * 100).round()}%',
                tooltip: labels.volume,
                active: snapshot.muted,
                panelsOpen: panelsOpen,
                builder: (context) => _VolumePanel(controller: controller),
              ),
              _TextButton(
                label: labels.subtitles,
                tooltip: labels.subtitles,
                active: tracks.any((t) => t.selected),
                panelsOpen: panelsOpen,
                builder: (context) => _SubtitlePanel(
                  tracks: tracks,
                  labels: labels,
                  style: subtitleStyle ?? const VideoSubtitleStyle(),
                  onStyleChanged: onSubtitleStyleChanged,
                  onSelected: (id) {
                    // 有宿主回调时**只走回调**：外挂轨要先落盘再 sub-add，
                    // 直接叫 transport.selectSubtitleTrack 会把文件路径当轨道号。
                    final chosen = onSubtitleSelected;
                    if (chosen != null) {
                      chosen(id);
                    } else {
                      controller.transport?.selectSubtitleTrack(id);
                    }
                  },
                ),
              ),
              // 音轨（mimage `set_audio_track`）：接口早就在 transport 上，
              // 但没有面板就等于「登记了却没实现」。多音轨片源（中日双语、评论音轨）
              // 全靠这一条。
              if (audioTracks.length > 1)
                _TextButton(
                  label: labels.audio,
                  tooltip: labels.audio,
                  active: audioTracks.any((t) => t.selected),
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
                icon: Icons.low_priority,
                tooltip: labels.abLoop,
                active: snapshot.abLoop != null || controller.markedPointA != null,
                onPressed: controller.tapAbLoop,
              ),
              if (snapshot.abLoop != null)
                _IconButton(
                  icon: Icons.clear,
                  tooltip: labels.abClear,
                  onPressed: controller.clearAbLoop,
                ),
              _IconButton(
                icon: Icons.photo_camera_outlined,
                tooltip: labels.screenshot,
                onPressed: onScreenshot == null ? null : () => onScreenshot!(),
              ),
              _IconButton(
                icon: snapshot.seekMode ? Icons.fast_forward : Icons.my_location,
                tooltip: labels.seekMode,
                active: snapshot.seekMode,
                onPressed: controller.toggleSeekMode,
              ),
              if (audioOnlyAvailable)
                _IconButton(
                  icon: snapshot.audioOnly ? Icons.music_note : Icons.videocam,
                  tooltip: labels.audioOnly,
                  active: snapshot.audioOnly,
                  onPressed: () => controller.setAudioOnly(!snapshot.audioOnly),
                ),
              _IconButton(
                icon: Icons.picture_in_picture_alt,
                tooltip: labels.pip,
                onPressed: onTogglePip,
              ),
              _IconButton(
                icon: Icons.fullscreen,
                tooltip: labels.fullscreen,
                onPressed: onFullscreen,
              ),
              _IconButton(
                icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                tooltip: labels.pin,
                active: pinned,
                onPressed: onTogglePin,
              ),
              _IconButton(
                icon: Icons.info_outline,
                tooltip: labels.info,
                onPressed: onOpenInfo,
              ),
              const SizedBox(width: 4),
              Text(
                '${formatVideoTime(snapshot.currentTime)} / '
                '${formatVideoTime(snapshot.duration)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final fraction = (event.position.dx / size.width).clamp(0.0, 1.0);
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
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _onHover(e, box.size);
      },
      onExit: (_) => setState(() {
        _hoverAt = null;
        _previewFrame = null;
      }),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          void seekAt(double dx) =>
              widget.controller.seekFraction((dx / width).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 30,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 13,
                    child: _ProgressBar(
                      snapshot: snapshot,
                      chapters: chapters,
                      abLoopColor: Colors.amberAccent,
                      waveform: widget.waveform,
                    ),
                  ),
                  if (_hoverAt != null && snapshot.duration > Duration.zero)
                    Positioned(
                      // 预览气泡夹在 ±80 px 内（neo 的同一条约束），
                      // 否则拖到两端时气泡会被裁掉一半。
                      left: ((_hoverLocal!.dx - 80).clamp(0.0, width - 160)),
                      bottom: 26,
                      child: _FramePreviewBubble(
                        at: _hoverAt!,
                        frame: _previewFrame,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 进度轨道：底槽 + 已播 + A–B 区间 + 章节刻度 + 滑块圆点。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.snapshot,
    required this.chapters,
    required this.abLoopColor,
    this.waveform = VideoWaveformStrip.empty,
  });

  final ReaderVideoSnapshot snapshot;
  final List<VideoChapter> chapters;
  final Color abLoopColor;
  final VideoWaveformStrip waveform;

  @override
  Widget build(BuildContext context) {
    final durationMs = snapshot.duration.inMilliseconds == 0
        ? 1
        : snapshot.duration.inMilliseconds;
    final progress = snapshot.progress;
    final ab = snapshot.abLoop;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x(Duration at) => (at.inMilliseconds / durationMs) * width;
        return SizedBox(
          height: 12,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: <Widget>[
              // 声音轮廓垫在最下面（mimage 的 seek strip wave）：它只是底纹，
              // 没有音轨或解码失败时整条不画，不占位也不报错。
              if (!waveform.isEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WaveformPainter(waveform),
                  ),
                ),
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: waveform.isEmpty
                      ? Colors.white24
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (ab != null)
                Positioned(
                  left: x(ab.a).clamp(0, width),
                  width: (x(ab.b) - x(ab.a)).clamp(0, width),
                  child: Container(
                    height: 4,
                    color: abLoopColor.withValues(alpha: 0.5),
                  ),
                ),
              FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              for (final chapter in chapters)
                if (chapter.at > Duration.zero)
                  Positioned(
                    left: x(chapter.at).clamp(0, width),
                    child: Container(width: 2, height: 12, color: Colors.white38),
                  ),
              Positioned(
                left: (progress * width - 5).clamp(-5, width - 5),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 波形条绘制：一格一根竖条，居中对称。
///
/// 刻意不用 `ui.Path` 描轮廓 —— 180 根竖条在 300 px 宽度上读起来才像 mimage
/// 那种「响度柱」，折线在小尺寸上会糊成一团。
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.strip);

  final VideoWaveformStrip strip;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = strip.samples;
    if (samples.isEmpty || size.width <= 0) return;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);
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
  bool shouldRepaint(_WaveformPainter old) => old.strip != strip;
}

String _rateText(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2);

class _FramePreviewBubble extends StatelessWidget {
  const _FramePreviewBubble({required this.at, required this.frame});

  final Duration at;
  final VideoFramePreview? frame;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 160,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
            image: frame == null
                ? null
                : DecorationImage(
                    image: FileImage(File(frame!.filePath)),
                    fit: BoxFit.contain,
                  ),
          ),
          child: frame == null
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 2),
        Text(
          formatVideoTime(at),
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ],
    );
  }
}

class _RatePanel extends StatelessWidget {
  const _RatePanel({required this.snapshot, required this.controller, required this.labels});

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
              divisions: ((snapshot.maximumPlaybackRate - snapshot.minimumPlaybackRate) / snapshot.playbackRateStep).round().clamp(1, 200),
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
                selectedId == null ? Icons.radio_button_checked : Icons.radio_button_off,
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
                          backgroundOpacityPercent: style.backgroundOpacityPercent,
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
                    onPressed: () => onStyleChanged!(const VideoSubtitleStyle()),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | parsed),
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.white24, width: 2),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({required this.filter, required this.labels, required this.onChanged});

  final VideoFilterState filter;
  final VideoLabels labels;
  final ValueChanged<VideoFilterState> onChanged;

  @override
  Widget build(BuildContext context) {
    // 0–200%：100 = 原样。上限 200 而不是 100 是 neo 的口径 ——
    // 「增强」需要往上一半的空间，往下只需要一半。
    Widget row(String label, int value, void Function(int) set) => _LabeledSlider(
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
            row(t.video.brightness, filter.brightness, (v) => onChanged(filter.copyWith(brightness: v))),
            row(t.video.contrast, filter.contrast, (v) => onChanged(filter.copyWith(contrast: v))),
            row(t.video.saturation, filter.saturation, (v) => onChanged(filter.copyWith(saturation: v))),
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
        Text('$label ${value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          color: active ? Colors.white24 : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
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
  });

  final String label;
  final String tooltip;
  final WidgetBuilder builder;
  final ValueNotifier<bool> panelsOpen;
  final bool active;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _open = false;

  @override
  void dispose() {
    // 被销毁时还开着的话要把计数减回去，否则控制条会永久停在「常显」。
    if (_open) _report(false);
    super.dispose();
  }

  void _report(bool open) {
    widget.panelsOpen.value = open;
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    _open = open;
    _report(open);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Tooltip(
          message: widget.tooltip,
          child: InkWell(
            onTap: () => _setOpen(!_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.active ? Colors.amberAccent : Colors.white,
                ),
              ),
            ),
          ),
        ),
        if (_open) ...<Widget>[
          // 点弹层外面要能关掉：盖一层透明全屏手势层。
          Positioned(
            left: 0,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _setOpen(false),
              child: const SizedBox.shrink(),
            ),
          ),
          Positioned(
            bottom: 34,
            left: 0,
            child: Material(
              elevation: 8,
              color: const Color(0xE6000000),
              borderRadius: BorderRadius.circular(8),
              child: Builder(builder: widget.builder),
            ),
          ),
        ],
      ],
    );
  }
}
