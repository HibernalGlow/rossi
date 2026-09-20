// 阅读器顶栏「透明档」的材质判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/comic_read/reader_top_bar_style_test.dart
//
// 全是纯逻辑：这一档的差别只在「选玻璃还是选蒙层」以及蒙层的颜色与阴影上，
// 而颜色是**算出来的**（主题 surface + 不透明度），不用起整个阅读页去截图比色。
//
// 成对断言是刻意的：「透明档真的变了」必须配「关掉之后真的没变」——
// 否则一个永远返回蒙层的实现也能让前半边全绿。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/reader/reader_top_bar_style.dart';

/// 一个深色主题的 surface。
const Color _surface = Color(0xFF1B1B1F);

/// 一个浅色主题的 surface。
const Color _lightSurface = Color(0xFFFDFBFF);

void main() {
  group('resolveReaderTopBarSpec', () {
    test('默认档（开关关着）就是改造前的样子：玻璃 + 那圈收小的阴影', () {
      final spec = resolveReaderTopBarSpec(
        const ReadSettingState(),
        surface: _surface,
      );

      expect(spec.liquidGlass, isTrue);
      expect(spec.isTransparent, isFalse);
      expect(spec.scrim, isNull, reason: '玻璃档不许再叠一层蒙层，否则颜色被算两遍');
      expect(spec.shadowScale, ReaderTopBarStyleLimits.glassShadowScale);
    });

    test('透明档：换成蒙层、拿掉阴影', () {
      final spec = resolveReaderTopBarSpec(
        const ReadSettingState(transparentTopBar: true),
        surface: _surface,
      );

      expect(spec.liquidGlass, isFalse, reason: '透明档不许再走玻璃');
      expect(spec.isTransparent, isTrue);
      expect(spec.scrim, isNotNull);
      expect(
        spec.shadowScale,
        ReaderTopBarStyleLimits.transparentShadowScale,
        reason: '没有材质还留着那圈阴影，看着像「玻璃没画完」',
      );
    });

    test('默认不透明度 85%，与 JHenTai 的 readPageMenuColor 同一档', () {
      expect(ReaderTopBarStyleLimits.defaultOpacityPercent, 85);

      final spec = resolveReaderTopBarSpec(
        const ReadSettingState(transparentTopBar: true),
        surface: _surface,
      );
      expect(spec.scrim, _surface.withValues(alpha: 0.85));
    });

    test('蒙层颜色跟着主题 surface 走（浅色主题不会得到「白底 + 浅色字」）', () {
      final dark = resolveReaderTopBarSpec(
        const ReadSettingState(transparentTopBar: true),
        surface: _surface,
      );
      final light = resolveReaderTopBarSpec(
        const ReadSettingState(transparentTopBar: true),
        surface: _lightSurface,
      );

      expect(light.scrim, _lightSurface.withValues(alpha: 0.85));
      expect(
        light.scrim,
        isNot(dark.scrim),
        reason: '两套主题必须算出两种蒙层 —— 写死黑的话浅色主题就废了',
      );
    });

    test('0% = 完全透明（顶栏只剩文字浮在画面上）', () {
      final spec = resolveReaderTopBarSpec(
        const ReadSettingState(
          transparentTopBar: true,
          topBarScrimOpacityPercent: 0,
        ),
        surface: _surface,
      );

      expect(spec.scrim, _surface.withValues(alpha: 0));
    });

    test('越界值两端各夹一次（设置可能来自云端同步或旧版本写入）', () {
      final over = resolveReaderTopBarSpec(
        const ReadSettingState(
          transparentTopBar: true,
          topBarScrimOpacityPercent: 400,
        ),
        surface: _surface,
      );
      expect(over.scrim, _surface.withValues(alpha: 1));

      final under = resolveReaderTopBarSpec(
        const ReadSettingState(
          transparentTopBar: true,
          topBarScrimOpacityPercent: -20,
        ),
        surface: _surface,
      );
      expect(under.scrim, _surface.withValues(alpha: 0));
    });

    test('clamp 单独一条：滑条与规格用的是同一把尺子', () {
      expect(clampReaderTopBarOpacityPercent(-1), 0);
      expect(clampReaderTopBarOpacityPercent(0), 0);
      expect(clampReaderTopBarOpacityPercent(85), 85);
      expect(clampReaderTopBarOpacityPercent(100), 100);
      expect(clampReaderTopBarOpacityPercent(101), 100);
    });

    test('开关关掉之后蒙层整个撤掉，留在设置里的不透明度不再生效', () {
      final spec = resolveReaderTopBarSpec(
        const ReadSettingState(topBarScrimOpacityPercent: 12),
        surface: _surface,
      );

      expect(spec.liquidGlass, isTrue);
      expect(spec.scrim, isNull, reason: '否则「关掉的开关还在偷偷上色」');
    });

    test('切开关只动材质这一件事（两种档位的取值互为反面）', () {
      final off = resolveReaderTopBarSpec(
        const ReadSettingState(topBarScrimOpacityPercent: 40),
        surface: _surface,
      );
      final on = resolveReaderTopBarSpec(
        const ReadSettingState(
          transparentTopBar: true,
          topBarScrimOpacityPercent: 40,
        ),
        surface: _surface,
      );

      expect(off.liquidGlass, isNot(on.liquidGlass));
      expect(on.scrim, _surface.withValues(alpha: 0.40));
    });
  });
}
