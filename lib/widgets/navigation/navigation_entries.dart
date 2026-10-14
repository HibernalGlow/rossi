// 顶部导航的**条目身份** + 条目清单的**纯函数**层。
//
// 一条「条目」有两种：
//
// - **页面**（[NavigationEntryIdX.isPage]）：切过去就换当前视图 ——
//   书架 / 发现 / 更多，以及「旧版页面」开关打开时的旧首页 / 旧排行；
// - **动作**（[NavigationEntryIdX.isAction]）：点一下推一条路由，**不换当前
//   视图** —— 工作台 / 打开本地漫画 / GPU 上屏 / 搜索 / 自定义导航。
//
// 两种共用同一套身份，但**分摆在两段**里（2026-10-10 用户提的口径）：
//
// - **主区**（侧栏上半 / Dock 胶囊）：页面与动作都能放，顺序即显示顺序；
// - **底部快捷区**（侧栏底部那块 / Dock 尾部溢出菜单）：**只放动作**。
//
// 分两段是因为底部那块以前是**写死的固定区**（`NavigationRail.trailing` 的
// 遗产，外加一颗硬编码的「自定义导航」按钮）：藏不掉、排不了序，手机端更
// 根本拿不到。现在两段各自能增删排序，而「自定义导航」也从写死按钮降格成
// 一条普通动作（见 [NavigationEntryId.customizeNavigation]）—— 设置里本来
// 就有入口，没必要一定钉在侧栏底部。
//
// 两段是**互斥**的：同一条不会同时出现在两处（`navigation_bar.dart` 起手就
// 把主区已有的从底部那段里减掉）。
//
// 为什么要有这一层：导航栏改造后，「当前在哪个页」不再能用下标表示 ——
// 桌面侧栏与移动 Dock 各有自己的条目清单，同一页在两边下标不同；用户还能
// 增删与排序（见 `navigation_customization_dialog.dart`）。所以**身份用 id、
// 下标只在某一支布局里当场算**。清单的解析 / 增删 / 排序都写成纯函数，
// 判据不必把导航栏挂起来（那一层依赖 ObjectBox、通知、下载队列）。
//
// 页面本身也在这里造：`navigation_bar.dart` 的两个布局分支必须拿到**同一份**
// 列表，否则「桌面删掉的页在手机上还在」这类分叉会立刻出现。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/bookshelf/bookshelf.dart';
import 'package:zephyr/page/discover/view/discover_page.dart';
import 'package:zephyr/page/more/view/more.dart';
import 'package:zephyr/page/old_page/old_home/old_home_page.dart';
import 'package:zephyr/page/old_page/old_ranking/old_ranking_page.dart';

/// 能放进导航栏的一条**条目**：页面或动作。
///
/// **`name` 是持久化契约**：设置里存的就是它（
/// `NavigationSettingState.desktopPageIds` / `mobilePageIds`，以及底部那两段），
/// 也是云同步跟着走的那份载荷。改名等于让老用户的选择全部落空，所以宁可改
/// 显示文案（[NavigationEntryIdX.label] 走 i18n），也不动 `name`。
///
/// 动作那几条（[workspace] 起）是后追加的。字符串是新的 ⇒ 老客户端读不懂，
/// `decodeNavigationEntryIds` 会安静丢掉 —— 那正是它该做的（不认识的 id
/// 不占位），而不是把整份清单判成坏数据。
enum NavigationEntryId {
  // ── 页面：切过去就换当前视图 ──
  bookshelf,
  discover,
  more,
  oldHome,
  oldRank,

  // ── 动作：点一下推一条路由，不换当前视图 ──
  workspace,
  openLocalComic,
  gpuPresent,
  search,

  /// 打开「自定义导航栏」弹窗本身。
  ///
  /// 它**也是一条动作**，不是特殊开关：以前它是侧栏底部写死的一颗按钮
  /// （不在这份清单里，谁也没法动它）。2026-10-10 用户提的口径是
  /// 「设置里已经有入口，没必要一定钉在底部」—— 于是它进池子，默认摆在
  /// 底部快捷区（开箱观感不变），想隐藏 / 换位置就跟别的动作一样改。
  customizeNavigation,
}

