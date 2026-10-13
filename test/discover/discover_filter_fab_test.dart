import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/view/discover_filter_fab.dart';

void main() {
  for (final width in [240.0, 1100.0]) {
    testWidgets('筛选在 $width 宽度的右下角，保留安全区、提示和筛选标记', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            floatingActionButton: DiscoverFilterFab(
              onPressed: () => taps++,
              hasFilters: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fab = find.byType(FloatingActionButton);
      final rect = tester.getRect(fab);
      expect(rect.right, lessThan(width));
      expect(rect.right, greaterThan(width - 40));
      expect(rect.bottom, lessThan(700));
      expect(rect.bottom, greaterThan(650));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(t.comicList.filter), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
