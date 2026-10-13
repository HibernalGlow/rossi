import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_online_translated_page_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_sheet.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_layout_panel.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_rotate_panel.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_upscale_status_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_translated_page_chip.dart';
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
import 'package:zephyr/page/comic_read/widgets/chrome/reader_chrome_transition.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_button.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';

part 'reader_toolbar_rows_part.dart';

/// 阅读器主行、常驻二级工具栏与互斥展开面板。
/// 根据可用空间移动控件，保留全部入口与原有回调。
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
    final appBarShape = BorderRadius.circular(ReaderToolbarMetrics.barRadius);
    // 顶栏材质：玻璃（改造前那一档）或「透明档」的半透明蒙层。
    // 判定与钳制都在 `resolveReaderTopBarSpec` 里，这里只照着画。
    final topBarSpec = resolveReaderTopBarSpec(
      readSetting,
      surface: Theme.of(context).colorScheme.surface,
    );

    // 主行与第二行**共用**的三份量：放在这里而不是各自算一遍，因为让位项搬到
    // 第二行之后，同一个入口只该有一处构造它。
    //
    // 缩放入口的图标跟着当前缩放档换，所以 select 只认 fitMode 这一个字段：
    // 拖滑条（改的是 manualScale）不会重建顶栏。
    final fitMode = context.select(
      (ReaderPresentationCubit c) => c.state.fitMode,
    );
    final bookTitle =
        widget.comicTitle ?? ReaderSessionCoordinator.instance.displayTitle;
    final showDownloadEntry =
        widget.type != ComicEntryType.download &&
        widget.type != ComicEntryType.historyAndDownload &&
        widget.from.isNotEmpty &&
        !isLocalComicSource(widget.from, widget.comicId);

    Widget surface(Widget child) {
      final content = ActionBubbleRegion(child: child);
      return topBarSpec.liquidGlass
          ? Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              elevation: 3,
              borderRadius: appBarShape,
              clipBehavior: Clip.antiAlias,
              child: content,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: topBarSpec.scrim,
                borderRadius: appBarShape,
              ),
              child: content,
            );
    }

    // 顶栏本体（两种材质共用同一份内容，只有外面那层材质不同）。
    final barContent = LayoutBuilder(
      builder: (context, constraints) {
        // 只看可用宽度分档：桌面端能把窗口拖到 400 宽，平板能把阅读器
        // 给到 900 宽，按设备类型判断在这两头都会骗人。
        final tier = resolveReaderToolbarTier(constraints.maxWidth);
        final secondaryRow = resolveReaderSecondaryRow(
          tier: tier,
          maxHeight: MediaQuery.sizeOf(context).height,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            surface(
              _buildPrimaryToolbar(
                context: context,
                readSetting: readSetting,
                cubit: globalSettingCubit,
                tier: tier,
                secondaryRow: secondaryRow,
                fitMode: fitMode,
                bookTitle: bookTitle,
                showDownloadEntry: showDownloadEntry,
                // 芯片要按可用宽度决定写不写分辨率：窄屏硬塞会撑爆这一行。
                availableWidth: constraints.maxWidth,
              ),
            ),
            if (secondaryRow)
              _buildSecondaryToolbar(
                context: context,
                readSetting: readSetting,
                cubit: globalSettingCubit,
                tier: tier,
                fitMode: fitMode,
                bookTitle: bookTitle,
                showDownloadEntry: showDownloadEntry,
              ),
            // 展开区一次只挂一个面板（neo 的 `ExpandedPanel` 同一互斥口径）。
            AnimatedSize(
              duration:
                  readSetting.noAnimation ||
                      globalSettingState.eInkSetting.enabled
                  ? Duration.zero
                  : ExpressiveMotion.spatialDuration,
              curve: ExpressiveMotion.spatialCurve,
              alignment: Alignment.topCenter,
              child: _buildExpandedPanel(),
            ),
          ],
        );
      },
    );
    // 墨水屏：工具栏滑入滑出的中间帧只会攒成残影，直接出图。
    final eInkInstant = context.select(
      (GlobalSettingCubit cubit) => cubit.state.eInkSetting.enabled,
    );

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        ignoring: !showTopAppBar,
        child: ReaderChromeTransition(
          visible: showTopAppBar,
          top: true,
          animate: !eInkInstant && !readSetting.noAnimation,
          child: MouseRegion(
            onEnter: (_) => hoverController?.onEnterTopBar(),
            onExit: (_) => hoverController?.onExitTopBar(),
            child: barContent,
          ),
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
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

  /// 「更多」菜单的项集：让位收进来的那些 + neo 有、本仓还没有的那五颗占位。
  ///
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
  ///
  /// 让位项**只在没有常驻第二行时**才进菜单（[secondaryRow]）：有了第二行还列
  /// 一遍，就是同一颗控件两个入口、两个选中态，改一处另一处不动。
  List<Widget> _buildOverflowItems(
    BuildContext context, {
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderFitMode fitMode,
    required bool inlineView,
    required bool inlineWindow,
    required bool secondaryRow,
    required bool isAutoScrollPaused,
    required bool showDownloadEntry,
    required String? bookTitle,
  }) {
    return [
      // 自动滚屏按用户的口径常驻二级（「不常用」）：这一项在所有档位都在。
      MenuItemButton(
        leadingIcon: const GlyphIcon(AppGlyphs.playCircle),
        trailingIcon: readSetting.autoScroll
            ? const GlyphIcon(AppGlyphs.check)
            : null,
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
          leadingIcon: const GlyphIcon(AppGlyphs.stopCircle),
          onPressed: () =>
              cubit.updateReadSetting((s) => s.copyWith(autoScroll: false)),
          child: const Text('关闭自动滚屏'),
        ),
      if (!inlineView && !secondaryRow) ...[
        // 让位的第一批：下载（整本下载是低频动作）与三块面板的入口。
        // 超分芯片不参与让位 —— 用户口径是它最常用，必须留在第一行。
        if (showDownloadEntry)
          MenuItemButton(
            leadingIcon: const GlyphIcon(AppGlyphs.download),
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
            leadingIcon: GlyphIcon(_readerPanelIcon(panel, fitMode)),
            trailingIcon: _expandedPanel == panel
                ? const GlyphIcon(AppGlyphs.check)
                : null,
            onPressed: () => _togglePanel(panel),
            child: Text(_readerPanelLabel(panel, fitMode)),
          ),
        const _ReaderMenuDivider(),
      ],
      if (!inlineWindow && !secondaryRow) ...[
        if (widget.onToggleFullscreen != null)
          MenuItemButton(
            leadingIcon: GlyphIcon(
              widget.isDesktopFullscreen
                  ? AppGlyphs.fullscreenExit
                  : AppGlyphs.fullscreen,
            ),
            onPressed: widget.onToggleFullscreen,
            child: Text(
              widget.isDesktopFullscreen
                  ? t.reader.exitFullscreen
                  : t.reader.enterFullscreen,
            ),
          ),
        MenuItemButton(
          leadingIcon: const GlyphIcon(AppGlyphs.pin),
          trailingIcon: readSetting.topBarPinned
              ? const GlyphIcon(AppGlyphs.check)
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
          leadingIcon: GlyphIcon(icon),
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
const List<(Glyph, String)> _kReaderComingSoon = [
  (AppGlyphs.sort, '页面排序'),
  (AppGlyphs.panorama, '全景模式'),
  (AppGlyphs.mouse, '悬停滚动'),
  (AppGlyphs.slideshow, '幻灯片'),
  (AppGlyphs.zoomIn, '放大镜'),
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

Glyph _readerPanelIcon(ReaderToolbarPanel panel, ReaderFitMode fitMode) =>
    switch (panel) {
      ReaderToolbarPanel.zoom => kReaderFitModeIcons[fitMode]!,
      ReaderToolbarPanel.rotate => AppGlyphs.rotateRight,
      ReaderToolbarPanel.layout => AppGlyphs.gridPlus,
    };

String _readerPanelLabel(ReaderToolbarPanel panel, ReaderFitMode fitMode) =>
    switch (panel) {
      ReaderToolbarPanel.zoom => '缩放模式：${kReaderFitModeLabels[fitMode]!}',
      ReaderToolbarPanel.rotate => '旋转设置',
      ReaderToolbarPanel.layout => '版式工具',
    };

/// 主行末尾的「更多」（MD3 `MenuAnchor`）。
class _ReaderToolbarOverflowButton extends StatelessWidget {
  const _ReaderToolbarOverflowButton({required this.items});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) => CommonPopupBox<void>(
    targetBuilder: (open) => ReaderToolbarIconButton(
      icon: AppGlyphs.more,
      tooltip: t.common.more,
      onPressed: () => open(),
    ),
    popupBuilder: (context) => CommonPopupMenu(
      maxWidth: 320,
      items: [
        for (final item in items)
          if (item is MenuItemButton)
            CommonPopupMenuItem(
              label: item.child is Text ? (item.child as Text).data ?? '' : '',
              glyph: item.leadingIcon is GlyphIcon
                  ? (item.leadingIcon as GlyphIcon).glyph
                  : null,
              checked: item.trailingIcon != null ? true : null,
              onPressed: item.onPressed,
            )
          else
            const CommonPopupMenuItem.divider(),
      ],
    ),
  );
}

class _ReaderMenuDivider extends StatelessWidget {
  const _ReaderMenuDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(height: 9, thickness: 1, color: colorScheme.outlineVariant);
  }
}
