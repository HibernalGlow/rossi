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
import 'package:zephyr/icons/icons.dart';

// 进度与拖动预览：位置构建器、拖动条、进度条、波形与帧预览气泡。
part 'parts/video_overlay_scrub_part.dart';
// 弹层面板：倍速、音量、字幕、滤镜与滑杆行。
part 'parts/video_overlay_panels_part.dart';
part 'parts/video_overlay_toolbar_part.dart';
part 'parts/video_expressive_track_part.dart';

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
              leading: GlyphIcon(
                selectedId == null ? AppGlyphs.radioChecked : AppGlyphs.ring,
              ),
              onTap: () => onSelected(null),
            ),
            for (final track in tracks)
              ListTile(
                dense: true,
                title: Text(track.title),
                subtitle: track.language == null ? null : Text(track.language!),
                leading: GlyphIcon(
                  track.id == selectedId
                      ? AppGlyphs.radioChecked
                      : AppGlyphs.ring,
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
    this.embedded = false,
    this.onScrubChanged,
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

  final bool embedded;
  final ValueChanged<bool>? onScrubChanged;

  @override
  Widget build(BuildContext context) {
    final transport = controller.transport;
    final engineTracks = transport?.subtitleTracks ?? const <VideoMediaTrack>[];
    // 外挂字幕（同目录 / 同归档里的 srt/ass）也要能在同一个弹层里选：
    // neoview 的字幕弹层列的就是「服务端匹配到的轨 + 容器内轨」。
    final tracks = <VideoMediaTrack>[...engineTracks, ...extraSubtitleTracks];
    final audioTracks = transport?.audioTracks ?? const <VideoMediaTrack>[];
    final filterState = filter;
    final loops = <ReaderVideoLoopMode, (Glyph, String)>{
      ReaderVideoLoopMode.list: (AppGlyphs.loop, labels.loop),
      ReaderVideoLoopMode.single: (AppGlyphs.loop, labels.loopSingle),
      ReaderVideoLoopMode.none: (AppGlyphs.loop, labels.loopOff),
    };
    final loop = loops[snapshot.loopMode]!;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget menuAction(
      Glyph icon,
      String label,
      VoidCallback? action, {
      bool selected = false,
    }) => MenuItemButton(
      leadingIcon: GlyphIcon(icon),
      trailingIcon: selected
          ? const GlyphIcon(AppGlyphs.check, size: 20)
          : null,
      onPressed: action,
      child: Text(label),
    );

    return Theme(
      data: theme.copyWith(
        sliderTheme: theme.sliderTheme.copyWith(
          trackHeight: 8,
          trackShape: const _ExpressiveVideoTrackShape(),
          thumbShape: const HandleThumbShape(),
          thumbSize: const WidgetStatePropertyAll(Size(4, 28)),
          trackGap: 4,
          activeTrackColor: colors.primary,
          inactiveTrackColor: colors.secondaryContainer,
        ),
      ),
      child: Material(
        key: const ValueKey('video-controls-surface'),
        color: embedded ? Colors.transparent : colors.surfaceContainerHigh,
        elevation: embedded ? 0 : 3,
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
              if (!embedded)
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
                      onScrubChanged: onScrubChanged,
                    ),
                  ),
                ),
              _AdaptiveVideoToolbar(
                clockText:
                    '${formatVideoTime(snapshot.duration)} / ${formatVideoTime(snapshot.duration)}',
                children: <Widget>[
                  IconButton.filled(
                    tooltip: snapshot.playing ? labels.pause : labels.play,
                    // 词表里早就有 `playPause(t)`：三角形的两条边各自长成一根竖条。
                    // 原先这一档在两颗图标之间硬切，那个函数全仓没人调用。
                    icon: MorphingGlyph(
                      on: snapshot.playing,
                      builder: AppGlyphs.playPause,
                    ),
                    onPressed: () => controller.togglePlay(),
                  ),
                  _IconButton(
                    icon: AppGlyphs.skipPrevious,
                    tooltip: labels.backward,
                    onPressed: () => controller.seekBackward(),
                  ),
                  _IconButton(
                    icon: AppGlyphs.skipNext,
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
                    icon: AppGlyphs.fullscreen,
                    tooltip: labels.fullscreen,
                    onPressed: onFullscreen,
                  ),
                  _IconButton(
                    buttonKey: const ValueKey('video-pin-controls'),
                    icon: AppGlyphs.pin,
                    selectedIcon: AppGlyphs.pin,
                    tooltip: pinned ? t.reader.unpinBottomBar : labels.pin,
                    active: pinned,
                    onPressed: onTogglePin,
                  ),
                  _TextButton(
                    label: t.common.more,
                    tooltip: t.common.more,
                    icon: AppGlyphs.more,
                    panelsOpen: panelsOpen,
                    builder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        menuAction(
                          AppGlyphs.skipPrevious,
                          labels.frameStepBackward,
                          () => controller.stepFrame(-1),
                        ),
                        menuAction(
                          AppGlyphs.skipNext,
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
                          AppGlyphs.loop,
                          labels.abLoop,
                          controller.tapAbLoop,
                          selected:
                              snapshot.abLoop != null ||
                              controller.markedPointA != null,
                        ),
                        if (snapshot.abLoop != null ||
                            controller.markedPointA != null)
                          menuAction(
                            AppGlyphs.close,
                            labels.abClear,
                            controller.clearAbLoop,
                          ),
                        const Divider(),
                        menuAction(
                          AppGlyphs.camera,
                          labels.screenshot,
                          onScreenshot == null ? null : () => onScreenshot!(),
                        ),
                        menuAction(
                          AppGlyphs.skipNext,
                          labels.seekMode,
                          controller.toggleSeekMode,
                          selected: snapshot.seekMode,
                        ),
                        if (audioOnlyAvailable)
                          menuAction(
                            AppGlyphs.music,
                            labels.audioOnly,
                            () => controller.setAudioOnly(!snapshot.audioOnly),
                            selected: snapshot.audioOnly,
                          ),
                        menuAction(AppGlyphs.pip, labels.pip, onTogglePip),
                        menuAction(AppGlyphs.info, labels.info, onOpenInfo),
                      ],
                    ),
                  ),
                ],
              ),
              if (embedded)
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
                      onScrubChanged: onScrubChanged,
                    ),
                  ),
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

  final Glyph icon;
  final Glyph? selectedIcon;
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
        icon: AnimatedGlyph(glyph: icon, filled: active),
        // Material 在 isSelected 时**整颗换掉** icon，所以这一支必须自己带填充：
        // 上一版给的是裸 GlyphIcon，等于把上面那层填充动画盖掉（pin 那颗
        // icon 与 selectedIcon 同一颗，选中后反而看不出差别）。
        selectedIcon: AnimatedGlyphIcon(selectedIcon!, filled: true),
        onPressed: onPressed,
      );
    }
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      icon: GlyphIcon(icon),
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
  final Glyph? icon;

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
            // 下面那颗文字按钮用 `active || isOpen` 换前景色，图标这一支原先
            // 两个状态都不体现；这里按同一口径填充。
            icon: AnimatedGlyphIcon(
              widget.icon!,
              filled: widget.active || menu.isOpen,
            ),
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
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Tooltip(message: widget.tooltip, child: Text(widget.label)),
        );
      },
    );
  }
}
