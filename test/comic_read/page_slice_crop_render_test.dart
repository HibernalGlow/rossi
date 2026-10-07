/// 横长页拆分（page split）的**渲染层**几何契约。
///
/// 只量宽高与偏移、不查像素：测试环境不加载 pubspec 字体，也不该依赖视口尺寸。
///
/// 这里刻意不泵 [ImageDisplay] 本体 —— 那条路要真实的图片文件与四个 cubit
/// （见 `image_display_replacement_test.dart`），而本文件要钉住的只是
/// [wrapPageSlice] 这套盒子机制，它与 `ImageSurface._wrapSlice` 是同一份形状。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/page/comic_read/widgets/image/image_display.dart';

const Key _slotKey = ValueKey('slot');
const Key _pageKey = ValueKey('page');

/// 裁剪盒只在拆分时存在，而且必须待在格子内部 —— 按子树找，免得把
/// `MaterialApp` 自己带来的同类型节点算进来（那会让负断言假绿）。
final Finder _cropBox = find.descendant(
  of: find.byKey(_slotKey),
  matching: find.byType(ClipRect),
);

final Finder _overflowBox = find.descendant(
  of: find.byKey(_slotKey),
  matching: find.byType(OverflowBox),
);

Future<void> _pumpPage(WidgetTester tester, PageSlice slice) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          key: _slotKey,
          width: 200,
          height: 100,
          child: wrapPageSlice(
            Container(
              key: _pageKey,
              width: 400,
              height: 100,
              color: Colors.red,
            ),
            slice: slice,
            width: 200,
            height: 100,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('PageSlice.full 原样返回子节点，不套任何裁剪盒子', () {
    const child = SizedBox(key: _pageKey);
    expect(
      wrapPageSlice(child, slice: PageSlice.full, width: 200, height: 100),
      same(child),
    );
  });

  test('高度无界（列模式 paintSize 未到位）时不裁，而不是当场抛异常', () {
    const child = SizedBox(key: _pageKey);
    for (final slice in [PageSlice.left, PageSlice.right]) {
      expect(
        wrapPageSlice(child, slice: slice, width: 200, height: double.infinity),
        same(child),
      );
    }
  });

  for (final slice in [PageSlice.left, PageSlice.right]) {
    testWidgets('$slice 只露出 200 逻辑像素宽的那一半', (tester) async {
      await _pumpPage(tester, slice);

      // 裁剪盒就是格子本身：宽 200，不是 400。
      expect(_cropBox, findsOneWidget);
      expect(_overflowBox, findsOneWidget);
      expect(tester.getSize(_cropBox), const Size(200, 100));
      // 内容仍然按**两倍宽**铺排 —— 这一格因此拿到原图的半幅，
      // 而不是整幅图被等比压进 200 宽（那才是拆分没生效的样子）。
      expect(tester.getSize(find.byKey(_pageKey)), const Size(400, 100));

      final double cropLeft = tester.getTopLeft(_cropBox).dx;
      final double pageLeft = tester.getTopLeft(find.byKey(_pageKey)).dx;
      // 左半：画面起点对齐格子左边；右半：画面整体往左挪一格。
      expect(pageLeft - cropLeft, slice == PageSlice.left ? 0.0 : -200.0);
      // 紧约束（min == max）的 OverflowBox 不该报溢出，也不该有无尺寸盒子。
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('PageSlice.full 渲染出来与拆分前同一棵树', (tester) async {
    await _pumpPage(tester, PageSlice.full);

    expect(_cropBox, findsNothing);
    expect(_overflowBox, findsNothing);
    // 没有裁剪层，格子把整格给了这一页。
    expect(tester.getSize(find.byKey(_pageKey)), const Size(200, 100));
    expect(tester.takeException(), isNull);
  });
}
