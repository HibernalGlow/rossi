import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  for (final (size, wide, native) in [
    (const Size(140, 270), false, false),
    (const Size(500, 270), true, false),
    (const Size(280, 180), true, true),
  ]) {
    testWidgets('$size 展墙阅读键在封面正中，信息键悬浮且无操作底栏', (tester) async {
      var reads = 0, details = 0, opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: LibraryEditorialTile(
                  wide: wide,
                  nativeShape: native,
                  onTap: () => opens++,
                  onInfo: () => details++,
                  entry: LibraryEntry(
                    key: 'book',
                    title: '书本',
                    onRead: () async => reads++,
                    media:
                        (
                          _, {
                          required width,
                          required height,
                          required radius,
                          required fit,
                        }) => SizedBox(
                          key: const ValueKey('cover'),
                          width: width,
                          height: height,
                          child: const ColoredBox(color: Colors.teal),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cover = tester.getRect(find.byKey(const ValueKey('cover')));
      final read = find.descendant(
        of: find.byType(ComicReadButton),
        matching: find.byType(InkWell),
      );
      expect((tester.getCenter(read) - cover.center).distance, lessThan(.1));
      final info = tester.getRect(find.byTooltip('展开信息'));
      expect(cover.contains(info.center), isTrue);
      expect(info.width, greaterThanOrEqualTo(48));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('书本'), findsOneWidget);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(details, 0);
      expect(opens, 0);
      await tester.tap(find.byTooltip('展开信息'));
      expect(details, 1);
      expect(opens, 0);
      await tester.tapAt(cover.topLeft + const Offset(8, 8));
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽卡保留完整图片与正常标题字号，直接展示真实标签', (tester) async {
    final mediaFits = <BoxFit>[];
    final widths = <double>[];
    final entry = LibraryEntry(
      key: 'integrated',
      title: '很长的作品标题包含画师和系列以及卷号',
      tags: const ['冒险', '全彩', '汉化'],
      media:
          (
            _, {
            required width,
            required height,
            required radius,
            required fit,
          }) {
            mediaFits.add(fit);
            widths.add(width);
            return SizedBox(
              width: width,
              height: height,
              child: const ColoredBox(color: Colors.teal),
            );
          },
    );
    Future<TextStyle?> render(double width, bool wide) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 270,
                child: LibraryEditorialTile(
                  entry: entry,
                  wide: wide,
                  spotlight: wide,
                  onTap: () {},
                  onInfo: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text(entry.title)).style;
    }

    final narrow = await render(160, false);
    final expanded = await render(500, true);
    expect(narrow!.fontSize, expanded!.fontSize);
    expect(mediaFits, everyElement(BoxFit.contain));
    expect(widths.last, 500);
    expect(find.text('冒险 · 全彩 · 汉化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final ratio in [2.0, 1.0, .55]) {
    testWidgets('原图比例 $ratio 等比适配，完整显示且无强制竖框', (tester) async {
      Size? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                height: 270,
                child: LibraryEditorialTile(
                  onTap: () {},
                  wide: true,
                  mediaAspectRatio: ratio,
                  entry: LibraryEntry(
                    key: 'ratio',
                    title: '原图',
                    media:
                        (
                          _, {
                          required width,
                          required height,
                          required radius,
                          required fit,
                        }) {
                          requested = Size(width, height);
                          expect(fit, BoxFit.contain);
                          return SizedBox(width: width, height: height);
                        },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested!.aspectRatio, closeTo(ratio, .001));
      expect(requested!.width, lessThanOrEqualTo(500));
      expect(requested!.height, lessThanOrEqualTo(270));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('已有标题的首页封面不再增加第二份标题或底部栏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 270,
              child: LibraryEditorialTile(
                onTap: () {},
                onInfo: () {},
                entry: LibraryEntry(
                  key: 'book',
                  title: '唯一标题',
                  mediaIncludesTitle: true,
                  onRead: () async {},
                  media:
                      (
                        _, {
                        required width,
                        required height,
                        required radius,
                        required fit,
                      }) => SizedBox(
                        key: const ValueKey('cover'),
                        width: width,
                        height: height,
                        child: const Align(
                          alignment: Alignment.bottomLeft,
                          child: Text('唯一标题'),
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('唯一标题'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('cover'))).height, 270);
    expect(tester.takeException(), isNull);
  });
}
