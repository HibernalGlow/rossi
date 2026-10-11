// `MorphingGlyph` 的判据：状态翻转必须是**连续过渡**，不是两颗硬切。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/widgets/morphing_glyph_test.dart
//
// 三条判别尺都带对照，缺一条就可能空过：
//   1. 中间帧的旋转角严格落在 0 与 90° 之间 —— 硬切只会量到两端之一。
//   2. rtl 下角度符号必须反过来（`GlyphIcon` 把整颗水平镜像了），并配一条
//      ltr 的阳性对照，否则「恒为 0」也能骗过第 1 条。
//   3. `builder` 那一支真吃到插值：`AppGlyphs.playPause` 在 0 是一颗三角形、
//      在 1 是两根竖条，中间帧必须既不是 0 也不是 1 的坐标。
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: Center(child: child)),
      ),
    );

GlyphIcon iconOf(WidgetTester tester) =>
    tester.widget<GlyphIcon>(find.byType(GlyphIcon));

/// 图标自己的世界变换里，2×2 部分是 `Transform.rotate` 的旋转（Center/Scaffold
/// 那些层不带旋转）。从渲染对象读，不去猜树里有几个 `Transform`。
double angleOf(WidgetTester tester) {
  final ro = tester.renderObject<RenderBox>(find.byType(GlyphIcon));
  final m = ro.getTransformTo(null);
  return math.atan2(m.storage[1], m.storage[0]);
}

void main() {
  testWidgets('旋转档：两端对得上，中间帧真的在转', (tester) async {
    Widget tree({required bool on}) => _host(
      MorphingGlyph(
        on: on,
        glyph: AppGlyphs.chevronForward,
        turns: 0.25,
        size: 16,
      ),
    );

    await tester.pumpWidget(tree(on: false));
    await tester.pumpAndSettle();
    expect(iconOf(tester).glyph, same(AppGlyphs.chevronForward));
    expect(angleOf(tester), closeTo(0, 1e-6));

    await tester.pumpWidget(tree(on: true));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = angleOf(tester);
    expect(mid, greaterThan(0.05), reason: '过渡中途该已经转出去一点');
    expect(mid, lessThan(math.pi / 2 - 0.05), reason: '中途不该已经到位（硬切会）');

    await tester.pumpAndSettle();
    expect(angleOf(tester), closeTo(math.pi / 2, 1e-6));
    // 转的是同一颗，不是换了一颗。
    expect(iconOf(tester).glyph, same(AppGlyphs.chevronForward));
  });

  testWidgets('rtl 下旋转反向，ltr 正向（配对照，防「恒为 0」蒙过）', (tester) async {
    Widget tree(TextDirection dir) => _host(
      MorphingGlyph(
        on: true,
        glyph: AppGlyphs.chevronForward,
        turns: 0.25,
      ),
      direction: dir,
    );
    expect(AppGlyphs.chevronForward.matchTextDirection, isTrue);

    await tester.pumpWidget(tree(TextDirection.ltr));
    await tester.pumpAndSettle();
    expect(angleOf(tester), closeTo(math.pi / 2, 1e-6));

    await tester.pumpWidget(tree(TextDirection.rtl));
    await tester.pumpAndSettle();
    expect(angleOf(tester), closeTo(-math.pi / 2, 1e-6));
  });

  testWidgets('插值档：playPause 的中间帧既不是 play 也不是 pause', (tester) async {
    final play = AppGlyphs.playPause(0);
    final pause = AppGlyphs.playPause(1);
    expect(play.shapes.length, isNot(pause.shapes.length), reason: '两端形状数不同');

    Widget tree({required bool on}) =>
        _host(MorphingGlyph(on: on, builder: AppGlyphs.playPause));

    await tester.pumpWidget(tree(on: false));
    await tester.pumpAndSettle();
    expect(iconOf(tester).glyph.shapes.length, play.shapes.length);

    await tester.pumpWidget(tree(on: true));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = iconOf(tester).glyph;
    List<double> coords(Glyph g) => [
      for (final shape in g.shapes)
        for (final v in (shape as GlyphPolyline).vertices) ...[v.x, v.y],
    ];
    // `playPause` 中途既不是 play 的形状数，坐标也不等于任何一端 ——
    // 硬切只会给出两端的坐标之一。（这里不能用「落在两端之间」的数值判据：
    // 这个函数同时绕心旋转，旋转会把点带出两端连线之外。）
    expect(mid.shapes.length, pause.shapes.length, reason: '中途该已经是两根条');
    expect(coords(mid), isNot(coords(play)));
    expect(coords(mid), isNot(coords(pause)));

    await tester.pumpAndSettle();
    expect(iconOf(tester).glyph.shapes.length, pause.shapes.length);
  });

  testWidgets('插值档：形状数不变时，参数严格在两端的数值区间内', (tester) async {
    // `sidebar(t)` 是「同一批形状、分隔线从 8.5 挪到 11.5」那一类，
    // 正好补上 playPause 那种两端形状数不同的例子测不到的口径。
    double dividerX(Glyph g) =>
        (g.shapes[1] as GlyphPolyline).vertices.first.x;
    expect(dividerX(AppGlyphs.sidebar(0)), closeTo(8.5, 1e-6));
    expect(dividerX(AppGlyphs.sidebar(1)), closeTo(11.5, 1e-6));

    Widget tree({required bool on}) =>
        _host(MorphingGlyph(on: on, builder: AppGlyphs.sidebar));

    await tester.pumpWidget(tree(on: false));
    await tester.pumpAndSettle();
    expect(dividerX(iconOf(tester).glyph), closeTo(8.5, 1e-6));

    await tester.pumpWidget(tree(on: true));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      dividerX(iconOf(tester).glyph),
      inInclusiveRange(8.6, 11.4),
      reason: '中途该在滑动过程中，而不是已经贴到某一边',
    );

    await tester.pumpAndSettle();
    expect(dividerX(iconOf(tester).glyph), closeTo(11.5, 1e-6));
  });
}
