import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/view/discover_filter_fab.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool hasFilters,
  required VoidCallback onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: DiscoverFilterFab(hasFilters: hasFilters, onPressed: onTap),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('筛选键是 56dp 图标钮：没有汉字、有提示、角标跟 hasFilters 走', (tester) async {
    var taps = 0;
    await _pump(tester, hasFilters: true, onTap: () => taps++);

    final rect = tester.getRect(find.byType(ExpressiveIconButton));
    expect(rect.width, 56);
    expect(rect.height, 56);
    // 带文字的胶囊会占掉半屏宽；「是哪件事」只走 tooltip。
    expect(find.text(t.comicList.filter), findsNothing);
    expect(find.byTooltip(t.comicList.filter), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);

    await tester.tap(find.byType(ExpressiveIconButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有生效筛选时角标灭掉', (tester) async {
    await _pump(tester, hasFilters: false, onTap: () {});
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });
}
