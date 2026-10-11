import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_field.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_header.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('内联搜索首次点击聚焦、提交后保留焦点、关闭后重开 reduced=$reduced', (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var expanded = false;
      var query = '';
      var submitted = '';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(280, 600),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, refresh) => ShelfSearchHeader(
                  expanded: expanded,
                  tabs: const SizedBox(
                    width: 320,
                    height: 48,
                    child: Text('收藏 / 历史 / 下载'),
                  ),
                  filter: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.filter_list),
                  ),
                  onExpand: () => refresh(() => expanded = true),
                  onClose: () {
                    focus.unfocus();
                    refresh(() => expanded = false);
                  },
                  searchField: ShelfSearchField(
                    query: query,
                    focusNode: focus,
                    hintText: '搜索书签',
                    onChanged: (value) => query = value,
                    onSubmitted: (value) => submitted = value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(ExpressiveIconButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(
        tester.getRect(find.byType(TextField)).right,
        lessThanOrEqualTo(280),
      );
      await tester.enterText(find.byType(TextField), '  阅读计划  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(submitted, '阅读计划');
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.byType(ExpressiveIconButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(ExpressiveIconButton));
      await tester.pumpAndSettle();
      expect(find.text('  阅读计划  '), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('AppBar 只放按钮行，搜索区域在下方自然增高且不遮挡正文', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var expanded = false;
    const bodyKey = ValueKey('shelf-content');
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, refresh) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 8,
              title: ShelfSearchHeader(
                expanded: expanded,
                tabs: const SizedBox(
                  width: 260,
                  height: 40,
                  child: Text('收藏 / 历史 / 下载'),
                ),
                filter: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {},
                ),
                onExpand: () => refresh(() => expanded = true),
                onClose: () => refresh(() => expanded = false),
              ),
            ),
            body: Column(
              children: [
                ShelfSearchRegion(
                  expanded: expanded,
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                  child: ShelfSearchField(
                    query: '',
                    focusNode: focus,
                    hintText: '搜索书签',
                    onChanged: (_) {},
                    onSubmitted: (_) {},
                  ),
                ),
                const Expanded(child: SizedBox.expand(key: bodyKey)),
              ],
            ),
          ),
        ),
      ),
    );
    final initialTop = tester.getRect(find.byKey(bodyKey)).top;
    await tester.tap(find.byType(ExpressiveIconButton));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(
      tester.getRect(find.byType(TextField)).top,
      greaterThanOrEqualTo(initialTop),
    );
    final inputBottom = tester.getRect(find.byType(TextField)).bottom;
    expect(tester.getRect(find.byKey(bodyKey)).top, greaterThan(inputBottom));
    await tester.enterText(find.byType(TextField), '一个很长的搜索关键词' * 10);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(bodyKey)).top,
      greaterThan(tester.getRect(find.byType(TextField)).bottom),
    );
    await tester.tap(find.byType(ExpressiveIconButton));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(bodyKey)).top, initialTop);
    expect(tester.takeException(), isNull);
  });
}