extension NavigationEntryIdX on NavigationEntryId {
  /// 点了不换页的那一类。
  ///
  /// 导航栏的「当前页」记账（`navigation_bar.dart` 的 `_syncSelection`）
  /// 靠它把动作排除在外：选中的下标**永远**落在一个页面上，否则动作夹在
  /// 中间时按下的那一格与画面对不上。
  bool get isAction => switch (this) {
    NavigationEntryId.workspace ||
    NavigationEntryId.openLocalComic ||
    NavigationEntryId.gpuPresent ||
    NavigationEntryId.search ||
    NavigationEntryId.customizeNavigation => true,
    _ => false,
  };

  bool get isPage => !isAction;

  String get label => switch (this) {
    NavigationEntryId.bookshelf => t.navigation.bookshelf,
    NavigationEntryId.discover => t.navigation.discover,
    NavigationEntryId.more => t.navigation.more,
    NavigationEntryId.oldHome => t.navigation.home,
    NavigationEntryId.oldRank => t.navigation.rank,
    NavigationEntryId.workspace => t.navigation.workspace,
    NavigationEntryId.openLocalComic => t.navigation.openLocalComic,
    NavigationEntryId.gpuPresent => t.navigation.gpuPresent,
    // 这两个是既有词条 —— 别再为同一个词开第二份翻译。
    NavigationEntryId.search => t.common.search,
    NavigationEntryId.customizeNavigation => t.navigation.customize,
  };

  /// 侧栏底部动作区 / Dock 尾部溢出菜单里那句**说明**。
  ///
  /// 页面的说明就是它自己的 [label]；动作这几句沿用的是改造前挂在
  /// `NavigationRail.trailing` 上的 tooltip，当时就没补 i18n 词条（它们是
  /// 本仓自有的开发期入口），这里保持原样、不顺手改口径。
  String get tooltip => switch (this) {
    NavigationEntryId.workspace => t.common.neoViewWorkspace,
    NavigationEntryId.openLocalComic => t.common.openLocalComicRossi,
    NavigationEntryId.gpuPresent => 'GPU 上屏（D3D12 共享纹理）',
    NavigationEntryId.search => t.common.search,
    NavigationEntryId.customizeNavigation => t.navigation.customizeHint,
    _ => label,
  };

  /// 自绘图标（glyph）体系里的对应图形。
  ///
  /// 这套图标是从 FlClash 整份搬来的（`lib/icons/app_glyphs.dart`），
  /// 里面没有「书本」「指南针」这种书站专属图形，所以这里挑的是**语义最近**的：
  /// - 书架 → `columnsThree`：一格格的封面网格；
  /// - 发现 → `target`：一圈准星，读作「去找」；
  /// - 更多 → `appsList`：一列带点的小方片，正是「更多」页那张功能清单；
  /// - 旧首页 → `dashboard`：四宫格；
  /// - 旧排行 → `sort`：三条递减的横线，读作「排名」。
  ///
  /// 想换图形只改这一处 —— 侧栏与 Dock 都从这里取，不存在两边不一致的可能。
  Glyph get glyph => switch (this) {
    NavigationEntryId.bookshelf => AppGlyphs.columnsThree,
    NavigationEntryId.discover => AppGlyphs.target,
    NavigationEntryId.more => AppGlyphs.appsList,
    NavigationEntryId.oldHome => AppGlyphs.dashboard,
    NavigationEntryId.oldRank => AppGlyphs.sort,
    // 动作那几个沿用侧栏底部原本配的图形。
    NavigationEntryId.workspace => AppGlyphs.layoutTabs,
    NavigationEntryId.openLocalComic => AppGlyphs.importFile,
    NavigationEntryId.gpuPresent => AppGlyphs.cpu,
    NavigationEntryId.search => AppGlyphs.search,
    NavigationEntryId.customizeNavigation => AppGlyphs.sliders,
  };

  /// 这一条是否只属于「旧版首页」那套（`oldPageRollbackEnabled` 打开时才存在）。
  bool get legacyOnly =>
      this == NavigationEntryId.oldHome || this == NavigationEntryId.oldRank;

