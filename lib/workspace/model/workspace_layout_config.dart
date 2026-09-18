// 本文件**刻意不 import Flutter**（不 import `dart:ui`），与
// `workspace_board_layout.dart` 同一纪律。原因不是洁癖：条带的宽度分配
// （`WorkspaceStripMetrics`）只有拿得到这里的 `LaneConfig` 才能被算出来，
// 而本机 `flutter test` 起不来 —— 判据只能靠 `dart run` 的**纯 Dart VM 脚本**，
// 它**加载不了** `package:flutter/foundation.dart`（`dart:ui` 缺失）。
// 所以这里不能用 foundation 的 `@immutable`：加上它，几何判据就永久失明。
// 代价仅仅是少一个 lint 标注，所有字段本来就是 final。

import 'package:zephyr/workspace/model/workspace_panel_bar.dart';

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

  /// 这条泳道的**面板操作栏**记账（模式 / 停靠边 / 悬浮位置 / 是否限制在泳道内）。
  ///
  /// 它跟着**泳道**存，而不是全局一份：左右两条泳道各有一个面板栏，
  /// 用户可以只把其中一条拖成竖轨、另一条留在栏头里。
  final PanelBarLayout panelBar;

  const LaneConfig({
    required this.width,
    this.widthRatio,
    this.minWidth = 220.0,
    this.maxWidth = 750.0,
    this.collapsed = false,
    required this.title,
    this.panelBar = const PanelBarLayout(),
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
    PanelBarLayout? panelBar,
  }) {
    return LaneConfig(
      width: width ?? this.width,
      widthRatio: widthRatio != null ? widthRatio() : this.widthRatio,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      collapsed: collapsed ?? this.collapsed,
      title: title ?? this.title,
      panelBar: panelBar ?? this.panelBar,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    if (widthRatio != null) 'widthRatio': widthRatio,
    'minWidth': minWidth,
    'maxWidth': maxWidth,
    'collapsed': collapsed,
    'title': title,
    'panelBar': panelBar.toJson(),
  };

  /// 任何一项缺失/非法都**只退回该项**的 [fallback]，不影响同一泳道里的其它项，
  /// 也不影响别的泳道 —— 配置文件被手改坏一个数字，不该让整套布局回到出厂。
  factory LaneConfig.fromJson(
    Map<String, Object?> json, {
    required LaneConfig fallback,
  }) {
    return LaneConfig(
      width: json['width'] is num
          ? (json['width']! as num).toDouble()
          : fallback.width,
      widthRatio: json['widthRatio'] is num
          ? (json['widthRatio']! as num).toDouble()
          : fallback.widthRatio,
      minWidth: json['minWidth'] is num
          ? (json['minWidth']! as num).toDouble()
          : fallback.minWidth,
      maxWidth: json['maxWidth'] is num
          ? (json['maxWidth']! as num).toDouble()
          : fallback.maxWidth,
      collapsed: json['collapsed'] is bool
          ? json['collapsed']! as bool
          : fallback.collapsed,
      title: json['title'] is String ? json['title']! as String : fallback.title,
      panelBar: json['panelBar'] is Map
          ? PanelBarLayout.fromJson(
              (json['panelBar']! as Map).cast<String, Object?>(),
            )
          : fallback.panelBar,
    );
  }
}

/// 工作区整体布局配置
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

  Map<String, Object?> toJson() => <String, Object?>{
    'laneOrder': laneOrder,
    'lanes': <String, Object?>{
      for (final entry in lanes.entries) entry.key: entry.value.toJson(),
    },
    'soloLaneId': soloLaneId,
    'edgeLeftOpen': edgeLeftOpen,
    'edgeRightOpen': edgeRightOpen,
    'edgeTopOpen': edgeTopOpen,
    'edgeBottomOpen': edgeBottomOpen,
  };

  /// 从 JSON 还原几何记账。
  ///
  /// 两条**归一化**（neoview：`The persisted order is generic and must be
  /// normalized so future lane identifiers can be introduced without replacing
  /// the workspace model`）：
  ///
  /// 1. `laneOrder` 里**未知的泳道丢掉、缺的泳道按默认顺序补到末尾**。
  ///    这样「将来新增一条泳道」不需要写迁移，老配置文件也不会因为少一个 id
  ///    就让新泳道在界面上凭空消失；反过来，把某个泳道下线之后，
  ///    旧的 `laneOrder` 里残留的 id 也不会在条带上留一个空槽。
  /// 2. 某条泳道的配置块非法/缺失时，**按默认值补一条**，而不是把整组布局判废。
  factory WorkspaceLayoutConfig.fromJson(Map<String, Object?> json) {
    final defaults = WorkspaceLayoutConfig.defaults();

    final rawOrder = json['laneOrder'];
    final persisted = <String>[
      if (rawOrder is List)
        for (final value in rawOrder)
          if (value is String) value,
    ];
    final laneOrder = <String>[
      for (final id in persisted)
        if (defaults.lanes.containsKey(id)) id,
      for (final id in defaults.laneOrder)
        if (!persisted.contains(id)) id,
    ];

    final rawLanes = json['lanes'];
    final lanes = <String, LaneConfig>{};
    for (final id in defaults.lanes.keys) {
      final fallback = defaults.lanes[id]!;
      final raw = rawLanes is Map ? rawLanes[id] : null;
      lanes[id] = raw is Map
          ? LaneConfig.fromJson(raw.cast<String, Object?>(), fallback: fallback)
          : fallback;
    }

    final rawSolo = json['soloLaneId'];
    // 指向一条**已经不存在**的泳道的 solo 记录要丢掉：留着它会让条带
    // 永远算不出一条独占泳道，表现为「所有泳道都变窄了」而没有任何解释。
    final soloLaneId = rawSolo is String && lanes.containsKey(rawSolo)
        ? rawSolo
        : null;

    bool flag(String key) =>
        json[key] is bool ? json[key]! as bool : false;

    return WorkspaceLayoutConfig(
      laneOrder: laneOrder,
      lanes: lanes,
      soloLaneId: soloLaneId,
      edgeLeftOpen: flag('edgeLeftOpen'),
      edgeRightOpen: flag('edgeRightOpen'),
      edgeTopOpen: flag('edgeTopOpen'),
      edgeBottomOpen: flag('edgeBottomOpen'),
    );
  }
}
