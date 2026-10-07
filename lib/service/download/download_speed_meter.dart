/// 下载速度采样器：以「图片完成」为粒度记录字节数与时间，用滑动窗口估算速度。
///
/// 网络层不暴露分块进度，所以速度只能按完成事件采样；窗口内没有新样本时
/// 估算值会随 span 增大自然衰减，超过窗口后归零，调用方据此隐藏速度。
class DownloadSpeedMeter {
  DownloadSpeedMeter({this.window = const Duration(seconds: 5)});

  /// 采样窗口长度：窗口内没有新样本时速度逐渐衰减，超过窗口后归零。
  final Duration window;
  final List<(DateTime, int)> _samples = <(DateTime, int)>[];

  void addBytes(int bytes, {DateTime? at}) {
    if (bytes <= 0) return;
    final now = at ?? DateTime.now();
    _samples.add((now, bytes));
    _prune(now);
  }

  double bytesPerSecondAt(DateTime now) {
    _prune(now);
    if (_samples.isEmpty) return 0;
    var total = 0;
    for (final sample in _samples) {
      total += sample.$2;
    }
    var spanSeconds = now.difference(_samples.first.$1).inMilliseconds / 1000.0;
    if (spanSeconds > window.inMilliseconds / 1000.0) {
      spanSeconds = window.inMilliseconds / 1000.0;
    }
    // 起步阶段样本跨度很小，避免把首张图放大成天文数字。
    if (spanSeconds < 0.25) spanSeconds = 0.25;
    return total / spanSeconds;
  }

  double get bytesPerSecond => bytesPerSecondAt(DateTime.now());

  void _prune(DateTime now) {
    _samples.removeWhere((sample) => now.difference(sample.$1) > window);
  }
}
