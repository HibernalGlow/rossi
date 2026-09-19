/// libmpv 传输实现：把 [VideoTransport] 的能力面映射到 media_kit / mpv 属性。
///
/// 选择 media_kit（MIT，libmpv 绑定，GitHub 上事实标准的跨平台 Flutter 播放器）
/// 而不是自建解码器，理由记在 ADR-0016。这里同时是「为什么不缺功能」的答案：
/// mImageViewer 的每个引擎语义都对应一个 mpv 属性，逐条写在对应方法上。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:zephyr/video/controller/video_transport.dart';

/// mpv 属性名 —— 左：本项目的语义；右：mpv 的键。
class MpvKeys {
  static const hwdec = 'hwdec';
  static const deinterlace = 'deinterlace';
  static const video = 'video';
  static const speed = 'speed';
  static const mute = 'mute';
  static const loopFile = 'loop-file';
  static const abLoopA = 'ab-loop-a';
  static const abLoopB = 'ab-loop-b';
  static const brightness = 'brightness';
  static const contrast = 'contrast';
  static const saturation = 'saturation';
  static const subScale = 'sub-scale';
  static const subPos = 'sub-pos';
  static const subDelay = 'sub-delay';
  static const subColor = 'sub-color';
  static const subBackColor = 'sub-back-color';
  static const subVisible = 'sub-visibility';
}

class MpvVideoTransport implements VideoTransport {
  MpvVideoTransport({Player? player}) : _player = player ?? Player() {
    _native = _player.platform is NativePlayer
        ? _player.platform as NativePlayer
        : null;
  }

  final Player _player;
  NativePlayer? _native;
  VideoController? _videoController;

  final StreamController<bool> _playingCtrl = StreamController<bool>.broadcast();
  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _completedCtrl = StreamController<bool>.broadcast();
  final StreamController<VideoEnginePhase> _phaseCtrl =
      StreamController<VideoEnginePhase>.broadcast();

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  VideoMetadata _metadata = VideoMetadata.unknown;
  List<VideoMediaTrack> _subtitleTracks = <VideoMediaTrack>[];
  List<VideoMediaTrack> _audioTracks = <VideoMediaTrack>[];
  VideoEnginePhase _phase = VideoEnginePhase.idle;
  bool _seeking = false;
  Timer? _seekClear;
  String? _failure;
  String? _openUri;
  VideoOpenOptions _options = const VideoOpenOptions();

  /// media_kit 的 `Video` 组件要这个控制器；Rossi 不用它的控制条。
  VideoController get videoController =>
      _videoController ??= VideoController(_player);

  String? get mpvUri => _openUri;
  VideoOpenOptions get openOptions => _options;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;
  @override
  Stream<bool> get completedStream => _completedCtrl.stream;
  @override
  Stream<VideoEnginePhase> get phaseStream => _phaseCtrl.stream;

  @override
  VideoMetadata get metadata => _metadata;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  bool get isPlaying => _player.state.playing;
  @override
  bool get isSeeking => _seeking;
  @override
  String? get failureReason => _failure;
  @override
  List<VideoMediaTrack> get subtitleTracks => _subtitleTracks;
  @override
  List<VideoMediaTrack> get audioTracks => _audioTracks;

  void _setPhase(VideoEnginePhase next) {
    if (_phase == next) return;
    _phase = next;
    if (!_phaseCtrl.isClosed) _phaseCtrl.add(next);
  }

  @override
  Future<void> open(
    String uri, {
    VideoOpenOptions options = const VideoOpenOptions(),
  }) async {
    _options = options;
    _openUri = uri;
    _failure = null;
    _setPhase(VideoEnginePhase.opening);
    _subscribe();

    try {
      await _player.open(Media(uri), play: options.autoplay);
    } catch (e) {
      _failure = e.toString();
      _setPhase(VideoEnginePhase.failed);
      return;
    }

    // 硬解 / 去隔行在 mpv 里可以运行时改（mimage 是构造参数），
    // 放在 open 之后发是为了让「设置页拨一下立刻生效」成立。
    await _set(
      MpvKeys.hwdec,
      options.hardwareDecode ? 'auto-copy' : 'no',
    );
    await _set(MpvKeys.deinterlace, options.deinterlace ? 'yes' : 'no');
    await setVolume(options.volume);
    await setMuted(options.muted);
    await setRate(options.rate);
    await setVideoEnabled(!options.audioOnly);
    final resume = options.resumeAt;
    if (resume != null && resume > Duration.zero) await seek(resume);
    _setPhase(VideoEnginePhase.prerolling);
    unawaited(_awaitFirstFrame());
  }

