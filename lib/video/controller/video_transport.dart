/// 视频传输端口：播放器的**能力面**，不带任何 Widget / media_kit 类型。
///
/// 形状照 mImageViewer `src/video/mod.rs` 的 `VideoPlayer` 公开面
/// （transport / seek / rate / volume / loop / frame-step / chapters），
/// 这样「引擎换成 mpv」这件事只发生在一个实现文件里。
library;

import 'dart:async';

/// 一条字幕 / 音轨。
class VideoMediaTrack {
  const VideoMediaTrack({
    required this.id,
    required this.title,
    this.language,
    this.external = false,
    this.selected = false,
  });

  final String id;
  final String title;
  final String? language;

  /// 是否是外挂字幕文件（而非容器内轨）。
  final bool external;
  final bool selected;

  @override
  String toString() => 'VideoMediaTrack($id, $title, ext=$external)';
}

/// 章节边界。mImageViewer `decoder.rs:1594 boundary_starts_from_chapters` 的产物。
class VideoChapter {
  const VideoChapter({required this.index, required this.title, required this.at});

  final int index;
  final String title;
  final Duration at;
}

/// 一次打开的元数据（mimage `VideoInfo` + neo 的信息卡字段）。
class VideoMetadata {
  const VideoMetadata({
    required this.duration,
    this.width = 0,
    this.height = 0,
    this.frameRate,
    this.bitrateKbps,
    this.videoCodec,
    this.audioCodec,
    this.chapters = const <VideoChapter>[],
    this.sarNum = 1,
    this.sarDen = 1,
  });

  static const VideoMetadata unknown = VideoMetadata(duration: Duration.zero);

  final Duration duration;
  final int width;
  final int height;
  final double? frameRate;
  final int? bitrateKbps;
  final String? videoCodec;
  final String? audioCodec;
  final List<VideoChapter> chapters;

  /// 采样宽高比分子/分母。**显示宽高比 = 像素宽高比 × SAR**，
  /// mimage 用 `normalize_sar`（`decoder.rs:1185`）把它归一化；mpv 会自己按 DAR 显示，
  /// 这里留着是为了信息卡能解释「为什么 1920×1080 看着不像 16:9」。
  final int sarNum;
  final int sarDen;

  /// 归一化 SAR。0/0 一类的非法值退回 1:1。
  (int, int) get normalizedSar => normalizeSar(sarNum, sarDen);

  static (int, int) normalizeSar(int num, int den) {
    if (num <= 0 || den <= 0) return (1, 1);
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(num, den);
    return (num ~/ g, den ~/ g);
  }
}

/// 画面滤镜三值（neo 的亮度/对比度/饱和度滑杆，0–200%，100 = 原样）。
class VideoFilterState {
  const VideoFilterState({this.brightness = 100, this.contrast = 100, this.saturation = 100});

  final int brightness;
  final int contrast;
  final int saturation;

  bool get isDefault =>
      brightness == 100 && contrast == 100 && saturation == 100;

  VideoFilterState copyWith({int? brightness, int? contrast, int? saturation}) =>
      VideoFilterState(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
      );

  static const VideoFilterState neutral = VideoFilterState();
}

/// 字幕渲染样式（neo：字号 em、颜色、底色不透明度、底部偏移）。
class VideoSubtitleStyle {
  const VideoSubtitleStyle({
    this.sizeEm = 1.0,
    this.colorHex = 'ffffff',
    this.backgroundOpacityPercent = 70,
    this.bottomPercent = 5,
  });

  final double sizeEm;
  final String colorHex;
  final int backgroundOpacityPercent;
  final int bottomPercent;
}

/// A–B 循环区间。
class VideoAbLoop {
  const VideoAbLoop({required this.a, required this.b});

  final Duration a;
  final Duration b;

  bool contains(Duration position) => position >= a && position <= b;
}

