import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_auxiliary_lane.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_bookshelf_lane.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_discover_lane.dart';

/// 一个**面板**的定义 —— 与 neoview 的 `ReaderPanelDefinition` 同构。
///
/// 面板是「泳道内部的一个功能位」，由泳道栏头的**图标轨**切换。
/// 它有两种内容来源，这是本项目对 neoview 的一处**有意扩展**：
///
/// - [acceptsCards] `true`：内容来自[卡片注册表]，卡片可以增删、重排、隐藏；
/// - [acceptsCards] `false`：内容是一整张**上游原版页面**（[page]）——
///   为了「上游 0 侵入 + 功能 100% 保留」，书架 / 发现 / 设置这三个上游页面
///   整页住进面板，而不是被拆成卡片重写一遍。
///
/// [exclusive] 表示内容自带 chrome（整页、或自己就是一块板），
/// 面板不再多画一行标题。
@immutable
class WorkspacePanelDefinition {
  final String id;
  final String title;
  final IconData icon;
  final WorkspacePanelSide side;

  /// 同侧内的默认次序（小者在前）。
  final int defaultOrder;

  final bool defaultVisible;

  /// 内容自带 chrome，面板不再画标题行。
  final bool exclusive;

  /// 是否允许用户把它拖到另一条泳道。
  final bool canMove;

  /// 是否允许用户把它从图标轨上隐藏（至少保留一个可见面板）。
  final bool canHide;

  /// 是否由卡片注册表填充。
  final bool acceptsCards;

  /// [acceptsCards] 为 `false` 时的整页内容。
  final WidgetBuilder? page;

  const WorkspacePanelDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.side,
    required this.defaultOrder,
    this.defaultVisible = true,
    this.exclusive = false,
    this.canMove = true,
    this.canHide = true,
    this.acceptsCards = true,
    this.page,
  });
}

/// 面板注册表：**面板清单的唯一出处**。
class WorkspacePanelRegistry {
  WorkspacePanelRegistry._();

  static final WorkspacePanelRegistry I = WorkspacePanelRegistry._();

  late final List<WorkspacePanelDefinition> panels = List.unmodifiable(
    <WorkspacePanelDefinition>[
      // ── 左泳道 ────────────────────────────────────────────────────────
      WorkspacePanelDefinition(
        id: WorkspacePanelId.bookshelf,
        title: '书架（上游原版）',
        icon: Icons.menu_book_rounded,
        side: WorkspacePanelSide.left,
        defaultOrder: 0,
        exclusive: true,
        canMove: false,
        canHide: false,
        acceptsCards: false,
        page: (_) => const EmbeddedBookshelfLane(),
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.favorite,
        title: '我的收藏',
        icon: Icons.bookmark_added_rounded,
        side: WorkspacePanelSide.left,
        defaultOrder: 1,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.history,
        title: '阅读历史',
        icon: Icons.history_rounded,
        side: WorkspacePanelSide.left,
        defaultOrder: 2,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.download,
        title: '下载与离线',
        icon: Icons.download_done_rounded,
        side: WorkspacePanelSide.left,
        defaultOrder: 3,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.shelf,
        title: '书架聚合卡片',
        icon: Icons.dashboard_customize_rounded,
        side: WorkspacePanelSide.left,
        defaultOrder: 4,
        defaultVisible: false,
      ),

      // ── 右泳道 ────────────────────────────────────────────────────────
      WorkspacePanelDefinition(
        id: WorkspacePanelId.discover,
        title: '发现（上游原版）',
        icon: Icons.explore_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 0,
        exclusive: true,
        canMove: false,
        canHide: false,
        acceptsCards: false,
        page: (_) => const EmbeddedDiscoverLane(),
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.fileManager,
        title: '文件管理',
        icon: Icons.folder_copy_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 1,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.pageList,
        title: '页面导航',
        icon: Icons.view_carousel_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 2,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.plugins,
        title: '图源扩展',
        icon: Icons.extension_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 3,
        exclusive: true,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.sources,
        title: '图源本地聚合',
        icon: Icons.auto_awesome_motion_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 4,
        defaultVisible: false,
      ),
      WorkspacePanelDefinition(
        id: WorkspacePanelId.tools,
        title: '工具与设置（上游原版）',
        icon: Icons.tune_rounded,
        side: WorkspacePanelSide.right,
        defaultOrder: 5,
        exclusive: true,
        canMove: false,
        canHide: false,
        acceptsCards: false,
        page: (_) => const EmbeddedAuxiliaryLane(),
      ),
    ],
  );

  WorkspacePanelDefinition? find(String panelId) {
    for (final panel in panels) {
      if (panel.id == panelId) return panel;
    }
    return null;
  }

  /// 某条泳道**当前应当显示的**面板（已排序、已滤掉隐藏项）；
  /// 与 neoview 一样，一个**一张卡都没有**的卡片面板不出现在图标轨上。
  List<WorkspacePanelDefinition> panelsForSide(
    WorkspacePanelSide side,
    WorkspaceBoardLayout board, {
    WorkspaceCardRegistry? cards,
  }) {
    final registry = cards ?? WorkspaceCardRegistry.I;
    final visible = <String>[];
    for (final panel in panels) {
      final effective = effectivePanelLayout(panel, board);
      if (effective.side != side || !effective.visible) continue;
      if (panel.acceptsCards &&
          registry.cardsForPanel(panel.id, board).isEmpty) {
        continue;
      }
      visible.add(panel.id);
    }
    final ordered = sortByOrder(visible, (id) {
      final panel = find(id);
      return panel == null ? 0 : effectivePanelLayout(panel, board).order;
    });
    return [
      for (final id in ordered)
        if (find(id) != null) find(id)!,
    ];
  }

  /// 一个面板**当前**的生效布局（没有覆盖项时用定义里的默认值）。
  PanelLayout effectivePanelLayout(
    WorkspacePanelDefinition panel,
    WorkspaceBoardLayout board,
  ) {
    return board.panelLayout(panel.id) ??
        PanelLayout(
          visible: panel.defaultVisible,
          order: panel.defaultOrder,
          side: panel.side,
        );
  }

  /// 图标轨上被用户**隐藏掉**的面板（恢复入口用）。
  List<WorkspacePanelDefinition> hiddenPanels(WorkspaceBoardLayout board) {
    return [
      for (final panel in panels)
        if (panel.canHide && !effectivePanelLayout(panel, board).visible) panel,
    ];
  }
}
