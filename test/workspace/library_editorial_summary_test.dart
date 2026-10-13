import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  for (final (size, scale) in [
    (const Size(440, 250), 1.0),
    (const Size(280, 180), 1.0),
    (const Size(440, 250), 2.0),
    (const Size(320, 180), 2.0),
    (const Size(800, 270), 1.5),
  ]) {
    testWidgets('长标题与路径在 $size、字体 $scale 下不溢出且悬浮动作可用', (tester) async {
      var reads = 0, infos = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox.fromSize(
                  size: size,
                  child: LibraryEditorialTile(
                    wide: true,
                    spotlight: true,
                    onTap: () {},
                    onInfo: () => infos++,
                    entry: LibraryEntry(
                      key: 'long-book',
                      title: '(碧蓝航线 · 塔什干) [Mimmi] [DJAWA Photo]',
                      subtitle: '本地 · P.14',
                      description:
                          '/Volumes/BOX/1Hub/EH/[02COS]/[DJAWA Photo]/001. '
                          '(碧蓝航线 · 塔什干) [Mimmi] [DJAWA Photo] 长目录和书本名称.cbz',
                      metaText: '继续阅读',
                      progress: .42,
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
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('(碧蓝航线 · 塔什干) [Mimmi] [DJAWA Photo]'), findsOneWidget);
      expect(find.text('本地 · P.14'), findsOneWidget);
      final cover = tester.getRect(find.byKey(const ValueKey('cover')));
      final read = find.descendant(
        of: find.byType(ComicReadButton),
        matching: find.byType(InkWell),
      );
      expect((tester.getCenter(read) - cover.center).distance, lessThan(.1));
      await tester.tap(read);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开信息'));
      expect(reads, 1);
      expect(infos, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
