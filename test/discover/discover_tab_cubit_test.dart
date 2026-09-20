import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/discover/cubit/discover_tab_cubit.dart';

/// 发现页标签条的状态判据。
///
/// 这一层刻意**不碰** `DiscoverPage`：那一页要插件注册表、ObjectBox、Rust 运行时，
/// 本机起不来。标签条真正会错的是这几件事——序号、当前项、关掉之后切到哪儿、
/// 首页关不掉——全都不需要画界面就能验。
DiscoverTab _tab(
  String id, {
  String source = '',
  String label = '排行',
  bool closable = true,
}) {
  return DiscoverTab(
    id: id,
    label: label,
    source: source,
    pluginName: '',
    iconUrl: '',
    closable: closable,
    content: (context) => const SizedBox.shrink(),
  );
}

/// 首页那条与生产一致：不可关闭。
DiscoverTabCubit _cubit() =>
    DiscoverTabCubit(homeTab: _tab('home', label: '发现', closable: false));

void main() {
  group('开标签', () {
    test('不限制重复：同一个插件点两次「搜索」得到两条标签', () {
      final cubit = _cubit();
      cubit.open(label: '搜索', source: 'p1', content: _content);
      cubit.open(label: '搜索', source: 'p1', content: _content);

      final labels = cubit.state.tabs.map((tab) => tab.label).toList();
      expect(labels, ['发现', '搜索', '搜索 2']);
    });

    test('不同插件的同名功能各是各的，都不带序号', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      cubit.open(label: '排行', source: 'p2', content: _content);

      expect(cubit.state.tabs.map((tab) => tab.label), ['发现', '排行', '排行']);
    });

    test('序号跳过已被占用的号', () {
      final cubit = _cubit();
      cubit.open(label: '搜索', source: 'p1', content: _content);
      cubit.open(label: '搜索', source: 'p1', content: _content);
      cubit.open(label: '搜索', source: 'p1', content: _content);
      expect(cubit.state.tabs.last.label, '搜索 3');
    });

    test('新开的一条总是当前那条', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      expect(cubit.state.activeId, cubit.state.tabs.last.id);
      expect(cubit.state.activeIndex, 1);
    });

    test('空标题不会画成一条空白标签', () {
      final cubit = _cubit();
      cubit.open(label: '   ', source: 'p1', content: _content);
      expect(cubit.state.tabs.last.label, isNotEmpty);
    });
  });

  group('关闭', () {
    test('关当前那条 → 切到左邻', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      final first = cubit.state.tabs[1];
      cubit.open(label: '最新', source: 'p1', content: _content);
      final second = cubit.state.tabs[2];

      cubit.closeTab(second.id);
      expect(cubit.state.activeId, first.id);
      expect(cubit.state.tabs.map((tab) => tab.label), ['发现', '排行']);
    });

    test('关的不是当前那条 → 当前项不动', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      final keep = cubit.state.tabs[1];
      cubit.open(label: '最新', source: 'p1', content: _content);

      cubit.closeTab(keep.id);
      expect(cubit.state.activeId, cubit.state.tabs.last.id);
    });

    test('首页那条关不掉（它是「回到列表」的落点）', () {
      final cubit = _cubit();
      cubit.closeTab('home');
      expect(cubit.state.tabs.length, 1);
    });

    test('关掉最后一条非首页标签 → 标签条收起', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      expect(cubit.state.showsStrip, isTrue);
      cubit.closeTab(cubit.state.tabs.last.id);
      expect(cubit.state.showsStrip, isFalse);
    });
  });

  group('切换', () {
    test('activate 只认存在的 id', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      cubit.activate('不存在的');
      expect(cubit.state.activeId, cubit.state.tabs.last.id);
    });

    test('goHome 回到首页', () {
      final cubit = _cubit();
      cubit.open(label: '排行', source: 'p1', content: _content);
      cubit.activateHome();
      expect(cubit.state.activeId, 'home');
    });
  });
}

Widget _content(BuildContext context) => const SizedBox.shrink();
