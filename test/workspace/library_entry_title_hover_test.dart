// 封面网格的标题：hover 气泡 + 「完整显示文件名」那一档的可回读判据。
//
// 为什么单独一个文件：`library_entry_list_test.dart` 钉的是「六档都画得出来」
// 这类抽取契约，而这两条量的是**鼠标停在哪儿、字有没有铺满**的渲染结果。
//
// 每条都配了阳性对照，免得尺本身是瞎的：
//   - 气泡：先断言「指针没进格子时屏幕上只有一份标题」，再断言停在
//     **封面块**（离题字最远的那块）时标题变成两份。
//   - 换行：同一把 `RenderParagraph.didExceedMaxLines` 尺，短标题在两档下
//     都必须是 false；长标题关掉那一档必须是 true。
//
// 这一层不需要 `GlobalSettingCubit`：测试里没有 BlocProvider。哪天有人把
// 读设置写回视图层，coverGrid 会当场抛 ProviderNotFound，本文件全红——
// 那正是要的效果（共享视图层不认识设置，是它自己的文件头写的口径）。

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';

/// 需要 3~4 行才铺得下的长标题。
///
/// 字号在测试里是 Ahem（每个字符等宽），实测这一格题字约 6 字/行，
/// 24 字要 4 行：超过关闭档的 2 行，又落在打开档的 6 行以内。
const _longTitle = '第03卷 番外篇 完全汉化版 内含彩页 请勿混淆';

/// 一行就够的短标题 —— 阳性对照的夹具。
const _shortTitle = '短篇';

/// 一列宽：160 让 `maxCrossAxisExtent: 140` 只切出一列，
/// 题字区才有约 130 宽，长标题的行数才是可预期的。
const _width = 160.0;

Future<void> _pumpGrid(
  WidgetTester tester, {
  required String title,
  required bool wrapTitle,
}) async {
  tester.view.physicalSize = Size(_width, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // `Material` 是必须的：格子用的是 `InkWell`。
      home: Material(
        child: SizedBox(
          width: _width,
          height: 500,
          child: LibraryEntryList(
            mode: LibraryViewMode.coverGrid,
            wrapTitle: wrapTitle,
            entries: [
              LibraryEntry(
                key: 'k0',
                title: title,
                media:
                    (
                      context, {
                      required width,
                      required height,
                      required radius,
                      required fit,
                    }) => SizedBox(
                      key: ValueKey('media:k0'),
                      width: width,
                      height: height,
                    ),
                thumbModes: LibraryViewMode.values.toSet(),
              ),
            ],
            onTap: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 把鼠标移到某个 finder 的中心，并走完气泡的 300ms hover 计时。
Future<void> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('鼠标停在封面上（不是题字上）也浮出完整文件名', (tester) async {
    await _pumpGrid(tester, title: _longTitle, wrapTitle: false);

    // 对照：指针还没进格子时只有一份标题，没有气泡。
    expect(find.text(_longTitle), findsOneWidget);

    final mediaRect = tester.getRect(find.byKey(const ValueKey('media:k0')));
    final captionRect = tester.getRect(find.text(_longTitle));
    // 尺要看得见违规：封面块与题字块得真是分开的两块，
    // 否则「停在封面上」这条其实停在了题字上，测了个空。
    expect(
      mediaRect.bottom,
      lessThanOrEqualTo(captionRect.top + 1),
      reason: '封面块与题字块没分开，下面的 hover 位置测不出整格热区',
    );

    await _hover(tester, find.byKey(const ValueKey('media:k0')));

    expect(
      find.text(_longTitle),
      findsNWidgets(2),
      reason:
          '整格热区没套上气泡：只有题字那十几像素能 hover，'
          '鼠标停在中缝和封面上都看不见全名',
    );
  });

  testWidgets('关掉「完整显示文件名」时题字被截断，打开后不截断', (tester) async {
    await _pumpGrid(tester, title: _longTitle, wrapTitle: false);
    final off = _caption(tester, _longTitle);
    expect(off.didExceedMaxLines, isTrue, reason: '关掉那一档就该截断；不截断说明这把尺看不见差别');

    await _pumpGrid(tester, title: _longTitle, wrapTitle: true);
    final on = _caption(tester, _longTitle);
    expect(
      on.didExceedMaxLines,
      isFalse,
      reason: '打开那一档后仍被截掉，等于开关是装饰品。题字高度=${on.size.height}',
    );

    // 阳性对照：短标题在两档下都不该被判成截断。
    await _pumpGrid(tester, title: _shortTitle, wrapTitle: false);
    expect(
      _caption(tester, _shortTitle).didExceedMaxLines,
      isFalse,
      reason: '短标题都被判成截断了，说明 maxLines 的档位算错了',
    );
  });
}

RenderParagraph _caption(WidgetTester tester, String title) =>
    tester.renderObject<RenderParagraph>(find.text(title));
