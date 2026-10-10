// 只用 material_ui：与主应用同一套 MaterialApp / Scaffold / Icons。
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';

/// 发现页标签「关闭」的判据。
///
/// 用户实机反馈：移动端点 × 不生效、只有长按菜单能关、长按稍微一动就转成拖拽。
/// 取证结论（纯 plat 探针复现）：`PlatTabChip` 的按下态会翻转
/// `Container.foregroundDecoration`，Container 合成链因此在按住期间插入一层
/// `DecoratedBox`，chip 内容整棵重挂 —— × 的识别器失联，抬起事件无人接听。
/// 修复 = `RossiPlatTabChip`（前景层恒在、只变色、不变结构）。
///
/// 这组判据把各条关闭路径钉住：
/// - **点 ×**（干净点按、指尖漂移、按住期间渲染帧）必须都能关；
/// - **长按 → 菜单 → 关闭** 必须通；
/// - **长按中漂移超过触控 slop** 不许起拖拽 —— vendored plat 在
///   `acceptsDrops: false` 的组里摘除了 `Draggable`（vendor/plat/VENDORED.md）。
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // 与 main.dart 的根一致：少了这几位 delegate，菜单会先抛
      // 「No MaterialLocalizations」把判据带偏。
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
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

Future<void> _openTab(DiscoverTabs tabs, String label) async {
  tabs.open(label: label, source: 'p1', content: (c) => const SizedBox());
}

bool _tabAlive(DiscoverTabs tabs, String label) =>
    tabs.tabs.any((tab) => tab.title == label);

/// 触摸手势：在 [target] 中心按下，走 [path] 的轨迹后抬起。
Future<void> _touchSwipe(
  WidgetTester tester,
  Finder target, {
  List<Offset> path = const [],
  Duration hold = Duration.zero,
  bool pumpDuringHold = false,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.touch,
  );
  await tester.pump();
  if (hold > Duration.zero) {
    await tester.pump(hold);
  }
  if (pumpDuringHold) {
    // 按住期间渲染一帧 —— 实机上 `_setPressed` 的 setState 必然走到这里，
    // 修复前正是这一帧把 chip 内容整棵重挂、吃掉点按。
    await tester.pump();
  }
  for (final step in path) {
    await gesture.moveBy(step);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点 × 直接关闭标签', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);
    expect(_tabAlive(tabs, '排行'), isTrue);

    await tester.tap(find.byType(PlatTabCloseButton));
    await tester.pumpAndSettle();

    expect(_tabAlive(tabs, '排行'), isFalse, reason: '点 × 必须关掉这条标签');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('按住期间渲染一帧（实机必经路径），点 × 仍要关闭', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    await _touchSwipe(
      tester,
      find.byType(PlatTabCloseButton),
      pumpDuringHold: true,
    );

    expect(
      _tabAlive(tabs, '排行'),
      isFalse,
      reason: '按住期间的重挂不许吃掉点 × —— 这是实机上「点关闭没反应」的根',
    );
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('点 × 时指尖轻微漂移（slop 内）仍要关闭', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    // (6, 4) 合成位移 7.2 逻辑像素：真机上一颗点歪的普通点按就是这个量级，
    // 远小于触控 slop（18），不该被拖拽或滚动抢走。
    await _touchSwipe(
      tester,
      find.byType(PlatTabCloseButton),
      path: const [Offset(4, 2), Offset(2, 2)],
    );

    expect(_tabAlive(tabs, '排行'), isFalse, reason: 'slop 内的漂移不该吃掉这次点按');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('长按 → 菜单 → 点「关闭标签页」也能关', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    await tester.longPress(find.text('排行').first);
    await tester.pumpAndSettle();
    expect(find.text(t.plat.closeTab), findsOneWidget);

    await tester.tap(find.text(t.plat.closeTab));
    await tester.pumpAndSettle();

    expect(_tabAlive(tabs, '排行'), isFalse);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('长按中漂移超过触控 slop：不再起拖拽（vendored plat，acceptsDrops:false）', (
    tester,
  ) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    // 按住 60ms 后移动 30px。修复前：plat 的 ImmediateMultiDrag 在超过触控
    // slop 的那一刻接管 —— `childWhenDragging` 把 chip 换成空盒、chip 从条上
    // 消失，长按菜单根本不出现（用户说的「稍微一动就变成拖拽」）。vendored
    // plat 在 acceptsDrops:false 的组里不再包 Draggable（vendor/plat/VENDORED.md），
    // 拖拽不该再起：chip 必须原地不动地留在条上。
    await _touchSwipe(
      tester,
      find.text('排行').first,
      hold: const Duration(milliseconds: 60),
      path: const [Offset(10, 10), Offset(10, 10), Offset(10, 10)],
    );

    expect(find.text(t.plat.closeTab), findsNothing,
        reason: '漂移超 slop 会取消长按，菜单不该弹');
    expect(find.text('排行'), findsWidgets,
        reason: '拖拽不许起手 —— 起手会把 chip 换成 childWhenDragging 空盒');
    expect(_tabAlive(tabs, '排行'), isTrue, reason: '漂移不关标签 —— 关闭只能靠点 × 或菜单');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });
}
