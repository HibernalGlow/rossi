/// 视频播放状态机。
///
/// 逐行对照翻译自 neoview
/// `src/nodes/neoview/features/video/ReaderVideoController.ts`
/// （快照字段 9-22、动作端口 24-35、注册栈与 `#active` 268-305、夹取规则、
/// `ended → onListEnded` 只在 `list` 档、每个动作返回 bool 表示「有没有活动目标」）。
/// 引擎阶段 / A–B 循环 / 逐帧步进这几档取自 mImageViewer
/// `src/video/engine/state.rs:23-118`、`mod.rs` 的 `step_frame` 与 `set_loop_target_secs`。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zephyr/video/controller/video_transport.dart';

enum ReaderVideoLoopMode {
  /// 播完接下一条（阅读里 = 翻到下一页）。
  list,

  /// 单条循环。
  single,

  /// 播完即止。
  none;

  ReaderVideoLoopMode next() => switch (this) {
    ReaderVideoLoopMode.list => ReaderVideoLoopMode.single,
    ReaderVideoLoopMode.single => ReaderVideoLoopMode.none,
    ReaderVideoLoopMode.none => ReaderVideoLoopMode.list,
  };
}

/// 对外可见的一帧播放状态（neo `ReaderVideoSnapshot`）。
@immutable
class ReaderVideoSnapshot {
  const ReaderVideoSnapshot({
    required this.playing,
    required this.currentTime,
    required this.duration,
    required this.volume,
    required this.muted,
    required this.playbackRate,
    required this.minimumPlaybackRate,
    required this.maximumPlaybackRate,
    required this.playbackRateStep,
    required this.loopMode,
    required this.seekMode,
    required this.active,
    this.phase = VideoEnginePhase.idle,
    this.buffered,
    this.abLoop,
    this.audioOnly = false,
    this.failureReason,
  });

  static const ReaderVideoSnapshot empty = ReaderVideoSnapshot(
    playing: false,
    currentTime: Duration.zero,
    duration: Duration.zero,
    volume: 1.0,
    muted: false,
    playbackRate: 1.0,
    minimumPlaybackRate: 0.25,
    maximumPlaybackRate: 16.0,
    playbackRateStep: 0.25,
    loopMode: ReaderVideoLoopMode.list,
    seekMode: false,
    active: false,
  );

  final bool playing;
  final Duration currentTime;
  final Duration duration;

  /// 0.0–1.0，与 neo 一致；传给引擎时才换算成百分比。
  final double volume;
  final bool muted;
  final double playbackRate;
  final double minimumPlaybackRate;
  final double maximumPlaybackRate;
  final double playbackRateStep;
  final ReaderVideoLoopMode loopMode;

  /// 「快进档」：开着时翻页输入改成跳转（neo `ReaderInputActionExecutor.ts:180-190`）。
  final bool seekMode;
  final bool active;
  final VideoEnginePhase phase;
  final Duration? buffered;
  final VideoAbLoop? abLoop;
  final bool audioOnly;
  final String? failureReason;

  bool get ready =>
      phase == VideoEnginePhase.ready ||
      phase == VideoEnginePhase.prerolling;

