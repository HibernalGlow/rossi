/// 拖动条上的缩略帧与波形 —— mImageViewer `src/video/seek_strip*.rs` 的等效实现。
///
/// 借的是它三个设计，而不是它的解码器：
/// 1. **容差最近帧**（`thumbnail.rs`）：缓存按整数 PTS 键放在有序表里，
///    取「最近一个不超过目标的帧」，容差是**每次请求**的参数而不是全局值 ——
///    于是「鼠标悬停要快（容忍旧帧）」和「落点要准（宁可等）」共用一份缓存。
/// 2. **单槽位调度**（neoview `VideoProcessScheduler.ts:9-17`）：同一时刻只跑一个抽帧任务，
///    新请求只保留最新的一个待办。快速划动进度条时，队列里堆十个待办没有任何意义。
/// 3. **预览自带一路解码器**（`thumbnail.rs` 的独立 worker：自己的输入、自己的解码器）：
///    悬停只解帧，**绝不碰主播放器的位置**。借主播放器 `seekPaused` 定位的写法
///    等于「鼠标划过进度条就把视频拖到那儿去」，播放中点一下预览还会打断播放。
///    代价是解帧时多一台 mpv 实例（空闲 [VideoFramePreviewProvider.idleDispose] 释放）。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:zephyr/video/controller/video_transport.dart';

class VideoFramePreview {
  const VideoFramePreview({required this.at, required this.filePath});

  final Duration at;
  final String filePath;
}

/// 有序帧缓存 + 容差查找。键是**整数微秒**（`Duration.inMicroseconds` ——
/// Dart 的时间精度就是 µs，上游 mimage 用的是 ns，别照抄那个单位），
/// 与 mimage 同口径（浮点秒做键会因为量化差异而查不中，表现为「明明有帧却重新解」）。
class VideoFrameCache {
  VideoFrameCache({this.maxEntries = 100});

  /// neoview `ReaderVideoPlayerUtils.ts` 的 100 条 LRU；mimage 的量化容差也落在这个量级。
  final int maxEntries;
  final SplayTreeMap<int, VideoFramePreview> _byMicros =
      SplayTreeMap<int, VideoFramePreview>();

  int get length => _byMicros.length;

  /// 量化到 0.5 s（neo 的帧缓存键），避免鼠标蹭同一片区域就重复解帧。
  static int quantizeMicros(Duration at) =>
      (at.inMicroseconds ~/ 500000) * 500000;

  void put(Duration at, String filePath) {
    final key = quantizeMicros(at);
    _byMicros[key] = VideoFramePreview(at: at, filePath: filePath);
    while (_byMicros.length > maxEntries) {
      // 丢最老的（BTreeMap 的第一项）。上游同样是「最旧优先淘汰」，
      // 因为进度条的访问模式是局部滑动，不是随机跳。
      _byMicros.remove(_byMicros.firstKey());
    }
  }

  /// 取容差范围内最近的帧；优先「已过的那一帧」，因为拖动时用户看的是
  /// 「我拖到这儿之前最后看到了什么」，未来的帧会让他觉得时间轴对不上。
  VideoFramePreview? nearest({
    required Duration target,
    Duration tolerance = const Duration(milliseconds: 1500),
  }) {
    if (_byMicros.isEmpty) return null;
    final key = quantizeMicros(target);
    // 精确命中优先：拖动条落点常常正好就是缓存里那一格，
    // 这时不该退到「上一格」去（画面会差半秒，而半秒在慢速镜头下看得出来）。
    final exact = _byMicros[key];
    if (exact != null && (target - exact.at).abs() <= tolerance) return exact;
    final pastKey = _byMicros.lastKeyBefore(key);
    if (pastKey != null) {
      final past = _byMicros[pastKey];
      if (past != null && target - past.at <= tolerance) return past;
    }
    final futureKey = _byMicros.firstKeyAfter(key);
    if (futureKey != null) {
      final future = _byMicros[futureKey];
      if (future != null && future.at - target <= tolerance) return future;
    }
    // 两端都超容差时不给帧（宁可不显示，也不显示一个差了好几秒的画面）。
    return null;
  }

  void clear() => _byMicros.clear();
}

/// 单槽位抽帧调度器。
class _SingleSlotScheduler {
  bool _busy = false;
  Duration? _pending;
  Completer<void>? _idle;

  Future<void> get idle => _idle?.future ?? Future<void>.value();

  Future<void> request(
    Duration at,
    Future<void> Function(Duration) work,
  ) async {
    if (_busy) {
      _pending = at;
      return;
    }
    _busy = true;
    _idle = Completer<void>();
    try {
      Duration? next = at;
      while (next != null) {
        await work(next);
        next = _pending;
        _pending = null;
      }
    } finally {
      _pending = null;
      _busy = false;
      _idle!.complete();
    }
  }
}

