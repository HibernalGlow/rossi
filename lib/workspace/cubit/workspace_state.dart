import 'package:flutter/foundation.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

/// 面板泳道里可切换的面板标识。
class PanelId {
  /// 上游 `DiscoverPage`（完整复用）
  static const String discover = 'discover';

  /// 图源与本地：真实卡片（插件列表 + 本地目录），不是整页复用
  static const String sources = 'sources';

  /// 上游 `MorePage`（完整复用：外观 / 同步 / 存储 / 关于）
  static const String tools = 'tools';
}

@immutable
class WorkspaceState {
  final WorkspaceMode mode;
  final WorkspaceLayoutConfig layout;
  final Map<String, bool> cardExpanded;

  /// 阅读器泳道当前打开的目标；`null` = 泳道空闲（显示空态画板）。
  final WorkspaceReaderTarget? readerTarget;

  /// 各面板泳道当前激活的面板 ID（每条泳道**各自独立**，互不覆盖）。
  final Map<String, String> activePanel;

  const WorkspaceState({
    required this.mode,
    required this.layout,
    required this.cardExpanded,
    this.readerTarget,
    this.activePanel = const <String, String>{},
  });

  factory WorkspaceState.initial() {
    return WorkspaceState(
      mode: WorkspaceMode.swimlane,
      layout: WorkspaceLayoutConfig.defaults(),
      cardExpanded: const {
        'favorite': true,
        'history': true,
        'download': true,
        'discover_plugins': true,
        'discover_tags': false,
        'local_tree': true,
        'system_status': true,
      },
      activePanel: const {LaneId.right: PanelId.discover},
    );
  }

  WorkspaceState copyWith({
    WorkspaceMode? mode,
    WorkspaceLayoutConfig? layout,
    Map<String, bool>? cardExpanded,
    WorkspaceReaderTarget? Function()? readerTarget,
    Map<String, String>? activePanel,
  }) {
    return WorkspaceState(
      mode: mode ?? this.mode,
      layout: layout ?? this.layout,
      cardExpanded: cardExpanded ?? this.cardExpanded,
      readerTarget: readerTarget != null ? readerTarget() : this.readerTarget,
      activePanel: activePanel ?? this.activePanel,
    );
  }
}
