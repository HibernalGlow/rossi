// 液态玻璃材质的判据。
//
// 纯逻辑部分（饱和矩阵 / 光照角映射 / alpha 缩放 / 档位表）直接断言数值；
// widget 部分只断言「结构对了」（BackdropFilter 存在、降级时换实色、
// 不透明度缩进材质、阴影按体量缩放）——视觉对不对最终靠肉眼，
// 但这些**关键数值与结构**在这里钉死。

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

void main() {
  group('saturationMatrix（玻璃与磨砂的分水岭）', () {
    test('饱和度 1.0 应为单位矩阵（无增强）', () {
      expect(saturationMatrix(1.0), <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ]);
    });

    test('饱和度 2.0 时 R 通道保留亮度权重混色', () {
      // R' = lumR*(1-s)+s = 0.213*(-1)+2 = 1.787
      final matrix = saturationMatrix(2.0);
      expect(matrix[0], closeTo(1.787, 1e-9));
      // G 权重混入 R 通道：0.715 * (1 - 2) = -0.715
      expect(matrix[1], closeTo(-0.715, 1e-9));
      // 偏移与 alpha 通道不动
      expect(matrix[3], 0);
      expect(matrix[4], 0);
      expect(matrix[18], 1);
    });
  });

  group('alignmentOfLightAngle（光照角 → 对齐）', () {
    // 角度从正上方顺时针量（同 CSS conic-gradient），315° 即苹果的左上打光。
    test('0° 是正上、90° 是正右、180° 是正下、270° 是正左', () {
      expect(alignmentOfLightAngle(0), Alignment.topCenter);
      expect(alignmentOfLightAngle(90), Alignment.centerRight);
      expect(alignmentOfLightAngle(180), Alignment.bottomCenter);
      expect(alignmentOfLightAngle(270), Alignment.centerLeft);
    });

    test('315° 落在左上象限（苹果基准光位）', () {
      final alignment = alignmentOfLightAngle(315);
      expect(alignment.x, lessThan(0));
      expect(alignment.y, lessThan(0));
      // 45° 对角：两个分量等值
      expect(alignment.x, closeTo(alignment.y, 1e-9));
    });
  });

  group('LiquidGlassSpecs（档位表对齐苹果材质参数）', () {
    test('三档的模糊半径与饱和度对齐苹果材质表', () {
      final expected = {
        LiquidGlassThickness.thin: (16.0, 1.4), // thinMaterial
        LiquidGlassThickness.regular: (24.0, 1.6), // regularMaterial
        LiquidGlassThickness.thick: (40.0, 1.8), // thickMaterial
      };
      expected.forEach((thickness, values) {
        final (blur, saturation) = values;
        final spec = LiquidGlassSpecs.of(thickness, Brightness.dark);
        expect(spec.blur, blur, reason: '$thickness blur');
        expect(spec.saturation, saturation, reason: '$thickness saturation');
      });
    });

    test('深浅模式的着色必须不同（中性色，各取一套）', () {
      final thickTint = LiquidGlassSpecs.of(
        LiquidGlassThickness.thick,
        Brightness.dark,
      ).tint.a;
      for (final thickness in LiquidGlassThickness.values) {
        final light = LiquidGlassSpecs.of(thickness, Brightness.light);
        final dark = LiquidGlassSpecs.of(thickness, Brightness.dark);
        expect(light.tint, isNot(dark.tint), reason: '$thickness tint');
        // 档位越高越不透明（层级越强的面板底越实）；thick 对自身取等。
        expect(
          dark.tint.a,
          lessThanOrEqualTo(thickTint),
          reason: '$thickness 不应比 thick 更实',
        );
      }
    });

    test('着色必须是半透明层（alpha < 1），否则玻璃变瓷砖', () {
      for (final thickness in LiquidGlassThickness.values) {
        for (final brightness in Brightness.values) {
          expect(
            LiquidGlassSpecs.of(thickness, brightness).tint.a,
            lessThan(1.0),
          );
        }
      }
    });
  });

  group('LiquidGlassSpec.withOpacity', () {
    test('只缩 alpha，不动模糊与饱和度', () {
      final spec = LiquidGlassSpecs.of(
        LiquidGlassThickness.regular,
        Brightness.dark,
      );
      final half = spec.withOpacity(0.5);
      expect(half.blur, spec.blur);
      expect(half.saturation, spec.saturation);
      expect(half.tint.a, closeTo(spec.tint.a * 0.5, 1e-9));
      expect(half.bezel.a, closeTo(spec.bezel.a * 0.5, 1e-9));
      expect(half.sheen.a, closeTo(spec.sheen.a * 0.5, 1e-9));
      expect(half.shadow.a, closeTo(spec.shadow.a * 0.5, 1e-9));
    });

    test('越界一律夹回 0~1', () {
      final spec = LiquidGlassSpecs.of(
        LiquidGlassThickness.thin,
        Brightness.light,
      );
      expect(spec.withOpacity(2.0).tint.a, spec.tint.a);
      expect(spec.withOpacity(-1).tint.a, 0);
    });
  });

  group('LiquidGlassSurface（widget 结构）', () {
    Widget host({required Widget child, bool highContrast = false}) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: Scaffold(body: Center(child: child)),
        ),
      );
    }

    testWidgets('玻璃模式：BackdropFilter 存在，内容在材质之上', (tester) async {
      const tint = Color(0x9E222226); // regular dark
      await tester.pumpWidget(
        host(
          child: LiquidGlassSurface(
            thickness: LiquidGlassThickness.regular,
            child: const Text('glass'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('glass'), findsOneWidget);
      // 着色层用的是中性深色 tint，而不是主题 surface。
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration?)?.color == tint,
        ),
        findsOneWidget,
      );
    });

    testWidgets('高对比度降级：无 BackdropFilter，用实色面板', (tester) async {
      await tester.pumpWidget(
        host(
          highContrast: true,
          child: const LiquidGlassSurface(child: Text('plain')),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('plain'), findsOneWidget);
    });

    testWidgets('enabled=false 显式降级同样走实色', (tester) async {
      await tester.pumpWidget(
        host(
          child: LiquidGlassSurface(enabled: false, child: const Text('off')),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('opacity 缩进材质而不是外层 Opacity', (tester) async {
      const full = Color(0x9E222226); // regular dark tint
      await tester.pumpWidget(
        host(
          child: LiquidGlassSurface(
            thickness: LiquidGlassThickness.regular,
            opacity: 0.5,
            child: const Text('faded'),
          ),
        ),
      );
      await tester.pump();

      // 不允许出现 Opacity 包裹（会给 BackdropFilter 套 saveLayer）。
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      // 着色层 alpha 应为原值的一半。
      final fadedTint = full.withValues(alpha: full.a * 0.5);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration?)?.color == fadedTint,
        ),
        findsOneWidget,
      );
    });

    testWidgets('shadowScale=0 时阴影完全消失（小控件场景）', (tester) async {
      await tester.pumpWidget(
        host(
          child: LiquidGlassSurface(
            shadowScale: 0,
            child: const SizedBox(width: 44, height: 44),
          ),
        ),
      );
      await tester.pump();

      final shadowLayers = tester
          .widgetList<DecoratedBox>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  (widget.decoration as BoxDecoration?)?.boxShadow != null,
            ),
          )
          .toList();
      expect(shadowLayers, hasLength(1));
      final shadow =
          (shadowLayers.single.decoration as BoxDecoration).boxShadow!.single;
      expect(shadow.color.a, 0);
    });
  });
}