/// 缩略帧提供者：**自带一台 headless 解码器**取帧。
///
/// 播放中也能出图，而且无论播放与否都不动主播放器的位置 —— 悬停只是预览。
class VideoFramePreviewProvider {
  VideoFramePreviewProvider({
    required VideoTransport Function() createPreviewTransport,
    VideoFrameCache? cache,
    this.cacheDirOverride,
    this.idleDispose = const Duration(minutes: 1),
  }) : _createTransport = createPreviewTransport,
       cache = cache ?? VideoFrameCache();

  /// 预览解码器工厂。页面把「与主播放器相同的硬解设置」从这里传进来：
  /// 用户关掉硬解时，预览那条路也不该偷偷走 GPU。
  final VideoTransport Function() _createTransport;

  final VideoFrameCache cache;

  /// 测试注入用：不给就走系统临时目录。
  final String? cacheDirOverride;

  /// 空闲这么久就把解码器放掉（下次悬停重开一次，几百毫秒）。
  /// 悬停是一阵一阵的，让一台 mpv 实例陪着看完整部片最浪费。
  final Duration idleDispose;

  static const Duration _openTimeout = Duration(seconds: 5);
  static const Duration _seekTimeout = Duration(seconds: 3);
  static const Duration _screenshotTimeout = Duration(seconds: 2);
  static const Duration _pollInterval = Duration(milliseconds: 40);
  static const Duration _shotRetryInterval = Duration(milliseconds: 120);

  /// `time-pos` 落到目标 ±这个范围就算 seek 落帧了。0.5 s 是帧缓存的量化格，
  /// 比它更紧没有意义（同一格本来就允许互相顶替）。
  static const Duration _seekTolerance = Duration(milliseconds: 400);

  final _SingleSlotScheduler _scheduler = _SingleSlotScheduler();
  Future<Directory>? _directory;
  bool _disposed = false;
  int _seq = 0;
  int _sourceGeneration = 0;
  String? _sourceUri;
  String? _readyUri;
  String? _brokenUri;
  VideoTransport? _grabber;
  Timer? _idleTimer;

  /// 预览解码器跟着页面走：换一页先把旧的放下（它可能正开着别的文件），
  /// 缓存同理 —— 键是时间点，换源后旧帧只会张冠李戴。
  void setSource(String uri) {
    if (_disposed || uri == _sourceUri) return;
    _sourceUri = uri;
    _sourceGeneration++;
    _brokenUri = null;
    cache.clear();
    unawaited(_releaseGrabber());
  }

  Future<Directory> _createCacheDir() async {
    final base = cacheDirOverride == null
        ? await getTemporaryDirectory()
        : Directory(cacheDirOverride!);
    await base.create(recursive: true);
    // 每页独占一个子目录，退出页面不能清掉其它泳道的预览帧。
    return base.createTemp('rossi-video-previews-');
  }

  /// 请求某一时刻的缩略帧。命中缓存直接回；未命中则排队解帧，
  /// 未命中且正在忙时**这次调用返回 null**（调用方显示占位），因为
  /// 「等一个正在解的旧位置」比「立刻给用户一个空白」更糟。
  Future<VideoFramePreview?> request(Duration at) async {
    if (_disposed) return null;
    final hit = cache.nearest(target: at);
    if (hit != null) return hit;
    if (_sourceUri == null || _brokenUri == _sourceUri) return null;
    final Directory dir;
    try {
      dir = await (_directory ??= _createCacheDir());
    } on FileSystemException {
      return null;
    }
    if (_disposed) return null;
    final generation = _sourceGeneration;
    unawaited(
      _scheduler.request(at, (target) async {
        final path = await _decode(generation, target, dir);
        if (path != null) cache.put(target, path);
        // 空闲从**最后一次用完之后**算起：解帧本身可能比空闲阈值长
        // （测试里就是），上弦太早会在取帧中途把解码器收走。
        if (!_disposed) _armIdleDispose();
      }),
    );
    return null;
  }

  /// 这一份工作还属于当前页面／当前源吗。翻页或退出之后，所有等待都要立刻收手 ——
  /// 否则新页面会陪着旧的解帧把超时等满（同 `MpvVideoTransport._awaitFirstFrame`）。
  bool _isStale(int generation) => _disposed || generation != _sourceGeneration;

  /// 一次抽帧：解码器常驻期间只 seek + 截图，不重开文件。
  Future<String?> _decode(
    int generation,
    Duration target,
    Directory dir,
  ) async {
    try {
      final grabber = await _ensureGrabber(generation);
      if (grabber == null || _isStale(generation)) return null;
      await grabber.seek(target);
      // seek 落帧之前 `screenshot` 截到的是**上一帧** —— 那正是「划到后段却显示
      // 前段画面」的形状，所以位置没落到目标附近就宁可不给帧（调用方显示占位）。
      if (!await _awaitSeekLanded(grabber, generation, target) ||
          _isStale(generation)) {
        return null;
      }
      final path = p.join(dir.path, 'f${_seq++}.jpg');
      final watch = Stopwatch()..start();
      while (watch.elapsed < _screenshotTimeout) {
        if (_isStale(generation)) return null;
        final shot = await grabber.screenshot(path);
        // 截图中途页面可能已经退出：那时落盘的帧连同目录一起被删了，
        // 再写进缓存就是给一个不存在的文件建索引。
        if (shot != null) return _isStale(generation) ? null : shot;
        await Future<void>.delayed(_shotRetryInterval);
      }
      return null;
    } catch (_) {
      // 预览失败只显示占位，不能中断播放或卡死后续抽帧任务。
      return null;
    }
  }

