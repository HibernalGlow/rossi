// 只用 material_ui：与主应用同一套 MaterialApp / Scaffold / Icons。
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerDownEvent, PointerUpEvent;
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
/// - **长按中漂移**：vendored plat 把触摸档拖拽改成「按满 kLongPressTimeout
///   才起手且不因移动放弃」（vendor/plat/VENDORED.md），时限内的短漂移
///   既不起拖拽也不弹菜单；按满时限 + 移动 = 真拖拽（分屏 / 换序可用）；
/// - **双击关闭**（默认开）与**关掉开关后双击不动作**（旁路观察，
///   `RossiPlatTabMenuRegion` 的 Listener，不给单击加延迟）。
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
  DiscoverSettingState setting = const DiscoverSettingState(),
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
                setting: setting,
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

/// 双击：两记 down→up，间隔 100ms（落在 kDoubleTapMinTime 40 与
/// kDoubleTapTimeout 300 的窗口里）。
///
/// **不用 `tester.tap`**：TestPointer 的事件时间戳恒为 0（测试脚手架不随
/// `pump` 推进），旁路双击观察的「间隔 ≥ kDoubleTapMinTime」会永远不成立 ——
/// 实机事件带真实时间戳，无此问题。这里显式给时间戳。
Future<void> _doubleTap(WidgetTester tester, Finder target) async {
  final center = tester.getCenter(target);
  await tester.sendEventToBinding(
    PointerDownEvent(position: center),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    PointerUpEvent(
      position: center,
      timeStamp: const Duration(milliseconds: 60),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.sendEventToBinding(
    PointerDownEvent(
      position: center,
      timeStamp: const Duration(milliseconds: 160),
    ),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    PointerUpEvent(
      position: center,
      timeStamp: const Duration(milliseconds: 220),
    ),
  );
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

  testWidgets('长按中漂移（时限内）：不起拖拽也不弹菜单', (
    tester,
  ) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    // 按住 60ms 后移动 30px。修复前：plat 的 ImmediateMultiDrag 在超过触控
    // slop 的那一刻接管 —— `childWhenDragging` 把 chip 换成空盒、chip 从条上
    // 消失，长按菜单根本不出现（用户说的「稍微一动就变成拖拽」）。vendored
    // plat 把触摸档拖拽改成「按满 kLongPressTimeout 才起手」（VENDORED.md），
    // 时限内的短漂移两样都不该发生：chip 必须原地不动地留在条上。
    // 真拖拽（按满时限 + 移动）另由分屏判据覆盖。
    await _touchSwipe(
      tester,
      find.text('排行').first,
      hold: const Duration(milliseconds: 60),
      path: const [Offset(10, 10), Offset(10, 10), Offset(10, 10)],
    );

    expect(find.text(t.plat.closeTab), findsNothing,
        reason: '漂移超 slop 会取消长按，菜单不该弹');
    expect(find.text('排行'), findsWidgets,
        reason: '时限内不许起拖拽 —— 起手会把 chip 换成 childWhenDragging 空盒');
    expect(_tabAlive(tabs, '排行'), isTrue, reason: '漂移不关标签 —— 关闭只能靠点 × 或菜单');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('双击标签（默认开）：第二次抬起后关闭', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(tester, tabs);

    // 两记 down→up 间隔 100ms。旁路观察看的是 down→up 对，内层的单击照常
    // 立即生效 —— 所以这同时也是「单击零延迟」的回归。
    await _doubleTap(tester, find.text('排行').first);

    expect(_tabAlive(tabs, '排行'), isFalse, reason: '双击必须关掉这条标签');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('双击关闭开关关掉后：双击不动作，标签活着', (tester) async {
    final tabs = _tabs();
    await _openTab(tabs, '排行');
    await _pump(
      tester,
      tabs,
      setting: const DiscoverSettingState(tabDoubleClickClose: false),
    );

    await _doubleTap(tester, find.text('排行').first);

    expect(_tabAlive(tabs, '排行'), isTrue, reason: '开关关掉后双击不许关标签');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });
}
