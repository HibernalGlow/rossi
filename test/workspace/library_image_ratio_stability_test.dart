import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/widgets/library_image_geometry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  testWidgets('解码尺寸取整产生微小比例差异时，横图卡片只适配一次且不持续重排', (tester) async {
    SharedPreferences.setMockInitialValues({});
    LibraryImageGeometryScope? geometry;
    var builds = 0;
    final data = [
      LibraryEntry(
        key: 'landscape',
        title: '横向封面',
        media:
            (
              context, {
              required width,
              required height,
              required radius,
              required fit,
            }) {
              geometry = LibraryImageGeometryScope.maybeOf(context);
              builds++;
              return SizedBox(width: width, height: height);
            },
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            scope: 'ratio-stability',
            entries: data,
            standalone: true,
            initialPresentation: const LibraryPresentation(
              hero: false,
              weight: LibraryWeight.imageShape,
            ),
            legacyBuilder: (_) => const SizedBox(),
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final callback = geometry!.onRatio;
    callback(2);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LibraryEditorialTile>(find.byType(LibraryEditorialTile))
          .mediaAspectRatio,
      2,
    );
    final settled = tester.getRect(find.byType(LibraryEditorialTile));
    final stableBuilds = builds;
    expect(geometry!.onRatio, same(callback));
    expect(settled.width, greaterThan(settled.height));
    expect(geometry!.keepFullImage, isTrue);
    for (var i = 0; i < 16; i++) {
      callback(i.isEven ? 1.998 : 2.002);
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getRect(find.byType(LibraryEditorialTile)), settled);
    }
    expect(builds, stableBuilds);
    expect(tester.takeException(), isNull);
  });
}
