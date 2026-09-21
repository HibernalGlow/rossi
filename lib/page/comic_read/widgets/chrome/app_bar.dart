import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_sheet.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_layout_panel.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_rotate_panel.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_upscale_status_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_zoom_panel.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reading_mode_capsule.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/reader/reader_top_bar_style.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// NeoView 风格的专业阅读器顶栏 (ReaderViewToolbar)。
///
/// 两行结构照 neoview 的 `ReaderViewToolbar.tsx`，但主行按 **MD3 的分组口径**
/// 排布：一组一职责，组间一条分隔线，宽度不够就整组让位（不是把图标挤在一起）。
///
/// - **主行**：导航（返回）｜ 标题 ｜ 视图（缩放·旋转·版式工具三块面板的入口）｜
///   版式（条漫⇄单页 · 单双页 · 阅读方向）｜ 增强（下载 · 超分状态 · 自动滚屏）｜
///   窗口（全屏 · 钉住 · 设置 · 更多）。
///   缩放那颗的图标跟着当前缩放模式换，不点开也看得见现在怎么铺。
/// - **三档宽度**（[resolveReaderToolbarTier]，纯函数、有判据）：
///   宽 = 芯片带文字；中 = 芯片收成图标；窄 = 版式组并成一颗循环按钮，
///   并把**视图三项 + 钉住 + 全屏**收进末尾的「更多」菜单。让位顺序是
///   「标题先省略到 0，再整组进菜单」，主行那颗 `Row` 从不折行。
/// - **展开区**：一次只挂一块面板（[ReaderZoomPanel] / [ReaderRotatePanel] /
///   [ReaderLayoutPanel]），互斥，再点一次收起。
///
/// 几何与配色只有一处口径：见 `top/reader_toolbar_shell.dart` 的
/// [ReaderToolbarMetrics] 与 [ReaderToolbarIconButton] —— 改造前那三种
/// 边长（30 圆钮 / 40 方钮 / 36 自绘框）并排，就是「图标堆在一起」的成因。
///
/// 其余子件：
/// - [ReadingModeCapsule] & [DoublePageToggle]：阅读模式与单双页胶囊
/// - [CompactReadingModeButton]：窄档的循环切换按钮
/// - [ReaderUpscaleStatusChip]：当前页超分状态（状态字 + 超分后分辨率 + 超分开关）
/// - [ReaderDownloadButton]：在线漫画边看边下载快捷入口与状态指示
///
/// 自动滚屏按用户口径**只住二级**（「不常用」）：主行三档都不画它，
/// 入口是「更多」菜单的第一项，见 [_toggleReaderAutoScroll]。
class ComicReadAppBar extends StatefulWidget {
  final String title;
  final String? comicTitle;
  final ValueChanged<int> changePageIndex;
  final bool isDesktopFullscreen;
  final VoidCallback? onToggleFullscreen;
  final ValueChanged<bool>? onLandscapeChanged;
  final VoidCallback? onToggleAutoRead;
  final ValueGetter<bool>? isAutoReadPaused;
  final String from;
  final String comicId;
  final ComicEntryType type;
  final dynamic comicInfo;
  final List<UnifiedComicChapterRef>? chapterRefs;

  const ComicReadAppBar({
    super.key,
    required this.title,
    this.comicTitle,
    required this.changePageIndex,
    this.isDesktopFullscreen = false,
    this.onToggleFullscreen,
    this.onLandscapeChanged,
    this.onToggleAutoRead,
    this.isAutoReadPaused,
    this.from = '',
    this.comicId = '',
    this.type = ComicEntryType.normal,
    this.comicInfo,
    this.chapterRefs,
  });

  @override
  State<ComicReadAppBar> createState() => _ComicReadAppBarState();
}

class _ComicReadAppBarState extends State<ComicReadAppBar> {
  /// 当前展开的那一块二级面板；null = 收起。
  ///
  /// 与 neoview 同一口径：**互斥**，点第二颗会把第一颗关掉，而不是叠两层。
  ReaderToolbarPanel? _expandedPanel;

