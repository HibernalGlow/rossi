import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_customization_dialog.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/navigation/navigation_entries.dart';
import 'package:zephyr/widgets/navigation/navigation_sidebar.dart';

/// 侧栏、Dock 与「自定义导航」弹窗的**冒烟**判据：能挂起来、能点、动作与
/// 换页不串、两段清单真的能改。
///
/// 侧栏与 Dock 是从 FlClash 原文搬来的，判据要钉的**不是**动效好不好看
/// （弹簧的手感没有数值判据），而是这几件会真的坏掉的事：
/// 1. 在没有任何宿主假设的 `Scaffold` 里能渲染（约束不自洽会抛断言）；
/// 2. 点目的地 = 报出下标，**点动作不换页**（两者共用同一套行画法，最容易串）；
/// 3. Dock 尾部那颗按钮「传了才出现」（它由底部快捷区那段清单决定，是本仓加的）；
/// 4. **`Scaffold.extendBody` 的那条框架契约**：内容铺到屏幕底部（胶囊四周才
///    是透的），同时 body 拿到的 `MediaQuery.padding.bottom` = 底栏实际高度
///    （内容因此不会被胶囊压住）。`navigation_bar.dart` 的 `_buildDockLayout`
///    整套「透明 + 不让位失手」都压在这条上，值得单独钉住；
/// 5. 弹窗里**两段都在**，隐藏与「两段之间搬」都真的回调出去 —— 底部那块
///    以前是写死的固定区，这一轮才让它可隐藏、可排序。
/// 按 tooltip 文案找组件。
///
/// **别用 `find.byTooltip`**：它比的是 `flutter/material` 的 `Tooltip` /
/// `RawTooltip`，而本仓界面（这两个组件也一样）用的是 `package:material_ui`
/// 里**同名但不同类**的那两个 —— 谓词恒为假，而且**静默返回 0 个**
/// （`tap` 时才报「找不到」，看起来像组件没渲染）。这个坑对整个仓的测试都成立。
Finder byTooltipText(String message) =>
    find.byWidgetPredicate((w) => w is Tooltip && w.message == message);

