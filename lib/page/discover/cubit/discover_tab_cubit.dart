import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/json/json_value.dart';

/// 发现页的一条**标签**。
///
/// 首页那条（插件列表）与点开的每一条共用同一个类型，差别只在 [closable]
/// 与 [source] 是否为空 —— 标签条因此不需要为首页写一套特殊分支。
@immutable
class DiscoverTab {
  const DiscoverTab({
    required this.id,
    required this.label,
    required this.source,
    required this.pluginName,
    required this.iconUrl,
    required this.content,
    this.closable = true,
    this.icon,
  });

  /// 稳定身份。内容换了就是另一条标签，不复用旧 id（否则 IndexedStack 里的
  /// State 会被错误地续上）。
  final String id;

  /// 功能名（「排行」「搜索」「设置」）或漫画标题。标签正文 = 插件缩写 · [label]。
  final String label;

  /// 插件 uuid；空串 = 首页这类没有插件来源的标签。
  final String source;

  final String pluginName;
  final String iconUrl;

  /// 没有插件来源（[source] 为空）时标签上画的那颗图标。
  ///
  /// 首页与「跨全部插件的聚合搜索」都属于这一类 —— 它们不属于任何一个插件，
  /// 硬套一个插件图标会撒谎，只留文字又在一片图标里没有落点。
  final IconData? icon;

  /// 标签内容。由 [DiscoverRouter] 的各分支填，与「谁在构建」解耦：
  /// 构建发生在标签条切到这一条的时候。
  final WidgetBuilder content;

  final bool closable;
}

@immutable
class DiscoverTabState {
  const DiscoverTabState({required this.tabs, required this.activeId});

  /// 首页恒在首位且不可关闭（它是「回到插件列表」那一下的落点）。
  final List<DiscoverTab> tabs;
  final String activeId;

  int get activeIndex {
    final index = tabs.indexWhere((tab) => tab.id == activeId);
    return index < 0 ? 0 : index;
  }

  DiscoverTab get active => tabs[activeIndex];

  bool get showsStrip => tabs.length > 1;

  DiscoverTabState copyWith({String? activeId}) =>
      DiscoverTabState(tabs: tabs, activeId: activeId ?? this.activeId);

  /// 同一条插件来源上已有的标签名，序号分配要看它。
  List<String> labelsOf(String source) => [
    for (final tab in tabs)
      if (tab.source == source) tab.label,
  ];
}

/// 发现页的标签条状态。
///
/// # 为什么不去重
///
/// 同一个插件点两次「搜索」得到两条标签，是**刻意**的：同时开几个搜索各查一个词
/// 是这里的日常用法（用户 2026-09-20 的口径）。重名的分辨交给标题上的序号
/// （见 [disambiguateLabel]），而不是把第二次点击吞成「切回旧标签」。
///
/// # 为什么不自己管导航
///
/// 标签内容全是上游原版页面，它们推下一个页面用的是 `context.pushRoute`。
/// 本 cubit 只负责「标签条上有什么」；「点开一个东西该不该变成一条新标签」
/// 由调用方（[DiscoverRouter] 与漫画卡片）显式决定，不设拦截层 ——
/// 拦截要靠「用户最后点在哪儿」那套记账，而一次按下会同时命中面板与标签两层，
/// 谁赢取决于监听器的派发顺序，那是个不该依赖的东西。
class DiscoverTabCubit extends Cubit<DiscoverTabState> {
  DiscoverTabCubit({required DiscoverTab homeTab})
    : super(DiscoverTabState(tabs: [homeTab], activeId: homeTab.id));

  int _seq = 0;

  /// 开一条新标签并切过去。
  ///
  /// [source] 是插件 uuid；名字与图标从插件注册表的缓存里取（取不到就留空，
  /// 标签于是只显示功能名 —— 比显示一个 uuid 好读）。
  void open({
    required String label,
    required String source,
    required WidgetBuilder content,
    IconData? icon,
  }) {
    final trimmed = label.trim();
    final resolved = trimmed.isEmpty ? '—' : trimmed;
    final (pluginName, iconUrl) = _pluginDisplay(source);
    final tab = DiscoverTab(
      id: 'tab-${++_seq}',
      label: disambiguateLabel(
        label: resolved,
        existingLabels: state.labelsOf(source),
      ),
      source: source,
      pluginName: pluginName,
      iconUrl: iconUrl,
      icon: icon,
      content: content,
    );
    emit(DiscoverTabState(tabs: [...state.tabs, tab], activeId: tab.id));
  }

  void activate(String id) {
    if (state.activeId == id) return;
    if (!state.tabs.any((tab) => tab.id == id)) return;
    emit(state.copyWith(activeId: id));
  }

  /// 关闭一条标签。关的是当前那条时，切到它的**左邻**（浏览器口径）。
  ///
  /// 不叫 `close`：`Cubit` 自己就有一个 `close()`，同名会把 cubit 的销毁流程盖掉。
  void closeTab(String id) {
    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final tab = state.tabs[index];
    if (!tab.closable) return;

    final next = [...state.tabs]..removeAt(index);
    if (next.isEmpty) return;
    final wasActive = state.activeId == id;
    final activeId = !wasActive
        ? state.activeId
        : next[(index - 1).clamp(0, next.length - 1)].id;
    emit(DiscoverTabState(tabs: next, activeId: activeId));
  }

  /// 回到首页标签（详情页里那颗「主页」按钮的落点）。
  void activateHome() {
    final home = state.tabs.first;
    emit(state.copyWith(activeId: home.id));
  }

  /// 插件的显示名与图标 URL，取自插件注册表缓存的 info。
  ///
  /// 取不到就返回两个空串：标签于是只显示功能名，比把 uuid 摆在标签上好读。
  /// 回退顺序与插件卡片一致（`name` → `creator.name`；`iconUrl` → `creator.coverUrl`），
  /// 两处不一样会让标签与卡片各说各话。
  (String, String) _pluginDisplay(String source) {
    if (source.isEmpty) return ('', '');
    final info = PluginRegistryService.I.getCachedPluginInfo(source);
    if (info == null) return ('', '');
    final creator = asJsonMap(info['creator']);
    final name = _text(info['name']) ?? _text(creator['name']) ?? '';
    final iconUrl = _text(info['iconUrl']) ?? _text(creator['coverUrl']) ?? '';
    return (name, iconUrl);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
