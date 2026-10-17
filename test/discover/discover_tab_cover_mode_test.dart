import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/service/plugin_function_kind.dart';
import 'package:zephyr/page/discover/widgets/discover_cover_tab_chip.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';

void main() {
  group('DiscoverLeafSpec & Cover Mode Spec', () {
    test('常规漫画详情页能够正确标识，不属于特殊页面', () {
      final spec = DiscoverLeafSpec(
        label: '电锯人 第1话',
        source: 'jm',
        pluginName: '禁漫',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        comicId: '12345',
        isComicInfo: true,
        initialCover: const DiscoverCoverData(url: 'https://example.com/cover.jpg'),
      );

      expect(spec.isComicInfo, isTrue);
      expect(spec.isSpecialPage, isFalse);
      expect(spec.coverNotifier.value?.url, 'https://example.com/cover.jpg');
    });

    test('特殊页面（排行榜、最新、发现、搜索）能正确推断与赋予特殊图标', () {
      final homeSpec = DiscoverLeafSpec(
        label: '发现',
        source: '',
        pluginName: '',
        iconUrl: '',
        icon: AppGlyphs.compass,
        content: (_) => const SizedBox.shrink(),
      );
      expect(homeSpec.isSpecialPage, isTrue);
      expect(
        homeSpec.specialIcon(homeTitle: '发现', searchTitle: '搜索'),
        AppGlyphs.compass,
      );

      final rankSpec = DiscoverLeafSpec(
        label: '排行榜',
        source: 'bika',
        pluginName: '哔咔',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.ranking,
      );
      expect(rankSpec.isSpecialPage, isTrue);
      expect(
        rankSpec.specialIcon(homeTitle: '发现', searchTitle: '搜索'),
        AppGlyphs.trophy,
      );

      final latestSpec = DiscoverLeafSpec(
        label: '最新更新',
        source: 'bika',
        pluginName: '哔咔',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.latest,
      );
      expect(latestSpec.isSpecialPage, isTrue);
      expect(
        latestSpec.specialIcon(homeTitle: '发现', searchTitle: '搜索'),
        AppGlyphs.clock,
      );

      final searchSpec = DiscoverLeafSpec(
        label: '搜索 东方',
        source: 'jm',
        pluginName: '禁漫',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.search,
      );
      expect(searchSpec.isSpecialPage, isTrue);
      expect(
        searchSpec.specialIcon(homeTitle: '发现', searchTitle: '搜索'),
        AppGlyphs.search,
      );
    });

    test('动态第一张封面通知机制生效', () {
      final spec = DiscoverLeafSpec(
        label: '排行榜',
        source: 'bika',
        pluginName: '哔咔',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.ranking,
      );

      expect(spec.coverNotifier.value, isNull);

      var notifiedCount = 0;
      spec.coverNotifier.addListener(() {
        notifiedCount++;
      });

      spec.coverNotifier.value = const DiscoverCoverData(
        url: 'https://example.com/first_manga.jpg',
        path: '/cache/cover1.jpg',
        from: 'bika',
      );

      expect(notifiedCount, 1);
      expect(spec.coverNotifier.value?.url, 'https://example.com/first_manga.jpg');
      expect(spec.coverNotifier.value?.path, '/cache/cover1.jpg');
    });
  });

  group('DiscoverCoverTabChip Widget Tests', () {
    testWidgets('常规标签在垂直轨下以封面展示，信息层叠加在封面之上', (tester) async {
      final spec = DiscoverLeafSpec(
        label: '葬送的芙莉莲',
        source: 'p1',
        pluginName: '漫画插件',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        comicId: 'manga-999',
        isComicInfo: true,
        initialCover: const DiscoverCoverData(url: 'https://example.com/cover.jpg'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 132,
              height: 200,
              child: DiscoverCoverTabChip(
                leaf: spec,
                states: const {WidgetState.selected},
                side: TabBarSide.left,
                showPluginShort: true,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('葬送的芙莉莲'), findsOneWidget);
      expect(find.byType(DiscoverCoverTabChip), findsOneWidget);
    });

    testWidgets('特殊页面在垂直轨下展示特殊图标徽章', (tester) async {
      final rankSpec = DiscoverLeafSpec(
        label: '本周排行',
        source: 'p1',
        pluginName: '漫画插件',
        iconUrl: '',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.ranking,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 132,
              height: 200,
              child: DiscoverCoverTabChip(
                leaf: rankSpec,
                states: const {},
                side: TabBarSide.left,
                showPluginShort: true,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('本周排行'), findsOneWidget);
      expect(find.byType(DiscoverCoverTabChip), findsOneWidget);
    });

    testWidgets('发现首页在垂直轨下以普通紧凑图标呈现，不占书本大卡片高度', (tester) async {
      final homeSpec = DiscoverLeafSpec(
        label: '发现',
        source: '',
        pluginName: '',
        iconUrl: '',
        icon: AppGlyphs.compass,
        content: (_) => const SizedBox.shrink(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 132,
              height: 200,
              child: DiscoverCoverTabChip(
                leaf: homeSpec,
                states: const {WidgetState.selected},
                side: TabBarSide.left,
                showPluginShort: true,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('发现'), findsOneWidget);
      expect(find.byType(DiscoverCoverTabChip), findsOneWidget);

      // 验证包含指南针普通 icon
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GlyphIcon && widget.glyph == AppGlyphs.compass,
        ),
        findsOneWidget,
      );

      // 验证外层高度远小于常规封面卡片（仅 44dp，含 38dp 内容及上下 3dp 边距）
      final containerFinder = find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxHeight == 38,
      );
      expect(containerFinder, findsOneWidget);
      final size = tester.getSize(containerFinder);
      expect(size.height, 44);
    });
  });

  group('DiscoverPlatView 封面开关模式集成', () {
    testWidgets('开关打开后，PlatView 使用 DiscoverCoverTabChip 进行渲染', (tester) async {
      final tabs = DiscoverTabs(
        side: DiscoverTabBarSide.left,
        home: DiscoverLeafSpec(
          label: '发现',
          source: '',
          pluginName: '',
          iconUrl: '',
          icon: AppGlyphs.compass,
          content: (_) => const SizedBox.shrink(),
        ),
      );

      tabs.open(
        label: '排行榜',
        source: 'p1',
        content: (_) => const SizedBox.shrink(),
        functionKind: PluginFunctionKind.ranking,
      );

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: BlocProvider(
            create: (_) => GlobalSettingCubit(),
            child: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: DiscoverPlatView(
                  tabs: tabs,
                  setting: const DiscoverSettingState(
                    tabSide: DiscoverTabBarSide.left,
                    tabCoverMode: true,
                  ),
                  onSearch: () {},
                  onCustomizeOrder: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(DiscoverCoverTabChip), findsWidgets);

      tabs.dispose();
    });

    testWidgets('开关关闭时，默认退回标准 RossiPlatTabChip', (tester) async {
      final tabs = DiscoverTabs(
        side: DiscoverTabBarSide.left,
        home: DiscoverLeafSpec(
          label: '发现',
          source: '',
          pluginName: '',
          iconUrl: '',
          icon: AppGlyphs.compass,
          content: (_) => const SizedBox.shrink(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: BlocProvider(
            create: (_) => GlobalSettingCubit(),
            child: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: DiscoverPlatView(
                  tabs: tabs,
                  setting: const DiscoverSettingState(
                    tabSide: DiscoverTabBarSide.left,
                    tabCoverMode: false,
                  ),
                  onSearch: () {},
                  onCustomizeOrder: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(DiscoverCoverTabChip), findsNothing);

      tabs.dispose();
    });
  });
}
