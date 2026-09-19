import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/discover_plugins_card.dart';
import 'package:zephyr/workspace/widgets/cards/download_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/favorite_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/history_shelf_card.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_card.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_card.dart';
import 'package:zephyr/workspace/widgets/cards/book_information_card.dart';
import 'package:zephyr/workspace/widgets/cards/image_information_card.dart';
import 'package:zephyr/workspace/widgets/cards/storage_information_card.dart';
import 'package:zephyr/workspace/widgets/cards/time_information_card.dart';
import 'package:zephyr/workspace/widgets/cards/preload_status_card.dart';
import 'package:zephyr/workspace/widgets/cards/switch_toast_card.dart';
import 'package:zephyr/workspace/widgets/cards/daily_trend_card.dart';
import 'package:zephyr/workspace/widgets/cards/reading_streak_card.dart';
import 'package:zephyr/workspace/widgets/cards/reading_heatmap_card.dart';
import 'package:zephyr/workspace/widgets/cards/source_breakdown_card.dart';

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

  /// 是否为独占面板模式（卡片占满整个面板，不渲染折叠外壳与固定高度限制）
  final bool standalone;

  const WorkspaceCardChrome({
    required this.expanded,
    required this.onToggle,
    this.index = 0,
    this.count = 1,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.standalone = false,
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
  static const String pageList = 'page_list';

  /// 控制面板（N-17）：切换提示
  static const String switchToast = 'switch_toast';

  /// 信息面板（叠加）五张卡 —— 与 neoview `info` 面板的同名卡片一一对应。
  static const String bookInformation = 'book_information';
  static const String imageInformation = 'image_information';
  static const String storageInformation = 'storage_information';
  static const String timeInformation = 'time_information';
  static const String preloadStatus = 'preload_status';

  /// 洞察面板四张卡 —— 与 neoview `insights` 面板的同名卡片一一对应。
  static const String dailyTrend = 'daily_trend';
  static const String readingStreak = 'reading_streak';
  static const String readingHeatmap = 'reading_heatmap';
  static const String sourceBreakdown = 'source_breakdown';

  late final List<WorkspaceCardDefinition> cards = List.unmodifiable([
    WorkspaceCardDefinition(
      id: favorite,
      title: '书签',
      icon: Icons.bookmark_added_rounded,
      defaultPanelId: WorkspacePanelId.favorite,
      defaultOrder: 0,
      builder: (context, chrome) => FavoriteShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: history,
      title: '阅读历史',
      icon: Icons.history_rounded,
      defaultPanelId: WorkspacePanelId.history,
      defaultOrder: 0,
      builder: (context, chrome) => HistoryShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: download,
      title: '下载与离线',
      icon: Icons.download_done_rounded,
      defaultPanelId: WorkspacePanelId.download,
      defaultOrder: 0,
      builder: (context, chrome) => DownloadShelfCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: plugins,
      title: '图源与扩展',
      icon: Icons.extension_rounded,
      defaultPanelId: WorkspacePanelId.plugins,
      defaultOrder: 0,
      builder: (context, chrome) => DiscoverPluginsCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: localFolder,
      title: '本地漫画',
      icon: Icons.folder_copy_rounded,
      defaultPanelId: WorkspacePanelId.fileManager,
      defaultOrder: 0,
      builder: (context, chrome) => FileManagerCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: pageList,
      title: '页面导航',
      icon: Icons.view_carousel_rounded,
      defaultPanelId: WorkspacePanelId.pageList,
      defaultOrder: 0,
      builder: (context, chrome) => PageListCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    // ── 信息面板（叠加在阅读器视口右缘，mimage 式） ──────────────────────
    // 面板本身不在面板注册表里（它不住在泳道页签轨上），
    // 但卡片的归属 / 展开 / 次序 / 隐藏仍按 `WorkspacePanelId.info` 记账。
    WorkspaceCardDefinition(
      id: bookInformation,
      title: '书籍信息',
      icon: Icons.menu_book_rounded,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 0,
      // 信息面板的固定主体：收掉它面板就空了，Neo 同款纪律（canHide: false）。
      canHide: false,
      builder: (context, chrome) => BookInformationCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: imageInformation,
      title: '图像信息',
      icon: Icons.image_rounded,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 1,
      builder: (context, chrome) => ImageInformationCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: storageInformation,
      title: '存储信息',
      icon: Icons.sd_storage_rounded,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 2,
      builder: (context, chrome) => StorageInformationCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: timeInformation,
      title: '时间信息',
      icon: Icons.schedule_rounded,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 3,
      builder: (context, chrome) => TimeInformationCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: preloadStatus,
      title: '预加载状态',
      icon: Icons.bolt_rounded,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 4,
      builder: (context, chrome) => PreloadStatusCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: switchToast,
      title: '切换提示',
      icon: Icons.notifications_active_rounded,
      defaultPanelId: WorkspacePanelId.control,
      defaultOrder: 0,
      builder: (context, chrome) => SwitchToastCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    // ── 洞察 ──────────────────────────────────────────────────────────────
    // 四张卡都只在**有历史**时才有内容，所以窗口为空时各自画一行提示而不是空板。
    // 归属刻意不散到 favorite / history 那些独占面板里：洞察是「读历史的另一双眼睛」，
    // 与 neoview 一样独立成一张面板，用户想拆再拖。
    WorkspaceCardDefinition(
      id: dailyTrend,
      title: '近 7 日阅读趋势',
      icon: Icons.trending_up_rounded,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 0,
      builder: (context, chrome) => DailyTrendCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: readingStreak,
      title: '连续阅读',
      icon: Icons.local_fire_department_rounded,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 1,
      builder: (context, chrome) => ReadingStreakCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: readingHeatmap,
      title: '阅读热力',
      icon: Icons.calendar_month_rounded,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 2,
      builder: (context, chrome) => ReadingHeatmapCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: sourceBreakdown,
      title: '来源拆分',
      icon: Icons.pie_chart_outline_rounded,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 3,
      builder: (context, chrome) => SourceBreakdownCard(
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
