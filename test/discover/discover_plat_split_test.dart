import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/widgets/plat/rossi_plat_tab_menu.dart';

/// 右键分屏（通用适配层）的判据。
///
/// 两条线一起验：
/// - **通用件本身**：最后一条用**裸 `PlatController`**（完全不碰发现页）跑通同样的
///   右键分屏 —— 这才叫「别的地方想用也能用」；
/// - **发现页接上了**：四个方向、locked 的首页不给拆、格子不够时置灰。
Widget _app(Widget child) => MaterialApp(
  supportedLocales: AppLocaleUtils.supportedLocales,
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => GlobalSettingCubit()),
      BlocProvider(create: (_) => PluginRegistryCubit()),
    ],
    child: Scaffold(body: child),
  ),
);

DiscoverTabs _tabs({DiscoverTabBarSide side = DiscoverTabBarSide.top}) {
  return DiscoverTabs(
    side: side,
    home: DiscoverLeafSpec(
      label: '发现',
      source: '',
      pluginName: '',
      iconUrl: '',
      content: (context) => const SizedBox(width: 40, height: 40),
    ),
  );
}

Future<void> _pumpDiscover(
  WidgetTester tester,
  DiscoverTabs tabs, {
  Size surface = const Size(900, 600),
  DiscoverSettingState setting = const DiscoverSettingState(),
}) async {
  await tester.pumpWidget(
    _app(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: surface.width,
          height: surface.height,
          child: DiscoverPlatView(
            tabs: tabs,
            setting: setting,
            onSearch: () {},
            onCustomizeOrder: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 右键某条标签（按标题找）。
Future<void> _rightTap(WidgetTester tester, String title) async {
  await tester.tap(
    find.text(title).first,
    buttons: kSecondaryButton,
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

/// 菜单里某一项当前可不可点。
///
/// 用 `byWidgetPredicate` + `is PopupMenuItem<dynamic>`：`find.byType` 比的是
/// **精确 runtimeType**，写 `PopupMenuItem<Object?>` 永远匹配不到泛型实参那一种。
bool _itemEnabled(String title) {
  final widget = find
      .ancestor(
        of: find.text(title),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem<dynamic>),
      )
      .evaluate()
      .single
      .widget;
  return (widget as PopupMenuItem<dynamic>).enabled;
}

void main() {
  testWidgets('右键标签：四个方向 + 关闭都在', (tester) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);

    await _rightTap(tester, '排行');
    for (final label in [
      t.plat.openAbove,
      t.plat.openBelow,
      t.plat.openLeft,
      t.plat.openRight,
      t.plat.closeTab,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '菜单里缺「$label」');
    }
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('点「在右侧打开」→ 树上真的分出第二个窗格，且不抛', (tester) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);
    expect(tabs.controller.root, isA<TabGroupSnapshot>());

    await _rightTap(tester, '排行');
    await tester.tap(find.text(t.plat.openRight));
    await tester.pumpAndSettle();

    expect(
      tabs.controller.root,
      isA<SplitSnapshot>(),
      reason: '点了「在右侧打开」但树上没有 split',
    );
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('四个方向逐个分屏都不抛（每次从单组起）', (tester) async {
    for (final label in [
      t.plat.openAbove,
      t.plat.openBelow,
      t.plat.openLeft,
      t.plat.openRight,
    ]) {
      final tabs = _tabs()
        ..open(label: '最新', source: 'p1', content: (c) => const SizedBox());
      await _pumpDiscover(tester, tabs);
      await _rightTap(tester, '最新');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '「$label」之后抛了');
      expect(tabs.controller.root, isA<SplitSnapshot>(), reason: '「$label」没分屏');
      tabs.dispose();
    }
  });

  testWidgets('分屏出来的那一格仍然不卡：悬停 + 切标签', (tester) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox())
      ..open(label: '最新', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);
    await _rightTap(tester, '排行');
    await tester.tap(find.text(t.plat.openRight));
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(const Offset(120, 12));
    await tester.pumpAndSettle();
    await gesture.moveTo(const Offset(600, 12));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('格子不够宽：左右置灰，上下仍给点', (tester) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    // 500 宽、横向档：一格 500，切两半各 250 < 280 ⇒ 左右不给点；
    // 高 600 切两半 300 ≥ 200 ⇒ 上下照给。
    await _pumpDiscover(tester, tabs, surface: const Size(500, 600));
    await _rightTap(tester, '排行');

    expect(_itemEnabled(t.plat.openLeft), isFalse, reason: '250 宽的一格摆得下个鬼');
    expect(_itemEnabled(t.plat.openRight), isFalse);
    expect(_itemEnabled(t.plat.openAbove), isTrue);
    expect(_itemEnabled(t.plat.openBelow), isTrue);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('首页那条 locked：四个方向都置灰', (tester) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);

    await _rightTap(tester, '发现');
    for (final label in [
      t.plat.openAbove,
      t.plat.openLeft,
      t.plat.openRight,
      t.plat.openBelow,
    ]) {
      expect(_itemEnabled(label), isFalse, reason: '「$label」不该给 locked 那条');
    }
    // 关闭也不给（locked），所以菜单里连那一项都不该出现。
    expect(find.text(t.plat.closeTab), findsNothing);
    tabs.dispose();
  });

  testWidgets('分屏收得回去：关掉那一格的标签 → 回到单组', (tester) async {
    // 分屏最容易把自己关进死路：那一格只剩一条标签，关掉它之后必须
    // 回到「一个组」，而不是留下一个空壳窗格占着半屏。
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);

    await _rightTap(tester, '排行');
    await tester.tap(find.text(t.plat.openRight));
    await tester.pumpAndSettle();
    expect(tabs.controller.root, isA<SplitSnapshot>());

    final copy = tabs.tabs.last.id;
    expect(copy, isNot(DiscoverTabs.homeId));
    tabs.close(copy);
    await tester.pumpAndSettle();

    expect(
      tabs.controller.root,
      isA<TabGroupSnapshot>(),
      reason: '关掉那一格之后没收回单组',
    );
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('通用性：裸 PlatController 也能用这套右键分屏', (tester) async {
    final controller = PlatController(
      initialPlat: Plat.tabs([
        PlatTab.leaf(id: 'a', title: 'A', data: 'a'),
      ], id: 'g'),
    );
    var seq = 0;
    await tester.pumpWidget(
      _app(
        PlatView(
          controller: controller,
          leafBuilder: (context, leaf) => GestureDetector(
            onTap: () {},
            child: RossiPlatTabMenuRegion(
              controller: controller,
              tabId: leaf.id,
              duplicateTab: () => PlatTab.leaf(
                id: 'copy-${++seq}',
                title: leaf.title,
                data: leaf.data,
              ),
              onClose: () => controller.close(leaf.id),
              child: SizedBox(
                height: 24,
                child: Center(child: Text(leaf.title)),
              ),
            ),
          ),
          tabBar: (context, group) => PlatTabBar(
            tabBuilder: (context, tab) => RossiPlatTabMenuRegion(
              controller: controller,
              tabId: tab.snapshot.id,
              duplicateTab: () => PlatTab.leaf(
                id: 'copy-${++seq}',
                title: tab.snapshot.title,
                data: 'copy',
              ),
              onClose: () => controller.close(tab.snapshot.id),
              child: PlatTabChip(label: Text(tab.snapshot.title)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.root, isA<TabGroupSnapshot>());

    await _rightTap(tester, 'A');
    await tester.tap(find.text(t.plat.openBelow));
    await tester.pumpAndSettle();

    expect(
      controller.root,
      isA<SplitSnapshot>(),
      reason: '通用件离不开发现页的话，就不该叫通用件',
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}
