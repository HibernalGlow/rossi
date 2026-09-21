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
import 'package:zephyr/widgets/plat/rossi_plat_theme.dart';

/// 右键「换边打开」（通用适配层）的判据。
///
/// 三条线一起验：
/// - **通用件本身**：最后两条用**裸 `PlatController`**（完全不碰发现页）跑通同样的
///   右键换边 —— 这才叫「别的地方想用也能用」；
/// - **横向档 = 移动**：这条标签离开原来那一格、单独成一格，**不**是多出一条复制；
/// - **竖向档 = 落在轨里**：竖轨下不出新窗格（新窗格自带一根画在内容中间的轨），
///   「在上方 / 在下方」是在轨里这条的前后多开一条。
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

  testWidgets('横向档「在右侧打开」= 移动：分出第二格，且标签总数没变', (
    tester,
  ) async {
    final tabs = _tabs()
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(tester, tabs);
    expect(tabs.controller.root, isA<TabGroupSnapshot>());
    final before = tabs.tabs.length;

    await _rightTap(tester, '排行');
    await tester.tap(find.text(t.plat.openRight));
    await tester.pumpAndSettle();

    expect(
      tabs.controller.root,
      isA<SplitSnapshot>(),
      reason: '点了「在右侧打开」但树上没有 split',
    );
    // 复制的话这里会变成 before + 1。
    expect(
      tabs.tabs.length,
      before,
      reason: '换边打开是**移动**这一条标签，不是再复制一条',
    );
    expect(
      tabs.tabs.where((tab) => tab.title == '排行').length,
      1,
      reason: '「排行」被复制成了两条：原来那一格没让位',
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

  testWidgets('通用性：裸 PlatController 也能用这套右键换边', (tester) async {
    final controller = PlatController(
      initialPlat: Plat.tabs([
        PlatTab.leaf(id: 'a', title: 'A', data: 'a'),
        PlatTab.leaf(id: 'b', title: 'B', data: 'b'),
      ], id: 'g'),
    );
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
                id: 'copy-${leaf.id}',
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
                id: 'copy-${tab.snapshot.id}',
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
    expect(
      _leafTitles(controller).where((title) => title == 'A').length,
      1,
      reason: '换边打开把标签复制了一份',
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('通用性：竖轨档在裸 PlatController 上也只在轨里开', (
    tester,
  ) async {
    final controller = PlatController(
      initialPlat: Plat.tabs(
        [
          PlatTab.leaf(id: 'a', title: 'A', data: 'a'),
          PlatTab.leaf(id: 'b', title: 'B', data: 'b'),
        ],
        id: 'g',
        side: TabBarSide.left,
      ),
    );
    await tester.pumpWidget(
      _app(
        RossiPlatTheme(
          barThickness: 132,
          vertical: true,
          child: PlatView(
            controller: controller,
            leafBuilder: (context, leaf) => const SizedBox.shrink(),
            tabBar: (context, group) => PlatTabBar(
              tabBuilder: (context, tab) => RossiPlatTabMenuRegion(
                controller: controller,
                tabId: tab.snapshot.id,
                duplicateTab: () => PlatTab.leaf(
                  id: 'copy-${tab.snapshot.id}',
                  title: tab.snapshot.title,
                  data: tab.snapshot.child is LeafSnapshot
                      ? (tab.snapshot.child as LeafSnapshot).data
                      : null,
                ),
                child: PlatTabChip(label: Text(tab.snapshot.title)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _rightTap(tester, 'A');
    expect(
      find.text(t.plat.openRight),
      findsNothing,
      reason: '竖轨下不给分屏：新窗格会带一根画在内容中间的轨',
    );
    await tester.tap(find.text(t.plat.openBelow));
    await tester.pumpAndSettle();

    expect(
      controller.root,
      isA<TabGroupSnapshot>(),
      reason: '竖轨下「在下方打开」应该落在轨里，而不是切出第二格',
    );
    // 落在轨里 = 多一条同内容的标签（这一档没有「移动」可言，它本来就一直在轨里）。
    expect(
      _leafTitles(controller).where((title) => title == 'A').length,
      2,
      reason: '轨里没多出那一条',
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('竖轨档：右键只有「在上方 / 在下方」，点下方落在轨里', (
    tester,
  ) async {
    final tabs = _tabs(side: DiscoverTabBarSide.left)
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(
      tester,
      tabs,
      setting: const DiscoverSettingState(tabSide: DiscoverTabBarSide.left),
    );
    expect(tabs.vertical, isTrue, reason: '这一档没转成竖轨，判据就是空的');

    await _rightTap(tester, '排行');
    expect(find.text(t.plat.openAbove), findsOneWidget);
    expect(find.text(t.plat.openBelow), findsOneWidget);
    expect(find.text(t.plat.openLeft), findsNothing);
    expect(find.text(t.plat.openRight), findsNothing);

    final before = tabs.tabs.length;
    await tester.tap(find.text(t.plat.openBelow));
    await tester.pumpAndSettle();

    expect(tabs.controller.root, isA<TabGroupSnapshot>(), reason: '竖轨下切出了第二格');
    expect(tabs.tabs.length, before + 1, reason: '轨里没多那一条');
    // 「在下方」= 落在被右键那条的**后面**，不是排到轨尾。
    final titles = tabs.tabs.map((tab) => tab.title).toList();
    final at = titles.indexOf('排行');
    expect(titles[at + 1], startsWith('排行'), reason: '新那条没挨在它下面：$titles');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('朝向混了会自己修回来：竖轨状态下从外面切出一格', (
    tester,
  ) async {
    // plat 自己的 Cmd + \ 不归本应用管，它切出来的新组**永远**是横档（top）。
    // 竖轨 + 一根横条 = 那根横条按全页唯一的轨厚画，就成了用户看到的
    // 「半屏高的一条空标签条」。这里绕开菜单直接切，验宿主兜得住。
    final tabs = _tabs(side: DiscoverTabBarSide.left)
      ..open(label: '排行', source: 'p1', content: (c) => const SizedBox())
      ..open(label: '最新', source: 'p1', content: (c) => const SizedBox());
    await _pumpDiscover(
      tester,
      tabs,
      // 900 宽摆得下「一条轨 + 两格内容」，否则钳制会把它拧回横档，
      // 那条判据就成了空的。
      surface: const Size(900, 700),
      setting: const DiscoverSettingState(tabSide: DiscoverTabBarSide.left),
    );

    final groupId = tabs.groupOf('tab-1')!;
    tabs.controller.insertTabBeside(
      targetId: groupId,
      side: PlatSide.right,
      // `data` 故意不是 `DiscoverLeafSpec`：这条 leaf 是「从外面塞进来的陌生人」，
      // 宿主对它只能当没内容，不能硬转 —— 硬转的 TypeError 发生在 build 里，
      // 那正是每帧刷断言直到卡死的那类引信。
      tab: PlatTab.leaf(id: 'forced', title: '强塞', data: 'x'),
    );
    await tester.pumpAndSettle();

    expect(
      tabs.sidesMixed,
      isFalse,
      reason: '混排没修回来：每一档的朝向应当跟着第一档走',
    );
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });
}

/// 树上每一条叶子的标题（分屏之后要按整棵树数，不能只读第一个组）。
List<String> _leafTitles(PlatController controller) {
  final out = <String>[];
  void walk(PlatSnapshot node) {
    switch (node) {
      case final TabGroupSnapshot group:
        for (final tab in group.tabs) {
          out.add(tab.title);
        }
      case final SplitSnapshot split:
        for (final child in split.children) {
          walk(child);
        }
      case final SlotSnapshot slot:
        final child = slot.child;
        if (child != null) walk(child);
      default:
        break;
    }
  }

  walk(controller.root);
  return out;
}