void main() {
  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  /// 组件里的文案走 `context.t`，它要 `TranslationProvider` 祖先
  /// （真机上由 `main.dart` 挂一次）。`LocaleSettings.setLocale` 只管全局那个 `t`，
  /// 顶不了这一层 —— 少了它会直接抛「Please wrap your app with "TranslationProvider"」。
  Widget host({required Widget body, Widget? bottom}) => TranslationProvider(
    child: MaterialApp(
      home: Scaffold(body: body, bottomNavigationBar: bottom),
    ),
  );

  const three = [
    SidebarDestination(glyph: AppGlyphs.columnsThree, label: '书架'),
    SidebarDestination(glyph: AppGlyphs.target, label: '发现'),
    SidebarDestination(glyph: AppGlyphs.appsList, label: '更多'),
  ];

  const destinations = [
    NavigationDockDestination(glyph: AppGlyphs.columnsThree, label: '书架'),
    NavigationDockDestination(glyph: AppGlyphs.target, label: '发现'),
    NavigationDockDestination(glyph: AppGlyphs.appsList, label: '更多'),
  ];

  testWidgets('侧栏：渲染出来，点目的地报下标，点动作不换页', (tester) async {
    final selected = <int>[];
    var workspaceTaps = 0;
    var customizeTaps = 0;

    await tester.pumpWidget(
      host(
        body: Row(
          children: [
            NavigationSidebar(
              destinations: three,
              selectedIndex: 0,
              expanded: false,
              onSelected: selected.add,
              onToggle: () {},
              actions: [
                SidebarAction(
                  glyph: AppGlyphs.layoutTabs,
                  label: '工作台',
                  onTap: () => workspaceTaps++,
                ),
              ],
              onCustomize: () => customizeTaps++,
              customizeLabel: t.navigation.customize,
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: '原始行放不下时不该抛断言');

    // 收起态：每条只有图标，标签走 tooltip。
    await tester.tap(byTooltipText('发现'));
    expect(selected, [1]);

    await tester.tap(byTooltipText('工作台'));
    expect(workspaceTaps, 1);
    expect(selected, [1], reason: '动作点了不换页 —— 与目的地共用行画法，这里最容易串');

    await tester.tap(byTooltipText(t.navigation.customize));
    expect(customizeTaps, 1);
  });

  testWidgets('侧栏：展开态把标签画出来（可见文案而不是 tooltip）', (tester) async {
    await tester.pumpWidget(
      host(
        body: Row(
          children: [
            NavigationSidebar(
              destinations: three,
              selectedIndex: 1,
              expanded: true,
              onSelected: (_) {},
              onToggle: () {},
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('书架'), findsOneWidget);
    // 没传 onCustomize 就整条不出现。
    expect(byTooltipText(t.navigation.customize), findsNothing);
  });

  testWidgets('Dock：渲染出来、点目的地报下标、尾部按钮传了才出现', (tester) async {
    final selected = <int>[];
    var overflowTaps = 0;

    await tester.pumpWidget(
      host(
        body: const SizedBox.expand(),
        bottom: NavigationDock(
          destinations: destinations,
          selectedIndex: 0,
          onSelected: selected.add,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      byTooltipText(t.navigation.moreActions),
      findsNothing,
      reason: '不传 trailing 时尾部那颗按钮不该出现',
    );

    await tester.tap(find.text('发现'));
    expect(selected, [1]);
    // 让 lens 的弹簧跑完，别把未结算的动画留给下一条断言。
    await tester.pump(const Duration(milliseconds: 800));

    await tester.pumpWidget(
      host(
        body: const SizedBox.expand(),
        bottom: NavigationDock(
          destinations: destinations,
          selectedIndex: 0,
          onSelected: selected.add,
          trailing: FloatingActionButton(
            onPressed: () => overflowTaps++,
            tooltip: t.navigation.moreActions,
            child: const GlyphIcon(AppGlyphs.more, size: 24),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    await tester.tap(byTooltipText(t.navigation.moreActions));
    expect(overflowTaps, 1);
    await tester.pump(const Duration(milliseconds: 800));
  });

  /// `_buildDockLayout` 那一整套「胶囊四周透明 + 内容不被压住」压在
  /// `Scaffold.extendBody` 上。这条钉的是**框架契约**（换 SDK 时会响），
  /// 不是我们那几行代码本身 —— 后者要挂起整个 `NavigationBar`（ObjectBox、
  /// GlobalSettingCubit、通知、下载队列）才够得着，代价与收益不成比例。
  testWidgets('Dock 垫底：extendBody 让 body 铺到屏幕底部，并拿到底栏的实际高度', (tester) async {
    const bodyKey = ValueKey('dock-body');
    double? paddingBottom;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: NavigationDock(
              destinations: destinations,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            body: Builder(
              key: bodyKey,
              builder: (context) {
                paddingBottom = MediaQuery.paddingOf(context).bottom;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final bodyHeight = tester.getSize(find.byKey(bodyKey)).height;
    final scaffoldHeight = tester.getSize(find.byType(Scaffold)).height;
    final dockHeight = tester.getSize(find.byType(NavigationDock)).height;

    expect(
      bodyHeight,
      scaffoldHeight,
      reason: 'body 要铺到屏幕底部（内容是「从胶囊底下穿过去」的），'
          '否则胶囊四周会露出一条与页面同色的空带',
    );
    expect(
      paddingBottom,
      dockHeight,
      reason: '框架把底栏的实际高度写进 body 的 MediaQuery.padding.bottom —— '
          'SafeArea 与 padding: null 的滚动视图都靠它让位',
    );
  });

  /// 「自定义导航」弹窗：两段（主区 / 底部快捷区）都在，隐藏与「两段之间搬」
  /// 都真的回调出去。
  ///
  /// 这一条钉的是用户 2026-10-10 提的那件事：底部那块（打开本地漫画 / GPU 上屏 /
  /// 搜索 / 自定义导航）以前是**写死的固定区**，藏不掉也排不了序。现在它在
  /// 弹窗里有自己的一段，动作行上的箭头在两段之间搬。
  testWidgets('自定义弹窗：两段都在，隐藏与「两段之间搬」都会回调', (tester) async {
    // 弹窗内容高度上限是 500（见 `CustomNavigationDialog.build`），而这一条要
    // 一次够到两段的所有行，所以把测试窗口拉高到让那个 500 生效。
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late NavigationLayoutDraft desktop;
    const initial = NavigationLayoutDraft(
      main: [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
      ],
      actions: kDefaultNavigationActionEntries,
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: CustomNavigationDialog(
            desktop: initial,
            mobile: initial,
            availableItems: availableNavigationEntries(false),
            onChanged: (next, _) => desktop = next,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    expect(find.text(t.navigation.customizeMainSection), findsOneWidget);
    expect(find.text(t.navigation.customizeActionsSection), findsOneWidget);

    // 在**底部快捷区**那一行点「移到主区」：两段都得跟着变。
    final searchRow = find.ancestor(
      of: find.text(t.common.search),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: searchRow,
        matching: byTooltipText(t.navigation.customizeMoveToMain),
      ),
    );
    await tester.pump();
    expect(desktop.main, contains(NavigationEntryId.search));
    expect(desktop.actions, isNot(contains(NavigationEntryId.search)));

    // 再从主区把它隐藏掉（动作没有下限，按钮是能按的）。
    await tester.tap(
      find.descendant(
        of: searchRow,
        matching: byTooltipText(t.navigation.customizeHide),
      ),
    );
    await tester.pump();
    expect(desktop.main, isNot(contains(NavigationEntryId.search)));

    // 待添加池在下面一屏（弹窗内容高度上限 500），滚一下才够得着 ——
    // 刚挪走并隐藏的「搜索」与出厂就没被摆上的「工作台」都该出现在那里。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pump();
    expect(find.widgetWithText(ActionChip, t.navigation.workspace), findsOneWidget);
    expect(find.widgetWithText(ActionChip, t.common.search), findsOneWidget);
  });

  /// 「自定义导航」弹窗：拖拽起手把行**提到根 Overlay** 里当拖拽代理 ——
  /// 那层在弹窗 `AlertDialog` 的 `Material` 之外。`SliverReorderableList` 裸用
  /// 时默认代理不包 Material，行里的 ListTile 会当场抛
  /// 「No Material widget found」（2026-10-10 用户截图，拖住一行就红）。
  /// 修法是给弹窗里的两个清单各配一个带 Material 的 `proxyDecorator`。
  testWidgets('自定义弹窗：拖拽起手（拖拽代理进 Overlay）不缺 Material', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const initial = NavigationLayoutDraft(
      main: [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
      ],
      actions: kDefaultNavigationActionEntries,
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: CustomNavigationDialog(
            desktop: initial,
            mobile: initial,
            availableItems: availableNavigationEntries(false),
            onChanged: (_, __) {},
          ),
        ),
      ),
    );

    // 按住「发现」行的拖拽手柄起手：`ReorderableDragStartListener` 在
    // pointer down 那一刻就把整行提进根 Overlay，异常就在下一帧抛出。
    final handle = find.ancestor(
      of: find.text(t.navigation.discover),
      matching: find.byType(ReorderableDragStartListener),
    );
    expect(handle, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
