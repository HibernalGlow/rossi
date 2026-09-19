import 'dart:async';

/// 当前页优先的单工作队列。翻页替换尚未开始的任务，避免预处理积压。
/// 已开始的推理完成后立即处理新的当前页；同一任务不会重复入队。
class SuperResolutionQueue<K> {
  final List<(K, Future<void> Function())> _pending = [];
  K? _running;
  Future<void>? _worker;
  bool _disposed = false;

  Future<void> get idle => _worker ?? Future<void>.value();

  void replace(List<(K, Future<void> Function())> jobs) {
    if (_disposed) return;
    _pending
      ..clear()
      ..addAll(jobs.where((job) => job.$1 != _running));
    _worker ??= _drain();
  }

  Future<void> _drain() async {
    // 先让 replace 完成 _worker 赋值，再开始处理同步完成的任务。
    await Future<void>.value();
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final job = _pending.removeAt(0);
        _running = job.$1;
        await job.$2();
      }
    } finally {
      _running = null;
      _worker = null;
    }
  }

  void clear() => _pending.clear();
  void dispose() {
    _disposed = true;
    clear();
  }
}

/// mImage 的前后页预处理顺序：下一页、上一页、下两页、上两页……
List<int> superResolutionTargets(
  int current,
  int count,
  int forward,
  int back,
) {
  final result = <int>[current];
  for (var distance = 1; distance <= forward || distance <= back; distance++) {
    if (distance <= forward && current + distance < count) {
      result.add(current + distance);
    }
    if (distance <= back && current - distance >= 0) {
      result.add(current - distance);
    }
  }
  return result;
}
