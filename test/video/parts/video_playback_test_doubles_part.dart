part of '../video_playback_logic_test.dart';
// 测试替身与等待助手


class _NullHost implements ReaderVideoHost {
  int listEndedCalls = 0;

  @override
  void onVideoListEnded() => listEndedCalls++;

  @override
  void onVideoProgress(VideoPlaybackProgress progress) {}
}


class _FakeTransport implements VideoTransport {
  _FakeTransport({
    this.duration = Duration.zero,
    this.chapters = const <VideoChapter>[],
  });

  /// 章节列表：跳转动作在「没有章节」时必须判定为不适用。
  final List<VideoChapter> chapters;

  final List<String> commands = <String>[];
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<VideoEnginePhase> _phase =
      StreamController<VideoEnginePhase>.broadcast();

  @override
  Duration duration;
  bool autoplayEnded = false;

  void emitCompleted() => _completed.add(true);
  void resetEnded() => _completed.add(false);
  void emitPosition(Duration at) => _position.add(at);

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<VideoEnginePhase> get phaseStream => _phase.stream;

  /// 逐帧回填要按 1/fps 算，所以 metadata 里得能给出帧率。
  double? fpsForStep;
  @override
  VideoMetadata get metadata => VideoMetadata(
    duration: duration,
    chapters: chapters,
    frameRate: fpsForStep,
  );
  @override
  Duration get position => _pos;
  @override
  bool get isSeeking => false;
  @override
  String? get failureReason => null;

  /// 可写：动作派发那条测试要有「容器里已经有两条字幕」的可观察条件。
  List<VideoMediaTrack> subs = const <VideoMediaTrack>[];
  @override
  List<VideoMediaTrack> get subtitleTracks => subs;
  @override
  List<VideoMediaTrack> get audioTracks => const <VideoMediaTrack>[];

  @override
  Future<void> open(
    String uri, {
    VideoOpenOptions options = const VideoOpenOptions(),
  }) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> playOrPause() async => commands.add('toggle');
  @override
  Future<void> setPlaying(bool playing) async =>
      commands.add('playing=$playing');

  /// 真位置：会跟着 seek 走，且按端点夹住 —— 「越界返回哪种 outcome」
  /// 是 mimage 边界规则的要点，只会返回 applied 的假实现验不出这些分支。
  Duration _pos = Duration.zero;
  @override
  Future<void> seek(Duration to) async {
    _pos = to;
    commands.add('seek=${to.inSeconds}s');
  }

  @override
  Future<void> seekPaused(Duration to) async => seek(to);
  @override
  Future<RelativeSeekOutcome> seekRelative(Duration delta) async {
    commands.add('rel=${delta.inSeconds}s');
    final next = _pos + delta;
    if (next < Duration.zero) {
      _pos = Duration.zero;
      return RelativeSeekOutcome.clampedToStart;
    }
    if (next > duration) {
      _pos = duration;
      return RelativeSeekOutcome.clampedToEnd;
    }
    _pos = next;
    return RelativeSeekOutcome.applied;
  }

  @override
  Future<void> stepFrame(int direction) async =>
      commands.add('frame=$direction');
  @override
  Future<void> jumpChapter(int direction) async =>
      commands.add('chapter=$direction');
  @override
  Future<void> setRate(double rate) async => commands.add('rate=$rate');
  @override
  Future<void> setVolume(int percent) async => commands.add('vol=$percent');
  @override
  Future<void> setMuted(bool muted) async => commands.add('mute=$muted');
  @override
  Future<void> setLoopFile(bool enabled) async =>
      commands.add('loopFile=$enabled');
  @override
  Future<void> setAbLoop(VideoAbLoop? range) async => commands.add(
    range == null
        ? 'ab=off'
        : 'ab=${range.a.inSeconds}s..${range.b.inSeconds}s',
  );

  @override
  Future<void> setFilter(VideoFilterState filter) async {}
  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle style) async {}
  @override
  Future<void> setSubtitleDelay(Duration delay) async =>
      commands.add('subDelay=${delay.inMilliseconds}ms');
  @override
  Future<void> selectSubtitleTrack(String? id) async =>
      commands.add('subTrack=$id');
  @override
  Future<void> selectAudioTrack(String? id) async {}
  @override
  Future<void> addSubtitleFile(String path) async {}
  @override
  Future<void> setVideoEnabled(bool enabled) async =>
      commands.add('video=$enabled');

  /// 可写：预览提供器要在「播放中」时故意不去抢位置，测试要能切换它。
  @override
  bool isPlaying = false;
  @override
  Future<String?> screenshot(String path) async {
    commands.add('shot');
    return path;
  }

  @override
  Future<double> avDriftMs() async => 0;
}


Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
