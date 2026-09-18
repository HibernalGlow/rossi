import 'package:flutter/foundation.dart';

/// 泳道 ID 常量
class LaneId {
  /// 左侧面板泳道：完整复用上游 `BookshelfPage`
  static const String left = 'left';

  /// 中央**阅读器**泳道：上游原版 `ComicReadPage` 就住在这一条里
  static const String reader = 'reader';

  /// 右侧面板泳道：发现 / 图源 / 工具
  static const String right = 'right';

  static const List<String> defaultOrder = [left, reader, right];
}

/// 单个泳道的几何配置。
///
/// 宽度的计量单位**按泳道性质分开**（neoview 契约）：
/// - 面板泳道用**绝对像素**，且**不按当前窗口宽夹取** —— 窗口变窄时宁可横向滚动；
/// - 阅读器泳道用**视口比例**，否则横竖屏切换 / 改窗口大小会把它撑得比工作区还宽。
@immutable
class LaneConfig {
  /// 面板泳道的宽度（绝对像素）；阅读器泳道只把它当**标称值**用于展示。
  final double width;

  /// 阅读器泳道的宽度比例（`viewportWidth * widthRatio`）。
  /// 面板泳道为 `null`。
  final double? widthRatio;

  final double minWidth;
  final double maxWidth;
  final bool collapsed;
  final String title;

  const LaneConfig({
    required this.width,
    this.widthRatio,
    this.minWidth = 220.0,
    this.maxWidth = 750.0,
    this.collapsed = false,
    required this.title,
  });

  /// 本泳道在给定视口下的实际宽度。
  double resolveWidth(double viewportWidth) {
    final ratio = widthRatio;
    final raw = ratio != null && viewportWidth > 0
        ? viewportWidth * ratio
        : width;
    return raw.clamp(minWidth, maxWidth);
  }

  LaneConfig copyWith({
    double? width,
    double? Function()? widthRatio,
    double? minWidth,
    double? maxWidth,
    bool? collapsed,
    String? title,
  }) {
    return LaneConfig(
      width: width ?? this.width,
      widthRatio: widthRatio != null ? widthRatio() : this.widthRatio,
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
  /// 折叠状态下的紧凑宽度（neoview 的 `COLLAPSED_WIDTH = 44`）
  static const double collapsedLaneWidth = 44.0;

  /// 泳道顺序（持久化的是**通用顺序**，新增泳道标识不需要换模型）
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
        // 阅读器：宽度是视口的一半，最少 400、最多 2000 —— 拖宽改的是比例本身，
        // 所以改窗口大小不会把记录下来的「用户想要多宽」弄丢。
        LaneId.reader: LaneConfig(
          width: 650.0,
          widthRatio: 0.5,
          minWidth: 400.0,
          maxWidth: 2000.0,
          title: '阅读器 (Reader)',
        ),
        LaneId.right: LaneConfig(
          width: 360.0,
          minWidth: 280.0,
          maxWidth: 620.0,
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
