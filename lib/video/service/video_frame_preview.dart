/// 拖动条上的缩略帧与波形 —— mImageViewer `src/video/seek_strip*.rs` 的等效实现。
///
/// 借的是它两个设计，而不是它的解码器：
/// 1. **容差最近帧**（`thumbnail.rs`）：缓存按整数 PTS 键放在有序表里，
///    取「最近一个不超过目标的帧」，容差是**每次请求**的参数而不是全局值 ——
///    于是「鼠标悬停要快（容忍旧帧）」和「落点要准（宁可等）」共用一份缓存。
/// 2. **单槽位调度**（neoview `VideoProcessScheduler.ts:9-17`）：同一时刻只跑一个抽帧任务，
///    新请求只保留最新的一个待办。快速划动进度条时，队列里堆十个待办没有任何意义。
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

  Future<void> request(Duration at, Future<void> Function(Duration) work) async {
    if (_busy) {
      _pending = at;
      return;
    }
    _busy = true;
    await work(at);
    _busy = false;
    final next = _pending;
    _pending = null;
    if (next != null) await request(next, work);
  }
}

/// 缩略帧提供者：用一个**后台播放器**截图，而不是把 FFmpeg 拉进依赖树（B4）。
class VideoFramePreviewProvider {
  VideoFramePreviewProvider({
    required this.transport,
    VideoFrameCache? cache,
    this.cacheDirOverride,
  }) : cache = cache ?? VideoFrameCache();

  /// 被预览的视频所在 transport（同一个播放器即可：截图不改变播放位置的话最省，
  /// 但暂停下逐帧 seek 也能接受 —— mimage 的做法是独立 worker，代价是双份解码）。
  final VideoTransport transport;
  final VideoFrameCache cache;

  /// 测试注入用：不给就走系统临时目录。
  final String? cacheDirOverride;

  final _SingleSlotScheduler _scheduler = _SingleSlotScheduler();
  String? _dir;
  int _seq = 0;

  Future<String> _cacheDir() async {
    if (cacheDirOverride != null) return cacheDirOverride!;
    if (_dir != null) return _dir!;
    if (_dir != null) return _dir!;
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'rossi-video-previews'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir.path;
  }

  /// 请求某一时刻的缩略帧。命中缓存直接回；未命中则排队解帧，
  /// 未命中且正在忙时**这次调用返回 null**（调用方显示占位），因为
  /// 「等一个正在解的旧位置」比「立刻给用户一个空白」更糟。
  Future<VideoFramePreview?> request(Duration at) async {
    final hit = cache.nearest(target: at);
    if (hit != null) return hit;
    final dir = await _cacheDir();
    final path = p.join(dir, 'f${_seq++}.jpg');
    unawaited(
      _scheduler.request(at, (target) async {
        // 预览要的是**鼠标所指那一刻**的画面，而 `screenshot` 截的是当前解码位置。
        // 不先定位就会得到「无论划到哪儿都是现在这一帧」——上游 neoview 用
        // 一个隐藏的 `<video>` 元素做这件事，mimage 单开一个 worker；
        // 这里没有第二台解码器，所以只在**已暂停**时借用当前播放器定位
        // （正是拖动选帧的时刻），播放中不抢用户正在看的位置。
        if (!transport.isPlaying) await transport.seekPaused(target);
        final shot = await transport.screenshot(path);
        if (shot == null) return;
        cache.put(target, shot);
      }),
    );
    return null;
  }

  /// 同步版：只在已缓存时给帧，用于鼠标拖动这种每帧都要问的场合。
  VideoFramePreview? peek(Duration at) => cache.nearest(target: at);

  Future<void> dispose() async {
    cache.clear();
    final dir = _dir;
    if (dir == null) return;
    try {
      await Directory(dir).delete(recursive: true);
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
