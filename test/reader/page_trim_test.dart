import 'dart:ui' show Rect, Size, Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/model/page_trim.dart';

/// 自动裁边的显示几何与模式策略。
///
/// 判据都来自 `page_trim.dart` 那三条口径：像素不动、盒子无界就不裁、
/// 条漫不裁上下。这里刻意只测纯函数，不过桥也不建 widget。
void main() {
  // 竖版页 800x1200 进 400x600 的盒子：等比相同，contain 落位正好铺满盒子。
  const Size page = Size(800, 1200);
  const Size box = Size(400, 600);
  const Rect drawn = Rect.fromLTWH(0, 0, 400, 600);

  /// 把变换作用到落位坐标系里的一个矩形（就是内容矩形在盒子里的像素位置）。
  Rect apply(PageTrimGeometry g, Rect r) => Rect.fromLTRB(
    r.left * g.scale + g.dx,
    r.top * g.scale + g.dy,
    r.right * g.scale + g.dx,
    r.bottom * g.scale + g.dy,
  );

  /// 内容矩形（归一化）在落位矩形里的像素位置。
  Rect innerOf(Rect content) => Rect.fromLTRB(
    drawn.left + content.left * drawn.width,
    drawn.top + content.top * drawn.height,
    drawn.left + content.right * drawn.width,
    drawn.top + content.bottom * drawn.height,
  );

  group('computePageTrim', () {
    test('整页矩形等于不裁', () {
      expect(
        computePageTrim(
          boxSize: box,
          imageSize: page,
          contentRect: const Rect.fromLTRB(0, 0, 1, 1),
        ),
        isNull,
      );
    });

    test('每边只裁 0.01% ⇒ 缩放不到 1.001 倍，不当成裁边', () {
      expect(
        computePageTrim(
          boxSize: box,
          imageSize: page,
          contentRect: const Rect.fromLTRB(0.0001, 0.0001, 0.9999, 0.9999),
        ),
        isNull,
      );
    });

    test('四周各留 10% 余白 ⇒ 放大 1.25 倍，内容矩形正好铺满落位矩形', () {
      const Rect content = Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
      final geometry = computePageTrim(
        boxSize: box,
        imageSize: page,
        contentRect: content,
      )!;
      expect(geometry.scale, closeTo(1.25, 1e-9));
      // 等比且内容居中于整页 ⇒ 变换后应严丝合缝盖住落位矩形。
      expect(
        apply(geometry, innerOf(content)),
        const Rect.fromLTRB(0, 0, 400, 600),
      );
    });

    test('非对称裁边：受约束的那一轴铺满，另一轴保持等比并居中', () {
      const Rect content = Rect.fromLTRB(0.2, 0.05, 1.0, 0.65);
      final geometry = computePageTrim(
        boxSize: box,
        imageSize: page,
        contentRect: content,
      )!;
      // 内容像素位置 80..400 x 30..390（320 x 360）。
      final Rect inner = innerOf(content);
      expect(inner, const Rect.fromLTRB(80, 30, 400, 390));
      // 横向是受限轴：320 → 400（k = 1.25）；纵向 360 → 450，落在 600 里居中。
      expect(geometry.scale, closeTo(1.25, 1e-9));
      final Rect mapped = apply(geometry, inner);
      expect(mapped.left, closeTo(0, 1e-6));
      expect(mapped.right, closeTo(400, 1e-6));
      expect(mapped.height, closeTo(450, 1e-6));
      expect(mapped.center.dy, closeTo(300, 1e-6));
      // 不许越出落位矩形（切多了就是事故）。
      expect(mapped.left, greaterThanOrEqualTo(drawn.left));
      expect(mapped.right, lessThanOrEqualTo(drawn.right));
      expect(mapped.top, greaterThanOrEqualTo(drawn.top));
      expect(mapped.bottom, lessThanOrEqualTo(drawn.bottom));
    });

    test('高度限制缩放时，左右裁边仍有 GPU 裁剪范围', () {
      final geometry = computePageTrim(
        boxSize: const Size(400, 400),
        imageSize: page,
        contentRect: const Rect.fromLTRB(0.25, 0, 0.75, 1),
      )!;
      expect(geometry.scale, closeTo(1, 1e-9));
      expect(geometry.clipRect.left, closeTo(400 / 3, 1e-9));
      expect(geometry.clipRect.right, closeTo(800 / 3, 1e-9));
      expect(geometry.clipRect.top, 0);
      expect(geometry.clipRect.bottom, 400);
    });

    test('倍率为 1 的非对称余白仍会被裁掉并重新居中', () {
      final geometry = computePageTrim(
        boxSize: const Size(400, 400),
        imageSize: page,
        contentRect: const Rect.fromLTRB(0, 0, .8, 1),
      )!;
      expect(geometry.scale, closeTo(1, 1e-9));
      expect(geometry.dx, closeTo(80 / 3, 1e-9));
      expect(geometry.clipRect.center, const Offset(200, 200));
      expect(geometry.clipRect.width, closeTo(640 / 3, 1e-9));
    });

    test('盒子高度无界（列模式 paintSize 未到位）一律不裁', () {
      expect(
        computePageTrim(
          boxSize: const Size(400, double.infinity),
          imageSize: page,
          contentRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
        ),
        isNull,
      );
    });

    test('退化输入不裁：零尺寸、方向反了', () {
      expect(
        computePageTrim(
          boxSize: Size.zero,
          imageSize: page,
          contentRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
        ),
        isNull,
      );
      expect(
        computePageTrim(
          boxSize: box,
          imageSize: page,
          contentRect: const Rect.fromLTRB(0.9, 0.1, 0.1, 0.9),
        ),
        isNull,
      );
    });
  });

  group('trimRectForScroll', () {
    test('检测不出来的页保持不裁', () {
      expect(trimRectForScroll(detected: null, verticalScroll: false), isNull);
      expect(trimRectForScroll(detected: null, verticalScroll: true), isNull);
    });

    test('条漫（纵向滚动）不裁上下，只裁左右', () {
      expect(
        trimRectForScroll(
          detected: const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
          verticalScroll: true,
        ),
        const Rect.fromLTRB(0.1, 0.0, 0.9, 1.0),
      );
    });

    test('横向翻页的整页四条边都按检测结果', () {
      const detected = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
      expect(
        trimRectForScroll(detected: detected, verticalScroll: false),
        detected,
      );
    });

    test('条漫里左右也裁不动 ⇒ 等于没裁，返回 null', () {
      expect(
        trimRectForScroll(
          detected: const Rect.fromLTRB(0.0, 0.2, 1.0, 0.8),
          verticalScroll: true,
        ),
        isNull,
      );
    });
  });

  group('coordinateSpreadTrim', () {
    test('两页都检测不出来 ⇒ 不裁', () {
      expect(coordinateSpreadTrim(left: null, right: null), isNull);
    });

    test('上下取并集（不切任何一页），中缝那条边不裁', () {
      final spread = coordinateSpreadTrim(
        left: const Rect.fromLTRB(0.05, 0.20, 1.0, 0.90),
        right: const Rect.fromLTRB(0.0, 0.10, 0.95, 0.80),
      )!;
      expect(spread.leftPage, const Rect.fromLTRB(0.05, 0.10, 0.5, 0.90));
      expect(spread.rightPage, const Rect.fromLTRB(0.5, 0.10, 0.95, 0.90));
    });

    test('只有一页检测出来时，另一页整幅参与协调', () {
      final spread = coordinateSpreadTrim(
        left: const Rect.fromLTRB(0.1, 0.3, 1.0, 0.7),
        right: null,
      )!;
      expect(spread.leftPage, const Rect.fromLTRB(0.1, 0.0, 0.5, 1.0));
      expect(spread.rightPage, const Rect.fromLTRB(0.5, 0.0, 1.0, 1.0));
    });
  });
}