  /// 关掉新版导航壳之后，退回的旧布局（`NavigationRail` 的
  /// `NavigationRailDestination` 与 `PersistentTabView` 的底栏项）用的是
  /// **Material 图标**，不是自绘 glyph —— 那两处是改造前就在的样子，
  /// 换图标等于顺手改了「关掉开关」的含义。
  ///
  /// 放在这里而不是散在 `navigation_bar.dart` 里：`glyph`、`label`、`build`
  /// 都在这一个 switch 组里，多一个「哪一条配哪个图标」也应当同源。
  /// 两处底栏（`style3`）只用未选中那一个，`selectedIcon` 给 NavigationRail。
  ///
  /// 动作条目在旧版**移动**布局里不出现（`PersistentTabView` 只认得页面），
  /// 这里给它们配图标只是为了那个 switch 完整 —— 免得将来有人加条目时忘掉。
  Glyph get legacyIcon => switch (this) {
    NavigationEntryId.bookshelf => AppGlyphs.book,
    NavigationEntryId.discover => AppGlyphs.compass,
    NavigationEntryId.more => AppGlyphs.apps,
    NavigationEntryId.oldHome => AppGlyphs.home,
    NavigationEntryId.oldRank => AppGlyphs.trophy,
    NavigationEntryId.workspace => AppGlyphs.gridPlus,
    NavigationEntryId.openLocalComic => AppGlyphs.folder,
    NavigationEntryId.gpuPresent => AppGlyphs.storage,
    NavigationEntryId.search => AppGlyphs.search,
    NavigationEntryId.customizeNavigation => AppGlyphs.sliders,
  };

  Glyph get legacySelectedIcon => switch (this) {
    NavigationEntryId.bookshelf => AppGlyphs.book,
    NavigationEntryId.discover => AppGlyphs.compass,
    NavigationEntryId.more => AppGlyphs.apps,
    NavigationEntryId.oldHome => AppGlyphs.home,
    NavigationEntryId.oldRank => AppGlyphs.trophy,
    NavigationEntryId.workspace => AppGlyphs.gridPlus,
    NavigationEntryId.openLocalComic => AppGlyphs.folder,
    NavigationEntryId.gpuPresent => AppGlyphs.storage,
    NavigationEntryId.search => AppGlyphs.search,
    NavigationEntryId.customizeNavigation => AppGlyphs.sliders,
  };

  Widget build() => switch (this) {
    NavigationEntryId.bookshelf => const BookshelfPage(),
    NavigationEntryId.discover => const DiscoverPage(),
    NavigationEntryId.more => const MorePage(),
    NavigationEntryId.oldHome => const OldHomePage(),
    NavigationEntryId.oldRank => const OldRankingPage(),
    // 动作不是视图。切页栈按条目对齐（`IndexedStack` 的下标 = 清单下标），
    // 所以给它留一个空的格子 —— 它永远不是选中项，没人会看见这个盒子。
    NavigationEntryId.workspace ||
    NavigationEntryId.openLocalComic ||
    NavigationEntryId.gpuPresent ||
    NavigationEntryId.search ||
    NavigationEntryId.customizeNavigation => const SizedBox.shrink(),
  };
}

/// 主区里至少要留这么多条**页面**。
///
/// 不是「至少两条条目」：**动作不算数**。手机那支在关掉 Dock 开关之后走
/// `PersistentTabView`，它只渲染页面，构造断言又要求 2..6 条 ——
/// 「一条页面 + 一条动作」会让那一支直接断言失败。下限按**页面**数算，
/// 同时也就保住了「导航栏总能指回一个视图」这条。
const int kMinNavigationPageCount = 2;

/// 出厂清单（不含旧版页面）。
///
/// **不含动作**：动作默认留在底部快捷区，与改造前一致 —— 于是开箱观感不变，
/// 而想把它摆到主区上的人自己去「自定义导航」里拖。
const List<NavigationEntryId> kDefaultNavigationEntries = [
  NavigationEntryId.bookshelf,
  NavigationEntryId.discover,
  NavigationEntryId.more,
];

/// 出厂清单（含旧版页面），顺序与改造前 `_buildPageList` 的拼接顺序一致。
const List<NavigationEntryId> kDefaultNavigationEntriesWithLegacy = [
  NavigationEntryId.oldHome,
  NavigationEntryId.oldRank,
  NavigationEntryId.bookshelf,
  NavigationEntryId.discover,
  NavigationEntryId.more,
];

