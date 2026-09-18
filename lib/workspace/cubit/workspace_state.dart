import 'package:flutter/foundation.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
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

  const WorkspaceState({
    required this.mode,
    required this.layout,
    this.board = const WorkspaceBoardLayout(),
    this.readerTarget,
    this.activePanel = const <String, String>{},
  });

  factory WorkspaceState.initial() {
    return WorkspaceState(
      mode: WorkspaceMode.swimlane,
      layout: WorkspaceLayoutConfig.defaults(),
      // 布局记账留空 —— 空账 = 全部用注册表里的默认值，
      // 于是「加卡片 / 改默认面板」不需要写迁移，也不会被旧记录挡住。
    );
  }

  WorkspaceState copyWith({
    WorkspaceMode? mode,
    WorkspaceLayoutConfig? layout,
    WorkspaceBoardLayout? board,
    WorkspaceReaderTarget? Function()? readerTarget,
    Map<String, String>? activePanel,
  }) {
    return WorkspaceState(
      mode: mode ?? this.mode,
      layout: layout ?? this.layout,
      board: board ?? this.board,
      readerTarget: readerTarget != null ? readerTarget() : this.readerTarget,
      activePanel: activePanel ?? this.activePanel,
    );
  }
}
