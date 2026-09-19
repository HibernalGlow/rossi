import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

// 本文件**刻意不 import Flutter**：快照的正确性只能靠 JSON 往返来钉，
// 而它同时是「重启之后回来的是不是同一套布局」这个问题的**唯一**判据 ——
// 判据在 `dart run test/workspace/layout_snapshot_check.dart`。

/// 工作台布局的**完整快照**（存进磁盘的那一份）。
///
/// ## 什么进快照、什么**刻意不进**
///
/// 进（neoview `Persistence boundary` 列的那一组）：
/// 呈现模式、泳道顺序、面板宽度 / Reader 宽度比例、折叠状态、激活面板、
/// 状态栏位（四边栏抽屉）、**激活泳道**、Reader solo 偏好、
/// Reader 悬停聚焦行为与三个延时、每条泳道的面板操作栏记账、
/// 面板与卡片的布局记账。
///
/// **不进**（都是「这一秒的画面」，不是「用户的偏好」）：
///
/// - **实时滚动偏移**：它由几何（[WorkspaceLaneFocusGeometry]）在每次激活时
///   算出来。存下来反而会让「上次拖到一半的窗口宽度」决定这次的落点，
///   比不存更难解释。
/// - **瞬态的边缘揭示**：契约原话 `Transient edge reveal and live scroll
///   offset are not persisted`。揭示是「指针正停在边上」的后果，
///   指针不在的时候它不该存在。
/// - **当前在读的那一本**：`WorkspaceReaderTarget` 里带着 cubit 与页面参数，
///   「冷启动要不要恢复上次那本」是**阅读历史**的职责，不是布局的；
///   混进来会让「重置布局」这个动作用户意料不到地把书也关掉。
class WorkspaceLayoutSnapshot {
  /// 快照格式版本。
  ///
  /// 它只用于**识别**：不认识的版本按「读不出来」处理（回默认），
  /// 而不是猜着解析。字段级的兼容由各 `fromJson` 自己兜底（缺项退回默认），
  /// 所以真正需要动它就是**语义变了**的时候（例如某个字段的单位从像素改成比例）。
  static const int currentVersion = 1;

  final WorkspaceMode mode;
  final WorkspaceLayoutConfig layout;
  final WorkspaceBoardLayout board;

  /// 每条泳道各自**激活的面板**（`泳道 id → 面板 id`）。
  final Map<String, String> activePanel;

  /// 当前激活的泳道。
  final String? activeLaneId;

  final WorkspaceInteractionSettings interaction;

  const WorkspaceLayoutSnapshot({
    required this.mode,
    required this.layout,
    this.board = const WorkspaceBoardLayout(),
    this.activePanel = const <String, String>{},
    this.activeLaneId,
    this.interaction = const WorkspaceInteractionSettings(),
  });

  factory WorkspaceLayoutSnapshot.defaults() => WorkspaceLayoutSnapshot(
    mode: WorkspaceMode.swimlane,
    layout: WorkspaceLayoutConfig.defaults(),
  );

  /// 换呈现模式，其余记账原样保留。
  WorkspaceLayoutSnapshot copyWithMode(WorkspaceMode mode) {
    return WorkspaceLayoutSnapshot(
      mode: mode,
      layout: layout,
      board: board,
      activePanel: activePanel,
      activeLaneId: activeLaneId,
      interaction: interaction,
    );
  }

  /// 换交互与唤出区，其余记账原样保留。
  WorkspaceLayoutSnapshot copyWithInteraction(
    WorkspaceInteractionSettings interaction,
  ) {
    return WorkspaceLayoutSnapshot(
      mode: mode,
      layout: layout,
      board: board,
      activePanel: activePanel,
      activeLaneId: activeLaneId,
      interaction: interaction,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'mode': mode.name,
    'layout': layout.toJson(),
    'board': board.toJson(),
    'activePanel': activePanel,
    'activeLaneId': activeLaneId,
    'interaction': interaction.toJson(),
  };

  /// 从 JSON 还原。
  ///
  /// **任何一块坏掉都只影响那一块**：模式不认识就退回 `swimlane`、布局块不是
  /// 对象就用默认布局、激活泳道指向一条不存在的泳道就丢掉它。
  /// 顶层整体不是对象 / 版本不认识时才回默认 —— 那时确实没有可用的信息。
  factory WorkspaceLayoutSnapshot.fromJson(Map<String, Object?> json) {
    final defaults = WorkspaceLayoutSnapshot.defaults();

    final rawLayout = json['layout'];
    final layout = rawLayout is Map
        ? WorkspaceLayoutConfig.fromJson(rawLayout.cast<String, Object?>())
        : defaults.layout;

    final rawBoard = json['board'];
    final board = rawBoard is Map
        ? WorkspaceBoardLayout.fromJson(rawBoard.cast<String, Object?>())
        : defaults.board;

    final activePanel = <String, String>{};
    final rawActive = json['activePanel'];
    if (rawActive is Map) {
      for (final entry in rawActive.entries) {
        final laneId = entry.key;
        final panelId = entry.value;
        if (laneId is! String || panelId is! String) continue;
        // 指向一条不存在的泳道 / 空面板 id 的记录丢掉：留着它会让
        // 那条泳道永远显示一个「找不到的面板」，而且没有恢复入口。
        if (!layout.lanes.containsKey(laneId) || panelId.isEmpty) continue;
        activePanel[laneId] = panelId;
      }
    }

    final rawLane = json['activeLaneId'];
    final activeLaneId = rawLane is String && layout.lanes.containsKey(rawLane)
        ? rawLane
        : null;

    final rawInteraction = json['interaction'];
    final interaction = rawInteraction is Map
        ? WorkspaceInteractionSettings.fromJson(
            rawInteraction.cast<String, Object?>(),
          )
        : defaults.interaction;

    return WorkspaceLayoutSnapshot(
      mode: _parseMode(json['mode']),
      layout: layout,
      board: board,
      activePanel: activePanel,
      activeLaneId: activeLaneId,
      interaction: interaction,
    );
  }

  static WorkspaceMode _parseMode(Object? value) {
    for (final mode in WorkspaceMode.values) {
      if (mode.name == value) return mode;
    }
    return WorkspaceMode.swimlane;
  }

  /// 顶层入口：先看版本，再看形状。
  static Map<String, Object?>? decode(Object? decoded) {
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    if (json['version'] != currentVersion) return null;
    return json;
  }
}