  Widget _buildExpandedPanel() => switch (_expandedPanel) {
    ReaderToolbarPanel.zoom => const ReaderZoomPanel(
      key: ValueKey(ReaderToolbarPanel.zoom),
    ),
    ReaderToolbarPanel.rotate => const ReaderRotatePanel(
      key: ValueKey(ReaderToolbarPanel.rotate),
    ),
    ReaderToolbarPanel.layout => const ReaderLayoutPanel(
      key: ValueKey(ReaderToolbarPanel.layout),
    ),
    null => const SizedBox(width: double.infinity, height: 0),
  };

  /// 展开 / 收起一块面板：再点一次收起（与 neoview 同一手感）。
  ///
  /// 主行那颗按钮与窄档「更多」菜单里的同名项**共用这一个入口**，
  /// 所以同一件事不会有两种结果。
  void _togglePanel(ReaderToolbarPanel panel) => setState(() {
    _expandedPanel = _expandedPanel == panel ? null : panel;
  });

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;
    // 顶栏可见性：**钉住 > 菜单 > 悬停**。`pinned` 写在选择器**里面**而不是选择器
    // 外面 OR：这样仍然只在「这一个 bool 翻转」时重建，不会退化成翻一页重建一次顶栏。
    final showTopAppBar = context.select(
      (ReaderCubit cubit) =>
          cubit.state.showTopAppBar(pinned: readSetting.topBarPinned),
    );
    final hoverController = ReaderHoverScope.of(context);
    const appBarShape = BorderRadius.vertical(
      bottom: Radius.circular(ReaderToolbarMetrics.barRadius),
    );
    // 顶栏材质：玻璃（改造前那一档）或「透明档」的半透明蒙层。
    // 判定与钳制都在 `resolveReaderTopBarSpec` 里，这里只照着画。
    final topBarSpec = resolveReaderTopBarSpec(
      readSetting,
      surface: Theme.of(context).colorScheme.surface,
    );

