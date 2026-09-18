import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/discover_plugins_card.dart';
import 'package:zephyr/workspace/widgets/cards/download_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/favorite_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/history_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/local_folder_card.dart';

/// 卡片外壳交给卡片自己的那点上下文。
///
/// 卡片**只管画内容**：展开态、上移/下移、隐藏这些「在轨上的位置」的事，
/// 一律由宿主（面板）通过这个对象传进来 —— 于是同一张卡在泳道面板、
/// 四边栏抽屉、将来的浮动窗里都能用，位置语义不会漏进卡片的业务里。
class WorkspaceCardChrome {
  final bool expanded;
  final VoidCallback onToggle;

  /// 在所属面板里的显示下标与总数（用于把「上移 / 下移」置灰）。
  final int index;
  final int count;

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const WorkspaceCardChrome({
    required this.expanded,
    required this.onToggle,
    this.index = 0,
    this.count = 1,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });
}

typedef WorkspaceCardBuilder =
    Widget Function(BuildContext context, WorkspaceCardChrome chrome);

/// 一张卡的**定义** —— 与 neoview 的 `ReaderCardDefinition` 同构。
@immutable
class WorkspaceCardDefinition {
  final String id;
  final String title;
  final IconData icon;

  /// 默认住在哪个面板里。卡片是**跨呈现共享**的：泳道与四边栏读的是同一份定义。
  final String defaultPanelId;

  final int defaultOrder;
  final bool defaultVisible;
  final bool defaultExpanded;

  /// 是否允许用户把它收起来（`false` = 面板的固定主体）。
  final bool canHide;

  final WorkspaceCardBuilder builder;

  const WorkspaceCardDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.defaultPanelId,
    required this.defaultOrder,
    required this.builder,
    this.defaultVisible = true,
    this.defaultExpanded = true,
    this.canHide = true,
  });
}

/// 卡片注册表。**所有卡片 id 的唯一出处** ——
/// 面板、泳道、四边栏都从这里取，别在各处再写一遍卡片清单。
class WorkspaceCardRegistry {
  WorkspaceCardRegistry._();

  static final WorkspaceCardRegistry I = WorkspaceCardRegistry._();

  /// 卡片 id 常量（引用处用常量，避免字符串写错没人拦）。
  static const String favorite = 'favorite';
  static const String history = 'history';
  static const String download = 'download';
  static const String plugins = 'plugins';
  static const String localFolder = 'local_folder';

  late final List<WorkspaceCardDefinition> cards = List.unmodifiable([
    WorkspaceCardDefinition(
      id: favorite,
      title: '我的收藏',
      icon: Icons.bookmark_added_rounded,
      defaultPanelId: WorkspacePanelId.shelf,
      defaultOrder: 0,
      builder: (context, chrome) => FavoriteShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: history,
      title: '阅读历史',
      icon: Icons.history_rounded,
      defaultPanelId: WorkspacePanelId.shelf,
      defaultOrder: 1,
      builder: (context, chrome) => HistoryShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: download,
      title: '下载与离线',
      icon: Icons.download_done_rounded,
      defaultPanelId: WorkspacePanelId.shelf,
      defaultOrder: 2,
      builder: (context, chrome) => DownloadShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: plugins,
      title: '图源与扩展',
      icon: Icons.extension_rounded,
      defaultPanelId: WorkspacePanelId.sources,
      defaultOrder: 0,
      builder: (context, chrome) => DiscoverPluginsCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: localFolder,
      title: '本地漫画',
      icon: Icons.folder_copy_rounded,
      defaultPanelId: WorkspacePanelId.sources,
      defaultOrder: 1,
      builder: (context, chrome) => LocalFolderCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
  ]);

  WorkspaceCardDefinition? find(String cardId) {
    for (final card in cards) {
      if (card.id == cardId) return card;
    }
    return null;
  }

  /// 某个面板当前应当显示的卡片（已按 order 排序、已滤掉隐藏项）。
  List<WorkspaceCardDefinition> cardsForPanel(
    String panelId,
    WorkspaceBoardLayout board,
  ) {
    final visible = <String>[];
    for (final card in cards) {
      final layout = board.cardLayout(card.id);
      final effectivePanel = layout?.panelId ?? card.defaultPanelId;
      final isVisible = layout?.visible ?? card.defaultVisible;
      if (effectivePanel == panelId && isVisible) visible.add(card.id);
    }
    final ordered = sortByOrder(visible, (id) {
      final layout = board.cardLayout(id);
      return layout?.order ?? find(id)?.defaultOrder ?? 0;
    });
    return [
      for (final id in ordered)
        if (find(id) != null) find(id)!,
    ];
  }

  /// 一张卡**当前**的生效布局（没有覆盖项时用定义里的默认值）。
  CardLayout effectiveLayout(
    WorkspaceCardDefinition card,
    WorkspaceBoardLayout board,
  ) {
    return board.cardLayout(card.id) ??
        CardLayout(
          panelId: card.defaultPanelId,
          visible: card.defaultVisible,
          order: card.defaultOrder,
          expanded: card.defaultExpanded,
        );
  }

  /// 某个面板里**用户隐藏掉**的卡片（面板底部的「恢复」入口用）。
  List<WorkspaceCardDefinition> hiddenCardsForPanel(
    String panelId,
    WorkspaceBoardLayout board,
  ) {
    final result = <WorkspaceCardDefinition>[];
    for (final card in cards) {
      final layout = board.cardLayout(card.id);
      if (layout == null || layout.visible) continue;
      if (layout.panelId == panelId) result.add(card);
    }
    return result;
  }
}
