import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_browser.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_scroll_spy.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/appearance_setting_page.dart';

class _MemorySettings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

void main() {
  tearDown(() => settingSectionJumpRequest.value = null);

  Future<void> viewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget browser(List<String> opened, {double textScale = 1}) => MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: SettingPageShell(
      title: '设置',
      maxWidth: 1440,
      collapsingTitle: false,
      child: SettingBrowser(
        summary: '中文 · 跟随系统',
        groups: [
          SettingDestinationGroup(
            title: '个性化',
            entries: [
              SettingDestination(
                id: 'appearance',
                title: '外观',
                subtitle: '明暗主题',
                icon: AppGlyphs.palette,
                onOpen: () => opened.add('appearance'),
                detailBuilder: (_) => const SettingPageShell(
                  title: '外观详情',
                  child: TextField(key: ValueKey('detail-input')),
                ),
              ),
              SettingDestination(
                id: 'files',
                title: '文件',
                subtitle: '目录与排序',
                icon: AppGlyphs.folder,
                onOpen: () => opened.add('files'),
                detailBuilder: (_) => const SettingPageShell(
                  title: '文件详情',
                  child: Text('file-options'),
                ),
              ),
              SettingDestination(
                id: 'bindings',
                title: '绑定',
                subtitle: '编辑与保存',
                icon: AppGlyphs.gamepad,
                onOpen: () => opened.add('bindings'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  testWidgets('手机入口执行原打开回调，没有隐式详情页', (tester) async {
    final opened = <String>[];
    await viewport(tester, const Size(390, 844));
    await tester.pumpWidget(browser(opened));
    await tester.pumpAndSettle();
    expect(find.byType(SettingDetailScope), findsNothing);
    final row = find.text('外观');
    expect(
      tester
          .getSize(find.ancestor(of: row, matching: find.byType(M3EListItem)))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(opened, ['appearance']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏切分类更新右侧，有保存保护的入口执行原回调', (tester) async {
    final opened = <String>[];
    await viewport(tester, const Size(1280, 900));
    await tester.pumpWidget(browser(opened));
    await tester.pumpAndSettle();
    expect(find.text('外观详情'), findsOneWidget);
    expect(
      tester
          .widget<AppBar>(
            find.ancestor(of: find.text('外观详情'), matching: find.byType(AppBar)),
          )
          .automaticallyImplyLeading,
      isFalse,
    );
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('文件详情'), findsOneWidget);
    expect(find.text('外观详情'), findsNothing);
    expect(opened, isEmpty);
    await tester.tap(find.text('绑定'));
    await tester.pumpAndSettle();
    expect(opened, ['bindings']);
    expect(find.text('文件详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类搜索匹配说明、空态可恢复，并保留详情编辑内容', (tester) async {
    await viewport(tester, const Size(1280, 900));
    await tester.pumpWidget(browser([]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('detail-input')), 'kept');
    final search = find.byKey(const ValueKey('settings-category-search'));
    await tester.enterText(search, '排序');
    await tester.pumpAndSettle();
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('外观'), findsNothing);
    expect(find.text('kept'), findsOneWidget);
    await tester.enterText(search, '不存在');
    await tester.pumpAndSettle();
    expect(find.text(t.settings.noMatchingCategories), findsOneWidget);
    await tester.tap(find.byTooltip(t.common.clear));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('kept'), findsOneWidget);
  });

  testWidgets('键盘可以进入分类并切换右侧详情', (tester) async {
    await viewport(tester, const Size(1280, 900));
    await tester.pumpWidget(browser([]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-search')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('文件详情'), findsOneWidget);
  });

  testWidgets('按面板实际宽度收回单栏，大字号窄屏无溢出', (tester) async {
    await viewport(tester, const Size(1280, 900));
    await tester.pumpWidget(browser([]));
    await tester.pumpAndSettle();
    expect(find.byType(SettingDetailScope), findsOneWidget);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpWidget(browser([], textScale: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SettingDetailScope), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实外观页的主题预览写回现有 GlobalSettingCubit', (tester) async {
    await viewport(tester, const Size(390, 844));
    final cubit = _MemorySettings();
    final semantics = tester.ensureSemantics();

    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AppearanceSettingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.darkMode));
    await tester.pumpAndSettle();
    expect(cubit.state.themeMode, ThemeMode.dark);

    expect(find.bySemanticsLabel(RegExp(t.common.darkMode)), findsWidgets);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类背景容纳图标、箭头和长说明，大字号时随内容增高', (tester) async {
    await viewport(tester, const Size(1440, 1100));
    const subtitle = '试验性功能，需要下载模型权重与配置翻译端点';
    Widget subject(double scale) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SettingBrowser(
          summary: '',
          groups: [
            SettingDestinationGroup(
              title: '阅读与画面',
              entries: [
                SettingDestination(
                  id: 'translate',
                  title: '漫画翻译（成品页）',
                  subtitle: subtitle,
                  icon: AppGlyphs.palette,
                  onOpen: () {},
                  detailBuilder: (_) => const SizedBox(),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    double checkInsets() {
      final row = find.byType(M3EListItem);
      final bounds = tester.getRect(row);
      final badge = tester.getRect(find.byType(SettingIconBadge));
      final arrow = tester.getRect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GlyphIcon && widget.glyph == AppGlyphs.chevronForward,
          ),
        ),
      );
      final text = tester.getRect(find.text(subtitle));
      expect(badge.left - bounds.left, greaterThanOrEqualTo(16));
      expect(bounds.right - arrow.right, greaterThanOrEqualTo(16));
      expect(badge.top - bounds.top, greaterThanOrEqualTo(10));
      expect(bounds.bottom - badge.bottom, greaterThanOrEqualTo(10));
      expect(text.left, greaterThan(badge.right));
      expect(text.right, lessThan(arrow.left));
      expect(text.top - bounds.top, greaterThanOrEqualTo(10));
      expect(bounds.bottom - text.bottom, greaterThanOrEqualTo(10));
      expect(tester.takeException(), isNull);
      return bounds.height;
    }

    await tester.pumpWidget(subject(1));
    await tester.pumpAndSettle();
    final normalHeight = checkInsets();
    await tester.pumpWidget(subject(2));
    await tester.pumpAndSettle();
    expect(checkInsets(), greaterThan(normalHeight));
  });

  testWidgets('可折叠侧栏子树 + Scroll Spy 双向联动 + 搜索直达后恢复展开状态', (tester) async {
    await viewport(tester, const Size(1280, 800));
    Widget multiSectionDetail() => SettingPageShell(
      title: '外观设置详情',
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingGroup(
            sectionId: 'appearance.theme',
            title: '主题模式',
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(height: 80, child: ListTile(title: Text('主题项 $i'))),
            ],
          ),
          SettingGroup(
            sectionId: 'appearance.language',
            title: '语言与字体',
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(height: 80, child: ListTile(title: Text('语言项 $i'))),
            ],
          ),
          SettingGroup(
            sectionId: 'appearance.navigation',
            title: '导航栏布局',
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(height: 80, child: ListTile(title: Text('导航项 $i'))),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingBrowser(
            summary: '中文 · 跟随系统',
            groups: [
              SettingDestinationGroup(
                title: '外观与反馈',
                entries: [
                  SettingDestination(
                    id: 'appearance',
                    title: '外观与显示',
                    subtitle: '主题与语言',
                    icon: AppGlyphs.palette,
                    onOpen: () {},
                    detailBuilder: (_) => multiSectionDetail(),
                    sections: const [
                      SettingSectionSpec(
                        id: 'appearance.theme',
                        title: '主题模式',
                        keywords: ['AMOLED', '纯黑'],
                      ),
                      SettingSectionSpec(
                        id: 'appearance.language',
                        title: '语言与字体',
                        keywords: ['霞鹜文楷', '字号'],
                      ),
                      SettingSectionSpec(
                        id: 'appearance.navigation',
                        title: '导航栏布局',
                        keywords: ['侧边栏', '底栏'],
                      ),
                    ],
                  ),
                ],
              ),
              SettingDestinationGroup(
                title: '书库与文件',
                entries: [
                  SettingDestination(
                    id: 'files',
                    title: '文件管理器',
                    subtitle: '主页与视图',
                    icon: AppGlyphs.folder,
                    onOpen: () {},
                    detailBuilder: (_) => const SettingPageShell(
                      title: '文件管理器详情',
                      child: SizedBox(),
                    ),
                    sections: const [
                      SettingSectionSpec(
                        id: 'files.home',
                        title: '主页路径',
                        keywords: ['启动目录'],
                      ),
                      SettingSectionSpec(
                        id: 'files.tabs',
                        title: '标签页恢复',
                        keywords: ['历史会话'],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 默认选中项「外观与显示」自动展开子树，且未选中的「文件管理器」子树默认收起
    expect(
      find.byKey(const ValueKey('setting-subtree:appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setting-subtree:files')), findsNothing);

    // 2. 点击侧栏子树中的「导航栏布局」，右侧长设置页自动平滑滚到该分组
    await tester.tap(
      find.byKey(
        const ValueKey('setting-subtree-node:appearance:appearance.navigation'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('导航项 0'), findsOneWidget);

    // 3. 搜索子项深层关键词「历史会话」：自动展开未展开的「文件管理器」祖先子树并显示关键词徽标
    final search = find.byKey(const ValueKey('settings-category-search'));
    await tester.enterText(search, '历史会话');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setting-subtree:files')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setting-subtree-node:files:files.tabs')),
      findsOneWidget,
    );
    expect(find.text('历史会话'), findsWidgets);

    // 4. 清空搜索后，自动恢复搜索前的展开状态（「外观与显示」展开，「文件管理器」收起）
    await tester.tap(find.byTooltip(t.common.clear));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('setting-subtree:appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setting-subtree:files')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板端（Medium 768px）响应式双栏与移动端长页吸顶目录胶囊', (tester) async {
    // 平板端宽度（768x1024）下启用紧凑双栏主从视图
    await viewport(tester, const Size(768, 1024));
    await tester.pumpWidget(browser([]));
    await tester.pumpAndSettle();
    expect(find.byType(SettingDetailScope), findsOneWidget);

    // 移动端独立进入多分组长设置页时，顶部常驻吸顶可展开目录胶囊（Sticky Outline Pill）
    await viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: SettingPageShell(
          title: '阅读设置',
          child: ListView(
            padding: kSettingPagePadding,
            children: [
              SettingGroup(
                sectionId: 'sec.a',
                title: '翻页与方向',
                children: [
                  for (var i = 0; i < 6; i++)
                    SizedBox(height: 80, child: ListTile(title: Text('A-$i'))),
                ],
              ),
              SettingGroup(
                sectionId: 'sec.b',
                title: '画面与滤镜',
                children: [
                  for (var i = 0; i < 6; i++)
                    SizedBox(height: 80, child: ListTile(title: Text('B-$i'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pill = find.byKey(const ValueKey('setting-sticky-outline-pill'));
    expect(pill, findsOneWidget);
    expect(find.textContaining('翻页与方向'), findsWidgets);

    // 点击吸顶目录胶囊展开目录菜单，点击「画面与滤镜」跳转到目标分组
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('setting-sticky-outline-menu')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('outline-item:sec.b')));
    await tester.pumpAndSettle();
    expect(find.text('B-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
