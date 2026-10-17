import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/cards/reading_activity_card.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/discover_plugins_card.dart';
import 'package:zephyr/workspace/widgets/cards/plugin_status_card.dart';
import 'package:zephyr/workspace/widgets/cards/plugin_shortcuts_card.dart';
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
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/workspace/widgets/cards/image_tuning_card.dart';
import 'package:zephyr/workspace/widgets/cards/super_resolution_card.dart';
import 'package:zephyr/workspace/widgets/cards/switch_toast_card.dart';
import 'package:zephyr/workspace/widgets/cards/translate_card.dart';
import 'package:zephyr/workspace/widgets/cards/daily_trend_card.dart';
import 'package:zephyr/workspace/widgets/cards/reading_streak_card.dart';
import 'package:zephyr/workspace/widgets/cards/reading_heatmap_card.dart';
import 'package:zephyr/workspace/widgets/cards/source_breakdown_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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

  /// 这张卡在**当前这台机器**上能不能用（`false` = 灰显 + 一颗 [unsupportedHint] tag）。
  final bool supported;

  /// [supported] 为 `false` 时挂在标题行上的那句说明（例如「仅桌面」）。
  final String? unsupportedHint;

  /// 卡片在网格布局中的跨度宽度（1..4，默认 4 为全宽）。
  final int widthSpan;

  /// 卡片在网格布局中的跨度高度（1..4，默认 2 为双高，1 为紧凑/半高）。
  final int heightSpan;

  /// 是否处于编辑排版模式。
  final bool isEditing;

  /// 调整卡片尺寸的回调。
  final void Function(int widthSpan, int heightSpan)? onResize;

  const WorkspaceCardChrome({
    required this.expanded,
    required this.onToggle,
    this.index = 0,
    this.count = 1,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.standalone = false,
    this.supported = true,
    this.unsupportedHint,
    this.widthSpan = 4,
    this.heightSpan = 2,
    this.isEditing = false,
    this.onResize,
  });
}

typedef WorkspaceCardBuilder =
    Widget Function(BuildContext context, WorkspaceCardChrome chrome);

/// 一张卡的**定义** —— 与 neoview 的 `ReaderCardDefinition` 同构。
@immutable
class WorkspaceCardDefinition {
  final String id;
  final String title;
  final Glyph icon;

  /// 默认住在哪个面板里。卡片是**跨呈现共享**的：泳道与四边栏读的是同一份定义。
  final String defaultPanelId;

  final int defaultOrder;
  final bool defaultVisible;
  final bool defaultExpanded;

  /// 默认跨度宽度（1..4）。
  final int defaultWidthSpan;

  /// 默认跨度高度（1..4）。
  final int defaultHeightSpan;

  /// 卡片内容需要的最小宽度；窄面板自动减少同一行的卡片数。
  final double minimumWidth;

  /// 是否为无常驻标题栏的 MD3 小组件（日常态隐藏标题行，右键/长按弹菜单，编辑态显示拖拽条）。
  final bool headerless;

  /// 是否在默认全宽排版下自动撑满面板的剩余可视高度（例如页面导航的中间展示区）。
  final bool fillRemainingHeight;

  /// 紧凑型工具条卡片在默认未手动拉高时的像素高度（避免工具条占用整格 96dp 高度）。
  final double? compactMainAxisExtent;

  /// 是否允许用户把它收起来（`false` = 面板的固定主体）。
  final bool canHide;

  /// 这张卡在**当前这台机器**上能不能用；`null` = 哪儿都能用。
  final bool Function()? supportedHere;

  /// [supportedHere] 判不动时挂在标题行上的那句说明（例如「仅桌面」）。
  final String? unsupportedHint;

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
    this.defaultWidthSpan = 4,
    this.defaultHeightSpan = 2,
    this.minimumWidth = 240,
    this.headerless = false,
    this.fillRemainingHeight = false,
    this.compactMainAxisExtent,
    this.canHide = true,
    this.supportedHere,
    this.unsupportedHint,
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

