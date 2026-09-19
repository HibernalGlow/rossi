/// 阅读页里的视频页 —— 「一页可以是视频」的落点。
///
/// 生命周期规则来自两个上游的合流：
/// - neoview `PageVideo.tsx`：自动播放、进度恢复、播完翻页、控制条显隐节奏；
/// - mImageViewer `video/mod.rs`：就绪闩（没解出第一帧前不显示控制条）、
///   打开失败要能归类成「这一页播不了」而不是「这本读不了」。
///
/// 为什么这里必须显式 dispose：静态图页是「取一次像素」，视频页是**一个活的播放器
/// 加一条音频输出**。泳道切 lane、换章、退出阅读时如果不关，音频会继续响。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_action_dispatch.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';
import 'package:zephyr/video/service/video_materializer.dart';
import 'package:zephyr/video/service/video_poster_service.dart';
import 'package:zephyr/video/service/video_progress_store.dart';
import 'package:zephyr/video/subtitle/video_subtitle.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/video/view/video_control_overlay.dart';
import 'package:zephyr/video/view/video_info_sheet.dart';

/// 一个视频页的取数描述。
///
/// 刻意不直接依赖 `PageSource`：视频页的字节可能来自文件夹（直接用原路径）、
/// 也可能来自 ZIP/RAR（要物化）。这两种情况由**宿主**判定并给出 [readBytes]，
/// 这个控件只负责「拿到一个可 seek 的路径」。
class VideoPageTarget {
  const VideoPageTarget({
    required this.sourcePath,
    required this.entryName,
    required this.pageIndex,
    required this.progressKey,
    required this.resolveDirectPath,
    required this.readBytes,
    this.sizeBytes = 0,
    this.siblingEntryNames = const <String>[],
  });

  /// 归档路径或文件夹根路径（进度与缓存键的一部分）。
  final String sourcePath;
  final String entryName;
  final int pageIndex;
  final String progressKey;

  /// 文件夹来源能直接拿到磁盘路径；归档来源返回 null。
  final Future<String?> Function() resolveDirectPath;

  /// 该页的编码字节（归档来源要物化时用）。
  final Future<Uint8List?> Function() readBytes;
  final int sizeBytes;

  /// 同目录 / 同归档里的其它条目名，用来找外挂字幕。
  final List<String> siblingEntryNames;

  /// 这一页是否可播：要么有原路径，要么取得到字节。
  bool get playable => true;
}

/// 视频页的可配置项（由宿主从阅读设置里映射过来）。
class VideoPageSettings {
  const VideoPageSettings({
    this.autoplay = true,
    this.controlsPinned = false,
    this.hardwareDecode = true,
    this.minRate = 0.25,
    this.maxRate = 16,
    this.rateStep = 0.25,
    this.subtitleStyle = const VideoSubtitleStyle(),
    this.autoHideMilliseconds = 3000,
    this.volumePercent = 100,
    this.deinterlace = false,
  });

  final bool autoplay;
  final bool controlsPinned;
  final bool hardwareDecode;
  final double minRate;
  final double maxRate;
  final double rateStep;
  final VideoSubtitleStyle subtitleStyle;
  final int autoHideMilliseconds;

  /// 起播音量。不传的话设置页里那条「默认音量」就是死的。
  final int volumePercent;

  /// 去隔行（mImageViewer 的 open 参数）。
  final bool deinterlace;
}

class VideoPageSurface extends StatefulWidget {
  const VideoPageSurface({
    super.key,
    required this.target,
    required this.labels,
    this.settings = const VideoPageSettings(),
    this.materializer,
    this.progressStore,
    this.onListEnded,
    this.onFullscreen,
    this.onActiveChanged,
    this.onScreenshotTaken,
    this.active = true,
    this.fit = BoxFit.contain,
  });

  final VideoPageTarget target;
  final VideoLabels labels;
  final VideoPageSettings settings;
  final VideoMaterializer? materializer;
  final VideoProgressStore? progressStore;

  /// 播完且循环档为 `list` 时翻页。
  final VoidCallback? onListEnded;
  final VoidCallback? onFullscreen;