/// 出厂清单：**底部快捷区**那一段。
///
/// 与改造前侧栏底部那块区域逐条一致（打开本地漫画 / GPU 上屏 / 搜索），
/// 只多了「自定义导航」—— 它以前是写死在那儿的按钮，现在是一条普通条目。
/// **不在主清单里**：开箱观感因此与改造前一致；谁想把它摆到主区去，自己在
/// 「自定义导航」里拖。
const List<NavigationEntryId> kDefaultNavigationActionEntries = [
  NavigationEntryId.openLocalComic,
  NavigationEntryId.gpuPresent,
  NavigationEntryId.search,
  NavigationEntryId.customizeNavigation,
];

/// 这台设备上**可选**的条目全集（顺序即「待添加」列表里的顺序）。
///
/// 动作不去按平台过滤：底部快捷区本来就在所有「有侧栏」的设备上摆着同样
/// 几条，这里保持一致（真按平台收，会变成「桌面加得进去、平板加不进去」
/// 这种更难解释的差别）。
List<NavigationEntryId> availableNavigationEntries(
  bool oldPageRollbackEnabled,
) => [
  for (final id in NavigationEntryId.values)
    if (oldPageRollbackEnabled || !id.legacyOnly) id,
];

/// 出厂清单，随「旧版页面」开关变化。
List<NavigationEntryId> defaultNavigationEntries(bool oldPageRollbackEnabled) =>
    oldPageRollbackEnabled
    ? kDefaultNavigationEntriesWithLegacy
    : kDefaultNavigationEntries;

/// 底部快捷区的出厂清单，只取这台设备**可选**的那些。
///
/// 与 [defaultNavigationEntries] 分开：那一个要随「旧版页面」开关变（旧首页 /
/// 旧排行只在开关打开时存在），而这一段全是动作、没有开关依赖。过滤一次
/// [allowed] 只是防御 —— 调用方本来就该传同一份 `allowed`。
List<NavigationEntryId> defaultNavigationActions(
  List<NavigationEntryId> allowed,
) => [
  for (final id in kDefaultNavigationActionEntries)
    if (allowed.contains(id)) id,
];

/// 存进设置里的形状。
List<String> encodeNavigationEntryIds(List<NavigationEntryId> ids) => [
  for (final id in ids) id.name,
];

/// 从设置里读回**主区**的清单。
///
/// 四条容错，前三条与 FlClash 的 `CustomNavigationProps.fromMap` 同义：
/// 1. 认不出的 id 丢掉（老版本存过、或云端同步来的新 id）；
/// 2. 重复的丢掉（保留第一次出现的位置）；
/// 3. **一条都不剩就退回 [fallback]** —— 空清单不是「用户想清空」，
///    而是「这份数据坏了」或「还没设置过」（出厂值就是空）；
/// 4. **剩下的全是动作也退回 [fallback]**（本仓自加的一条）：主区得有一个
///    **视图**可指，否则「当前页」无处落脚 —— 动作点了不换页，一屏动作等于
///    没有导航。
///
/// [allowed] 之外的 id 也丢掉：关掉「旧版页面」之后，清单里残留的
/// 旧首页 / 旧排行不该继续占着位置。
List<NavigationEntryId> decodeNavigationEntryIds(
  List<String> raw, {
  required List<NavigationEntryId> fallback,
  required List<NavigationEntryId> allowed,
}) {
  final parsed = <NavigationEntryId>[];
  for (final name in raw) {
    final matched = NavigationEntryId.values.where((id) => id.name == name);
    if (matched.isEmpty) continue;
    final id = matched.first;
    if (!allowed.contains(id) || parsed.contains(id)) continue;
    parsed.add(id);
  }
  if (parsed.isEmpty || parsed.every((id) => id.isAction)) return fallback;
  return parsed;
}

