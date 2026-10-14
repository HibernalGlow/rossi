import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:zephyr/page/comic_read/model/reader_slideshow.dart';

/// 幻灯片（整页驻留放映）控制器。
///
/// 与 `ReaderAutoReadController` 同一套纪律：只养一张 `Timer.periodic` 和「暂停」这一位，
/// **不持有业务真相**。「这一拍该干什么」由宿主每次给的 [sync] 里的 `decideTick` 现场问
/// （判据住在 `model/reader_slideshow.dart`：章末、帧是否就位、有没有下一章，
/// 三样都只有宿主查得到）。分派结果只转成四个回调，控制器自己不认识页码与章节。
class ReaderSlideshowController {
  Timer? _timer;
  bool _isPaused = false;
  bool _lastEnabled = false;
  int _lastIntervalMs = 0;

  ReaderSlideshowTick Function()? _decideTick;
  void Function()? _onAdvance;
  void Function()? _onLoopToChapterStart;
  void Function()? _onStop;

  /// 计时器在飞**且**未暂停 —— 面板那颗芯片与浮层读数都按它画。
  bool get isRunning => _isActive && !_isPaused;

  bool get isPaused => _isPaused;

  bool get _isActive => _timer?.isActive ?? false;

  /// 每次构建时同步放映状态（自动滚屏那份的对应物）。
  ///
  /// [intervalMs] 应当已由 `normalizeReaderSlideshowIntervalMs` 归一化；这里再夹一次，
  /// 是因为 `Timer.periodic` 对非正周期直接抛 `ArgumentError` —— 一个还没接好的
  /// 调用方会把阅读页炸成白屏，而不是「放映慢一点」。
  void sync({
    required bool enabled,
    required int intervalMs,
    required ReaderSlideshowTick Function() decideTick,
    required void Function() onAdvance,
    required void Function() onLoopToChapterStart,
    required void Function() onStop,
  }) {
    _bind(
      decideTick: decideTick,
      onAdvance: onAdvance,
      onLoopToChapterStart: onLoopToChapterStart,
      onStop: onStop,
    );

    final normalizedIntervalMs = normalizeReaderSlideshowIntervalMs(intervalMs);
    final wasEnabled = _lastEnabled;
    final configChanged =
        _lastEnabled != enabled || _lastIntervalMs != normalizedIntervalMs;

    _lastEnabled = enabled;
    _lastIntervalMs = normalizedIntervalMs;

    if (!enabled) {
      // 用户自己关掉的：静默停表。回叫 onStop 走的是「章末停表」那条路径，
      // 宿主会据此再写一次设置，等于替用户改了他的意图。
      stop();
      return;
    }

    // 关→开算一次重新起放，上一轮的暂停不该带过来。
    if (!wasEnabled) {
      _isPaused = false;
    }

    if (_isPaused) {
      stop();
      return;
    }

    if (configChanged || !_isActive) {
      _start(normalizedIntervalMs);
    }
  }

  /// 切换暂停/继续，**不改动用户设置项本身**（与自动滚屏那颗同一契约）。
  void togglePaused({
    required ReaderSlideshowTick Function() decideTick,
    required void Function() onAdvance,
    required void Function() onLoopToChapterStart,
    required void Function() onStop,
    required int intervalMs,
  }) {
    _bind(
      decideTick: decideTick,
      onAdvance: onAdvance,
      onLoopToChapterStart: onLoopToChapterStart,
      onStop: onStop,
    );
    _isPaused = !_isPaused;

    if (_isPaused) {
      stop();
      return;
    }

    // 放映本来没开时这里也会起表：下一次 sync 见 enabled=false 会静默停掉，
    // 而宿主只在开着放映的面板里给这颗芯片，所以不会翻出「关着却在翻页」。
    _start(normalizeReaderSlideshowIntervalMs(intervalMs));
  }

  /// 只停表：不回调、不碰设置。判据要停时由分发路径先调它、再调 `onStop`。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    // 这几个闭包抓着宿主的 context 与 cubit，State 都销毁了就不该再留一份。
    _decideTick = null;
    _onAdvance = null;
    _onLoopToChapterStart = null;
    _onStop = null;
  }

  void _bind({
    required ReaderSlideshowTick Function() decideTick,
    required void Function() onAdvance,
    required void Function() onLoopToChapterStart,
    required void Function() onStop,
  }) {
    _decideTick = decideTick;
    _onAdvance = onAdvance;
    _onLoopToChapterStart = onLoopToChapterStart;
    _onStop = onStop;
  }

  void _start(int intervalMs) {
    stop();
    _timer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _dispatch(),
    );
  }

  void _dispatch() {
    // 停表之后不该再分发：`onStop` 通常会把 enabled 写回设置，那次写回触发的那一版
    // 判据仍是 stop，没有这道闸门就会二次回调（宿主据此再提示一次「放映已结束」）。
    if (!_isActive) return;

    final decide = _decideTick;
    if (decide == null) return;

    switch (decide()) {
      case ReaderSlideshowTick.advance:
        _onAdvance?.call();
      case ReaderSlideshowTick.loopToChapterStart:
        _onLoopToChapterStart?.call();
      case ReaderSlideshowTick.stop:
        // 先停表再回调：反过来会让 onStop 里那次 sync 又起一张新表，停不掉。
        stop();
        _onStop?.call();
      case ReaderSlideshowTick.hold:
        // 刻意不取消计时器：hold 的全部意义就是「这一拍别说翻过了」，
        // 下一拍照常重判（帧就位了就照常推进）。
        break;
    }
  }

  /// 测试入口：立刻走一次「计时器响了」的分发。
  ///
  /// 本仓没有直接依赖 `fake_async`（它只是传递依赖），而按最小间隔真等 800ms
  /// 会让这些断言变成计时器抖动的实验。
  @visibleForTesting
  void debugTick() => _dispatch();

  /// 测试入口：计时器本体。「还在跑」证明不了 `sync` 没重启 ——
  /// 参数没变时**同一张表**才算数（重启会先 stop 再新建一张）。
  @visibleForTesting
  Timer? get debugTimer => _timer;
}