  /// 页面导航面板三组件：搜索栏、中间展示栏（pageList）、底部跳转栏
  static const String pageListSearch = 'page_list_search';
  static const String pageList = 'page_list';
  static const String pageListJump = 'page_list_jump';

  /// 控制面板（N-17）：切换提示
  static const String switchToast = 'switch_toast';

  /// 控制面板：从阅读设置搬进来的三节（超分 / 翻译 / 画面调节）
  static const String superResolution = 'super_resolution';
  static const String translate = 'translate';
  static const String imageTuning = 'image_tuning';

  /// 信息面板（叠加）五张卡 —— 与 neoview `info` 面板的同名卡片一一对应。
  static const String bookInformation = 'book_information';
  static const String imageInformation = 'image_information';
  static const String storageInformation = 'storage_information';
  static const String timeInformation = 'time_information';
  static const String preloadStatus = 'preload_status';

  /// 发现面板的两张插件小组件卡
  static const String pluginStatus = 'plugin_status';
  static const String pluginShortcuts = 'plugin_shortcuts';

  static const String readingOverview = 'reading_overview';
  static const String activityCalendar = 'activity_calendar';
  static const String weeklyRhythm = 'weekly_rhythm';
  static const String readingPeriods = 'reading_periods';

  /// 洞察面板的原四张卡 —— 与 neoview `insights` 面板的同名卡片一一对应。
  static const String dailyTrend = 'daily_trend';
  static const String readingStreak = 'reading_streak';
  static const String readingHeatmap = 'reading_heatmap';
  static const String sourceBreakdown = 'source_breakdown';

