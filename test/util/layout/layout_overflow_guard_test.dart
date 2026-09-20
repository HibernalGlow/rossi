import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';

FlutterErrorDetails _flutterError(String message) =>
    FlutterErrorDetails(exception: FlutterError(message));

void main() {
  // [layoutOverflowStripesEnabled] 是可变顶层变量：每个用例都要复原，
  // 否则「关掉」那个用例会把后面所有用例的基线改掉（假红/假绿都这么来的）。
  tearDown(() => setLayoutOverflowStripesEnabled(enabled: true));

  group('溢出类错误的认定', () {
    test('认框架那句 overflowed by … pixels（RenderFlex / shift-box 同形）', () {
      expect(
        isLayoutOverflowReport(
          _flutterError('A RenderFlex overflowed by 294 pixels on the right.'),
        ),
        isTrue,
      );
      expect(
        isLayoutOverflowReport(
          _flutterError(
            'A RenderConstraintsTransformBox overflowed by 12 pixels on the bottom.',
          ),
        ),
        isTrue,
      );
    });

    test('别的错误一律不认 —— 这个开关只管条纹，不是「关闭错误上报」', () {
      // 少一个词就不算：只有 `overflowed` 的话，我们自己手写的那类
      // FlutterError 也会被静音。
      expect(
        isLayoutOverflowReport(_flutterError('A RenderFlex overflowed.')),
        isFalse,
      );
      expect(
        isLayoutOverflowReport(
          _flutterError('Build scheduled during frame.'),
        ),
        isFalse,
      );
      // 非 FlutterError（比如 Rust 侧抛上来的）即使文案相似也不碰。
      expect(
        isLayoutOverflowReport(
          FlutterErrorDetails(exception: StateError('overflowed by 3 pixels')),
        ),
        isFalse,
      );
    });
  });

  group('上报滤网', () {
    final overflow = _flutterError(
      'A RenderFlex overflowed by 294 pixels on the right.',
    );
    final other = _flutterError('Build scheduled during frame.');

    test('默认（开关开）⇒ 全部放行', () {
      expect(shouldReportFlutterError(overflow), isTrue);
      expect(shouldReportFlutterError(other), isTrue);
    });

    test('关掉 ⇒ 只丢溢出，其余照报', () {
      setLayoutOverflowStripesEnabled(enabled: false);
      expect(shouldReportFlutterError(overflow), isFalse);
      expect(shouldReportFlutterError(other), isTrue);
    });
  });

  group('设置项', () {
    test('默认开（＝改造前的行为），且 copyWith 只动这一个字段', () {
      const defaults = GlobalSettingState();
      expect(defaults.showLayoutOverflowStripes, isTrue);

      final updated = defaults.copyWith(showLayoutOverflowStripes: false);
      expect(updated.showLayoutOverflowStripes, isFalse);
      expect(updated.enableMemoryDebug, defaults.enableMemoryDebug);
      expect(updated.blockRustHttpRequests, defaults.blockRustHttpRequests);
      expect(
        updated.themeMode,
        defaults.themeMode,
        reason: '别的字段不该被这次 copyWith 碰到',
      );
    });
  });
}
