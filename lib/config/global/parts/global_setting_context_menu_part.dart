part of '../global_setting.dart';

// 右键 / 长按上下文菜单的用户偏好。
//
// 为什么放全局设置而不是 `workspace_layout.json`：菜单散布在书架、文件管理、
// 泳道、标签栏与工作台卡片上，它跟导航栏一样属于「应用外壳长什么样」，
// 用户没进过工作台也要能设。放进全局设置还顺带吃到现成的云同步。
//
// 存的形状：
// - [scopes] 的 key 是 scope id（`shelf` / `fileManager` / …），只存**动过的**
//   scope；没动过的 scope 一个键都不写（出厂次序由 definition 提供）。
// - 单个 scope 的 `order` / `overrides` 语义见
//   `lib/model/context_menu/context_menu_model.dart` 顶部注释。
//
// 为什么不用新 ObjectBox 实体：这份偏好要随 `globalSettingData` 整串同步，
// 单独开表就得多写一套同步逻辑，而它本来就只有十几 KB。

/// 右键菜单偏好的持久化。
@freezed
abstract class ContextMenuSettingState with _$ContextMenuSettingState {
  const factory ContextMenuSettingState({
    /// scope id → 该菜单的用户偏好。只装改过的 scope。
    @Default(<String, ContextMenuScopeLayout>{})
    Map<String, ContextMenuScopeLayout> scopes,

    /// 顶部图标条总开关。默认开 —— 没有 pin 到顶部的项时本来就不会出现。
    @Default(true) bool topStripEnabled,

    /// 菜单底部是否显示「自定义此菜单…」。关掉后只能从设置页调整。
    @Default(true) bool customizeEntryVisible,
  }) = _ContextMenuSettingState;

  factory ContextMenuSettingState.fromJson(Map<String, dynamic> json) =>
      _$ContextMenuSettingStateFromJson(json);
}
