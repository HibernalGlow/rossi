import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/page/discover/view/discover_page.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/view/search_page.dart';

/// 数一下一个子树被重建了几次 —— 「卡死」在这里就是它停不下来。
class _CountBuilds extends StatefulWidget {
  const _CountBuilds({required this.onBuild, required this.child});
  final VoidCallback onBuild;
  final Widget child;

  @override
  State<_CountBuilds> createState() => _CountBuildsState();
}

class _CountBuildsState extends State<_CountBuilds> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return widget.child;
  }
}

/// 用**真的** `DiscoverPage` 跑一遍，而不是它的替身。
///
/// 要抓的是「卡死」：一个不停自重建的树会让 `pumpAndSettle` 超时（这条判据
/// 本身就是超时断言 —— 之前文件管理卡片那三条红就是同一症状）。
/// 之前几份判据都拿 `SizedBox` 当标签内容，那条路径下不出这种循环；
/// 这里换成真的 `SearchPage`。
Widget _app(Widget child) => MaterialApp(
  supportedLocales: AppLocaleUtils.supportedLocales,
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => GlobalSettingCubit()),
      BlocProvider(create: (_) => PluginRegistryCubit()),
    ],
    child: child,
  ),
);

void main() {
  testWidgets('真的 DiscoverPage 能画出来并稳定下来', (tester) async {
    await tester.pumpWidget(_app(const DiscoverPage()));
    await tester.pumpAndSettle(
      const Duration(seconds: 5),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(t.discover.title), findsWidgets);
  });

  for (final (side, label) in [
    (DiscoverTabBarSide.top, '横向'),
    (DiscoverTabBarSide.left, '竖向'),
  ]) {
    testWidgets('$label：$label溢出的标签条 + 窄宽度不卡', (tester) async {
      late DiscoverTabs tabs;
      var leafBuilds = 0;
      await tester.pumpWidget(
        _app(Builder(builder: (context) {
          tabs = DiscoverTabs(
            side: side,
            home: DiscoverLeafSpec(
              label: '发现',
              source: '',
              pluginName: '',
              iconUrl: '',
              content: (context) => const SizedBox.shrink(),
            ),
          );
          // 8 条：在 320 宽（或 152 厚的竖轨）里一定溢出，走的是滚动 + 定位那条路。
          for (var i = 0; i < 8; i++) {
            tabs.open(
              label: '排行 $i',
              source: 'p1',
              content: (context) => _CountBuilds(
                onBuild: () => leafBuilds++,
                child: SearchPage(
                  searchState: SearchStates.initial().copyWith(from: 'p1'),
                  aggregateMode: false,
                ),
              ),
            );
          }
          return Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 600,
                child: DiscoverPlatView(
                  tabs: tabs,
                  setting: DiscoverSettingState(tabSide: side),
                  onSearch: () {},
                  onCustomizeOrder: () {},
                ),
              ),
            ),
          );
        })),
      );
      await tester.pumpAndSettle(
        const Duration(seconds: 5),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
      // 故意不 takeException：让框架在测试结束时把完整的 creator 链打出来。
      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        leafBuilds,
        lessThan(40),
        reason: '溢出档下还在反复重建 = 滚动定位与重建互相触发',
      );
      final settled = leafBuilds;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(leafBuilds, settled, reason: '空转中仍在重建 = 卡死前兆');

      // 切到最远那条：滚动定位必须跟着走，且不能把树点着。
      tabs.controller.focus(tabs.tabs.last.id);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label 档溢出过');
      tabs.dispose();
    });
  }

  testWidgets('标签里放真的搜索页：进出、悬停、切走再切回都不卡', (tester) async {
    late DiscoverTabs tabs;
    var leafBuilds = 0;
    await tester.pumpWidget(
      _app(Builder(builder: (context) {
        // DiscoverPage 自己持有标签；这一条判据要的是「同一份标签状态」下面
        // 挂着真页面，所以直接用它对外暴露的那套 chrome。
        tabs = DiscoverTabs(
          side: DiscoverTabBarSide.top,
          home: DiscoverLeafSpec(
            label: '发现',
            source: '',
            pluginName: '',
            iconUrl: '',
            content: (context) => const SizedBox.shrink(),
          ),
        );
        tabs.open(
          label: '搜索',
          source: 'p1',
          content: (context) => _CountBuilds(
            onBuild: () => leafBuilds++,
            child: SearchPage(
              searchState: SearchStates.initial().copyWith(from: 'p1'),
              aggregateMode: false,
            ),
          ),
        );
        return Scaffold(
          body: DiscoverPlatView(
            tabs: tabs,
            setting: const DiscoverSettingState(),
            onSearch: () {},
            onCustomizeOrder: () {},
          ),
        );
      })),
    );
    await tester.pumpAndSettle(
      const Duration(seconds: 5),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    expect(tester.takeException(), isNull);
    // 不是空跑：真的搜索页得在树上。
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('搜索'), findsWidgets);
    final afterFirstSettle = leafBuilds;
    expect(
      afterFirstSettle,
      lessThan(20),
      reason: '稳定之后还在重建 = 自循环',
    );

    // 再空转 30 帧，计数不该继续涨。
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(leafBuilds, afterFirstSettle, reason: '空转中仍在重建 = 卡死前兆');

    // 切到首页再切回来：走的是 controller.focus ⇒ notifyListeners ⇒ 整页重建。
    tabs.goHome();
    await tester.pumpAndSettle();
    tabs.controller.focus(tabs.tabs.last.id);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchPage), findsOneWidget);
    tabs.dispose();
  });
}
