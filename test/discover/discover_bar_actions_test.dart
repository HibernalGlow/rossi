// 发现页右上角那一组动作：必须走全应用统一的那一份
// （`ActionGroup` + `ActionIconButton` + `ElasticButton`），两种朝向都塞得下。
//
// 2026-10-11 用户口径：「发现界面右上角为什么你不统一呢 —— 就是和其他按钮一样，
// 也换成 GLYPH 图标，以及加入拖动动效」。
//
// 在此之前那一组是**裸 `IconButton`**（32 见方、`visualDensity.compact`、无按压
// 形变）加一颗 **M2 `PopupMenuButton`** —— 于是它既没有别的工具条那套
// 「按住鼓一下、按住拖跟着手指走」，尺寸口径也与它们各漂一点。
//
// 为什么单开一个文件而不是加进 `discover_plat_view_test.dart`：那边是别人正在
// 改的文件（并发写入方会覆盖未提交的编辑），另起一份更安全。

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/icons/icons.dart';

/// 首页那一条（locked），于是「自定义插件顺序」那颗也在 —— 三颗齐。
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

/// 只做内存写入的设置 cubit：生产那份 `updateDiscoverSetting` 会落 ObjectBox，
/// 而本机测试起不来那套原生库。
class _MemSettingCubit extends GlobalSettingCubit {
  @override
  void updateDiscoverSetting(
    DiscoverSettingState Function(DiscoverSettingState current) updates,
  ) {
    emit(state.copyWith(discoverSetting: updates(state.discoverSetting)));
  }
}

Future<_MemSettingCubit> _pump(
  WidgetTester tester,
  DiscoverTabs tabs, {
  Size surface = const Size(900, 600),
  DiscoverTabBarSide preferred = DiscoverTabBarSide.top,
}) async {
  final cubit = _MemSettingCubit();
  if (preferred != DiscoverTabBarSide.top) {
    cubit.updateDiscoverSetting(
      (current) => current.copyWith(
        tabSide: preferred,
        // 偏好与树要一致：只设树的话窄页面钳制会把树推回横向，界面停在
        // Offstage 里，那一组根本不在可命中树里。
        tabRailWidth: DiscoverPlatView.railMinWidth,
      ),
    );
    tabs.setSide(preferred);
  }
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider<GlobalSettingCubit>(
        // 类型参数必须写 `GlobalSettingCubit`：`_DisplayOptionsButton` 读的是它，
        // 传子类型只会让 Provider 找不到。
        create: (_) => cubit,
        child: Scaffold(
          body: SizedBox(
            width: surface.width,
            height: surface.height,
            child: DiscoverPlatView(
              tabs: tabs,
              setting: cubit.state.discoverSetting,
              onSearch: () {},
              onCustomizeOrder: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  testWidgets('那一组就是全应用统一的那份：药丸槽 + 每颗都套 ElasticButton', (tester) async {
    final tabs = _tabs();
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    final group = find.byType(ActionGroup);
    expect(group, findsOneWidget, reason: '那一组必须走统一的药丸槽');

    // 图标必须是**自绘 glyph**（`GlyphIcon`），不是 Material `Icon` ——
    // 这正是用户说的「也换成 GLYPH 图标」。
    // （「自定义顺序」那颗只在首页那一档摆出来，所以这里按它自己的条件写。）
    for (final glyph in [AppGlyphs.search, AppGlyphs.sliders]) {
      expect(
        find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == glyph),
        findsOneWidget,
      );
    }
    expect(find.byType(Icon), findsNothing, reason: '这一组里不该再混 Material 图标');

    // 每一颗都要套 `ElasticButton` ⇒ 才有「按住鼓一下 + 按住拖跟着手指走」。
    // 这一条就是用户说的「动效没迁过来」的判据。
    //
    // 用**相对数量**而不是写死 3：组里那颗菜单触发键不是 `ActionIconButton`
    // （它是 `FluentPopupMenuButton`），而「自定义顺序」按 `onHome` 条件渲染。
    final buttons = find.byType(ActionIconButton).evaluate().length;
    final elastic = find
        .descendant(of: group, matching: find.byType(ElasticButton))
        .evaluate()
        .length;
    expect(buttons, greaterThanOrEqualTo(2));
    expect(
      elastic,
      buttons + 1,
      reason: '每颗动作键加那颗菜单触发键，一个都不能少',
    );

    // M2 的菜单不该再出现：本仓的弹出菜单**只有一份动画**（淡入 + 从锚点缩放）。
    expect(
      find.byType(PopupMenuButton<Object>),
      findsNothing,
      reason: '「标签显示」那一颗换成了 FluentPopupMenuButton',
    );
    tabs.dispose();
  });

  testWidgets('横向档：那一组塞得进发现页顶栏（48 高）', (tester) async {
    final tabs = _tabs();
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    final group = tester.getSize(find.byType(ActionGroup));
    expect(group.height, lessThanOrEqualTo(48), reason: '顶栏只有 48 高');
    // 反面对照：这一组**确实**是那一组，不是别处飘来的空壳。
    expect(group.width, greaterThan(0));
    tabs.dispose();
  });

  testWidgets('竖向档：那一组塞得进最窄的轨（68 宽）', (tester) async {
    final tabs = _tabs();
    // 900 宽才转得成竖轨：`_effectiveSide` 在「轨厚 + 内容下限」放不下时会钳回横向。
    await _pump(
      tester,
      tabs,
      preferred: DiscoverTabBarSide.left,
    );
    expect(tester.takeException(), isNull, reason: '竖轨那一档溢出了');

    final group = tester.getSize(find.byType(ActionGroup));
    // 轨最窄 68，`RossiPlatTheme.railPadding` 左右各 6 ⇒ 动作组最多 56 宽。
    expect(group.width, lessThanOrEqualTo(56), reason: '轨最窄那一档只有 56 可用');
    tabs.dispose();
  });

  testWidgets('两种朝向都切一遍：不抛，且每一档那一组都在', (tester) async {
    final tabs = _tabs();
    await _pump(tester, tabs);
    expect(find.byType(ActionGroup), findsOneWidget);

    for (final side in DiscoverTabBarSide.values) {
      tabs.setSide(side);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '切到「${side.label}」之后抛了');
      expect(
        find.byType(ActionGroup),
        findsOneWidget,
        reason: '「${side.label}」这一档那一组不见了',
      );
      // 动作清单不随朝向变（只换排布）：搜索与那一颗菜单触发键每一档都在。
      expect(
        find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == AppGlyphs.search),
        findsOneWidget,
        reason: '「${side.label}」这一档少了搜索键',
      );
      expect(
        find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == AppGlyphs.sliders),
        findsOneWidget,
        reason: '「${side.label}」这一档少了菜单触发键',
      );
    }
    tabs.dispose();
  });
}
