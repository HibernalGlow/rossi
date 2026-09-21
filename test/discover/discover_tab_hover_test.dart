import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';

/// 复现「发现页标签条把界面卡死」的判据。
///
/// 症状是日志里每帧刷 `MouseTracker` 的 `!_debugDuringDeviceUpdate`。那条断言是
/// 次生的：`_deviceUpdatePhase` 只在 `task()` 正常返回后才复位标志，所以**任何**
/// 在悬停回调里抛的异常都会让标志永久卡在 true，之后每帧都撞、界面不再响应。
/// 因此这里要找的是「在指针移动的过程中抛的第一异常」。
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

Future<void> _pump(WidgetTester tester, DiscoverTabs tabs) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: Scaffold(
          body: DiscoverPlatView(
            tabs: tabs,
            setting: const DiscoverSettingState(),
            onSearch: () {},
            onCustomizeOrder: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 一只真实鼠标：进 → 停到 tooltip 弹出 → 出，全程逐帧推进。
Future<void> _sweep(
  WidgetTester tester,
  List<String> targets, {
  required Duration dwell,
}) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  for (final target in targets) {
    await mouse.moveTo(tester.getCenter(find.text(target).first));
    await tester.pump();
    await tester.pump(dwell);
  }
  await mouse.moveTo(const Offset(4, 400));
  await tester.pump();
  await tester.pump(dwell);
  await mouse.removePointer();
  await tester.pump();
}

void main() {
  testWidgets('鼠标扫过标签：tooltip 弹出又摘掉，不留下任何异常', (tester) async {
    final tabs = _tabs();
    for (final label in ['排行', '最新']) {
      tabs.open(
        label: label,
        source: 'p1',
        content: (context) => const SizedBox(width: 40, height: 40),
      );
    }
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    // 1.6s 比 Tooltip 默认的 1.5s 显示延时长，确保真的弹出过。
    await _sweep(tester, ['排行', '最新'], dwell: const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.byType(Tooltip), findsWidgets);
    tabs.dispose();
  });

  testWidgets('反复扫过（进出多轮）之后指针仍然工作', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '收藏',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);

    for (var round = 0; round < 3; round++) {
      await _sweep(tester, ['收藏'], dwell: const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: '第 $round 轮进出之后');
    }
    tabs.dispose();
  });
}