/// 从设置里读回**底部快捷区**的清单。
///
/// 与 [decodeNavigationEntryIds] 有三点不同：
/// 1. **不退回出厂清单** —— 这一段问的是「用户勾了哪几条」，空 = 一条都不留
///    （底部整块不出现）是个合法状态。是不是「没设置过」由
///    [resolveNavigationActionIds] 的 `stored == null` 判，所以出厂值存的是
///    `null` 而不是 `[]`（见 `NavigationSettingState.desktopActionIds`）——
///    默认给 `[]` 的话，这两件事就再也分不开了；
/// 2. **只收动作**：底部快捷区里出现页面没有意义（页面得在主区里当「当前
///    视图」），混进这一段的（写坏的、同步来的）在这里丢掉；
/// 3. 认不出 / 重复的照旧丢掉，与上面同义。
List<NavigationEntryId> decodeNavigationActionIds(
  List<String> raw, {
  required List<NavigationEntryId> allowed,
}) {
  final parsed = <NavigationEntryId>[];
  for (final name in raw) {
    final matched = NavigationEntryId.values.where((id) => id.name == name);
    if (matched.isEmpty) continue;
    final id = matched.first;
    if (!id.isAction || !allowed.contains(id) || parsed.contains(id)) continue;
    parsed.add(id);
  }
  return parsed;
}

/// 某一支布局最终该摆哪几条（主区）。
///
/// [stored] 是设置里那份（出厂为空），[allowed] 是这台设备可选的全集。
List<NavigationEntryId> resolveNavigationEntryIds({
  required List<String> stored,
  required List<NavigationEntryId> allowed,
  required List<NavigationEntryId> fallback,
}) => decodeNavigationEntryIds(stored, fallback: fallback, allowed: allowed);

/// 某一支布局的底部快捷区最终该摆哪几条。
///
/// [stored] 为 `null` = 用户没动过 ⇒ 用 [fallback]；`[]` = 用户把它们全隐藏
/// 了 ⇒ 真的是空的。这个区分做不出来就只好把「空」也当「没设置过」，那样
/// 用户永远关不掉底部那块 —— 那正是这次要修的东西。
List<NavigationEntryId> resolveNavigationActionIds({
  required List<String>? stored,
  required List<NavigationEntryId> allowed,
  required List<NavigationEntryId> fallback,
}) => stored == null
    ? fallback
    : decodeNavigationActionIds(stored, allowed: allowed);

/// 这条当前能不能从**主区**删 —— 弹窗据此决定按钮是灰的还是能按。
///
/// 只有一条下限（与 [toggleNavigationEntry] 逐条对应）：页面不能删到少于
/// [kMinNavigationPageCount] 条。动作可以全删光（主区只是没有快捷入口）。
bool canRemoveNavigationEntry(
  List<NavigationEntryId> current,
  NavigationEntryId id, {
  int minPages = kMinNavigationPageCount,
}) {
  if (!current.contains(id)) return false;
  if (id.isPage && current.where((item) => item.isPage).length <= minPages) {
    return false;
  }
  return true;
}

/// 主区里增 / 删一条。返回 `null` = 这次操作不合法（已经在、或触到上面那条
/// 下限），调用方据此决定是「什么也不做」还是「给一句提示」。
///
/// 抽成纯函数是为了让「删到只剩一条会怎样」能被直接断言 ——
/// 这条边界只在弹窗里点得出来，起整个 app 去点太贵。
List<NavigationEntryId>? toggleNavigationEntry(
  List<NavigationEntryId> current,
  NavigationEntryId id, {
  int minPages = kMinNavigationPageCount,
}) {
  if (!current.contains(id)) return [...current, id];
  if (!canRemoveNavigationEntry(current, id, minPages: minPages)) return null;
  return [
    for (final item in current)
      if (item != id) item,
  ];
}

/// 底部快捷区里增 / 删一条。**没有下限** —— 动作全隐藏是合法的（那时底部
/// 整块不出现）。要下限的是主区，见 [canRemoveNavigationEntry]。
List<NavigationEntryId> toggleNavigationAction(
  List<NavigationEntryId> current,
  NavigationEntryId id,
) => current.contains(id)
    ? [
        for (final item in current)
          if (item != id) item,
      ]
    : [...current, id];

/// 拖动排序。下标越界一律按「没动」处理（[newIndex] 由
/// `ReorderableListView.onReorderItem` / `SliverReorderableList.onReorderItem`
/// 给出，已被框架按「先摘后插」修正过，与 `onReorder` 那个「新下标要减一」
/// 的老口径不同）。
List<NavigationEntryId> reorderNavigationEntry(
  List<NavigationEntryId> current,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= current.length) return current;
  final clamped = newIndex.clamp(0, current.length - 1);
  if (oldIndex == clamped) return current;
  final next = List<NavigationEntryId>.from(current);
  final item = next.removeAt(oldIndex);
  next.insert(clamped, item);
  return next;
}