  late final List<WorkspaceCardDefinition> cards = List.unmodifiable([
    WorkspaceCardDefinition(
      id: favorite,
      title: t.workspace.bookmarks,
      icon: AppGlyphs.bookmark,
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
      title: t.workspace.readingHistory,
      icon: AppGlyphs.history,
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
      title: t.workspace.downloadsOffline,
      icon: AppGlyphs.downloadDone,
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
      title: t.workspace.imageSources,
      icon: AppGlyphs.puzzle,
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
      title: t.workspace.localComics,
      icon: AppGlyphs.folderCopy,
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
    // ── 页面导航面板：无标题栏 MD3 小组件三件套（搜索栏 / 展示栏 / 跳转栏） ──
    WorkspaceCardDefinition(
      id: pageListSearch,
      title: t.workspace.searchField,
      icon: AppGlyphs.search,
      defaultPanelId: WorkspacePanelId.pageList,
      defaultOrder: -1,
      defaultWidthSpan: 4,
      defaultHeightSpan: 1,
      minimumWidth: 200,
      headerless: true,
      compactMainAxisExtent: 50,
      builder: (context, chrome) => PageListSearchCard(
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
      title: t.workspace.pageNavigation,
      icon: AppGlyphs.cardMedium,
      defaultPanelId: WorkspacePanelId.pageList,
      defaultOrder: 0,
      defaultWidthSpan: 4,
      defaultHeightSpan: 5,
      minimumWidth: 200,
      headerless: true,
      fillRemainingHeight: true,
      builder: (context, chrome) => PageListCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: pageListJump,
      title: t.workspace.jumpBar,
      icon: AppGlyphs.linearScale,
      defaultPanelId: WorkspacePanelId.pageList,
      defaultOrder: 1,
      defaultWidthSpan: 4,
      defaultHeightSpan: 1,
      minimumWidth: 200,
      headerless: true,
      compactMainAxisExtent: 46,
      builder: (context, chrome) => PageListJumpCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    // ── 信息面板（右栏停靠页签，neoview `panel("info")` 同款） ────────────
    // 卡片面板规则照旧：归属 / 展开 / 次序 / 隐藏都按 `WorkspacePanelId.info` 记账。
    WorkspaceCardDefinition(
      id: bookInformation,
      title: t.workspace.bookInformation,
      icon: AppGlyphs.book,
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
      title: t.workspace.imageInformation,
      icon: AppGlyphs.photos,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 1,
      defaultWidthSpan: 2,
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
      title: t.workspace.storageInformation,
      icon: AppGlyphs.storage,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 2,
      defaultWidthSpan: 2,
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
      title: t.workspace.timeInformation,
      icon: AppGlyphs.clock,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 3,
      defaultWidthSpan: 2,
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
      title: t.workspace.preloadStatus,
      icon: AppGlyphs.bolt,
      defaultPanelId: WorkspacePanelId.info,
      defaultOrder: 4,
      defaultWidthSpan: 2,
      builder: (context, chrome) => PreloadStatusCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    // ── 发现面板：只注册插件小组件；上游发现页是面板本身 ────────────────
    WorkspaceCardDefinition(
      id: pluginStatus,
      title: t.workspace.pluginRunState,
      icon: AppGlyphs.puzzle,
      defaultPanelId: WorkspacePanelId.discover,
      defaultOrder: 1,
      defaultVisible: false,
      defaultWidthSpan: 4,
      defaultHeightSpan: 3,
      minimumWidth: 260,
      builder: (context, chrome) => PluginStatusCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
      ),
    ),
    WorkspaceCardDefinition(
      id: pluginShortcuts,
      title: t.workspace.sourceShortcuts,
      icon: AppGlyphs.apps,
      defaultPanelId: WorkspacePanelId.discover,
      defaultOrder: 2,
      defaultVisible: false,
      defaultWidthSpan: 4,
      defaultHeightSpan: 2,
      minimumWidth: 240,
      builder: (context, chrome) => PluginShortcutsCard(
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
      title: t.workspace.switchToast,
      icon: AppGlyphs.bell,
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
    // ── 控制面板：阅读设置里「读的时候真会去拨」的那三节 ────────────────
    // 卡片与阅读设置面板渲染的是**同一批** section widget，读写的是同一份
    // 存储（超分/翻译在 SharedPreferences + 各自的 ChangeNotifier，
    // 画面调节在 app 级 GlobalSettingCubit）—— 所以两边不需要任何同步代码。
    WorkspaceCardDefinition(
      id: superResolution,
      title: 'AI 超分辨率',
      icon: AppGlyphs.sparkle,
      defaultPanelId: WorkspacePanelId.control,
      defaultOrder: 1,
      defaultWidthSpan: 2,
      minimumWidth: 320,
      builder: (context, chrome) => SuperResolutionCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
        disabledHint: chrome.supported ? null : chrome.unsupportedHint,
      ),
    ),
    WorkspaceCardDefinition(
      id: translate,
      title: '翻译',
      icon: AppGlyphs.translate,
      defaultPanelId: WorkspacePanelId.control,
      defaultOrder: 2,
      defaultWidthSpan: 2,
      minimumWidth: 320,
      // Android / iOS 是 ADR-0018 §决定 6 的排除项：`ort` 那两端没注册加速器 EP，
      // 识别模型还是 fp32 的 441 MB。入口画出来却必然报错比不画更坏 ——
      // 但整张卡凭空消失又会被读成「没有这个功能」，所以留壳、灰显、说明。
      supportedHere: () => ocrSupportedHere,
      unsupportedHint: t.workspace.desktopOnly,
      builder: (context, chrome) => TranslateCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
        disabledHint: chrome.supported ? null : chrome.unsupportedHint,
      ),
    ),
    WorkspaceCardDefinition(
      id: imageTuning,
      title: t.workspace.imageTuning,
      icon: AppGlyphs.wand,
      defaultPanelId: WorkspacePanelId.control,
      defaultOrder: 3,
      defaultWidthSpan: 2,
      minimumWidth: 320,
      builder: (context, chrome) => ImageTuningCard(
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
        isStandalone: chrome.standalone,
        disabledHint: chrome.supported ? null : chrome.unsupportedHint,
      ),
    ),
    // ── 洞察 ──────────────────────────────────────────────────────────────
    // 洞察卡都只在**有历史**时才有内容，所以窗口为空时各自画一行提示而不是空板。
    // 归属刻意不散到 favorite / history 那些独占面板里：洞察是「读历史的另一双眼睛」，
    // 与 neoview 一样独立成一张面板，用户想拆再拖。
    WorkspaceCardDefinition(
      id: readingOverview,
      title: t.workspace.readingOverview,
      icon: AppGlyphs.openBook,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: -1,
      defaultWidthSpan: 4,
      defaultHeightSpan: 2,
      builder: (context, chrome) => ReadingActivityCard(
        kind: ReadingActivityKind.overview,
        cardId: readingOverview,
        title: t.workspace.readingOverview,
        icon: AppGlyphs.openBook,
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: activityCalendar,
      title: t.workspace.last28Active,
      icon: AppGlyphs.calendar,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 4,
      defaultWidthSpan: 2,
      defaultHeightSpan: 3,
      builder: (context, chrome) => ReadingActivityCard(
        kind: ReadingActivityKind.calendar,
        cardId: activityCalendar,
        title: t.workspace.last28Active,
        icon: AppGlyphs.calendar,
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: weeklyRhythm,
      title: t.workspace.weeklyReadingRhythm,
      icon: AppGlyphs.trend,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 5,
      defaultWidthSpan: 2,
      defaultHeightSpan: 3,
      builder: (context, chrome) => ReadingActivityCard(
        kind: ReadingActivityKind.rhythm,
        cardId: weeklyRhythm,
        title: t.workspace.weeklyReadingRhythm,
        icon: AppGlyphs.trend,
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: readingPeriods,
      title: t.workspace.readingPeriods,
      icon: AppGlyphs.clock,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 6,
      defaultWidthSpan: 4,
      defaultHeightSpan: 2,
      builder: (context, chrome) => ReadingActivityCard(
        kind: ReadingActivityKind.periods,
        cardId: readingPeriods,
        title: t.workspace.readingPeriods,
        icon: AppGlyphs.clock,
        isExpanded: chrome.expanded,
        onToggle: chrome.onToggle,
        onMoveUp: chrome.onMoveUp,
        onMoveDown: chrome.onMoveDown,
        onHide: chrome.onHide,
      ),
    ),
    WorkspaceCardDefinition(
      id: dailyTrend,
      title: t.workspace.last7ReadingTrend,
      icon: AppGlyphs.trend,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 0,
      defaultWidthSpan: 2,
      defaultHeightSpan: 3,
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
      title: t.workspace.streakReading,
      icon: AppGlyphs.fire,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 1,
      defaultWidthSpan: 2,
      defaultHeightSpan: 3,
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
      title: t.workspace.readingHeat,
      icon: AppGlyphs.calendar,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 2,
      defaultWidthSpan: 4,
      defaultHeightSpan: 3,
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
      title: t.workspace.sourceBreakdown,
      icon: AppGlyphs.pieChart,
      defaultPanelId: WorkspacePanelId.insights,
      defaultOrder: 3,
      defaultWidthSpan: 2,
      defaultHeightSpan: 3,
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

  String _fallbackPanelFor(
    WorkspaceCardDefinition card,
    WorkspaceBoardLayout board,
  ) {
    if (card.id == pageListSearch || card.id == pageListJump) {
      return board.cardLayout(pageList)?.panelId ?? card.defaultPanelId;
    }
    return card.defaultPanelId;
  }

  /// 某个面板当前应当显示的卡片（已按 order 排序、已滤掉隐藏项）。
  List<WorkspaceCardDefinition> cardsForPanel(
    String panelId,
    WorkspaceBoardLayout board,
  ) {
    final visible = <String>[];
    for (final card in cards) {
      final layout = board.cardLayout(card.id);
      final effectivePanel = layout?.panelId ?? _fallbackPanelFor(card, board);
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
    final existing = board.cardLayout(card.id);
    if (existing != null) {
      return existing.copyWith(
        widthSpan: existing.widthSpan ?? card.defaultWidthSpan,
        heightSpan: existing.heightSpan ?? card.defaultHeightSpan,
      );
    }
    return CardLayout(
      panelId: _fallbackPanelFor(card, board),
      visible: card.defaultVisible,
      order: card.defaultOrder,
      expanded: card.defaultExpanded,
      widthSpan: card.defaultWidthSpan,
      heightSpan: card.defaultHeightSpan,
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
