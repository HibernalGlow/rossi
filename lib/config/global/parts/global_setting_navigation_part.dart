part of '../global_setting.dart';

// 顶部导航栏（Arc 侧栏 / 悬浮 Dock）的偏好。
//
// 为什么放全局设置而不是 `workspace_layout.json`：那一份是**工作台**的布局
// （泳道宽度、面板记账），而这里问的是「应用外壳长什么样」——它跟工作台开关
// 一样属于外壳，用户没进过工作台也要能设。两类东西分开放，才不会出现
// 「重置工作台布局把导航栏也重置了」。

/// 侧栏与 Dock 的持久化。
///
/// - [sidebarEnabled]：桌面 / 平板这一支用新版侧栏（关掉退回改造前的
///   `NavigationRail`）。默认开 —— 用户点名要的就是它。
/// - [sidebarExpanded]：侧栏展开态（带文案的那一档）。默认关 = 只有图标，
///   与改造前 `NavigationRailLabelType.all` 相比更省横向空间，也正好是
///   侧栏切换按钮的初始形态。
/// - [dockEnabled]：移动端这一支用新版悬浮 Dock 栏（关掉退回
///   `PersistentTabView` 自带的那条底栏）。默认开。
/// - [autoNarrowMobileLayout]：窗口窄到阈值以下时**自动**从侧栏切到移动端布局
///   （桌面小窗 / 平板分屏）。默认开 —— FlClash 的侧栏本来就会随宽度切，
///   而这条同时解释了「为什么桌面上把窗口拉窄会长出底部 Dock」。
/// - [narrowNavigationWidth]：上面那条的阈值。默认
///   [kDefaultNarrowNavigationWidth]，用户可调；越界由
///   [clampNarrowNavigationWidth] 收口。
/// - [desktopPageIds] / [mobilePageIds]：两支各自的**主区**摆哪几条、按什么
///   顺序。条目是**页面或动作**（见 `lib/widgets/navigation/navigation_entries.dart`）。
///   **空 = 用出厂清单**（不是「清空」）—— 出厂值就是空，
///   `decodeNavigationEntryIds` 靠这条把「没设置过」与「数据坏了」都落回默认。
///   存的是 `NavigationEntryId.name`，改名等于让老用户的选择全部落空。
/// - [desktopActionIds] / [mobileActionIds]：两支各自的**底部快捷区**
///   （侧栏底部那块 / Dock 尾部溢出菜单）摆哪几条、按什么顺序，**只放动作**。
///
///   这两个**可空**是刻意的，也是它俩与上面那两个唯一的区别：
///   - `null` = 用户没动过 ⇒ 用出厂清单
///     [kDefaultNavigationActionEntries]（打开本地漫画 / GPU 上屏 / 搜索 /
///     自定义导航），开箱观感与改造前一致；
///   - `[]` = 用户把它们**全隐藏了** ⇒ 底部整块不出现。
///
///   默认给 `[]` 的话这两件事就分不开了 —— 用户永远关不掉底部那块。
///   另外注意 `copyWith` 对可空字段**没法赋 null**（`x ?? this.x`），所以
///   「恢复出厂」这条路径写的是**展开后的清单**而不是 null；`null` 只属于
///   「从没写过」这一个状态。
@freezed
abstract class NavigationSettingState with _$NavigationSettingState {
  const factory NavigationSettingState({
    @Default(true) bool sidebarEnabled,
    @Default(false) bool sidebarExpanded,
    @Default(true) bool dockEnabled,
    @Default(true) bool autoNarrowMobileLayout,
    @Default(kDefaultNarrowNavigationWidth) double narrowNavigationWidth,
    @Default([]) List<String> desktopPageIds,
    @Default([]) List<String> mobilePageIds,
    List<String>? desktopActionIds,
    List<String>? mobileActionIds,
  }) = _NavigationSettingState;

  factory NavigationSettingState.fromJson(Map<String, dynamic> json) =>
      _$NavigationSettingStateFromJson(json);
}
