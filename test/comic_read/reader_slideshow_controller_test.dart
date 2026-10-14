import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/controller/reader_slideshow_controller.dart';
import 'package:zephyr/page/comic_read/model/reader_slideshow.dart';

/// 放映控制器走的是「宿主给判据、控制器只分派」这条路，所以测试不需要 Widget、
/// 也不需要 cubit：脚本化的判据 + 计数回调就能把这几条契约钉死。
/// 控制器只 import `dart:async` 与判据模型，不碰 `global_setting.dart`，
/// 于是这批用例不会被生成代码的在途状态拖着红。
///
/// 计时由 `debugTick` 手动触发：本仓没有直接依赖 `fake_async`，而按最小间隔
/// 真等 800ms 只会让断言赌机器负载。
void main() {
  group('ReaderSlideshowController', () {
    test('hold 只让位这一拍：不推进、也不撤掉计时器', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      expect(controller.isRunning, isTrue);

      controller.debugTick();

      expect(recorder.advances, 0);
      expect(recorder.stops, 0);
      // hold 的全部意义：帧还没就位，下一拍照常重判，所以表必须在。
      expect(controller.isRunning, isTrue);
      expect(controller.debugTimer, isNotNull);

      // 帧就位后同一张表就能正常推进。
      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      controller.debugTick();
      expect(recorder.advances, 1);
    });

    test('advance 每拍回调一次，且不停表', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );

      for (var i = 0; i < 3; i++) {
        controller.debugTick();
      }

      expect(recorder.advances, 3);
      expect(recorder.stops, 0);
      expect(controller.isRunning, isTrue);
    });

    test('loopToChapterStart 走独立回调，不混进 advance', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.loopToChapterStart,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      controller.debugTick();

      expect(recorder.loops, 1);
      expect(recorder.advances, 0);
      expect(controller.isRunning, isTrue);
    });

    test('判据要停：停表 + onStop 恰好一次', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.stop,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );

      controller.debugTick();

      expect(controller.debugTimer, isNull);
      expect(controller.isRunning, isFalse);
      expect(recorder.stops, 1);

      // 表已经没了还继续被戳（宿主写回设置前可能又构建一次）不许再报第二次。
      controller.debugTick();
      controller.debugTick();
      expect(recorder.stops, 1);
    });

    test('enabled 转 false 是静默停表，不回叫 onStop', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      controller.debugTick();
      expect(recorder.advances, 1);

      controller.sync(
        enabled: false,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );

      expect(controller.debugTimer, isNull);
      expect(controller.isRunning, isFalse);
      // 用户自己关的：走 onStop 会被宿主当成「章末停表」，那是另一件事。
      expect(recorder.stops, 0);
    });

    test('参数没变的 sync 不重启计时器；间隔变了才换表', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      final firstTimer = controller.debugTimer;
      expect(firstTimer, isNotNull);

      // 每次构建都要便宜：同一张表才证明没重排一遍计时。
      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      expect(controller.debugTimer, same(firstTimer));

      controller.sync(
        enabled: true,
        intervalMs:
            kReaderSlideshowIntervalDefaultMs + kReaderSlideshowIntervalStepMs,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      expect(controller.debugTimer, isNot(same(firstTimer)));
      expect(controller.debugTimer, isNotNull);
    });

    test('togglePaused 只停表/起表，不回调 onStop', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );

      controller.togglePaused(
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
      );
      expect(controller.isPaused, isTrue);
      expect(controller.isRunning, isFalse);
      expect(controller.debugTimer, isNull);
      expect(recorder.stops, 0);

      controller.debugTick();
      expect(recorder.advances, 0);

      controller.togglePaused(
        decideTick: () => ReaderSlideshowTick.advance,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
        intervalMs: kReaderSlideshowIntervalDefaultMs,
      );
      expect(controller.isPaused, isFalse);
      expect(controller.isRunning, isTrue);
      expect(controller.debugTimer, isNotNull);
    });

    test('非正间隔夹到下限：不抛 ArgumentError，且落的正是那个值', () {
      final recorder = _Recorder();
      final controller = ReaderSlideshowController();
      addTearDown(controller.dispose);

      controller.sync(
        enabled: true,
        intervalMs: 0,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );

      // 宿主接错线时阅读页不该直接白屏：`Timer.periodic` 对非正周期是抛，不是慢放。
      expect(controller.isRunning, isTrue);
      final clampedTimer = controller.debugTimer;
      expect(clampedTimer, isNotNull);

      // 0 归一化后就是下限：与「显式给下限」的那次 sync 落在同一张表上，
      // 才算真夹到了那个值，而不是随便起了另一张表。
      controller.sync(
        enabled: true,
        intervalMs: kReaderSlideshowIntervalMinMs,
        decideTick: () => ReaderSlideshowTick.hold,
        onAdvance: recorder.advance,
        onLoopToChapterStart: recorder.loop,
        onStop: recorder.stop,
      );
      expect(controller.debugTimer, same(clampedTimer));
    });
  });
}

class _Recorder {
  int advances = 0;
  int loops = 0;
  int stops = 0;

  void advance() => advances++;
  void loop() => loops++;
  void stop() => stops++;
}
