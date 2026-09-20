// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';

/// 标签条的悬停判据。
///
/// 起因：实机日志里刷了一串 `MouseTracker` 的 `!_debugDuringDeviceUpdate` 断言。
/// 那条断言是**次生**的 —— `_deviceUpdatePhase` 里的异常会跳过复位标志，之后每帧都撞。
/// 所以这里要抓的是「悬停标签/关闭钮/tooltip 时抛的第一异常」。
DiscoverTabs _tabs() => DiscoverTabs(
  side: DiscoverTabBarSide.top,
  home: DiscoverLeafSpec(
    label: '发现',
    source: '',
    pluginName: '',
    iconUrl: '',
    content: (context) => const SizedBox(width: 40, height: 40),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  DiscoverTabs tabs, {
  Size surface = const Size(800, 600),
  bool centered = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // 与 main.dart 的根一致：少了这几位 delegate，PopupMenuButton 会先抛
      // 「No MaterialLocalizations」，然后它的 ErrorWidget 把标签条撑爆 ——
      // 那会把这个判据本身带偏。
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: Scaffold(
          body: Align(
            alignment: centered ? Alignment.center : Alignment.topLeft,
            child: SizedBox(
              width: surface.width,
              height: surface.height,
              child: DiscoverPlatView(
                tabs: tabs,
                setting: const DiscoverSettingState(),
                onSearch: () {},
                onCustomizeOrder: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 拖一条标签：`Draggable<TabDragPayload>` 的整条链路（拖起、跟随指针的浮层、
/// 落点判定）都要过一遍 —— 这是标签条上唯一会在指针移动中途改命中树的动作。
Future<void> _dragChip(WidgetTester tester, String from, Offset delta) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.text(from).first));
  await tester.pumpAndSettle();
  await gesture.down(tester.getCenter(find.text(from).first));
  await tester.pumpAndSettle();
  for (var step = 1; step <= 6; step++) {
    await gesture.moveBy(Offset(delta.dx / 6, delta.dy / 6));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
  await gesture.removePointer();
}

void main() {
  testWidgets('只有一条标签时画得出来，且不抛', (tester) async {
    final tabs = _tabs();
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);
    expect(find.text('发现'), findsWidgets);
    tabs.dispose();
  });

  testWidgets('开两条标签后悬停到标签上，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    final chip = find.text('排行');
    expect(chip, findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(chip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('悬停关闭按钮再移开，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '最新',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);

    final close = find.byIcon(Icons.close);
    expect(close, findsWidgets);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(close.first));
    await tester.pumpAndSettle();
    await gesture.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('横向拖一条标签换序，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    tabs.open(
      label: '最新',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    await _dragChip(tester, '排行', const Offset(80, 0));
    expect(tester.takeException(), isNull);
    expect(tabs.tabs.length, 3);
    tabs.dispose();
  });

  testWidgets('窄泳道里开三条标签：标签条不溢出、不抛', (tester) async {
    final tabs = _tabs();
    for (final label in ['排行', '最新', '收藏']) {
      tabs.open(
        label: label,
        source: 'p1',
        content: (context) => const SizedBox(width: 40, height: 40),
      );
    }
    // 320 宽是「面板图标必须完整」那笔账里最窄的一档；标签条在这里必须走滚动，
    // 而不是把 trailing 那三颗挤出去 —— 布局异常会顺手把 MouseTracker 的
    // 复位标志跳过去，表现就是日志里刷一串 !_debugDuringDeviceUpdate。
    await _pump(tester, tabs, surface: const Size(320, 600), centered: false);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('竖向轨在窄宽度下也不抛', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    tabs.setSide(DiscoverTabBarSide.left);
    await _pump(tester, tabs, surface: const Size(320, 600), centered: false);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('结果页那颗伪装搜索框：在标签里点它 ⇒ 开一条同来源的搜索标签', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) {
        final scope = DiscoverTabScope.maybeOf(context)!;
        return Align(
          child: TextButton(
            onPressed: () => scope.openSearchInput(
              SearchStates.initial().copyWith(from: 'p1'),
              aggregateMode: false,
            ),
            child: const Text('去搜索'),
          ),
        );
      },
    );
    await _pump(tester, tabs);
    final before = tabs.tabs.length;

    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();

    expect(tabs.tabs.length, before + 1);
    final opened = DiscoverTabs.specOfLeaf(
      tabs.tabs.last.child as LeafSnapshot,
    )!;
    // 来源必须跟着走：在 p1 的搜索结果里点搜索框，不该跳成一个没来源的搜索。
    expect(opened.source, 'p1');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('往内容区拖（这一组不收外来落点）也不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '收藏',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    await _dragChip(tester, '收藏', const Offset(0, 160));
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });
}
