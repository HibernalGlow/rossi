/// 视频控制条：MD3 主题颜色、标准按钮/滑杆与 MenuAnchor 弹层。
/// 播放交互语义参考 neoview `features/video/ReaderVideoControlOverlay.tsx`。
///
/// 借过来的三条硬规则（都是上游踩过之后定下来的）：
/// 1. **自动隐藏 3 s，但暂停或钉住时常显** —— 暂停时收起等于把进度条藏起来，
///    用户下一步一定是「先让它出来」。
/// 2. **弹层打开期间不隐藏**（`shown = visible || anyPanelOpen`）。
/// 3. 拖动条上的**悬停帧预览**是 160×90、夹在 ±80 px 内，配一个 `formatVideoTime` 气泡；
///    **悬停只预览，不改变播放位置** —— 落点归 Slider 的点击与拖动，预览由自带解码器解帧。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:zephyr/i18n/strings.g.dart';

import 'package:flutter/material.dart';

import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';

// 进度与拖动预览：位置构建器、拖动条、进度条、波形与帧预览气泡。
part 'parts/video_overlay_scrub_part.dart';
// 弹层面板：倍速、音量、字幕、滤镜与滑杆行。
part 'parts/video_overlay_panels_part.dart';

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

String _rateText(double rate) => rate == rate.roundToDouble()
    ? rate.toStringAsFixed(0)
    : rate.toStringAsFixed(2);

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
