/// 长按节奏与动画共用一个周期，快速档不会被固定动画时长限制。
class ReaderKeyboardRepeatTiming {
  ReaderKeyboardRepeatTiming({
    required double pagesPerSecond,
    required int holdDelayMs,
  }) : pagesPerSecond = pagesPerSecond.isFinite
           ? pagesPerSecond.clamp(0.5, 15)
           : 4,
       holdDelay = Duration(milliseconds: holdDelayMs.clamp(100, 2000));

  final double pagesPerSecond;
  final Duration holdDelay;

  Duration get interval =>
      Duration(microseconds: (1000000 / pagesPerSecond).round());

  Duration get animationDuration => Duration(
    microseconds: (interval.inMicroseconds * 0.8).round().clamp(1, 300000),
  );

  // 首次仍采用单次翻页的手感，但必须在连续翻页开始前结束。
  Duration get firstAnimationDuration =>
      Duration(microseconds: holdDelay.inMicroseconds.clamp(1, 300000));
}