  /// 「解出第一帧」= mimage 的 preroll 闩。
  ///
  /// mpv 侧没有一个叫 ready 的属性，所以等**任何一条能证明画面已经动起来的流**：
  /// 视频参数出现、时长非零、或位置开始前进；同时盯 error 流，出错就立刻进 failed。
  Future<void> _awaitFirstFrame() async {
    await Future.any<void>(<Future<void>>[
      () async {
        await _player.stream.videoParams
            .firstWhere((p) => (p.w ?? 0) > 0 || (p.dw ?? 0) > 0);
      }(),
      () async {
        await _player.stream.duration.firstWhere((d) => d > Duration.zero);
      }(),
      () async {
        await _player.stream.position.firstWhere((d) => d > Duration.zero);
      }(),
      () async {
        final error = await _player.stream.error.first;
        _failure = error;
        _setPhase(VideoEnginePhase.failed);
      }(),
    ]);
    if (_phase == VideoEnginePhase.failed) return;
    await _refreshMetadata();
    _setPhase(VideoEnginePhase.ready);
  }

  void _subscribe() {
    if (_subs.isNotEmpty) return;
    _subs.add(_player.stream.playing.listen((v) => _playingCtrl.add(v)));
    _subs.add(_player.stream.position.listen((v) {
      _positionCtrl.add(v);
      if (_seeking) {
        // mpv 没有「正在 seek」这个属性。位置一恢复前进就说明 seek 落帧了，
        // 于是用「seek 后置位 + 位置推进后清位」近似 mimage 的 `is_seeking`。
        _seekClear?.cancel();
        _seekClear = Timer(const Duration(milliseconds: 120), () {
          _seeking = false;
        });
      }
    }));
    _subs.add(_player.stream.duration.listen((v) {
      _durationCtrl.add(v);
      _metadata = _copyMeta(duration: v);
    }));
    _subs.add(_player.stream.completed.listen(_completedCtrl.add));
    _subs.add(_player.stream.tracks.listen((tracks) {
      _subtitleTracks = tracks.subtitle
          .map(
            (t) => VideoMediaTrack(
              id: t.id,
              title: t.title ?? t.language ?? t.id,
              language: t.language,
              // media_kit 用 uri / data 两个标记表示「外挂进来的字幕」。
              external: t.uri || t.data,
              selected: _player.state.track.subtitle.id == t.id,
            ),
          )
          .toList(growable: false);
      _audioTracks = tracks.audio
          .map(
            (t) => VideoMediaTrack(
              id: t.id,
              title: t.title ?? t.language ?? t.id,
              language: t.language,
              selected: _player.state.track.audio.id == t.id,
            ),
          )
          .toList(growable: false);
    }));
    _subs.add(_player.stream.videoParams.listen((p) {
      final w = p.w ?? 0;
      final h = p.h ?? 0;
      if (w == 0 || h == 0) return;
      // mpv 给的是像素宽高比 par（浮点），信息卡要的是 mimage 那对 sar 整数：
      // 用 1000 为分母取近似再约分，误差 < 0.1%，够解释「为什么不是 16:9」。
      final par = p.par ?? 1.0;
      final sar = VideoMetadata.normalizeSar(
        (par * 1000).round(),
        1000,
      );
      _metadata = _copyMeta(
        width: w,
        height: h,
        sarNum: sar.$1,
        sarDen: sar.$2,
      );
    }));
    _subs.add(_player.stream.audioBitrate.listen((b) {
      if (b == null) return;
      _metadata = _copyMeta(bitrateKbps: b.round());
    }));
  }

