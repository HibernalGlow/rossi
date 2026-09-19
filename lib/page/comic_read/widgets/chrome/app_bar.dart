import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/auto_scroll_quick_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_upscale_status_chip.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reading_mode_capsule.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/secondary_toolbar.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// NeoView 风格的专业阅读器顶栏 (ReaderViewToolbar)。
///
/// 模块化设计：
/// - [ReadingModeCapsule] & [DoublePageToggle]：阅读模式与单双页胶囊
/// - [CompactReadingModeButton]：移动窄屏循环切换按钮
/// - [ReaderUpscaleStatusChip]：当前页超分状态（状态字 + 超分后分辨率 + 超分开关）
/// - [ReaderDownloadButton]：在线漫画边看边下载快捷入口与状态指示
/// - [AutoScrollQuickButton]：自动滚屏状态快捷按钮
/// - [ReaderSecondaryToolbar]：二级展开版式高级工具面板
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
  bool _isSecondaryBarExpanded = false;

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;
    // 顶栏可见性：**钉住 > 菜单 > 悬停**。`pinned` 写在选择器**里面**而不是选择器
    // 外面 OR：这样仍然只在「这一个 bool 翻转」时重建，不会退化成翻一页重建一次顶栏。
    final showTopAppBar = context.select(
      (ReaderCubit cubit) => cubit.state.showTopAppBar(
        pinned: readSetting.topBarPinned,
      ),
    );
    final hoverController = ReaderHoverScope.of(context);
    const appBarRadius = 16.0;

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
            child: LiquidGlassSurface(
              // 顶栏压在漫画内容上，前景必须永远读得清，走最实的一档；
              // 贴着屏幕顶，阴影按体量收小。
              thickness: LiquidGlassThickness.thick,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(appBarRadius),
              ),
              shadowScale: 0.4,
              child: SafeArea(
                top: true,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPrimaryToolbar(
                          context: context,
                          readSetting: readSetting,
                          cubit: globalSettingCubit,
                          isWide: isWide,
                          // 芯片要按可用宽度决定写不写分辨率：窄屏硬塞会撑爆这一行。
                          availableWidth: constraints.maxWidth,
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 220),
                          crossFadeState: _isSecondaryBarExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox(
                            width: double.infinity,
                            height: 0,
                          ),
                          secondChild: ReaderSecondaryToolbar(
                            readSetting: readSetting,
                            cubit: globalSettingCubit,
                            changePageIndex: widget.changePageIndex,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶栏主操作行 (Primary Row)
  Widget _buildPrimaryToolbar({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required bool isWide,
    required double availableWidth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bookTitle =
        widget.comicTitle ?? ReaderSessionCoordinator.instance.displayTitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            // 1. 返回按钮
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              tooltip: t.common.back,
              onPressed: () => Navigator.maybePop(context),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // 2. 书籍与章节标题
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title.isEmpty ? t.common.unknown : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
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
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 3. 版式模式胶囊组 (宽屏展开胶囊组，窄屏提供紧凑循环切换按钮)
            if (isWide) ...[
              const SizedBox(width: 12),
              ReadingModeCapsule(
                currentMode: readSetting.readMode,
                onModeChanged: (mode) {
                  cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
                  widget.changePageIndex(0);
                },
              ),
              const SizedBox(width: 8),
              DoublePageToggle(
                isDoublePage: readSetting.doublePageMode,
                onToggle: (isDouble) {
                  // 不在这里动阅读位置：单/双页换的是「槽位怎么切」，
                  // 位置由阅读器按「同一张图」重算（见
                  // `_ComicReadPageState._syncPairingLayoutChange`）。
                  // 以前这里跟着 `changePageIndex(0)`，等于每次切换都回到第一页。
                  cubit.updateReadSetting(
                    (s) => s.copyWith(doublePageMode: isDouble),
                  );
                },
                isWide: true,
              ),
              // 阅读方向（右开 ⇄ 左开，即下一页在右还是在左）。只在横翻模式下可用；
              // **不动阅读位置** —— 两个方向同属 RowModeWidget，槽位含义不变，
              // 只是翻页语义反过来（左开下「下一页」在左边）。
              if (readSetting.readingDirectionToggle) ...[
                const SizedBox(width: 8),
                ReadingDirectionToggle(
                  currentMode: readSetting.readMode,
                  onModeChanged: (mode) {
                    cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
                  },
                ),
              ],
              const SizedBox(width: 12),
            ] else ...[
              const SizedBox(width: 6),
              CompactReadingModeButton(
                currentMode: readSetting.readMode,
                onModeChanged: (mode) {
                  final previousMode = readSetting.readMode;
                  cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
                  // 窄屏没有那颗方向按钮，这颗循环按钮要顺手把方向也切了，
                  // 所以它**只在跨条漫时**归位：右开⇄左开清零等于「切个方向
                  // 跳回第一页」（宽屏那条路同一个道理）。
                  if ((previousMode == kReadModeColumn) !=
                      (mode == kReadModeColumn)) {
                    widget.changePageIndex(0);
                  }
                },
              ),
              const SizedBox(width: 4),
            ],

            // 4. 右侧功能区 (下载、超分、自动阅读、二级工具展开、全屏、设置)
            if (widget.type != ComicEntryType.download &&
                widget.type != ComicEntryType.historyAndDownload &&
                widget.from.isNotEmpty &&
                !isLocalComicSource(widget.from, widget.comicId)) ...[
              ReaderDownloadButton(
                from: widget.from,
                comicId: widget.comicId,
                comicTitle: bookTitle ?? widget.title,
                comicInfo: widget.comicInfo,
                chapterRefs: widget.chapterRefs,
              ),
              const SizedBox(width: 4),
            ],
            ReaderUpscaleStatusChip(availableWidth: availableWidth),
            const SizedBox(width: 4),
            AutoScrollQuickButton(
              isEnabled: readSetting.autoScroll,
              isPaused: widget.isAutoReadPaused?.call() ?? false,
              onToggleAutoScroll: (enabled) {
                cubit.updateReadSetting((s) => s.copyWith(autoScroll: enabled));
              },
              onTogglePause: widget.onToggleAutoRead,
            ),
            const SizedBox(width: 4),
            _buildSecondaryExpandButton(context),
            if (widget.onToggleFullscreen != null) ...[
              const SizedBox(width: 2),
              IconButton(
                tooltip: widget.isDesktopFullscreen
                    ? t.reader.exitFullscreen
                    : t.reader.enterFullscreen,
                onPressed: widget.onToggleFullscreen,
                icon: Icon(
                  widget.isDesktopFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 20,
                ),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            // 钉住顶栏（neo 的 edge `pinned`）：钉住之后这一条不再被「点中间收起」
            // 或指针离开边缘收走；取消钉住立刻交还给那两套自动收起。
            IconButton(
              tooltip: readSetting.topBarPinned
                  ? t.reader.unpinTopBar
                  : t.reader.pinTopBar,
              color: readSetting.topBarPinned ? colorScheme.primary : null,
              icon: Icon(
                readSetting.topBarPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 20,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => cubit.updateReadSetting(
                (s) => s.copyWith(topBarPinned: !s.topBarPinned),
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              tooltip: t.reader.settings,
              icon: const Icon(Icons.tune_rounded, size: 20),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => showReaderSettingsSheet(
                context,
                changePageIndex: widget.changePageIndex,
                onLandscapeChanged: widget.onLandscapeChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 二级面板展开/折叠切换按钮
  Widget _buildSecondaryExpandButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _isSecondaryBarExpanded ? '收起版式工具' : '展开版式工具',
      child: IconButton(
        icon: AnimatedRotation(
          duration: const Duration(milliseconds: 200),
          turns: _isSecondaryBarExpanded ? 0.5 : 0.0,
          child: Icon(
            _isSecondaryBarExpanded
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded,
            size: 22,
            color: _isSecondaryBarExpanded
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        style: IconButton.styleFrom(
          backgroundColor: _isSecondaryBarExpanded
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () {
          setState(() {
            _isSecondaryBarExpanded = !_isSecondaryBarExpanded;
          });
        },
      ),
    );
  }
}