/// 引擎阶段 —— mImageViewer `engine/state.rs:23-118` 的 `EngineState` + `ReadinessLatch`。
///
/// 为什么要有这么多档：就绪闩决定「什么时候才允许显示控制条 / 允许翻页」。
/// 只有 `playing|paused` 两档的话，第一帧还没解出来时控制条上的时长是 0，
/// 用户一拖就跳到结尾 —— 那是上游用 `ReadinessRequirements::for_media()` 挡住的具体故障。
enum VideoEnginePhase {
  idle,
  opening,
  /// 已解出足够帧、可以出声/出画（mimage 的 preroll gate）。
  prerolling,
  ready,
  failed,
}

/// 打开一个视频源的参数（mimage `VideoPlayer::open` 的参数子集）。
class VideoOpenOptions {
  const VideoOpenOptions({
    this.autoplay = true,
    this.resumeAt,
    this.hardwareDecode = true,
    this.deinterlace = false,
    this.audioOnly = false,
    this.volume = 100,
    this.muted = false,
    this.rate = 1.0,
  });

  final bool autoplay;
  final Duration? resumeAt;
  final bool hardwareDecode;
  final bool deinterlace;

  /// mimage 的「视频→纯音频」模式：不解画面、只出声，省掉整条 GPU 路。
  final bool audioOnly;
  final int volume;
  final bool muted;
  final double rate;
}

/// 相对跳转的结果（mimage `seek_relative -> RelativeSeekOutcome`）。
enum RelativeSeekOutcome { applied, clampedToStart, clampedToEnd, noMedia }

/// 播放器能力面。实现者：`MpvVideoTransport`（media_kit / libmpv）。
abstract class VideoTransport {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;
  Stream<VideoEnginePhase> get phaseStream;

  VideoMetadata get metadata;
  Duration get position;
  Duration get duration;
  bool get isPlaying;
  bool get isSeeking;

  Future<void> open(String uri, {VideoOpenOptions options = const VideoOpenOptions()});
  Future<void> close();

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> setPlaying(bool playing);

  Future<void> seek(Duration to);
  Future<RelativeSeekOutcome> seekRelative(Duration delta);
  /// 暂停下也要能定位（mimage `seek_paused`：逐帧看时不能顺手把播放打开）。
  Future<void> seekPaused(Duration to);
  /// 逐帧步进。direction = ±1（mimage `step_frame`）。
  Future<void> stepFrame(int direction);

  /// 跳到下/上一章。direction = ±1（mimage 的章节边界 + neoview 的
  /// `boundary_starts_from_chapters`：章节只是数据时用户没法用它跳转）。
  /// 容器没有章节时实现应静默返回，不抛。
  Future<void> jumpChapter(int direction);

  Future<void> setRate(double rate);
  Future<void> setVolume(int percent);
  Future<void> setMuted(bool muted);

  /// 循环：`null` = 单帧循环关闭；`yes` = 单文件循环；mimage 的 `set_loop_enabled`。
  Future<void> setLoopFile(bool enabled);
  Future<void> setAbLoop(VideoAbLoop? range);

  Future<void> setFilter(VideoFilterState filter);
  Future<void> setSubtitleStyle(VideoSubtitleStyle style);
  Future<void> setSubtitleDelay(Duration delay);

  List<VideoMediaTrack> get subtitleTracks;
  List<VideoMediaTrack> get audioTracks;
  Future<void> selectSubtitleTrack(String? id);
  Future<void> selectAudioTrack(String? id);
  /// 外挂字幕文件（SRT/ASS 直接喂给引擎；VTT 要先转换）。
  Future<void> addSubtitleFile(String path);

  /// 视频→纯音频模式开关（mimage 的 video->audio）。
  Future<void> setVideoEnabled(bool enabled);

  /// 截图到文件，返回落盘路径（neo 的「截图」按钮、mimage 的 seek 条缩略图都靠它）。
  Future<String?> screenshot(String path);

  /// 音画漂移（ms）。mimage `av_drift_ms()`：出问题时用户要能在信息卡上看到是谁慢了。
  Future<double> avDriftMs();

  /// 解码/打开失败的可读原因；成功时 null。
  String? get failureReason;
}