  VideoMetadata _copyMeta({
    Duration? duration,
    int? width,
    int? height,
    int? sarNum,
    int? sarDen,
    int? bitrateKbps,
  }) => VideoMetadata(
    duration: duration ?? _metadata.duration,
    width: width ?? _metadata.width,
    height: height ?? _metadata.height,
    frameRate: _metadata.frameRate,
    bitrateKbps: bitrateKbps ?? _metadata.bitrateKbps,
    videoCodec: _metadata.videoCodec,
    audioCodec: _metadata.audioCodec,
    chapters: _metadata.chapters,
    sarNum: sarNum ?? _metadata.sarNum,
    sarDen: sarDen ?? _metadata.sarDen,
  );

  Future<void> _refreshMetadata() async {
    final fps = double.tryParse(await _get('container-fps') ?? '');
    final bitrate = int.tryParse(
      (await _get('bitrate') ?? '').replaceAll(RegExp(r'[^\d]'), ''),
    );
    final codec = await _get('video-codec');
    final audioCodec = await _get('audio-codec-name');
    final chapters = await _readChapters();
    _metadata = _copyMeta(
      duration: _player.state.duration,
      bitrateKbps: bitrate,
    );
    _metadata = VideoMetadata(
      duration: _metadata.duration,
      width: _metadata.width,
      height: _metadata.height,
      frameRate: fps,
      bitrateKbps: _metadata.bitrateKbps,
      videoCodec: _clean(codec),
      audioCodec: _clean(audioCodec),
      chapters: chapters,
      sarNum: _metadata.sarNum,
      sarDen: _metadata.sarDen,
    );
  }

  String? _clean(String? v) =>
      v == null || v.isEmpty || v == '(null)' ? null : v;

  /// mpv 的 `chapter-list` 是节点属性，`getProperty` 回一段 JSON 文本。
  Future<List<VideoChapter>> _readChapters() async {
    final raw = await _get('chapter-list');
    if (raw == null || raw.isEmpty || raw == '(null)') {
      return const <VideoChapter>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <VideoChapter>[];
      final out = <VideoChapter>[];
      for (final item in decoded.whereType<Map>()) {
        final title = item['title'];
        if (title is! String || title.isEmpty) continue;
        final time = item['time'];
        out.add(
          VideoChapter(
            index: (item['num'] as num?)?.toInt() ?? out.length,
            title: title,
            at: Duration(seconds: math.max(0, (time as num?)?.toInt() ?? 0)),
          ),
        );
      }
      return out;
    } on FormatException {
      return const <VideoChapter>[];
    }
  }

  // ── 底层：mpv command / property ──────────────────────────────────────

  Future<void> _set(String key, String value) async {
    await _cmd(<String>['set', key, value]);
  }

  Future<String?> _get(String key) async {
    final native = _native;
    if (native == null) return null;
    try {
      final value = await native.getProperty(key);
      return value == 'nil' ? null : value;
    } catch (_) {
      // 属性在这个 mpv 构建里不可读：返回 null，界面按「该字段不可用」显示 —。
      return null;
    }
  }

  Future<void> _cmd(List<String> args) async {
    final native = _native;
    if (native == null) return;
    try {
      await native.command(args);
    } catch (_) {
      // 命令不被支持：与属性同理，不让它冒成「视频播不了」。
    }
  }

  // ── transport 实现 ────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> setPlaying(bool playing) =>
      playing ? _player.play() : _player.pause();

  @override
  Future<void> seek(Duration to) async {
    _seeking = true;
    _seekClear?.cancel();
    // 超时兜底：位置不推进的坏文件不该把「正在 seek」永远挂在界面上。
    _seekClear = Timer(const Duration(seconds: 2), () => _seeking = false);
    await _player.seek(to);
  }

  @override
  Future<void> seekPaused(Duration to) async {
    if (isPlaying) await _player.pause();
    await seek(to);
  }

  @override
  Future<RelativeSeekOutcome> seekRelative(Duration delta) async {
    final total = duration;
    if (total <= Duration.zero) return RelativeSeekOutcome.noMedia;
    final next = position + delta;
    if (next < Duration.zero) {
      await seek(Duration.zero);
      return RelativeSeekOutcome.clampedToStart;
    }
    if (next > total) {
      await seek(total);
      return RelativeSeekOutcome.clampedToEnd;
    }
    await seek(next);
    return RelativeSeekOutcome.applied;
  }

