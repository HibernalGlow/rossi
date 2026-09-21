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

  /// 换标题用（复制成第二个窗格时标题要带新序号，其余一律照旧）。
  DiscoverLeafSpec copyWith({String? label}) => DiscoverLeafSpec(
    label: label ?? this.label,
    source: source,
    pluginName: pluginName,
    iconUrl: iconUrl,
    icon: icon,
    content: content,
  );
}

/// 发现页的标签：**一个 plat 的 `PlatTabGroup`**。
///
/// 为什么交给 plat 而不是自己排 Row：垂直轨、拖拽换序、pin / lock、undo、
/// 快照这几件事是同一套东西，自己写等于再造一份 `WorkspaceCubit` 的几何记账。
///
/// # 一组打底，分屏由右键开
///
/// 默认就一个组（[groupId]）：发现页要的是「多条同类页面切换」，不是「任意切分的
/// 工作区」。横向档下右键标签「在上/下/左/右打开」会经 `moveTabBeside` 把**这一条
/// 标签挪**到新窗格里（移动，不是复制），于是树上会出现 split；竖向轨那一档不分屏，
/// 新标签直接落在轨里（见 `RossiPlatTabMenuRegion`）。两条路都不开放拖拽落点
/// （`acceptsDrops: false`），免得随手一拖就把列表切成两半。
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

  /// 树上**所有组**里的标签，按「先原组、后分出来的组」的顺序。
  ///
  /// 不能只读 [groupId] 那一组：右键分屏之后树上会有第二个组，序号与
  /// 「关掉这一格」都要能找到分出去的那条标签，否则分屏就收不回去。
  List<TabSnapshot> get tabs {
    final out = <TabSnapshot>[];
    _collectTabs(controller.root, out);
    return out;
  }

  static void _collectTabs(PlatSnapshot node, List<TabSnapshot> out) {
    switch (node) {
      case final TabGroupSnapshot group:
        out.addAll(group.tabs);
      case final SplitSnapshot split:
        for (final child in split.children) {
          _collectTabs(child, out);
        }
      case final SlotSnapshot slot:
        final child = slot.child;
        if (child != null) _collectTabs(child, out);
      default:
        break;
    }
  }

  /// 这条标签所在的组（分屏后不止一个组）。
  String? groupOf(String tabId) => controller.tabGroupContaining(tabId);

  /// 树上**每一个**组的 id。分屏之后不止一个，朝向与钳制都要按个数组算。
  List<String> get groupIds {
    final out = <String>[];
    _collectGroups(controller.root, out);
    return out;
  }

  static void _collectGroups(PlatSnapshot node, List<String> out) {
    switch (node) {
      case final TabGroupSnapshot group:
        out.add(group.id);
      case final SplitSnapshot split:
        for (final child in split.children) {
          _collectGroups(child, out);
        }
      case final SlotSnapshot slot:
        final child = slot.child;
        if (child != null) _collectGroups(child, out);
      default:
        break;
    }
  }

  /// 标签条**当前**的朝向：只认树上的那一份。
  ///
  /// 这里不能改读设置：设置是「下次启动也要这样」的持久值，树才是眼前这一条。
  /// 两处各读一份的结局是轨宽按横向档算（40），竖排标签被压到 8px 宽然后溢出。
  TabBarSide get side => _group?.side ?? TabBarSide.top;

  bool get vertical => side != TabBarSide.top;

  /// 树上的组之间朝向不一致。
  ///
  /// plat 分出来的新组**永远**是 `top`（`_singleTabPane` 用的默认值），所以在竖轨
  /// 状态下分屏就会得到「一根竖轨 + 一根有轨那么高的横条」。右键菜单那一档已经不
  /// 再在竖向分屏，但 plat 自己的 `Cmd + \` 不受我们管，所以宿主拿这个标志兜底。
  bool get sidesMixed {
    final ids = groupIds;
    if (ids.length < 2) return false;
    final first = sideOf(ids.first);
    return ids.any((id) => sideOf(id) != first);
  }

  /// 某一个组的朝向；组不在树上（刚被关掉）就是 `null`。
  TabBarSide? sideOf(String groupId) {
    final snapshot = controller.snapshot(groupId);
    return snapshot is TabGroupSnapshot ? snapshot.side : null;
  }

  /// 树上那一份换算回设置里的枚举（钳制逻辑要拿它跟偏好比）。
  DiscoverTabBarSide get tabSide => switch (side) {
    TabBarSide.left => DiscoverTabBarSide.left,
    TabBarSide.right => DiscoverTabBarSide.right,
    _ => DiscoverTabBarSide.top,
  };

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

  TabSnapshot? _tabById(String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// 这条标签的内容规格；取不到返回 `null`。
  DiscoverLeafSpec? specOf(String tabId) => _specOf(_tabById(tabId));

  /// 复制一条标签（右键「在这一侧打开」用）：同内容、新 id、标题带新序号。
  ///
  /// 返回 `null` = 这条不给拆。首页那条是 `locked` 的：它既不能关，也不该被复制成
  /// 两个窗格 —— 两个「插件列表」没有意义，还会让「回到列表」出现两个出口。
  PlatTab? duplicateTabOf(String tabId) {
    final source = _tabById(tabId);
    if (source == null || source.locked) return null;
    final spec = _specOf(source);
    if (spec == null) return null;
    final label = disambiguateLabel(
      label: spec.label,
      existingLabels: _labelsOf(spec.source),
    );
    return PlatTab.leaf(
      id: 'tab-${++_seq}',
      title: label,
      data: spec.copyWith(label: label),
    );
  }

  void goHome() => controller.focus(homeId);

  /// 转朝向：树上**每一个**组一起转。
  ///
  /// 只改 [groupId] 那一份的话，分屏出来的那一格会留在横档上，而轨厚是全页一个值
  /// —— 结果是「一条竖轨 + 一根 132 高的横条」。包在 `transaction` 里是为了只通知
  /// 一次：逐组 notify 会让宿主每一组重建一遍，中间那一帧正是布局异常趁虚而入的地方。
  void setSide(DiscoverTabBarSide side) {
    final plat = platSideOf(side);
    controller.transaction(() {
      for (final id in groupIds) {
        controller.setTabBarSide(id, plat);
      }
    });
  }

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

  static DiscoverLeafSpec? _specOf(TabSnapshot? tab) {
    final child = tab?.child;
    return child is LeafSnapshot ? specOfLeaf(child) : null;
  }

  static TabBarSide platSideOf(DiscoverTabBarSide side) => switch (side) {
    DiscoverTabBarSide.top => TabBarSide.top,
    DiscoverTabBarSide.left => TabBarSide.left,
    DiscoverTabBarSide.right => TabBarSide.right,
  };

  /// 从 leaf 快照上取回内容规格；取不到（不是发现页的标签）返回 `null`。
  ///
  /// 这里**不做硬转**：树上混进一条别的 leaf（跨视图拖放、以后接进来的别的面板）
  /// 时，`data as DiscoverLeafSpec?` 会直接抛类型错误，而它发生在 build 里 ——
  /// 认不出来就当没有内容，比整片标签炸掉好。
  static DiscoverLeafSpec? specOfLeaf(LeafSnapshot leaf) {
    final data = leaf.data;
    return data is DiscoverLeafSpec ? data : null;
  }

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
