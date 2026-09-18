import 'package:flutter/foundation.dart';

/// 泳道 ID 常量
class LaneId {
  static const String left = 'left';
  static const String reader = 'reader';
  static const String right = 'right';

  static const List<String> defaultOrder = [left, reader, right];
}

/// 单个泳道的配置
@immutable
class LaneConfig {
  final double width;
  final double minWidth;
  final double maxWidth;
  final bool collapsed;
  final String title;

  const LaneConfig({
    required this.width,
    this.minWidth = 220.0,
    this.maxWidth = 750.0,
    this.collapsed = false,
    required this.title,
  });

  LaneConfig copyWith({
    double? width,
    double? minWidth,
    double? maxWidth,
    bool? collapsed,
    String? title,
  }) {
    return LaneConfig(
      width: width ?? this.width,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      collapsed: collapsed ?? this.collapsed,
      title: title ?? this.title,
    );
  }
}

/// 工作区整体布局配置
@immutable
class WorkspaceLayoutConfig {
  /// 折叠状态下的紧凑宽度（类似 NeoView 的 COLLAPSED_WIDTH = 44）
  static const double collapsedLaneWidth = 44.0;

  /// 泳道顺序
  final List<String> laneOrder;

  /// 各泳道配置
  final Map<String, LaneConfig> lanes;

  /// 当前独占（Solo）的泳道 ID，为空表示常规多栏并排
  final String? soloLaneId;

  /// 四边栏抽屉展开状态（在 edges 模式下有效）
  final bool edgeLeftOpen;
  final bool edgeRightOpen;
  final bool edgeTopOpen;
  final bool edgeBottomOpen;

  const WorkspaceLayoutConfig({
    required this.laneOrder,
    required this.lanes,
    this.soloLaneId,
    this.edgeLeftOpen = false,
    this.edgeRightOpen = false,
    this.edgeTopOpen = false,
    this.edgeBottomOpen = false,
  });

  factory WorkspaceLayoutConfig.defaults() {
    return const WorkspaceLayoutConfig(
      laneOrder: LaneId.defaultOrder,
      lanes: {
        LaneId.left: LaneConfig(
          width: 380.0,
          minWidth: 300.0,
          maxWidth: 700.0,
          title: '书架 (Bookshelf)',
        ),
        LaneId.reader: LaneConfig(
          width: 650.0,
          minWidth: 400.0,
          maxWidth: 2000.0,
          title: '阅读器 (Reader)',
        ),
        LaneId.right: LaneConfig(
          width: 350.0,
          minWidth: 280.0,
          maxWidth: 600.0,
          title: '发现与工具 (Tools)',
        ),
      },
    );
  }

  WorkspaceLayoutConfig copyWith({
    List<String>? laneOrder,
    Map<String, LaneConfig>? lanes,
    String? Function()? soloLaneId,
    bool? edgeLeftOpen,
    bool? edgeRightOpen,
    bool? edgeTopOpen,
    bool? edgeBottomOpen,
  }) {
    return WorkspaceLayoutConfig(
      laneOrder: laneOrder ?? this.laneOrder,
      lanes: lanes ?? this.lanes,
      soloLaneId: soloLaneId != null ? soloLaneId() : this.soloLaneId,
      edgeLeftOpen: edgeLeftOpen ?? this.edgeLeftOpen,
      edgeRightOpen: edgeRightOpen ?? this.edgeRightOpen,
      edgeTopOpen: edgeTopOpen ?? this.edgeTopOpen,
      edgeBottomOpen: edgeBottomOpen ?? this.edgeBottomOpen,
    );
  }
}
