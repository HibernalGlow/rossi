import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';

/// 发现页标签（plat 的 `PlatTabGroup` 薄封装）的判据。
///
/// 这一层刻意**不碰** `DiscoverPage`：那一页要插件注册表、ObjectBox、Rust 运行时，
/// 本机起不来。真正会错的是这几件事——序号、当前项、首页关不掉、朝向改得动，
/// 全都不需要画界面就能验。
DiscoverTabs _tabs() => DiscoverTabs(
  side: DiscoverTabBarSide.top,
  home: DiscoverLeafSpec(
    label: '发现',
    source: '',
    pluginName: '',
    iconUrl: '',
    icon: Icons.explore,
    content: (context) => const SizedBox.shrink(),
  ),
);

/// 每条标签的功能名（序号算在内），按轨上的次序读出来。
List<String> _labels(DiscoverTabs tabs) => [
  for (final tab in tabs.tabs)
    if (tab.child case final LeafSnapshot leaf)
      DiscoverTabs.specOfLeaf(leaf)?.label ?? '',
];

void main() {
  group('开标签', () {
    test('不限制重复：同一个插件点两次「搜索」得到两条标签', () {
      final tabs = _tabs();
      tabs.open(label: '搜索', source: 'p1', content: _content);
      tabs.open(label: '搜索', source: 'p1', content: _content);

      expect(_labels(tabs), ['发现', '搜索', '搜索 2']);
      tabs.dispose();
    });

    test('不同插件的同名功能各是各的，都不带序号', () {
      final tabs = _tabs();
      tabs.open(label: '排行', source: 'p1', content: _content);
      tabs.open(label: '排行', source: 'p2', content: _content);

      expect(_labels(tabs), ['发现', '排行', '排行']);
      tabs.dispose();
    });

    test('新开的一条总是当前那条，onHome 随之翻 false', () {
      final tabs = _tabs();
      expect(tabs.onHome, isTrue);
      tabs.open(label: '排行', source: 'p1', content: _content);
      expect(tabs.onHome, isFalse);
      tabs.dispose();
    });

    test('空标题不会画成一条空白标签', () {
      final tabs = _tabs();
      tabs.open(label: '   ', source: 'p1', content: _content);
      expect(_labels(tabs).last, isNotEmpty);
      tabs.dispose();
    });
  });

  group('关闭与切换', () {
    test('首页那条关不掉（locked）', () {
      final tabs = _tabs();
      tabs.open(label: '排行', source: 'p1', content: _content);
      tabs.close(DiscoverTabs.homeId);
      expect(_labels(tabs), ['发现', '排行']);
      tabs.dispose();
    });

    test('关掉当前那条之后回到还在的标签上', () {
      final tabs = _tabs();
      tabs.open(label: '排行', source: 'p1', content: _content);
      tabs.open(label: '最新', source: 'p1', content: _content);
      final current = tabs.controller.activeTabId(DiscoverTabs.groupId);
      tabs.close(current!);
      expect(tabs.controller.activeTabId(DiscoverTabs.groupId), isNotNull);
      expect(_labels(tabs).length, 2);
      tabs.dispose();
    });

    test('goHome 切回首页', () {
      final tabs = _tabs();
      tabs.open(label: '排行', source: 'p1', content: _content);
      tabs.goHome();
      expect(tabs.onHome, isTrue);
      tabs.dispose();
    });
  });

  group('朝向', () {
    test('setSide 改的是树上那一组，读回来就是新值', () {
      final tabs = _tabs();
      expect(_side(tabs), TabBarSide.top);
      tabs.setSide(DiscoverTabBarSide.left);
      expect(_side(tabs), TabBarSide.left);
      tabs.dispose();
    });

    test('三档设置各自映射到 plat 的那一侧', () {
      expect(DiscoverTabs.platSideOf(DiscoverTabBarSide.top), TabBarSide.top);
      expect(DiscoverTabs.platSideOf(DiscoverTabBarSide.left), TabBarSide.left);
      expect(
        DiscoverTabs.platSideOf(DiscoverTabBarSide.right),
        TabBarSide.right,
      );
    });
  });

  group('标签标题', () {
    test('缩写开关关掉就只剩功能名', () {
      final spec = DiscoverLeafSpec(
        label: '排行',
        source: 'p1',
        pluginName: '绅士漫画',
        iconUrl: '',
        content: _content,
      );
      expect(DiscoverTabs.labelOf(spec, showPluginShort: true), '绅士 · 排行');
      expect(DiscoverTabs.labelOf(spec, showPluginShort: false), '排行');
    });
  });
}

TabBarSide _side(DiscoverTabs tabs) =>
    (tabs.controller.snapshot(DiscoverTabs.groupId) as TabGroupSnapshot).side;

Widget _content(BuildContext context) => const SizedBox.shrink();
