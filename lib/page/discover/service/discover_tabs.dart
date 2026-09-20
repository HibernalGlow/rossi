import 'package:flutter/widgets.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/json/json_value.dart';

/// 一条标签的内容规格。塞进 `PlatLeaf.data`，`leafBuilder` 按它分发。
@immutable
class DiscoverLeafSpec {
  const DiscoverLeafSpec({
    required this.label,
    required this.source,
    required this.pluginName,
    required this.iconUrl,
    required this.content,
    this.icon,
  });

  /// 功能名（「排行」「搜索 2」「设置」）或漫画标题。已带序号。
  final String label;

  /// 插件 uuid；空串 = 首页这类没有插件来源的标签。
  final String source;

  final String pluginName;
  final String iconUrl;

  /// 没有插件来源时标签上画的那颗图标。
  final IconData? icon;

  final WidgetBuilder content;
}

/// 发现页的标签：**一个 plat 的 `PlatTabGroup`**。
///
/// 为什么交给 plat 而不是自己排 Row：垂直轨、拖拽换序、pin / lock、undo、
/// 快照这几件事是同一套东西，自己写等于再造一份 `WorkspaceCubit` 的几何记账。
///
/// # 只有一组
///
/// 整页就一个组（[groupId]），没有分栏 —— 发现页要的是「多条同类页面切换」，
/// 不是「任意切分的工作区」。plat 的 split 能力留在这里但不启用。
///
/// # 不去重
///
/// 同一个插件点两次「搜索」就是两条标签（用户 2026-09-20 的口径：
/// 「我可能会多个搜索」）。重名的分辨交给标题上的序号（见 [disambiguateLabel]）。
class DiscoverTabs {
  DiscoverTabs({
    required DiscoverTabBarSide side,
    required DiscoverLeafSpec home,
  }) : controller = PlatController(
         initialPlat: Plat.tabs(
           [
             PlatTab.leaf(
               id: homeId,
               title: home.label,
               // 首页关不掉也拖不走：它是「回到插件列表」那一下的落点。
               data: home,
               locked: true,
             ),
           ],
           id: groupId,
           side: platSideOf(side),
           // 整页只有一组：拖进来的落点会造出第二个组或分栏，那不在设计里。
           // 关掉它不影响轨内换序（plat 的轨道拖拽不走这个开关）。
           acceptsDrops: false,
         ),
       );

  static const String groupId = 'discover-tabs';
  static const String homeId = 'discover-home';

  final PlatController controller;
  int _seq = 0;

  bool get onHome => controller.activeTabId(groupId) == homeId;

  /// 只有一条标签时没有可切的东西：发现页把标题位让回「发现」两个字，
  /// 也不占掉那一行 chrome。
  bool get showsChrome => tabs.length > 1;

  List<TabSnapshot> get tabs => _group?.tabs ?? const <TabSnapshot>[];

  /// 标签条**当前**的朝向：只认树上的那一份。
  ///
  /// 这里不能改读设置：设置是「下次启动也要这样」的持久值，树才是眼前这一条。
  /// 两处各读一份的结局是轨宽按横向档算（40），竖排标签被压到 8px 宽然后溢出。
  TabBarSide get side => _group?.side ?? TabBarSide.top;

  bool get vertical => side != TabBarSide.top;

  TabGroupSnapshot? get _group {
    final snapshot = controller.snapshot(groupId);
    return snapshot is TabGroupSnapshot ? snapshot : null;
  }

  /// 开一条新标签并切过去。
  void open({
    required String label,
    required String source,
    required WidgetBuilder content,
    IconData? icon,
  }) {
    final trimmed = label.trim();
    final (pluginName, iconUrl) = _pluginDisplay(source);
    final spec = DiscoverLeafSpec(
      label: disambiguateLabel(
        label: trimmed.isEmpty ? '—' : trimmed,
        existingLabels: _labelsOf(source),
      ),
      source: source,
      pluginName: pluginName,
      iconUrl: iconUrl,
      icon: icon,
      content: content,
    );
    controller.insertTab(
      tabGroupId: groupId,
      tab: PlatTab.leaf(id: 'tab-${++_seq}', title: spec.label, data: spec),
    );
  }

  /// 关掉一条标签。首页那条是 locked 的，plat 会直接拒掉。
  void close(String id) => controller.close(id);

  void goHome() => controller.focus(homeId);

  void setSide(DiscoverTabBarSide side) =>
      controller.setTabBarSide(groupId, platSideOf(side));

  void dispose() => controller.dispose();

  /// 同一插件来源上已有的标签名，序号分配要看它。
  List<String> _labelsOf(String source) => [
    for (final tab in tabs)
      if (_specOf(tab)?.source == source) _specOf(tab)?.label ?? '',
  ];

  /// 标签的显示标题：`缩写 · 功能名`。两颗开关关掉任何一颗都只剩功能名。
  static String labelOf(
    DiscoverLeafSpec spec, {
    required bool showPluginShort,
  }) {
    if (!showPluginShort) return spec.label;
    return joinTabLabel(
      shortName: pluginShortName(spec.pluginName),
      label: spec.label,
    );
  }

  static DiscoverLeafSpec? _specOf(TabSnapshot tab) {
    final child = tab.child;
    return child is LeafSnapshot ? child.data as DiscoverLeafSpec? : null;
  }

  static TabBarSide platSideOf(DiscoverTabBarSide side) => switch (side) {
    DiscoverTabBarSide.top => TabBarSide.top,
    DiscoverTabBarSide.left => TabBarSide.left,
    DiscoverTabBarSide.right => TabBarSide.right,
  };

  /// 从 leaf 快照上取回内容规格；取不到（不是发现页的标签）返回 `null`。
  static DiscoverLeafSpec? specOfLeaf(LeafSnapshot leaf) =>
      leaf.data as DiscoverLeafSpec?;

  /// 插件的显示名与图标 URL，取自插件注册表缓存的 info。
  ///
  /// 取不到就返回两个空串：标签只显示功能名，比把 uuid 摆在标签上好读。
  /// 回退顺序与插件卡片一致（`name` → `creator.name`；`iconUrl` → `creator.coverUrl`）。
  static (String, String) _pluginDisplay(String source) {
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