  double get progress => duration.inMilliseconds == 0
      ? 0
      : (currentTime.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  ReaderVideoSnapshot copyWith({
    bool? playing,
    Duration? currentTime,
    Duration? duration,
    double? volume,
    bool? muted,
    double? playbackRate,
    ReaderVideoLoopMode? loopMode,
    bool? seekMode,
    bool? active,
    VideoEnginePhase? phase,
    Duration? buffered,
    VideoAbLoop? abLoop,
    bool clearAbLoop = false,
    bool? audioOnly,
    String? failureReason,
  }) => ReaderVideoSnapshot(
    playing: playing ?? this.playing,
    currentTime: currentTime ?? this.currentTime,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    playbackRate: playbackRate ?? this.playbackRate,
    minimumPlaybackRate: minimumPlaybackRate,
    maximumPlaybackRate: maximumPlaybackRate,
    playbackRateStep: playbackRateStep,
    loopMode: loopMode ?? this.loopMode,
    seekMode: seekMode ?? this.seekMode,
    active: active ?? this.active,
    phase: phase ?? this.phase,
    buffered: buffered ?? this.buffered,
    abLoop: clearAbLoop ? null : (abLoop ?? this.abLoop),
    audioOnly: audioOnly ?? this.audioOnly,
    failureReason: failureReason ?? this.failureReason,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderVideoSnapshot &&
      other.playing == playing &&
      other.currentTime == currentTime &&
      other.duration == duration &&
      other.volume == volume &&
      other.muted == muted &&
      other.playbackRate == playbackRate &&
      other.loopMode == loopMode &&
      other.seekMode == seekMode &&
      other.active == active &&
      other.phase == phase &&
      other.abLoop?.a == abLoop?.a &&
      other.abLoop?.b == abLoop?.b &&
      other.audioOnly == audioOnly;

  @override
  int get hashCode => Object.hash(
    playing,
    currentTime,
    duration,
    volume,
    muted,
    playbackRate,
    loopMode,
    seekMode,
    active,
    phase,
    abLoop?.a,
    abLoop?.b,
    audioOnly,
  );
}

/// 速率档边界归一化（neo `normalizeRuntime`，源码 339）。
///
/// 上游把「用户能填什么」和「运行时能用什么」分开：配置里写 min=0、max=0 也不能让
/// 播放器拿到 0 倍速 —— 那会让时钟停在原地，而界面显示成「卡住了」。
({double min, double max, double step}) normalizePlaybackRateRuntime({
  double min = 0.25,
  double max = 16,
  double step = 0.25,
}) {
  final normalizedMin = min < 0.05 ? 0.05 : min;
  final normalizedMax = max < normalizedMin ? normalizedMin : max;
  final normalizedStep = step < 0.01 ? 0.01 : step;
  return (
    min: normalizedMin,
    max: normalizedMax,
    step: normalizedStep,
  );
}

/// 播放控制器的宿主接口：把「播完了要翻页」这类跨界动作交回上层。
abstract interface class ReaderVideoHost {
  /// `loopMode == list` 且一条播完 —— 阅读页在这里翻页，文件预览在这里什么都不做。
  void onVideoListEnded();

  /// 需要落盘的进度（位置 / 总时长）。
  void onVideoProgress(VideoPlaybackProgress progress);
}

class VideoPlaybackProgress {
  const VideoPlaybackProgress({
    required this.key,
    required this.position,
    required this.duration,
    required this.completed,
  });

  /// 归属键（书 + 章 + 页），与 neo 一样由上层决定，控制器不关心其构成。
  final String key;
  final Duration position;
  final Duration duration;
  final bool completed;

  /// 「看完」判定：结尾 5 s 内，或总时长的 5% 内 —— **取两者的小值**。
  /// 长视频用 5% 会太宽松（3 分钟视频的「看完」线落到 9 s 前），短视频用固定 5 s
  /// 又太苛刻，所以两边取小。上游 `PageVideo.tsx:99-141` 同式。
  static bool isCompletedAt({
    required Duration position,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return false;
    final fiveSeconds = Duration(seconds: 5);
    final fivePercent = Duration(
      milliseconds: (duration.inMilliseconds * 0.05).round(),
    );
    final tolerance = fiveSeconds < fivePercent ? fiveSeconds : fivePercent;
    return position >= duration - tolerance;
  }

  /// 恢复播放位置的门槛：没看完、且位置落在「结尾 5 s」之前才恢复。
  static Duration? restorePosition({
    required Duration position,
    required Duration duration,
    required bool completed,
  }) {
    if (completed) return null;
    if (position <= Duration.zero) return null;
    if (position >= duration - const Duration(seconds: 5)) return null;
    return position;
  }
}

/// 一个播放目标（一个视频页）对应一个控制器实例。
///
/// 为什么控制器不直接是 Widget 的 State：绑定体系（ADR-0015）要能被程序化驱动，
/// 判据要能单测，而 `Focus` 里写死的按键路径两样都做不到。所以状态机是纯 Dart，
/// Widget 只订阅它的 [snapshot]。
class ReaderVideoController extends ChangeNotifier {
  ReaderVideoController({
    required this.host,
    required this.progressKey,
    VideoTransport? transport,
    ({double min, double max, double step})? rateRuntime,
  }) : _transport = transport {
    final r = normalizePlaybackRateRuntime(
      min: rateRuntime?.min ?? 0.25,
      max: rateRuntime?.max ?? 16,
      step: rateRuntime?.step ?? 0.25,
    );
    _snapshot = ReaderVideoSnapshot(
      playing: false,
      currentTime: Duration.zero,
      duration: Duration.zero,
      volume: 1.0,
      muted: false,
      playbackRate: 1.0,
      minimumPlaybackRate: r.min,
      maximumPlaybackRate: r.max,
      playbackRateStep: r.step,
      loopMode: ReaderVideoLoopMode.list,
      seekMode: false,
      active: transport != null,
      phase: VideoEnginePhase.idle,
    );
  }

  final ReaderVideoHost host;
  final String progressKey;

  VideoTransport? _transport;
  ReaderVideoSnapshot _snapshot = ReaderVideoSnapshot.empty;
  Timer? _progressTimer;
  double _previousPlaybackRate = 1.0;
  bool _endedFired = false;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  Duration _lastReported = Duration.zero;

  ReaderVideoSnapshot get snapshot => _snapshot;
  VideoTransport? get transport => _transport;

  /// 挂上播放器并开始转发事件（neo 的 `register`）。
  Future<void> attach(VideoTransport transport) async {
    await detach();
    _transport = transport;
    _endedFired = false;
    // 先用 transport 的当前值打一份底：**流只投递未来的事件**，而页面完全可能在
    // 播放器已经加载完之后才挂上来（画中画、重新聚焦、晚到的首帧）。
    // 不打这个底，快照里的时长会停在 0 —— 而跳转夹取与进度上报都以它为准，
    // 症状是「进度条拖不动、进度永远不写」。
    _update(
      _snapshot.copyWith(
        duration: transport.duration,
        currentTime: transport.position,
        playing: transport.isPlaying,
        active: true,
      ),
    );
    _subs.add(
      transport.playingStream.listen((p) {
        _update(_snapshot.copyWith(playing: p));
      }),
    );
    _subs.add(transport.positionStream.listen(_onPosition));
    _subs.add(
      transport.durationStream.listen(
        (d) => _update(_snapshot.copyWith(duration: d)),
      ),
    );
    _subs.add(
      transport.completedStream.listen((done) {
        if (!done) {
          // 「不再处于结束态」就是新一播放的开始：结束闩必须复位，
          // 否则同一条视频第二次播完不会再翻页。
          _endedFired = false;
          return;
        }
        _onEnded();
      }),
    );
    _subs.add(
      transport.phaseStream.listen(
        (phase) => _update(
          _snapshot.copyWith(
            phase: phase,
            failureReason: phase == VideoEnginePhase.failed
                ? transport.failureReason
                : null,
          ),
        ),
      ),
    );
    _update(_snapshot.copyWith(active: true));
    _startProgressTimer();
  }

  Future<void> detach() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _progressTimer?.cancel();
    _progressTimer = null;
    flushProgress();
    _transport = null;
    _update(_snapshot.copyWith(active: false, playing: false));
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  void _update(ReaderVideoSnapshot next) {
    if (next == _snapshot) return;
    _snapshot = next;
    notifyListeners();
  }

  void _onPosition(Duration position) {
    // A–B 循环：越界回到 A（neo 把这条放在 overlay 的 timeupdate 里，
    // 但放在控制器里才可能被测试覆盖，也不会因为控制条收起而失效）。
    final ab = _snapshot.abLoop;
    if (ab != null && position > ab.b && ab.contains(_lastReported)) {
      _transport?.seek(ab.a);
      position = ab.a;
    }
    _lastReported = position;
    _update(_snapshot.copyWith(currentTime: position));
  }

  void _onEnded() {
    if (_endedFired) return;
    _endedFired = true;
    flushProgress();
    if (_snapshot.loopMode == ReaderVideoLoopMode.list) {
      host.onVideoListEnded();
    } else {
      _update(_snapshot.copyWith(playing: false));
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    // 5 s 节流写盘：位置每帧都在动，每帧写一次会把存储打穿。
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _reportProgress();
    });
  }

  void _reportProgress() {
    final duration = _snapshot.duration;
    if (duration <= Duration.zero) return;
    final position = _snapshot.currentTime;
    host.onVideoProgress(
      VideoPlaybackProgress(
        key: progressKey,
        position: position,
        duration: duration,
        completed: VideoPlaybackProgress.isCompletedAt(
          position: position,
          duration: duration,
        ),
      ),
    );
  }

  void flushProgress() => _reportProgress();

  // ── 动作：全部返回 bool，false = 没有活动目标（neo 的「动作不可用」）──

  Future<bool> togglePlay() async {
    final t = _transport;
    if (t == null) return false;
    if (_snapshot.playing) {
      await t.pause();
    } else {
      await t.play();
    }
    return true;
  }

  Future<bool> setPlaying(bool playing) async {
    final t = _transport;
    if (t == null) return false;
    await t.setPlaying(playing);
    return true;
  }

  /// 绝对跳转，夹到 `[0, duration]`。
  Future<bool> seek(Duration to) async {
    final t = _transport;
    if (t == null) return false;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (to > _snapshot.duration ? _snapshot.duration : to);
    _endedFired = false;
    await t.seek(clamped);
    _update(_snapshot.copyWith(currentTime: clamped));
    return true;
  }

  /// 按比例跳转（拖动条用）。
  Future<bool> seekFraction(double fraction) =>
      seek(_snapshot.duration * fraction.clamp(0.0, 1.0));

  Future<bool> seekRelative(Duration delta) async {
    final t = _transport;
    if (t == null) return false;
    _endedFired = false;
    await t.seekRelative(delta);
    return true;
  }

  /// 快退 10 s（neo 点左半屏 / 默认绑定）。
  Future<bool> seekBackward() => seekRelative(const Duration(seconds: -10));

  Future<bool> seekForward() => seekRelative(const Duration(seconds: 10));

  /// 逐帧步进（mimage `step_frame`）。暂停下也用，所以不顺手改播放状态。
  Future<bool> stepFrame(int direction) async {
    final t = _transport;
    if (t == null) return false;
    await t.stepFrame(direction < 0 ? -1 : 1);
    return true;
  }

  /// 跳到下/上一章。返回 false = 没有活动目标，或这个容器根本没有章节
  /// （mimage 把章节边界当数据用，但**没有章节时这条动作就是不适用**，
  /// 不该跳出一个「跳到了第 0 章」的假反馈）。
  Future<bool> jumpChapter(int direction) async {
    final t = _transport;
    if (t == null) return false;
    if (t.metadata.chapters.isEmpty) return false;
    _endedFired = false;
    await t.jumpChapter(direction);
    return true;
  }

  Future<bool> nextChapter() => jumpChapter(1);

  Future<bool> previousChapter() => jumpChapter(-1);

  Future<bool> setVolume(double volume) async {
    final t = _transport;
    if (t == null) return false;
    final clamped = volume.clamp(0.0, 1.0);
    // `muted ⇔ volume == 0`：上游把这两件事合成一条，是为了避免出现
    // 「音量为 0 但没静音」这种用户看不出差别却要让图标二选一的中间态。
    _update(_snapshot.copyWith(volume: clamped, muted: clamped == 0));
    await t.setVolume((clamped * 100).round());
    await t.setMuted(clamped == 0);
    return true;
  }

  Future<bool> toggleMute() async {
    final t = _transport;
    if (t == null) return false;
    final next = !_snapshot.muted;
    _update(_snapshot.copyWith(muted: next));
    await t.setMuted(next);
    return true;
  }

  /// 归一到配置的步长，再夹到 `[min, max]`。
  double clampPlaybackRate(double rate) {
    final s = _snapshot;
    final step = s.playbackRateStep;
    final snapped = (rate / step).roundToDouble() * step;
    return snapped.clamp(s.minimumPlaybackRate, s.maximumPlaybackRate);
  }

  Future<bool> setPlaybackRate(double rate) async {
    final t = _transport;
    if (t == null) return false;
    final clamped = clampPlaybackRate(rate);
    _previousPlaybackRate = clamped;
    _update(_snapshot.copyWith(playbackRate: clamped));
    await t.setRate(clamped);
    return true;
  }

  /// 1.0 ⇄ 上一个用过的倍速（neo 的 `toggleSpeed`）。
  Future<bool> toggleSpeed() => setPlaybackRate(
    _snapshot.playbackRate == 1.0 ? _previousPlaybackRate : 1.0,
  );

  Future<void> cycleLoopMode() async {
    final next = _snapshot.loopMode.next();
    _update(_snapshot.copyWith(loopMode: next));
    final t = _transport;
    if (t != null) await t.setLoopFile(next == ReaderVideoLoopMode.single);
  }

  Future<bool> setLoopMode(ReaderVideoLoopMode mode) async {
    _update(_snapshot.copyWith(loopMode: mode));
    final t = _transport;
    if (t == null) return false;
    await t.setLoopFile(mode == ReaderVideoLoopMode.single);
    return true;
  }

  /// 快进档开关：开着时「翻页」输入被重映射成跳转（判定在绑定派发里）。
  void toggleSeekMode() =>
      _update(_snapshot.copyWith(seekMode: !_snapshot.seekMode));

  void setSeekMode(bool enabled) => _update(_snapshot.copyWith(seekMode: enabled));

  // ── A–B 循环（mimage `loop_target_secs` / neo overlay A-B）──

  Duration? _pointA;

  /// 三态：设 A → 设 B（不成区间则清掉）→ 清空。
  void tapAbLoop() {
    final now = _snapshot.currentTime;
    if (_pointA == null) {
      _pointA = now;
      _update(_snapshot.copyWith(clearAbLoop: true));
      return;
    }
    if (now <= _pointA!) {
      _pointA = null;
      _update(_snapshot.copyWith(clearAbLoop: true));
      _transport?.setAbLoop(null);
      return;
    }
    final range = VideoAbLoop(a: _pointA!, b: now);
    _pointA = null;
    _update(_snapshot.copyWith(abLoop: range));
    _transport?.setAbLoop(range);
  }

  void clearAbLoop() {
    _pointA = null;
    _update(_snapshot.copyWith(clearAbLoop: true));
    _transport?.setAbLoop(null);
  }

  /// 当前 A 点（界面要显示「已标记 A」的中间态，它不在快照里）。
  Duration? get markedPointA => _pointA;

  Future<bool> setAudioOnly(bool enabled) async {
    final t = _transport;
    _update(_snapshot.copyWith(audioOnly: enabled));
    if (t == null) return false;
    await t.setVideoEnabled(!enabled);
    return true;
  }

  Future<bool> setFilter(VideoFilterState filter) async {
    final t = _transport;
    if (t == null) return false;
    await t.setFilter(filter);
    return true;
  }

  Future<bool> resetFilter() => setFilter(VideoFilterState.neutral);

  Future<String?> screenshot(String path) async =>
      await _transport?.screenshot(path);
}

/// 时长格式化：`m:ss`，一小时以上才带小时位（neo `formatVideoTime`）。
String formatVideoTime(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  String two(int v) => v.toString().padLeft(2, '0');
  final h = total.inHours;
  final m = total.inMinutes % 60;
  final s = total.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
