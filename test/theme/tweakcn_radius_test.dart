// 主题圆角的传导链：`ThemeShapeScope` → `LiquidGlassSurface` 的默认值。
//
// 这条链是「导入主题带 --radius」唯一的落地路径，而它最容易坏在两个地方：
// 一是 scope 挂不进 widget 树（`MaterialApp` 与桥接层的层级关系变了），
// 二是显式传值的调用点被主题的圆角覆盖掉。两条都在这里钉住。

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

void main() {
  Widget host({required Widget child, double? scopeRadius}) {
    final app = MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 120, height: 80, child: child)),
      ),
    );
    if (scopeRadius == null) return app;
    return ThemeShapeScope(radius: scopeRadius, child: app);
  }

  BorderRadiusGeometry surfaceRadius(WidgetTester tester, Finder surface) {
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: surface, matching: find.byType(ClipRRect)).first,
    );
    return clip.borderRadius;
  }

  group('themeRadius', () {
    test('没有 scope、没有 context 都回落到默认值，不抛', () {
      expect(themeRadius(null), kDefaultPanelRadius);
      expect(themeRadius(null, fallback: 7), 7);
    });
  });

  group('LiquidGlassSurface 的圆角来源', () {
    testWidgets('未显式传值时跟主题走', (tester) async {
      await tester.pumpWidget(
        host(
          scopeRadius: 24,
          child: const LiquidGlassSurface(
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      expect(
        surfaceRadius(tester, find.byType(LiquidGlassSurface)),
        BorderRadius.circular(24),
      );
    });

    testWidgets('调用点显式传的 radius / borderRadius 不被主题覆盖', (tester) async {
      await tester.pumpWidget(
        host(
          scopeRadius: 24,
          child: const LiquidGlassSurface(
            radius: 8,
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      expect(
        surfaceRadius(tester, find.byType(LiquidGlassSurface)),
        BorderRadius.circular(8),
      );

      await tester.pumpWidget(
        host(
          scopeRadius: 24,
          child: const LiquidGlassSurface(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      expect(
        surfaceRadius(tester, find.byType(LiquidGlassSurface)),
        BorderRadius.circular(2),
      );
    });

    testWidgets('没有 scope 时仍是改造前的 16', (tester) async {
      await tester.pumpWidget(
        host(
          child: const LiquidGlassSurface(
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      expect(
        surfaceRadius(tester, find.byType(LiquidGlassSurface)),
        BorderRadius.circular(kDefaultPanelRadius),
      );
    });

    testWidgets('换主题圆角后重绘即生效（scope 会通知依赖）', (tester) async {
      await tester.pumpWidget(
        host(
          scopeRadius: 24,
          child: const LiquidGlassSurface(
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          scopeRadius: 6,
          child: const LiquidGlassSurface(
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
      );
      expect(
        surfaceRadius(tester, find.byType(LiquidGlassSurface)),
        BorderRadius.circular(6),
      );
    });
  });
}