  @override
  Future<void> stepFrame(int direction) =>
      _cmd(<String>[direction < 0 ? 'frame-back-step' : 'frame-step']);

  @override
  Future<void> jumpChapter(int direction) =>
      _cmd(<String>['add', 'chapter', direction < 0 ? '-1' : '1']);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(int percent) =>
      _player.setVolume(percent.clamp(0, 130).toDouble());

  @override
  Future<void> setMuted(bool muted) => _set(MpvKeys.mute, muted ? 'yes' : 'no');

  @override
  Future<void> setLoopFile(bool enabled) =>
      _set(MpvKeys.loopFile, enabled ? 'inf' : 'no');

  @override
  Future<void> setAbLoop(VideoAbLoop? range) async {
    if (range == null) {
      await _set(MpvKeys.abLoopA, 'no');
      await _set(MpvKeys.abLoopB, 'no');
      return;
    }
    await _set(MpvKeys.abLoopA, range.a.inMilliseconds.toString());
    await _set(MpvKeys.abLoopB, range.b.inMilliseconds.toString());
  }

  @override
  Future<void> setFilter(VideoFilterState filter) async {
    // neo 的 UI 是 0–200%（100 = 原样），mpv 的属性是 0–100（50 = 原样），所以除以 2。
    await _set(MpvKeys.brightness, (filter.brightness / 2).toStringAsFixed(1));
    await _set(MpvKeys.contrast, (filter.contrast / 2).toStringAsFixed(1));
    await _set(MpvKeys.saturation, (filter.saturation / 2).toStringAsFixed(1));
  }

  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle style) async {
    await _set(MpvKeys.subScale, style.sizeEm.toStringAsFixed(2));
    await _set(MpvKeys.subPos, style.bottomPercent.toString());
    await _set(MpvKeys.subColor, _mpvAssColor(style.colorHex, 0));
    await _set(
      MpvKeys.subBackColor,
      _mpvAssColor('000000', style.backgroundOpacityPercent),
    );
    await _set(MpvKeys.subVisible, 'yes');
  }

  /// mpv/ASS 的颜色是 `&HBBGGRRAA`（尾缀是「透明量」，不是 alpha 前缀）。
  String _mpvAssColor(String hex, int opacityPercent) {
    final clean = hex.replaceAll('#', '');
    if (clean.length < 6) return '&Hffffff&';
    final r = clean.substring(0, 2);
    final g = clean.substring(2, 4);
    final b = clean.substring(4, 6);
    final alpha = (255 - (opacityPercent.clamp(0, 100) * 255 / 100)).round();
    return '&H$b$g$r${alpha.toRadixString(16).padLeft(2, '0')}&';
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _set(MpvKeys.subDelay, (delay.inMilliseconds / 1000).toStringAsFixed(3));

  @override
  Future<void> selectSubtitleTrack(String? id) async {
    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final match = _subtitleTracks.where((t) => t.id == id).firstOrNull;
    if (match != null && match.external) {
      // 外挂字幕：归档里的条目已经由 VideoMaterializer 落成磁盘文件。
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(id, title: match.title, language: match.language),
      );
      return;
    }
    await _player.setSubtitleTrack(SubtitleTrack(id, null, null));
  }

  @override
  Future<void> selectAudioTrack(String? id) async {
    await _player.setAudioTrack(
      id == null ? AudioTrack.no() : AudioTrack(id, null, null),
    );
  }

  @override
  Future<void> addSubtitleFile(String path) async {
    if (!await File(path).exists()) return;
    await _cmd(<String>['sub-add', path]);
  }

  @override
  Future<void> setVideoEnabled(bool enabled) =>
      _set(MpvKeys.video, enabled ? 'yes' : 'no');

  @override
  Future<String?> screenshot(String path) async {
    await _cmd(<String>['screenshot-to-file', path, 'video']);
    // mpv 异步落盘，稍等一下再报路径，否则调用方拿去显示会读到半个文件。
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (await File(path).exists()) return path;
    }
    return null;
  }

  @override
  Future<double> avDriftMs() async {
    final raw = await _get('avsync');
    return (double.tryParse(raw ?? '') ?? 0) * 1000;
  }

  @override
  Future<void> close() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _seekClear?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
  }
}
