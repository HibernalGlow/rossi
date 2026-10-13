import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_info/widgets/all_chip.dart';
import 'package:zephyr/page/comic_info/widgets/comic_inline_details_surface.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [220.0, 390.0, 1100.0]) {
    testWidgets('原位内容 $width：直接操作、Tag、预览、章节，无重复封面书名', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tagged = 0, downloaded = 0, closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const Text('唯一书名'),
                  ComicInlineDetailsSurface(
                    onClose: () => closed++,
                    operations: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => downloaded++,
                          icon: const Icon(Icons.download),
                          label: const Text('下载'),
                        ),
                        FilledButton.tonal(
                          onPressed: () {},
                          child: const Text('收藏'),
                        ),
                      ],
                    ),
                    metadata: Wrap(
                      children: [
                        AllChipItem(
                          label: '长标签' * 30,
                          expressive: true,
                          onTap: () => tagged++,
                          onLongPress: () {},
                        ),
                      ],
                    ),
                    description: const Text('作品简介'),
                    preview: ComicInlinePreviewGallery(
                      count: 3,
                      itemBuilder: (_, i) =>
                          ColoredBox(color: Colors.teal, child: Text('预览 $i')),
                    ),
                    chapters: ComicInlineChapterBoard(
                      count: 50,
                      onReverse: () {},
                      itemBuilder: (_, i) =>
                          SizedBox(height: 48, child: Text('章节 $i')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('唯一书名'), findsOneWidget);
      expect(find.text('章节与完整详情'), findsNothing);
      expect(find.text('作品简介'), findsOneWidget);
      expect(find.text('预览 0'), findsOneWidget);
      await tester.tap(find.text('下载'));
      expect(downloaded, 1);
      await tester.tap(find.byType(ActionChip));
      expect(tagged, 1);
      await tester.ensureVisible(find.text('显示更多章节'));
      await tester.tap(find.text('显示更多章节'));
      await tester.pumpAndSettle();
      expect(find.text('章节 35'), findsOneWidget);
      expect(find.text('章节 36'), findsNothing);
      await tester.ensureVisible(find.byTooltip('收起详情'));
      await tester.tap(find.byTooltip('收起详情'));
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('原图比例保持页序，横竖图改变形状，远处页可定位', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entries = List.generate(
      120,
      (i) => LibraryEntry(
        key: '$i',
        title: '页面 $i',
        mediaAspectRatio: i.isEven ? 2 : .55,
        media:
            (
              _, {
              required width,
              required height,
              required radius,
              required fit,
            }) {
              expect(fit, BoxFit.contain);
              return SizedBox(
                width: width,
                height: height,
                child: Text('画面 $i'),
              );
            },
      ),
    );
    final presentation = const LibraryPresentation(
      hero: false,
      weight: LibraryWeight.imageShape,
    );
    final rows = libraryCanvasRows(
      entries: entries,
      columns: 4,
      presentation: presentation,
    );
    expect(
      rows.expand((r) => r.indices),
      orderedEquals(List.generate(120, (i) => i)),
    );
    expect(rows.first.spans.first, 2);
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            key: key,
            scope: 'native-test',
            entries: entries,
            standalone: true,
            initialPresentation: presentation,
            onTap: (_) {},
            legacyBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.text('画面 0')).height,
      lessThan(tester.getSize(find.text('画面 1')).height),
    );
    key.currentState!.revealEntry('100');
    await tester.pumpAndSettle();
    expect(find.text('页面 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
