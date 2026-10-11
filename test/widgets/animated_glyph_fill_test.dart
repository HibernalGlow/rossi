// `AnimatedGlyphIcon` 的填充动画、尺寸/颜色透传与 RTL 口径。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/widgets/animated_glyph_fill_test.dart
//
// 为什么单独一份：页签条的活动页签、详情页的操作磁贴、绑定编辑器的分组 chip
// 与动作行、视频控件的图标按钮 —— 这些「选中态会在屏上翻」的地方原先是
// `GlyphIcon(fill: 条件 ? 1 : 0)`（瞬跳）或干脆只换颜色。换成
// `AnimatedGlyphIcon` 之后要证三件事：
//
//   1. fill 是**动画过去**的：中间帧严格落在 0 与 1 之间。这条就是判别尺 ——
//      裸 `GlyphIcon` 只量得到 0 或 1，接错（例如把 `filled` 传成常量）当场红。
//   2. **往返**：取消选中该退回 0。只测 0→1 会放过「reverse 没接」的写法。
//   3. 换壳不许丢 RTL：`matchTextDirection` 那颗在 rtl 下仍要横向翻转
//      （`GlyphIcon` 自己做的，这一条是「别在包装层丢掉它」的守卫），
//      并配一条 ltr 的阴性对照，免得断言空过。
//
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

const _color = Color(0xFF123456);

Widget _host({
  required Glyph glyph,
  required bool filled,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Center(
        child: AnimatedGlyphIcon(
          glyph,
          filled: filled,
          size: 20,
          color: _color,
        ),
      ),
    ),
  ),
);

double fillOf(WidgetTester tester) =>
    tester.widget<GlyphIcon>(find.byType(GlyphIcon)).fill!;

/// 有没有哪一层 `Transform` 把 x 轴翻了符号（`Transform.flip` 的矩阵特征：
/// 列主序 storage[0] 就是 xx 分量；`Transform.scale` 那层它是正的）。
bool flipped(WidgetTester tester) => tester
    .widgetList<Transform>(find.byType(Transform))
    .any((t) => t.transform.storage[0] < 0);

void main() {
  testWidgets('填充是动画过去的，不是瞬跳', (tester) async {
    await tester.pumpWidget(_host(glyph: AppGlyphs.star, filled: false));
    await tester.pumpAndSettle();
    expect(fillOf(tester), 0, reason: '未选中该是描边（fill 0）');

    await tester.pumpWidget(_host(glyph: AppGlyphs.star, filled: true));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = fillOf(tester);
    expect(mid, greaterThan(0), reason: '选中该开始填充');
    expect(mid, lessThan(1), reason: '填充该是动画过去的');

    await tester.pumpAndSettle();
    expect(fillOf(tester), 1, reason: '动画结束该是完全实心');
  });

  testWidgets('取消选中该退回描边（往返）', (tester) async {
    await tester.pumpWidget(_host(glyph: AppGlyphs.star, filled: true));
    await tester.pumpAndSettle();
    expect(fillOf(tester), 1);

    await tester.pumpWidget(_host(glyph: AppGlyphs.star, filled: false));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = fillOf(tester);
    expect(mid, lessThan(1), reason: '退回也该是动画过去的');
    expect(mid, greaterThan(0));

    await tester.pumpAndSettle();
    expect(fillOf(tester), 0);
  });

  testWidgets('size 与 color 透传到 GlyphIcon（这是它存在的理由）', (tester) async {
    await tester.pumpWidget(_host(glyph: AppGlyphs.star, filled: false));
    final icon = tester.widget<GlyphIcon>(find.byType(GlyphIcon));
    expect(icon.size, 20);
    expect(icon.color, _color);
  });

  testWidgets('RTL 翻转不丢，且 ltr 下确实没翻（阳性/阴性对照）', (tester) async {
    expect(AppGlyphs.arrowForward.matchTextDirection, isTrue);

    await tester.pumpWidget(
      _host(
        glyph: AppGlyphs.arrowForward,
        filled: false,
        direction: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();
    expect(flipped(tester), isTrue, reason: 'matchTextDirection 该在 rtl 下翻');

    await tester.pumpWidget(
      _host(
        glyph: AppGlyphs.arrowForward,
        filled: false,
        direction: TextDirection.ltr,
      ),
    );
    await tester.pumpAndSettle();
    expect(flipped(tester), isFalse, reason: 'ltr 下不许翻');
  });
}
