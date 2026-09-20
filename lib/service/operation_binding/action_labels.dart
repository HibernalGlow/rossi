// 动作 id → **显示名**：唯一的一份映射。
//
// 为什么单独一个文件：轮盘浮层、槽位列表、按键区、冲突清单四处都要显示同一个名字。
// 各写一份 switch 的话，「设置页叫『下一页』、轮盘里叫『reader.next-page』」
// 这种分裂迟早会出现。
//
// 动作**清单**仍然只有 Rust 注册表那一份权威（ADR-0015）：这里只做「把注册表给的
// label 换成本仓译文」这一步，译文缺条目就用注册表的原文 —— 不在 Dart 里另立
// 「有哪些动作」的名单。

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';

/// 一条动作的显示名（优先本仓译文：英文界面下不该出现中文动作名）。
String actionLabel(BindingActionInfo entry) => switch (entry.id) {
  BindingAction.nextPage => t.settings.operationBindingActionNextPage,
  BindingAction.previousPage => t.settings.operationBindingActionPreviousPage,
  BindingAction.firstPage => t.settings.operationBindingActionFirstPage,
  BindingAction.lastPage => t.settings.operationBindingActionLastPage,
  BindingAction.pageLeft => t.settings.operationBindingActionPageLeft,
  BindingAction.pageRight => t.settings.operationBindingActionPageRight,
  BindingAction.fullscreen => t.settings.operationBindingActionFullscreen,
  BindingAction.toggleReadingDirection =>
    t.settings.operationBindingActionToggleDirection,
  BindingAction.toggleBookMode => t.settings.operationBindingActionBookMode,
  BindingAction.resetView => t.settings.operationBindingActionResetView,
  BindingAction.toggleControls => t.settings.operationBindingActionToggleBars,
  BindingAction.openSettings => t.settings.operationBindingActionOpenSettings,
  BindingAction.openRadialMenu => t.settings.operationBindingActionOpenRadial,
  BindingAction.confirmRadialMenu =>
    t.settings.operationBindingActionConfirmRadial,
  'reader.toggle-library' => t.settings.operationBindingActionToggleLibrary,
  BindingAction.zoomIn => t.settings.operationBindingActionZoomIn,
  BindingAction.zoomOut => t.settings.operationBindingActionZoomOut,
  BindingAction.fitWindow => t.settings.operationBindingActionFitWindow,
  BindingAction.actualSize => t.settings.operationBindingActionActualSize,
  BindingAction.rotateClockwise =>
    t.settings.operationBindingActionRotateClockwise,
  BindingAction.rotate180 => t.settings.operationBindingActionRotate180,
  _ => entry.label,
};

/// 注册表全量的 `id → 显示名`（轮盘浮层给每一格配文字时用）。
Map<String, String> actionLabelsById() => {
  for (final entry in OperationBindingStore.actionCatalog())
    entry.id: actionLabel(entry),
};

/// 某个动作 id 的显示名；注册表里没有这个 id 时原样返回 id
/// —— 「导入的表里有个本仓不认识的动作」要看得见，而不是显示成空白。
String actionLabelForId(String actionId) =>
    actionLabelsById()[actionId] ?? actionId;