    // 顶栏本体（两种材质共用同一份内容，只有外面那层材质不同）。
    final barContent = SafeArea(
      top: true,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 只看可用宽度分档：桌面端能把窗口拖到 400 宽，平板能把阅读器
          // 给到 900 宽，按设备类型判断在这两头都会骗人。
          final tier = resolveReaderToolbarTier(constraints.maxWidth);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPrimaryToolbar(
                context: context,
                readSetting: readSetting,
                cubit: globalSettingCubit,
                tier: tier,
                // 芯片要按可用宽度决定写不写分辨率：窄屏硬塞会撑爆这一行。
                availableWidth: constraints.maxWidth,
              ),
              // 展开区一次只挂一个面板（neo 的 `ExpandedPanel` 同一互斥口径）。
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _buildExpandedPanel(),
              ),
            ],
          );
        },
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showTopAppBar,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          offset: showTopAppBar ? Offset.zero : const Offset(0, -1),
          child: MouseRegion(
            onEnter: (_) => hoverController?.onEnterTopBar(),
            onExit: (_) => hoverController?.onExitTopBar(),
            child: topBarSpec.liquidGlass
                // 顶栏压在漫画内容上，前景必须永远读得清，走最实的一档；
                // 贴着屏幕顶，阴影按体量收小。
                ? LiquidGlassSurface(
                    thickness: LiquidGlassThickness.thick,
                    borderRadius: appBarShape,
                    shadowScale: topBarSpec.shadowScale,
                    child: barContent,
                  )
                // 透明档：只有一层蒙层铺在画面上，不模糊、不带阴影。
                // 颜色是主题 `surface` 加透明度，所以顶栏里的文字与图标
                // 一个都不用改色（`onSurface` 对 `surface` 的对比度天然成立）。
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: topBarSpec.scrim,
                      borderRadius: appBarShape,
                    ),
                    child: barContent,
                  ),
          ),
        ),
      ),
    );
  }

  /// 顶栏主操作行 (Primary Row)。
  ///
  /// 排布口径：**一组一职责，组间一条分隔线**，宽度不够就整组让位。
  /// 改造前这里是一条平铺的 `Row`，三种边长的图标钮（30 圆 / 40 方 / 36 自绘框）
  /// 混在一行里、彼此只差 2~4px，那就是「功能图标堆在一起」的成因。
  /// 分组 + 统一几何才是解法，少摆几颗只是把问题挪走。
  Widget _buildPrimaryToolbar({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderToolbarTier tier,
    required double availableWidth,
  }) {
    // 主行那颗缩放入口要跟着当前档位换图标，所以在这里 select 一次；
    // 放在 select 里而不是整份 presentation 上，拖滑条时就不会重建主行。
    final fitMode = context.select(
      (ReaderPresentationCubit c) => c.state.fitMode,
    );
    final bookTitle =
        widget.comicTitle ?? ReaderSessionCoordinator.instance.displayTitle;
    // 让位分两级：中档以下「视图三项 + 下载」进「更多」，宽档以下再搭上
    // 「钉住 + 全屏」。neo 占位的那五颗**永远**在菜单里，主行不再为它们让宽度。
    final inlineView = tier.keepsViewControlsInline;
    final inlineWindow = tier.keepsWindowControlsInline;
    final showDownloadEntry =
        widget.type != ComicEntryType.download &&
        widget.type != ComicEntryType.historyAndDownload &&
        widget.from.isNotEmpty &&
        !isLocalComicSource(widget.from, widget.comicId);
    // 超分芯片的让位判断按「没有下载那颗时的可用宽度」算：两者互斥，
    // 一起记账会把芯片压成永远不写文字的哑巴。
    final chipWidth = availableWidth - (showDownloadEntry ? 44 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height: ReaderToolbarMetrics.rowHeight,
        child: Row(
          children: [
            // 导航
            ReaderToolbarIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: t.common.back,
              onPressed: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 8),

            // 标题：这一行唯一的弹性项，所以「谁先让位」的答案就是它先省略到 0。
            Expanded(child: _buildTitle(context, bookTitle: bookTitle)),

            // 视图组：三块二级面板的入口。
            if (inlineView) ...[
              const ReaderToolbarSeparator(),
              ReaderToolbarGroup(
                children: [
                  for (final panel in ReaderToolbarPanel.values)
                    ReaderToolbarIconButton(
                      icon: _readerPanelIcon(panel, fitMode),
                      tooltip: '${_readerPanelLabel(panel, fitMode)}（点击展开面板）',
                      selected: _expandedPanel == panel,
                      onPressed: () => _togglePanel(panel),
                    ),
                ],
              ),
            ],

            // 版式组。
            _buildLayoutGroup(
              context,
              readSetting: readSetting,
              cubit: cubit,
              tier: tier,
            ),
            // 窄档这一组只剩一颗循环按钮，标题本身就是分隔，不再补第二条线
            // ——每少一条线就是 13px 留给书名。
            if (tier.expandsLayoutGroup)
              const ReaderToolbarSeparator()
            else
              const SizedBox(width: ReaderToolbarMetrics.gapBetweenGroups),

            // 增强组：下载 / 超分状态 / 自动滚屏。
            //
            // 这一组**永不折叠**：超分那颗既是状态显示也是开关，用户口径是
            // 「最常用的那一档」，收进菜单就等于看不见了。而且它与下载互斥
            // （下载只在在线图源出现，超分芯片只在本地 GPU 会话出现），
            // 这一组的最坏情况就是「芯片 + 滚屏」，比视图三项窄得多。
            ReaderToolbarGroup(
              children: [
                if (showDownloadEntry && inlineView)
                  _buildDownloadEntry(bookTitle),
                ReaderUpscaleStatusChip(availableWidth: chipWidth),
                // 自动滚屏按用户口径放**二级**：主行不画它，入口与开/关状态
                // 在「更多」菜单的第一项（所有档位都在那里）。
              ],
            ),

            // 窗口组 + 更多。
            const ReaderToolbarSeparator(),
            ReaderToolbarGroup(
              children: [
                if (inlineWindow && widget.onToggleFullscreen != null)
                  ReaderToolbarIconButton(
                    icon: widget.isDesktopFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: widget.isDesktopFullscreen
                        ? t.reader.exitFullscreen
                        : t.reader.enterFullscreen,
                    onPressed: widget.onToggleFullscreen,
                  ),
                // 钉住顶栏（neo 的 edge `pinned`）：钉住之后这一条不再被
                // 「点中间收起」或指针离开边缘收走；取消钉住立刻交还给那两套自动收起。
                if (inlineWindow)
                  ReaderToolbarIconButton(
                    icon: readSetting.topBarPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    tooltip: readSetting.topBarPinned
                        ? t.reader.unpinTopBar
                        : t.reader.pinTopBar,
                    selected: readSetting.topBarPinned,
                    onPressed: () => cubit.updateReadSetting(
                      (s) => s.copyWith(topBarPinned: !s.topBarPinned),
                    ),
                  ),
                _ReaderToolbarOverflowButton(
                  items: _buildOverflowItems(
                    context,
                    readSetting: readSetting,
                    cubit: cubit,
                    fitMode: fitMode,
                    inlineView: inlineView,
                    inlineWindow: inlineWindow,
                    isAutoScrollPaused:
                        widget.isAutoReadPaused?.call() ?? false,
                    showDownloadEntry: showDownloadEntry,
                    bookTitle: bookTitle,
                  ),
                ),
                ReaderToolbarIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: t.reader.settings,
                  onPressed: () => showReaderSettingsSheet(
                    context,
                    changePageIndex: widget.changePageIndex,
                    onLandscapeChanged: widget.onLandscapeChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 标题两行：页面标题在上，书名在下（与上面对得上的那一份就不重复写）。
  Widget _buildTitle(BuildContext context, {required String? bookTitle}) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title.isEmpty ? t.common.unknown : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (bookTitle != null &&
            bookTitle.isNotEmpty &&
            bookTitle != widget.title) ...[
          const SizedBox(height: 1),
          Text(
            bookTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 版式组：宽/中档摊开成「条漫⇄单页 · 单双页 · 方向」，窄档并成一颗循环按钮。
  Widget _buildLayoutGroup(
    BuildContext context, {
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderToolbarTier tier,
  }) {
    if (!tier.expandsLayoutGroup) {
      return CompactReadingModeButton(
        currentMode: readSetting.readMode,
        onModeChanged: (mode) {
          final previousMode = readSetting.readMode;
          cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
          // 窄屏那颗循环按钮要顺手把方向也切了，所以它**只在跨条漫时**归位：
          // 右开⇄左开清零等于「切个方向跳回第一页」（宽屏那条路同一个道理）。
          if ((previousMode == kReadModeColumn) != (mode == kReadModeColumn)) {
            widget.changePageIndex(0);
          }
        },
      );
    }
    return ReaderToolbarGroup(
      children: [
        ReadingModeCapsule(
          currentMode: readSetting.readMode,
          onModeChanged: (mode) {
            cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
            widget.changePageIndex(0);
          },
        ),
        DoublePageToggle(
          isDoublePage: readSetting.doublePageMode,
          showLabel: tier.showsChipLabels,
          onToggle: (isDouble) {
            // 不在这里动阅读位置：单/双页换的是「槽位怎么切」，
            // 位置由阅读器按「同一张图」重算（见
            // `_ComicReadPageState._syncPairingLayoutChange`）。
            // 以前这里跟着 `changePageIndex(0)`，等于每次切换都回到第一页。
            cubit.updateReadSetting(
              (s) => s.copyWith(doublePageMode: isDouble),
            );
          },
        ),
        // 阅读方向（右开 ⇄ 左开，即下一页在右还是在左）。只在横翻模式下可用；
        // **不动阅读位置** —— 两个方向同属 RowModeWidget，槽位含义不变，
        // 只是翻页语义反过来（左开下「下一页」在左边）。
        if (readSetting.readingDirectionToggle)
          ReadingDirectionToggle(
            currentMode: readSetting.readMode,
            showLabel: tier.showsChipLabels,
            onModeChanged: (mode) {
              cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
            },
          ),
      ],
    );
  }

  /// 下载快捷入口。主行与窄档的「更多」菜单共用这一份构造。
  Widget _buildDownloadEntry(String? bookTitle) {
    return ReaderDownloadButton(
      from: widget.from,
      comicId: widget.comicId,
      comicTitle: bookTitle ?? widget.title,
      comicInfo: widget.comicInfo,
      chapterRefs: widget.chapterRefs,
    );
  }

  /// 「更多」菜单的项集：让位收进来的那些 + neo 有、本仓还没有的那五颗占位。
  List<Widget> _buildOverflowItems(
    BuildContext context, {
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderFitMode fitMode,
    required bool inlineView,
    required bool inlineWindow,
    required bool isAutoScrollPaused,
    required bool showDownloadEntry,
    required String? bookTitle,
  }) {
    return [
      // 自动滚屏按用户的口径常驻二级（「不常用」）：这一项在所有档位都在。
      MenuItemButton(
        leadingIcon: const Icon(Icons.play_circle_outline_rounded),
        trailingIcon: readSetting.autoScroll ? const Icon(Icons.check) : null,
        onPressed: () => _toggleReaderAutoScroll(
          isEnabled: readSetting.autoScroll,
          isPaused: isAutoScrollPaused,
          onToggleAutoScroll: (enabled) =>
              cubit.updateReadSetting((s) => s.copyWith(autoScroll: enabled)),
          onTogglePause: widget.onToggleAutoRead,
        ),
        child: Text(readSetting.autoScroll ? '暂停 / 继续自动滚屏' : '开启自动滚屏'),
      ),
      if (readSetting.autoScroll)
        MenuItemButton(
          leadingIcon: const Icon(Icons.stop_circle_outlined),
          onPressed: () =>
              cubit.updateReadSetting((s) => s.copyWith(autoScroll: false)),
          child: const Text('关闭自动滚屏'),
        ),
      if (!inlineView) ...[
        // 让位的第一批：下载（整本下载是低频动作）与三块面板的入口。
        // 超分芯片不参与让位 —— 用户口径是它最常用，必须留在第一行。
        if (showDownloadEntry)
          MenuItemButton(
            leadingIcon: const Icon(Icons.download_rounded),
            onPressed: () => showReaderDownloadSheet(
              context,
              from: widget.from,
              comicId: widget.comicId,
              comicTitle: bookTitle ?? widget.title,
              comicInfo: widget.comicInfo,
              chapterRefs: widget.chapterRefs,
            ),
            child: Text(t.reader.startDownload),
          ),
        for (final panel in ReaderToolbarPanel.values)
          MenuItemButton(
            leadingIcon: Icon(_readerPanelIcon(panel, fitMode)),
            trailingIcon: _expandedPanel == panel
                ? const Icon(Icons.check)
                : null,
            onPressed: () => _togglePanel(panel),
            child: Text(_readerPanelLabel(panel, fitMode)),
          ),
        const _ReaderMenuDivider(),
      ],
      if (!inlineWindow) ...[
        if (widget.onToggleFullscreen != null)
          MenuItemButton(
            leadingIcon: Icon(
              widget.isDesktopFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
            onPressed: widget.onToggleFullscreen,
            child: Text(
              widget.isDesktopFullscreen
                  ? t.reader.exitFullscreen
                  : t.reader.enterFullscreen,
            ),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.push_pin_outlined),
          trailingIcon: readSetting.topBarPinned
              ? const Icon(Icons.check)
              : null,
          onPressed: () => cubit.updateReadSetting(
            (s) => s.copyWith(topBarPinned: !s.topBarPinned),
          ),
          child: Text(t.reader.pinTopBar),
        ),
        const _ReaderMenuDivider(),
      ],
      // 占位的说明写在菜单里，不用点一下才知道：这一节整段是「还没接」的。
      MenuItemButton(onPressed: null, child: const Text('以下尚未接进本仓')),
      for (final (icon, name) in _kReaderComingSoon)
        MenuItemButton(
          leadingIcon: Icon(icon),
          onPressed: () => showReaderToolbarComingSoon(context, name),
          child: Text(name),
        ),
    ];
  }
}

/// neo 主行上有、本仓还没有对应能力的那几颗。
///
/// 保留入口是**刻意的**：将来做出一块就把那颗从菜单搬回主行对应的那一组，
/// 不用重排列。它们不占主行宽度（改造前靠 `availableWidth >= 900` 决定摆不摆全，
/// 于是主行的形状跟着窗口宽度跳），统一住在「更多」里。
const List<(IconData, String)> _kReaderComingSoon = [
  (Icons.sort_rounded, '页面排序'),
  (Icons.panorama_wide_angle_rounded, '全景模式'),
  (Icons.mouse_rounded, '悬停滚动'),
  (Icons.slideshow_rounded, '幻灯片'),
  (Icons.zoom_in_map_rounded, '放大镜'),
];

/// 自动滚屏那颗开关的**分派**：没开就开启，开着就暂停（没有暂停回调时直接关掉）。
///
/// 主行不再画它的芯片，所以这个分派只有菜单一个调用方 —— 但它得与芯片当年
/// 完全同一套行为：开与暂停都要给一句话，否则点了没反应只会让人以为没生效。
void _toggleReaderAutoScroll({
  required bool isEnabled,
  required bool isPaused,
  required ValueChanged<bool> onToggleAutoScroll,
  VoidCallback? onTogglePause,
}) {
  if (!isEnabled) {
    onToggleAutoScroll(true);
    showInfoToast('已开启自动滚屏');
  } else if (onTogglePause != null) {
    onTogglePause();
  } else {
    onToggleAutoScroll(false);
  }
}

IconData _readerPanelIcon(ReaderToolbarPanel panel, ReaderFitMode fitMode) =>
    switch (panel) {
      ReaderToolbarPanel.zoom => kReaderFitModeIcons[fitMode]!,
      ReaderToolbarPanel.rotate => Icons.rotate_right_rounded,
      ReaderToolbarPanel.layout => Icons.dashboard_customize_outlined,
    };

String _readerPanelLabel(ReaderToolbarPanel panel, ReaderFitMode fitMode) =>
    switch (panel) {
      ReaderToolbarPanel.zoom => '缩放模式：${kReaderFitModeLabels[fitMode]!}',
      ReaderToolbarPanel.rotate => '旋转设置',
      ReaderToolbarPanel.layout => '版式工具',
    };

/// 主行末尾的「更多」（MD3 `MenuAnchor`）。
class _ReaderToolbarOverflowButton extends StatelessWidget {
  final List<Widget> items;

  const _ReaderToolbarOverflowButton({required this.items});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: items,
      builder: (context, controller, child) => ReaderToolbarIconButton(
        icon: Icons.more_vert_rounded,
        tooltip: '更多',
        selected: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// 菜单里两节之间的那条线（material_ui 的这份 `MenuAnchor` 没有 `MenuGroup`，
/// 分隔线自己画一条，颜色用 MD3 的 divider 角色）。
class _ReaderMenuDivider extends StatelessWidget {
  const _ReaderMenuDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(height: 9, thickness: 1, color: colorScheme.outlineVariant);
  }
}
