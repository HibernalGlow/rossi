import 'package:flutter/foundation.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

@immutable
class WorkspaceState {
  final WorkspaceMode mode;
  final WorkspaceLayoutConfig layout;

  /// 面板 / 卡片的布局记账（可见性、次序、卡片归属）。
  final WorkspaceBoardLayout board;

  /// 阅读器泳道当前打开的目标；`null` = 泳道空闲（显示空态画板）。
  final WorkspaceReaderTarget? readerTarget;

  /// 各泳道当前激活的面板 ID（每条泳道**各自独立**，互不覆盖）。
  final Map<String, String> activePanel;

  /// 当前**激活**的泳道 ID。
  ///
  /// 「激活」不是「独占」：独占（solo）是**泳道自己的属性**，激活是
  /// 「工作台当前把交互交给谁」。两条契约都建在它之上：
  ///
  /// - 非激活泳道的第一下点击要被工作台**吃掉**（用来激活它），不派发给内容；
  /// - solo 的生效宽度以「那条泳道同时是激活泳道」为前提 ——
  ///   激活别的泳道会让 Reader 回到常规宽度，但**不清除** solo 偏好。
  ///
  /// 为 `null` 表示「还没定过」：此时不吞任何点击，一切按改造前行为派发。
  /// 这个「没定过」的初始态是刻意的 —— 冷启动不该因为一个默认激活项
  /// 就把用户在左泳道里的第一次点击无声吃掉。
  final String? activeLaneId;

  /// 交互延时与开关（悬停聚焦 / 边缘揭示 / 揭示恢复 / Reader 窄缝宽）。
  final WorkspaceInteractionSettings interaction;

  const WorkspaceState({
    required this.mode,
    required this.layout,
    this.board = const WorkspaceBoardLayout(),
    this.readerTarget,
    this.activePanel = const <String, String>{},
    this.activeLaneId,
    this.interaction = const WorkspaceInteractionSettings(),
  });

  factory WorkspaceState.initial() {
    return WorkspaceState(
      mode: WorkspaceMode.swimlane,
      layout: WorkspaceLayoutConfig.defaults(),
      // 布局记账留空 —— 空账 = 全部用注册表里的默认值，
      // 于是「加卡片 / 改默认面板」不需要写迁移，也不会被旧记录挡住。
    );
  }

  /// solo 的**生效**泳道：只有它同时也是激活泳道时才算数。
  ///
  /// 契约原文是 `When the Reader lane is active and solo is enabled, its
  /// effective width is the workspace viewport width` —— 前提条件就是
  /// 「激活」。把这条判断放在**一个地方**（这里），是因为条带宽度分配与
  /// 滚动落点都要问同一个问题；两处各写一遍必然会在某个边界上分叉。
  String? get effectiveSoloLaneId =>
      layout.soloLaneId != null && layout.soloLaneId == activeLaneId
      ? layout.soloLaneId
      : null;

  WorkspaceState copyWith({
    WorkspaceMode? mode,
    WorkspaceLayoutConfig? layout,
    WorkspaceBoardLayout? board,
    WorkspaceReaderTarget? Function()? readerTarget,
    Map<String, String>? activePanel,
    String? Function()? activeLaneId,
    WorkspaceInteractionSettings? interaction,
  }) {
    return WorkspaceState(
      mode: mode ?? this.mode,
      layout: layout ?? this.layout,
      board: board ?? this.board,
      readerTarget: readerTarget != null ? readerTarget() : this.readerTarget,
      activePanel: activePanel ?? this.activePanel,
      activeLaneId: activeLaneId != null ? activeLaneId() : this.activeLaneId,
      interaction: interaction ?? this.interaction,
    );
  }
}
