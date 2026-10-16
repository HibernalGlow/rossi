import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_navigation_controller.dart';
import 'package:zephyr/page/comic_list/view/discover_browse_menu.dart';

void main() {
  testWidgets('通用菜单包含筛选、展示、恢复与跳页，显示当前页并验证输入', (tester) async {
    final nav = PluginListNavigationController();
    final owner = Object();
    var jump = 0, restored = 0, filtered = 0;
    nav.attach(
      owner,
      jump: (page) async {
        jump = page;
      },
      restore: () async {
        restored++;
      },
    );
    nav.update(owner, page: 12, total: 60, saved: 35, loading: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: DiscoverBrowseMenu(
              navigation: nav,
              onFilter: () {
                filtered++;
              },
              onPresentation: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(t.comicList.pageOfTotal(page: 12, total: 60)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(t.comicList.browseMenu));
    await tester.pumpAndSettle();
    expect(find.text(t.comicList.filter), findsOneWidget);
    expect(find.text(t.workspace.displayWallSettings), findsOneWidget);
    expect(find.text(t.comicList.restorePage(page: 35)), findsOneWidget);
    await tester.tap(find.text(t.comicList.restorePosition));
    await tester.pumpAndSettle();
    expect(restored, 1);
    await tester.tap(find.byTooltip(t.comicList.browseMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.widgetWithText(FilledButton, t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    expect(find.text(t.comicList.invalidPage), findsOneWidget);
    expect(jump, 0);
    await tester.enterText(find.byType(TextFormField), '61');
    await tester.tap(find.widgetWithText(FilledButton, t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    expect(find.text(t.comicList.pageOutOfRange(total: 60)), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '38');
    await tester.tap(find.widgetWithText(FilledButton, t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    expect(jump, 38);
    await tester.tap(find.byTooltip(t.comicList.browseMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.comicList.filter));
    await tester.pumpAndSettle();
    expect(filtered, 1);
    await tester.pumpWidget(const SizedBox());
    nav.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('未知总页数不编造上限，没有恢复记录时禁用恢复', (tester) async {
    final nav = PluginListNavigationController();
    final owner = Object();
    var jumped = 0;
    nav.attach(
      owner,
      jump: (page) async {
        jumped = page;
      },
      restore: () async {},
    );
    nav.update(owner, page: 1, total: null, saved: null, loading: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverBrowseMenu(
            navigation: nav,
            onPresentation: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(t.comicList.currentPage(page: 1)), findsOneWidget);
    await tester.tap(find.byTooltip(t.comicList.browseMenu));
    await tester.pumpAndSettle();
    final restore = tester.widget<ListTile>(
      find.widgetWithText(ListTile, t.comicList.restorePosition),
    );
    expect(restore.enabled, isFalse);
    expect(find.text(t.comicList.filter), findsNothing);
    await tester.tap(find.text(t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '400');
    await tester.tap(find.widgetWithText(FilledButton, t.comicList.jumpToPage));
    await tester.pumpAndSettle();
    expect(jumped, 400);
    await tester.pumpWidget(const SizedBox());
    nav.dispose();
    expect(tester.takeException(), isNull);
  });
}
