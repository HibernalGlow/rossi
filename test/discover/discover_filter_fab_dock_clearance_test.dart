import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_list/models/comic_list_scene.dart';
import 'package:zephyr/page/comic_list/view/comic_list_page.dart';
import 'package:zephyr/page/comic_list/view/discover_filter_fab.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';

/// 一条「列表配置缺失」的场景：`body.request` 为 null，cubit 校验当场失败，
/// 不会去叫插件运行时 —— 但 `requiresFilter` 已经为真，筛选键照样挂出来。
const _scene = ComicListScene(
  title: '测试列表',
  from: 'test-source',
  body: ComicListBodyConfig(request: null),
  filter: ComicListRequestConfig(fnPath: 'getFilter'),
);

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  // 真机上 padding 与 viewPadding 一起是 34；只设一个会漏掉 Scaffold 的
  // `minViewPadding` 那一支，测出来的底边距就不是手机上的数。
  tester.view.padding = FakeViewPadding(bottom: 34);
  tester.view.viewPadding = FakeViewPadding(bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// 移动端那一支：外层 Dock Scaffold（`extendBody: true`）里套漫画列表页自己的
/// Scaffold。见 `navigation_bar.dart` 的 `_buildDockLayout`。
Future<void> _pumpDockedListPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: NavigationDock(
          destinations: const [
            NavigationDockDestination(glyph: AppGlyphs.compass, label: '发现'),
            NavigationDockDestination(glyph: AppGlyphs.home, label: '书架'),
          ],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
        body: const ComicListPage(scene: _scene),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('筛选键抬到 Dock 之上，且收起态只有图标', (tester) async {
    _usePhone(tester);
    await _pumpDockedListPage(tester);

    final fabRect = tester.getRect(find.byTooltip(t.comicList.filter));
    final dockRect = tester.getRect(find.byType(NavigationDock));
    debugPrint('FAB=$fabRect DOCK=$dockRect');

    // 不被盖住，也没有飞到半空（贴 Dock 上沿留 16 的边距）。
    expect(fabRect.bottom, lessThanOrEqualTo(dockRect.top));
    expect(fabRect.bottom, greaterThan(dockRect.top - 40));
    // 汉字只在 tooltip 里，按钮本体不占文字宽度。
    expect(find.text(t.comicList.filter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('尺子自检：贴在 bottom:16 的旧写法确实会被 Dock 盖住', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          resizeToAvoidBottomInset: false,
          bottomNavigationBar: NavigationDock(
            destinations: const [
              NavigationDockDestination(glyph: AppGlyphs.compass, label: '发现'),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              const Positioned(
                bottom: 16,
                right: 16,
                child: DiscoverFilterFab(onPressed: _noop),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fabRect = tester.getRect(find.byTooltip(t.comicList.filter));
    final dockRect = tester.getRect(find.byType(NavigationDock));
    expect(
      fabRect.bottom,
      greaterThan(dockRect.top),
      reason: '这条是正控：尺子看不见违规就不算尺子',
    );
  });
}

void _noop() {}