  /// 预览解码器：懒创建，打开一次后常驻到空闲超时。
  Future<VideoTransport?> _ensureGrabber(int generation) async {
    final uri = _sourceUri;
    if (uri == null) return null;
    final existing = _grabber;
    if (existing != null && _readyUri == uri) return existing;
    await _releaseGrabber();
    if (_isStale(generation)) return null;
    final grabber = _createTransport();
    _grabber = grabber;
    try {
      // `autoplay: false` 同时决定了它是一台「有画面的暂停播放器」：
      // 传输层的 open 会写 `vid=auto` —— 不开视频轨的 headless 播放器
      // 截不出图，而且是完全静默的（海报那条路的注脚）。
      await grabber.open(uri, options: const VideoOpenOptions(autoplay: false));
    } catch (_) {
      return _failGrabber(uri);
    }
    if (_isStale(generation)) {
      await _releaseGrabber();
      return null;
    }
    // 时长未知时 `seek` 会被引擎吞掉（海报那条路的注脚），先等它出现。
    // 轮询而不是订阅：`durationStream` 是广播流，订阅之前到达的那一帧不会补发。
    var ready = await _awaitDuration(grabber, generation);
    // 同进程里已经起过别的 mpv 实例时，**第一次** load 偶尔什么都不上报
    // （探针 5 次撞 2 次）。主播放器的传输层为此自动重开一次；预览这台是新起的，
    // 得自己兜住，否则表现就是「这一页的预览永远不出来」。
    if (!ready && !_isStale(generation)) {
      try {
        await grabber.open(
          uri,
          options: const VideoOpenOptions(autoplay: false),
        );
        ready = await _awaitDuration(grabber, generation);
      } catch (_) {
        ready = false;
      }
    }
    if (!ready) {
      if (_isStale(generation)) return null;
      return _failGrabber(uri);
    }
    if (_isStale(generation)) {
      await _releaseGrabber();
      return null;
    }
    _readyUri = uri;
    return grabber;
  }

  /// 坏源在这一页剩下的时间里只走占位：坏文件不该每悬停一次就重开一次播放器。
  Future<VideoTransport?> _failGrabber(String uri) async {
    _brokenUri = uri;
    await _releaseGrabber();
    return null;
  }

  Future<void> _releaseGrabber() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final grabber = _grabber;
    _grabber = null;
    _readyUri = null;
    if (grabber == null) return;
    try {
      await grabber.close();
    } catch (_) {
      // 关不掉的实例交给进程回收，预览链不该因此断掉。
    }
  }

  void _armIdleDispose() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDispose, () => unawaited(_releaseGrabber()));
  }

  Future<bool> _awaitDuration(VideoTransport grabber, int generation) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < _openTimeout) {
      if (_isStale(generation)) return false;
      if (grabber.duration > Duration.zero) return true;
      // 引擎已经给了结论（协议不认识、容器解不动）就不必把超时等满。
      if (grabber.failureReason != null) return false;
      await Future<void>.delayed(_pollInterval);
    }
    return false;
  }

  Future<bool> _awaitSeekLanded(
    VideoTransport grabber,
    int generation,
    Duration target,
  ) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < _seekTimeout) {
      if (_isStale(generation)) return false;
      if ((grabber.position - target).abs() <= _seekTolerance) return true;
      await Future<void>.delayed(_pollInterval);
    }
    return false;
  }

  /// 同步版：只在已缓存时给帧，用于鼠标拖动这种每帧都要问的场合。
  VideoFramePreview? peek(Duration at) => cache.nearest(target: at);

  Future<void> dispose() async {
    _disposed = true;
    _sourceGeneration++;
    cache.clear();
    await _scheduler.idle;
    await _releaseGrabber();
    final directory = _directory;
    if (directory == null) return;
    try {
      await (await directory).delete(recursive: true);
    } on FileSystemException {
      // 目录已被系统回收。
    }
  }
}

/// 波形条的一整条列 —— 一格一个 0–1 的 RMS 值。
///
/// 只保留「一列 + 它代表多久」这两个事实：取样、降采样、按窗口取区间这些
/// 都曾经在这里，但整条列一次算完后 UI 直接用，留着的分支就是没人走的死路。
class VideoWaveformStrip {
  const VideoWaveformStrip({
    required this.samples,
    required this.duration,
    this.binSecs = 0.1,
  });

  static const VideoWaveformStrip empty = VideoWaveformStrip(
    samples: <double>[],
    duration: Duration.zero,
  );

  final List<double> samples;
  final Duration duration;

  /// 每格宽度（秒）：让「一格代表多久」由数据带着走，而不是由格数反推。
  final double binSecs;

  bool get isEmpty => samples.isEmpty;
}
