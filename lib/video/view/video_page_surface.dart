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

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_action_dispatch.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';
import 'package:zephyr/video/service/video_materializer.dart';
import 'package:zephyr/video/service/video_poster_service.dart';
import 'package:zephyr/video/service/video_waveform_service.dart';
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
  final VideoPanelController _panelsOpen = VideoPanelController();
  final ValueNotifier<(ReaderVideoSnapshot, Duration?)> _controlsState =
      ValueNotifier((ReaderVideoSnapshot.empty, null));

  int _generation = 0;
  Future<void>? _startup;
  String? _error;
  bool _controlsVisible = true;
  bool _pinned = false;
  bool _pip = false;
  Timer? _hideTimer;
  bool _observedPlaying = false;
  final Object _infoPanel = Object();
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
    _panelsOpen.addListener(_onPanelsChanged);
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetForNewTarget();
    });
  }

  @override
  void didUpdateWidget(VideoPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.entryName != widget.target.entryName ||
        oldWidget.target.sourcePath != widget.target.sourcePath) {
      // 换源先收完旧会话，再启动最新目标，避免旧的异步加载回写或继续占用解码器。
      _resetForNewTarget();
    }
    if (oldWidget.settings.controlsPinned != widget.settings.controlsPinned) {
      _pinned = widget.settings.controlsPinned;
      _revealControls();
    }
    if (oldWidget.settings.autoHideMilliseconds !=
        widget.settings.autoHideMilliseconds) {
      _armHideTimer();
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

  bool _isCurrent(int generation) => mounted && generation == _generation;

  Future<void> _start(int generation) async {
    if (!_isCurrent(generation)) return;
    final target = widget.target;
    final settings = widget.settings;
    resetVideoSubtitleActionState();
    // build 与 dispose 必须持有同一个播放器，否则页面永远停在初始加载态。
    final transport = _transport = MpvVideoTransport(
      hardwareDecode: settings.hardwareDecode,
    );
    transport.tracksRevision.addListener(_onTracksChanged);
    // 先建立视频输出，open 会等初始化完成再加载媒体和设置解码选项。
    transport.videoController;
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
    _observedPlaying = controller.snapshot.playing;
    controller.addListener(_onPlaybackChanged);
    _preview = VideoFramePreviewProvider(
      createPreviewTransport: () =>
          MpvVideoTransport(hardwareDecode: settings.hardwareDecode),
    );
    _uiSub ??= ActiveVideoScope.instance.uiActions.listen(_onUiAction);
    // 只有当前页才登记为「活动视频」：邻居页也挂着，先登记的那个会抢走按键归属。
    if (widget.active) _claimActive();
    setState(() {});

    try {
      final resolved = await _resolvePlayablePath(target);
      if (!_isCurrent(generation)) return;
      if (resolved == null) {
        if (mounted) setState(() => _error = t.video.noBytes);
        return;
      }
      _materializedPath = resolved;
      final uri = 'file://${Uri.file(resolved).path}';
      // 预览那台解码器自己开这个文件 —— 悬停因此与主播放器的位置无关。
      _preview?.setSource(uri);
      await controller.attach(transport);
      if (!_isCurrent(generation)) return;

      final saved = await (widget.progressStore ?? _sharedProgressStore).load(
        target.progressKey,
      );
      if (!_isCurrent(generation)) return;
      await transport.open(
        uri,
        options: VideoOpenOptions(
          autoplay:
              widget.settings.autoplay &&
              widget.active &&
              saved?.isFinished != true,
          resumeAt: saved?.resumeAt,
          hardwareDecode: widget.settings.hardwareDecode,
          deinterlace: widget.settings.deinterlace,
          volume: widget.settings.volumePercent,
        ),
      );
      if (!_isCurrent(generation)) return;
      if (!widget.active) await transport.pause();
      // 快照里的音量要跟实际一致：只把音量交给引擎、不回报给控制器，
      // 界面就会显示 100% 而听上去是 40%。
      await controller.setVolume(widget.settings.volumePercent / 100);
      await transport.setFilter(_filter);
      await transport.setSubtitleStyle(_subtitleStyle);
      if (!_isCurrent(generation)) return;
      await _attachSidecarSubtitles(resolved, generation);
      if (!_isCurrent(generation)) return;
      unawaited(_loadWaveform(resolved));
      _armHideTimer();
    } catch (e) {
      if (_isCurrent(generation)) setState(() => _error = e.toString());
    }
  }

  /// 归档 → 物化到临时区；文件夹 → 原路径直接用。
  Future<String?> _resolvePlayablePath(VideoPageTarget target) async {
    final direct = await target.resolveDirectPath();
    if (direct != null) {
      _isArchive = false;
      return File(direct).existsSync() ? direct : null;
    }
    _isArchive = true;
    final materializer = widget.materializer ?? _sharedMaterializer;
    final file = await materializer.materialize(
      sourcePath: target.sourcePath,
      pageIndex: target.pageIndex,
      entryName: target.entryName,
      entrySize: target.sizeBytes,
      readBytes: () async => (await target.readBytes()) ?? Uint8List(0),
    );
    return file.filePath;
  }

  bool _isArchive = false;

  static final VideoMaterializer _sharedMaterializer = VideoMaterializer();

  /// 外挂字幕：同目录/同归档里同名的 srt/ass 直接挂上，第一条自动选中。
  Future<void> _attachSidecarSubtitles(
    String playablePath,
    int generation,
  ) async {
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
    if (!_isCurrent(generation)) return;
    setState(() => _sidecarSubtitles = candidates);
    if (candidates.isEmpty) return;
    final first = candidates.first;
    final transport = _transport;
    if (transport == null) return;
    // 只有一条字幕时自动挂上（neoview 也是首条自动选），并把选中态记下来，
    // 否则弹层里看不出「现在挂的是外挂轨还是容器内轨」。
    _activeSidecarId = 'file:${first.path}';
    // 归档内的字幕要先落盘才能喂给 mpv（字幕条目本身很小，直接写字节）；
    // `.sub`（MicroDVD）还要再过一道转换，mpv 解不动那一档。
    final landed = first.path.startsWith('archive:')
        ? await _materializeSidecar(first.path)
        : first.path;
    if (landed == null || !_isCurrent(generation)) return;
    final ready = await _prepareSubtitle(landed, first.format);
    if (ready == null || !_isCurrent(generation)) return;
    await transport.addSubtitleFile(ready);
    if (_isCurrent(generation)) setState(() {});
  }

  String? _activeSidecarId;

  VideoWaveformStrip _waveform = VideoWaveformStrip.empty;

  /// 波形条是装饰：解码在核心侧异步跑，回来时页面可能已经翻页了，所以要判 mounted
  /// 与路径未变。失败就是「不画」，不报错、不挡播放。
  Future<void> _loadWaveform(String path) async {
    final controller = _controller;
    if (controller == null) return;
    var duration = controller.snapshot.duration;
    if (duration <= Duration.zero) {
      // 时长可能还没回来（mpv 的 duration 事件比 open 晚）。等一下，最多 2 s。
      for (var i = 0; i < 20 && duration <= Duration.zero; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        duration = controller.snapshot.duration;
      }
    }
    if (duration <= Duration.zero) return;
    final strip = await VideoWaveformService.instance.stripFor(path, duration);
    if (!mounted || _materializedPath != path || strip.isEmpty) return;
    setState(() => _waveform = strip);
  }

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
    final ready = await _prepareSubtitle(real, _sidecarAt(id)?.format ?? 'srt');
    if (ready == null) return;
    _activeSidecarId = id;
    await transport.addSubtitleFile(ready);
    if (mounted) setState(() {});
  }

  /// 交给引擎前的准备：只转换 mpv 解不动的那一档（MicroDVD），其余原样。
  Future<String?> _prepareSubtitle(String path, String format) =>
      convertSubtitleFileForEngine(path, format: format);

  SubtitleCandidate? _sidecarAt(String id) {
    for (final candidate in _sidecarSubtitles) {
      if ('file:${candidate.path}' == id) return candidate;
    }
    return null;
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
    final generation = ++_generation;
    final previousStartup = _startup;
    final previousTransport = _transport;
    previousTransport?.tracksRevision.removeListener(_onTracksChanged);
    final previewClosed = _preview?.dispose();
    _hideTimer?.cancel();
    _releaseInactive();
    _controller?.removeListener(_onPlaybackChanged);
    _controller?.dispose();
    _controller = null;
    _controlsVisible = true;
    _transport = null;
    _preview = null;
    _error = null;
    _materializedPath = null;
    _sidecarSubtitles = const <SubtitleCandidate>[];
    _activeSidecarId = null;
    _waveform = VideoWaveformStrip.empty;
    _startup = () async {
      // 旧的 open / 截图结束后才销毁原生纹理，不让它们访问已经释放的 mpv。
      await previousStartup;
      await previewClosed;
      await previousTransport?.close();
      if (_isCurrent(generation)) await _start(generation);
    }();
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

  void _onPlaybackChanged() {
    final controller = _controller;
    if (controller != null) {
      // 高频位置通知只交给进度条和时钟，整排菜单只在操作状态改变时重建。
      _controlsState.value = (
        controller.snapshot.copyWith(currentTime: Duration.zero),
        controller.markedPointA,
      );
    }
    final playing = _controller?.snapshot.playing ?? false;
    if (_observedPlaying == playing) return;
    _observedPlaying = playing;
    // 只响应播放/暂停切换，进度事件不能不断续期隐藏计时。
    _revealControls();
  }

  void _onPanelsChanged() => _revealControls();

  void _onTracksChanged() {
    if (mounted) setState(() {});
  }

  void _togglePin() {
    setState(() => _pinned = !_pinned);
    // 取消固定、关弹层、恢复播放都必须重新计时，不能依赖下一次鼠标移动。
    _revealControls();
    unawaited(_persistPinned(_pinned));
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    if (!mounted ||
        !_controlsVisible ||
        _pinned ||
        _panelsOpen.value ||
        _controller?.snapshot.playing != true) {
      return;
    }
    _hideTimer = Timer(
      Duration(milliseconds: widget.settings.autoHideMilliseconds),
      () {
        if (!mounted) return;
        if (_controller?.snapshot.playing == true &&
            !_pinned &&
            !_panelsOpen.value) {
          setState(() => _controlsVisible = false);
        }
      },
    );
  }

  void _revealControls() {
    if (!mounted) return;
    if (_controlsVisible) {
      _armHideTimer();
      return;
    }
    setState(() => _controlsVisible = true);
    _armHideTimer();
  }

  @override
  void dispose() {
    ++_generation;
    _hideTimer?.cancel();
    _panelsOpen.removeListener(_onPanelsChanged);
    _panelsOpen.dispose();
    _controlsState.dispose();
    _activation.dispose();
    unawaited(_uiSub?.cancel());
    final controller = _controller;
    _releaseInactive();
    controller?.removeListener(_onPlaybackChanged);
    controller?.dispose();
    final startup = _startup;
    final transport = _transport;
    transport?.tracksRevision.removeListener(_onTracksChanged);
    final previewClosed = _preview?.dispose();
    unawaited(() async {
      await startup;
      await previewClosed;
      await transport?.close();
    }());
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

  Future<void> _showInfo() async {
    final controller = _controller;
    if (controller == null) return;
    _panelsOpen.setOpen(_infoPanel, true);
    try {
      await showVideoInfoSheet(
        context,
        controller: controller,
        labels: widget.labels,
        sidecars: _sidecarSubtitles,
      );
    } finally {
      _panelsOpen.setOpen(_infoPanel, false);
    }
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
    ),
  );

  /// 未激活时吃掉这一次点击，只把焦点拿过来。返回 true = 已消费。
  bool _activateOnly() {
    if (_activation.hasFocus) return false;
    _activation.requestFocus();
    widget.onActiveChanged?.call(true);
    _revealControls();
    return true;
  }

  Widget _videoBody(MpvVideoTransport transport) {
    final video = RepaintBoundary(
      child: Video(
        controller: transport.videoController,
        fit: widget.fit,
        controls: NoVideoControls,
      ),
    );
    if (!_pip) return _tapZones(video);
    return Align(
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
                  child: IconButton.filledTonal(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _pip = false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

    return Listener(
      onPointerDown: (_) => _revealControls(),
      child: ColoredBox(
        color: Colors.black,
        child: MouseRegion(
          onHover: (_) => _revealControls(),
          child: ListenableBuilder(
            listenable: _controlsState,
            // 位置更新不重建画面、按钮与菜单，只刷新控制条里的进度和时间。
            child: _videoBody(transport),
            builder: (context, videoBody) {
              final snapshot = controller.snapshot;
              final showControls =
                  _controlsVisible ||
                  !snapshot.playing ||
                  _pinned ||
                  _panelsOpen.value;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (!_pip) videoBody!,
                  if (snapshot.phase == VideoEnginePhase.prerolling &&
                      snapshot.duration <= Duration.zero)
                    const Center(child: CircularProgressIndicator()),
                  if (snapshot.phase == VideoEnginePhase.failed)
                    ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          snapshot.failureReason ?? t.video.cannotPlay,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      ignoring: !showControls,
                      child: ExcludeFocus(
                        excluding: !showControls,
                        child: AnimatedOpacity(
                          key: const ValueKey('video-controls-visibility'),
                          opacity: showControls ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1080),
                              child: VideoControlOverlay(
                                snapshot: snapshot,
                                progressUpdates: showControls,
                                controlUpdates: _controlsState,
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
                                onTogglePin: _togglePin,
                                onScreenshot: _screenshot,
                                onFullscreen: widget.onFullscreen,
                                onTogglePip: () => setState(() => _pip = !_pip),
                                onOpenInfo: _showInfo,
                                extraSubtitleTracks: _subtitleOptions,
                                onSubtitleSelected: _chooseSubtitle,
                                waveform: _waveform,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (_pip) videoBody!,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
