/// 媒体进度存储 —— neoview `application/reader/ReaderMediaProgressService.ts:6-70`
/// 与 `ports/ReaderMediaProgressStore.ts` 的等效实现。
///
/// 为什么**不挂在 `UnifiedComicHistory.pageIndex` 上**：上游把「页码进度」与
/// 「这一页内部的播放位置」分成两份存储，因为一个视频页的页码是整数、
/// 播放位置是 5 s 节流写的一串浮点秒。合成一份会让每帧位置变化都去写数据库，
/// 而页码进度只在翻页时写 —— 两者的写入频率差两个数量级。
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/video/controller/reader_video_controller.dart';

class VideoProgressEntry {
  const VideoProgressEntry({
    required this.position,
    required this.duration,
    required this.completed,
    required this.updatedAt,
  });

  final Duration position;
  final Duration duration;
  final bool completed;
  final DateTime updatedAt;

  bool get isFinished =>
      completed ||
      VideoPlaybackProgress.isCompletedAt(
        position: position,
        duration: duration,
      );

  /// 恢复位置：看完就不恢复（用户重开一本书不该从上一集的 3 分钟前开始）。
  Duration? get resumeAt => VideoPlaybackProgress.restorePosition(
    position: position,
    duration: duration,
    completed: completed,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'p': position.inMilliseconds,
    'd': duration.inMilliseconds,
    'c': completed,
    't': updatedAt.millisecondsSinceEpoch,
  };

  static VideoProgressEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final p = json['p'];
    final d = json['d'];
    if (p is! int || d is! int) return null;
    return VideoProgressEntry(
      position: Duration(milliseconds: p),
      duration: Duration(milliseconds: d),
      completed: json['c'] == true,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t'] as int : 0,
      ),
    );
  }
}

abstract interface class VideoProgressStore {
  Future<VideoProgressEntry?> load(String key);
  Future<void> save(VideoProgressEntry entry, {required String key});
  Future<void> remove(String key);
}

/// 一条内存写入通道 + 500 ms 合并落盘（上游的 coalesced write-behind）。
///
/// 上游注释里的理由在 Rossi 同样成立：位置每帧都变，直接写会把偏好存储打穿；
/// 而「刚打开就退出」的窗口期靠 [flush] 在 dispose 时补一次写。
class SharedPreferencesVideoProgressStore implements VideoProgressStore {
  SharedPreferencesVideoProgressStore({
    this.namespace = 'rossi.video.progress',
  });

  static const int _maxEntries = 400;
  final String namespace;
  final Map<String, VideoProgressEntry> _cache = <String, VideoProgressEntry>{};
  Timer? _coalesce;
  bool _loading = false;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(namespace);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = VideoProgressEntry.fromJson(entry.value);
            if (value != null) _cache[entry.key] = value;
          }
        }
      }
      _loaded = true;
    } finally {
      _loading = false;
    }
  }

  @override
  Future<VideoProgressEntry?> load(String key) async {
    await _ensureLoaded();
    return _cache[key];
  }

  @override
  Future<void> save(VideoProgressEntry entry, {required String key}) async {
    await _ensureLoaded();
    _cache[key] = entry;
    if (_cache.length > _maxEntries) _trim();
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 500), _write);
  }

  void _trim() {
    // 按最近使用淘汰：条目数上限是防「读了 5000 本书之后偏好文件无限长」。
    final sorted = _cache.entries.toList(growable: false)
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    _cache
      ..clear()
      ..addEntries(sorted.take(_maxEntries));
  }

  @override
  Future<void> remove(String key) async {
    await _ensureLoaded();
    _cache.remove(key);
    await _write();
  }

  /// 退出阅读 / App 挂起时立刻落盘。
  Future<void> flush() async {
    _coalesce?.cancel();
    await _write();
  }

  Future<void> _write() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      for (final e in _cache.entries) e.key: e.value.toJson(),
    };
    await prefs.setString(namespace, jsonEncode(payload));
  }
}

/// 阅读页用的进度键：**同一本书同一章同一页**必须是稳定值。
///
/// 用 `chapterId` 而不是标题：换图源的同一本书标题可能不同，而页码位置
/// 对不上不会要用户命，但对错了会把「已看完」的标记打到另一页上。
String videoProgressKey({
  required String comicId,
  required String chapterId,
  required int pageIndex,
}) => '$comicId|$chapterId|$pageIndex';