  /// `video` 输入上下文激活/失活（绑定体系按它决定优先级别名，ADR-0015）。
  final ValueChanged<bool>? onActiveChanged;
  final ValueChanged<String>? onScreenshotTaken;

  /// 这一页是不是**当前页**。双页模式下相邻两页会同时挂载，
  /// 两页都自动播放就等于两条音频；非当前页只准备、不出声。
  final bool active;

  final BoxFit fit;

  @override
  State<VideoPageSurface> createState() => _VideoPageSurfaceState();
}

class _VideoPageSurfaceState extends State<VideoPageSurface>
    implements ReaderVideoHost {
  MpvVideoTransport? _transport;
  ReaderVideoController? _controller;
  VideoFramePreviewProvider? _preview;
  final ValueNotifier<bool> _panelsOpen = ValueNotifier<bool>(false);

  bool _starting = false;
  String? _error;
  bool _controlsVisible = true;
  bool _pinned = false;
  bool _pip = false;
  Timer? _hideTimer;
  VideoFilterState _filter = VideoFilterState.neutral;
  VideoSubtitleStyle _subtitleStyle = const VideoSubtitleStyle();

  /// 「先激活、后操作」用的焦点节点（见 `_tapZones` 的注释）。
  final FocusNode _activation = FocusNode();
  List<SubtitleCandidate> _sidecarSubtitles = const <SubtitleCandidate>[];
  String? _materializedPath;
  StreamSubscription<String>? _uiSub;
  bool _claimed = false;

  /// 登记成「当前活动视频」，并让 `video` context 进活跃集合。
  void _claimActive() {
    final controller = _controller;
    if (controller == null || _claimed) return;
    _claimed = true;
    ActiveVideoScope.instance.claim(controller);
    widget.onActiveChanged?.call(true);
  }

  void _releaseInactive() {
    if (!_claimed) return;
    _claimed = false;
    final controller = _controller;
    if (controller != null) ActiveVideoScope.instance.release(controller);
    widget.onActiveChanged?.call(false);
  }

  /// 显隐控制条 / 全屏这两条动作的落地处（它们的效果长在页面上）。
  void _onUiAction(String actionId) {
    if (!mounted) return;
    switch (actionId) {
      case BindingVideoAction.toggleControls:
        setState(() => _controlsVisible = !_controlsVisible);
        if (_controlsVisible) _armHideTimer();
      case BindingVideoAction.toggleFullscreen:
        widget.onFullscreen?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _pinned = widget.settings.controlsPinned;
    _subtitleStyle = widget.settings.subtitleStyle;
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didUpdateWidget(VideoPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.entryName != widget.target.entryName ||
        oldWidget.target.sourcePath != widget.target.sourcePath) {
      // 换页 = 换源。播放器**复用**（省一次 mpv 实例化），但控制器里的
      // 位置/时长必须清零，否则进度条会在旧时长上画新的位置。
      _resetForNewTarget();
    }
    if (oldWidget.active && !widget.active) {
      // 从「当前页」掉下去：暂停并补写一次进度。让它继续出声是明确的错误 ——
      // 用户看到的是另一页，听到的却是这一页。
      unawaited(_controller?.setPlaying(false));
      _controller?.flushProgress();
      _releaseInactive();
    }
    if (!oldWidget.active && widget.active) _claimActive();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    final transport = _transport ?? MpvVideoTransport();
    final controller = ReaderVideoController(
      host: this,
      progressKey: widget.target.progressKey,
      transport: transport,
      rateRuntime: (
        min: widget.settings.minRate,
        max: widget.settings.maxRate,
        step: widget.settings.rateStep,
      ),
    );
    _controller = controller;
    _preview = VideoFramePreviewProvider(transport: transport);
    _uiSub ??= ActiveVideoScope.instance.uiActions.listen(_onUiAction);
    // 只有当前页才登记为「活动视频」：邻居页也挂着，先登记的那个会抢走按键归属。
    if (widget.active) _claimActive();
    setState(() {});

    try {
      final resolved = await _resolvePlayablePath();
      if (resolved == null) {
        if (mounted) setState(() => _error = '这个视频条目取不到字节');
        return;
      }
      _materializedPath = resolved;
      await controller.attach(transport);

      final saved = await widget.progressStore?.load(widget.target.progressKey);
      await transport.open(
        'file://${Uri.file(resolved).path}',
        options: VideoOpenOptions(
          autoplay:
              widget.settings.autoplay && widget.active && saved?.isFinished != true,
          resumeAt: saved?.resumeAt,
          hardwareDecode: widget.settings.hardwareDecode,
          deinterlace: widget.settings.deinterlace,
          volume: widget.settings.volumePercent,
        ),
      );
      // 快照里的音量要跟实际一致：只把音量交给引擎、不回报给控制器，
      // 界面就会显示 100% 而听上去是 40%。
      await controller.setVolume(widget.settings.volumePercent / 100);
      await transport.setFilter(_filter);
      await transport.setSubtitleStyle(_subtitleStyle);
      await _attachSidecarSubtitles(resolved);
      _armHideTimer();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _starting = false;
    }
  }

  /// 归档 → 物化到临时区；文件夹 → 原路径直接用。
  Future<String?> _resolvePlayablePath() async {
    final direct = await widget.target.resolveDirectPath();
    if (direct != null) {
      _isArchive = false;
      return File(direct).existsSync() ? direct : null;
    }
    _isArchive = true;
    final materializer = widget.materializer ?? _sharedMaterializer;
    final file = await materializer.materialize(
      sourcePath: widget.target.sourcePath,
      pageIndex: widget.target.pageIndex,
      entryName: widget.target.entryName,
      entrySize: widget.target.sizeBytes,
      readBytes: () async => (await widget.target.readBytes()) ?? Uint8List(0),
    );
    return file.filePath;
  }

  bool _isArchive = false;

  static final VideoMaterializer _sharedMaterializer = VideoMaterializer();

  /// 外挂字幕：同目录/同归档里同名的 srt/ass 直接挂上，第一条自动选中。
  Future<void> _attachSidecarSubtitles(String playablePath) async {
    final candidates = <SubtitleCandidate>[];
    if (_isArchive) {
      candidates.addAll(
        matchSubtitleNames(
          videoName: widget.target.entryName,
          entryNames: widget.target.siblingEntryNames,
        ).map(
          (c) => SubtitleCandidate(
            path: 'archive:${widget.target.sourcePath}#${c.path}',
            label: c.label,
            language: c.language,
            format: c.format,
          ),
        ),
      );
    } else {
      candidates.addAll(await discoverSidecarSubtitles(playablePath));
    }
    if (!mounted) return;
    setState(() => _sidecarSubtitles = candidates);
    if (candidates.isEmpty) return;
    final first = candidates.first;
    final transport = _transport;
    if (transport == null) return;
    // 只有一条字幕时自动挂上（neoview 也是首条自动选），并把选中态记下来，
    // 否则弹层里看不出「现在挂的是外挂轨还是容器内轨」。
    _activeSidecarId = 'file:${first.path}';
    if (first.path.startsWith('archive:')) {
      // 归档内的字幕要先落盘才能喂给 mpv：字幕条目本身很小，直接写字节。
      final local = await _materializeSidecar(first.path);
      if (local != null) await transport.addSubtitleFile(local);
    } else {
      await transport.addSubtitleFile(first.path);
    }
    if (mounted) setState(() {});
  }

  String? _activeSidecarId;

  /// 外挂字幕在弹层里长成一条普通轨道，id 前缀 `file:` 表示「要先落盘再挂」。
  List<VideoMediaTrack> get _subtitleOptions => <VideoMediaTrack>[
    for (final c in _sidecarSubtitles)
      VideoMediaTrack(
        id: 'file:${c.path}',
        title: c.label,
        language: c.language,
        external: true,
        selected: _activeSidecarId == 'file:${c.path}',
      ),
  ];

  Future<void> _chooseSubtitle(String? id) async {
    final transport = _transport;
    if (transport == null) return;
    if (id == null) {
      _activeSidecarId = null;
      await transport.selectSubtitleTrack(null);
      if (mounted) setState(() {});
      return;
    }
    if (!id.startsWith('file:')) {
      // 容器内轨：交给引擎，外挂轨的选中态要清掉，否则两处同时显「已选」。
      _activeSidecarId = null;
      await transport.selectSubtitleTrack(id);
      if (mounted) setState(() {});
      return;
    }
    final marker = id.substring('file:'.length);
    final real = marker.startsWith('archive:')
        ? await _materializeSidecar(marker)
        : marker;
    if (real == null) return;
    _activeSidecarId = id;
    await transport.addSubtitleFile(real);
    if (mounted) setState(() {});
  }

  Future<String?> _materializeSidecar(String archiveMarker) async {
    // `archive:<source>#<entry>` —— 复用同一份字节读取，落进视频缓存目录旁边。
    final separator = archiveMarker.indexOf('#');
    if (separator < 0) return null;
    final entry = archiveMarker.substring(separator + 1);
    final bytes = await widget.target.readBytes();
    if (bytes == null) return null;
    final file = await _sharedMaterializer.materialize(
      sourcePath: widget.target.sourcePath,
      pageIndex: -1,
      entryName: entry,
      entrySize: bytes.lengthInBytes,
      readBytes: () async => bytes,
    );
    return file.filePath;
  }

  void _resetForNewTarget() {
    _controller?.detach();
    _controller = null;
    _error = null;
    _materializedPath = null;
    _sidecarSubtitles = const <SubtitleCandidate>[];
    unawaited(_start());
  }

  // ── ReaderVideoHost ───────────────────────────────────────────────────

  @override
  void onVideoListEnded() => widget.onListEnded?.call();

  @override
  void onVideoProgress(VideoPlaybackProgress progress) {
    unawaited(
      (widget.progressStore ?? _sharedProgressStore).save(
        VideoProgressEntry(
          position: progress.position,
          duration: progress.duration,
          completed: progress.completed,
          updatedAt: DateTime.now(),
        ),
        key: progress.key,
      ),
    );
  }

  static final SharedPreferencesVideoProgressStore _sharedProgressStore =
      SharedPreferencesVideoProgressStore();

  // ── 控制条显隐（neo：播放中 3 s 后收起，暂停/钉住/弹层开着时常显）──

  void _armHideTimer() {
    _hideTimer?.cancel();
    final controller = _controller;
    if (controller == null) return;
    if (!_controlsVisible) return;
    _hideTimer = Timer(
      Duration(milliseconds: widget.settings.autoHideMilliseconds),
      () {
        final snapshot = controller.snapshot;
        if (snapshot.playing && !_pinned && !_panelsOpen.value) {
          setState(() => _controlsVisible = false);
        }
      },
    );
  }

  void _revealControls() {
    if (_controlsVisible) {
      _armHideTimer();
      return;
    }
    setState(() => _controlsVisible = true);
    _armHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _panelsOpen.dispose();
    _activation.dispose();
    unawaited(_uiSub?.cancel());
    final controller = _controller;
    _releaseInactive();
    controller?.dispose();
    unawaited(_transport?.close());
    unawaited(_preview?.dispose());
    super.dispose();
  }

  Future<void> _persistPinned(bool value) async {
    final store = VideoSettingsStore.instance;
    await store.save((await store.load()).copyWith(controlsPinned: value));
  }

  Future<void> _persistSubtitleStyle(VideoSubtitleStyle style) async {
    final store = VideoSettingsStore.instance;
    await store.save((await store.load()).copyWith(subtitleStyle: style));
  }

  Future<void> _screenshot() async {
    final controller = _controller;
    if (controller == null || _materializedPath == null) return;
    final path = await nextVideoScreenshotPath();
    final taken = await controller.screenshot(path);
    if (taken != null) widget.onScreenshotTaken?.call(taken);
  }

  /// 中/左/右三段点击区（neo `PageVideo.tsx`：中间播放暂停、左右 ±10 s）。
  ///
  /// 外面套一层 `Focus` 是为了复刻 neoview 的泳道规则
  /// （`docs/neoview-swimlane-ui.md:56`）：**点一个还没激活的 lane，那一次点击归
  /// 工作区所有**，不该顺手把视频暂停掉。这里用「拿到焦点之前的那一次点击只激活、
  /// 不执行」实现同一件事 —— 否则用户在泳道里点一下视频，第一次永远是「暂停」，
  /// 而他要的只是「把这页切过来」。
  Widget _tapZones(Widget child) => Focus(
    focusNode: _activation,
    child: LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child,
          Positioned(
            left: 0,
            width: width * 0.25,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_activateOnly()) return;
                _controller?.seekBackward();
                _revealControls();
              },
            ),
          ),
          Positioned(
            right: 0,
            width: width * 0.25,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_activateOnly()) return;
                _controller?.seekForward();
                _revealControls();
              },
            ),
          ),
          Positioned(
            left: width * 0.25,
            right: width * 0.25,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_activateOnly()) return;
                _controller?.togglePlay();
                _revealControls();
              },
            ),
          ),
        ],
      );
    },
  ));

  /// 未激活时吃掉这一次点击，只把焦点拿过来。返回 true = 已消费。
  bool _activateOnly() {
    if (_activation.hasFocus) return false;
    _activation.requestFocus();
    widget.onActiveChanged?.call(true);
    _revealControls();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final transport = _transport;
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (controller == null || transport == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: MouseRegion(
        onHover: (_) => _revealControls(),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final snapshot = controller.snapshot;
            final showControls =
                _controlsVisible || !_pinned && !snapshot.playing || _pinned;
            final video = Video(
              controller: transport.videoController,
              fit: widget.fit,
              controls: NoVideoControls,
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (!_pip) _tapZones(video) else const SizedBox.shrink(),
                if (snapshot.phase == VideoEnginePhase.prerolling &&
                    snapshot.duration <= Duration.zero)
                  const Center(child: CircularProgressIndicator()),
                if (snapshot.phase == VideoEnginePhase.failed)
                  ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text(
                        snapshot.failureReason ?? '这一页播不了',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                if (showControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: <Color>[
                            Color(0xE6000000),
                            Color(0xA6000000),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: VideoControlOverlay(
                        snapshot: snapshot,
                        controller: controller,
                        labels: widget.labels,
                        pinned: _pinned,
                        panelsOpen: _panelsOpen,
                        framePreview: _preview,
                        filter: _filter,
                        subtitleStyle: _subtitleStyle,
                        onFilterChanged: (next) {
                          setState(() => _filter = next);
                          transport.setFilter(next);
                        },
                        onSubtitleStyleChanged: (next) {
                          setState(() => _subtitleStyle = next);
                          transport.setSubtitleStyle(next);
                          // 字号/颜色/位置是「读下一本也想保持」的偏好，上游同样持久化。
                          unawaited(_persistSubtitleStyle(next));
                        },
                        onTogglePin: () {
                          setState(() => _pinned = !_pinned);
                          // 图钉要跨书、跨重启保持（上游同样是持久化的），
                          // 否则桌面端每次重开都要重新钉一次，这条功能等于没做。
                          unawaited(_persistPinned(_pinned));
                        },
                        onScreenshot: _screenshot,
                        onFullscreen: widget.onFullscreen,
                        onTogglePip: () => setState(() => _pip = !_pip),
                        onOpenInfo: () => showVideoInfoSheet(
                          context,
                          controller: controller,
                          labels: widget.labels,
                          sidecars: _sidecarSubtitles,
                        ),
                        extraSubtitleTracks: _subtitleOptions,
                        onSubtitleSelected: _chooseSubtitle,
                      ),
                    ),
                  ),
                if (_pip)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: 320,
                        height: 180,
                        child: Material(
                          elevation: 12,
                          color: Colors.black,
                          child: Stack(
                            children: <Widget>[
                              Positioned.fill(child: video),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => setState(() => _pip = false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
