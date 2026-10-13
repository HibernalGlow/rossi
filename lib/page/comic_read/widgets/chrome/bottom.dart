import 'dart:math' as math;
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/jump_chapter.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_bottom_toolbar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_chrome_transition.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom_thumbnail_strip.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/video/view/reader_video_controls_scope.dart';

part 'bottom_controls_layout_part.dart';

class BottomWidget extends StatefulWidget {
  final ComicEntryType type;
  final dynamic comicInfo;

  /// 进度条构造器，参数是「要不要嵌进父级玻璃面板」。
  ///
  /// 展开缩略图时两者要并成同一块玻璃（`embedded: true`），播放器不能预先
  /// 造好一个固定形态的 widget —— 那会让进度条永远自带材质。
  final Widget Function(bool embedded) sliderBuilder;

  final int order;
  final int epsNumber;
  final String comicId;
  final String from;
  final JumpChapter jumpChapter;
  final ValueChanged<bool>? onLandscapeChanged;
  final ValueChanged<int>? onJumpToSlot;

  const BottomWidget({
    super.key,
    required this.type,
    required this.comicInfo,
    required this.sliderBuilder,
    required this.order,
    required this.epsNumber,
    required this.comicId,
    required this.from,
    required this.jumpChapter,
    this.onLandscapeChanged,
    this.onJumpToSlot,
  });

  @override
  State<BottomWidget> createState() => _BottomWidgetState();
}

class _BottomWidgetState extends State<BottomWidget> {
  bool get isDownload =>
      widget.type == ComicEntryType.download ||
      widget.type == ComicEntryType.historyAndDownload;

  JumpChapter get jumpChapter => widget.jumpChapter;

  /// 缩略图条的展开高度。并进控制栏面板后比独立浮条矮一点，
  /// 免得「一块面板顶掉半屏漫画」。
  static const double _fusedStripHeight = 92;

  late ComicEntryType tempType;
  late String comicId;
  List<UnifiedComicChapterRef> chapterRefs = [];

  @override
  void initState() {
    super.initState();

    tempType = widget.type;
    comicId = widget.comicId;
    if (tempType == ComicEntryType.historyAndDownload) {
      tempType = ComicEntryType.download;
    }
    if (tempType == ComicEntryType.history) {
      tempType = ComicEntryType.normal;
    }
    chapterRefs = resolveUnifiedComicChapters(widget.comicInfo, widget.from);
  }

  /// 缩略图条的显隐住在**全局设置**里，不是本 State。
  ///
  /// 本 State 每个阅读 route 一份，换书 / 换章（`router.replace` 换 key）
  /// 都会重建 —— 放这里就表现为「开新书就重置」。
  void _setThumbnailStripVisible(bool visible) {
    context.read<GlobalSettingCubit>().updateReadSetting(
      (current) => current.copyWith(showThumbnailStrip: visible),
    );
  }

  void _jumpToSlot(int index) {
    if (widget.onJumpToSlot != null) {
      widget.onJumpToSlot!(index);
    } else {
      ReaderSessionCoordinator.instance.jumpTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ReaderVideoControlsScope.of(context);
    if (scope == null) return _buildBottomBar(context);
    return ValueListenableBuilder<ReaderVideoControls?>(
      valueListenable: scope.slot,
      builder: (context, controls, _) => ListenableBuilder(
        listenable: controls?.panelsOpen ?? scope.slot,
        builder: (context, _) => _buildBottomBar(
          context,
          videoControls: controls?.isCurrent() == true ? controls : null,
          integrateVideo: scope.enabled,
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context, {
    ReaderVideoControls? videoControls,
    bool integrateVideo = false,
  }) {
    final pinned = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.bottomBarPinned,
    );
    // `pinned` 放进选择器**里面**：只在这个 bool 翻转时重建，不被翻页带着走。
    final readerBottomVisible = context.select(
      (ReaderCubit cubit) => cubit.state.showBottomBar(pinned: pinned),
    );
    final showVideoControls =
        videoControls != null &&
        (videoControls.pinned ||
            videoControls.panelsOpen.value ||
            (!integrateVideo && videoControls.visible));
    final showBottomBar = readerBottomVisible || showVideoControls;
    final hoverController = ReaderHoverScope.of(context);
    final currentSlot = context.select(
      (ReaderCubit cubit) => cubit.state.currentSlot,
    );
    final totalSlots = context.select(
      (ReaderCubit cubit) => cubit.state.totalSlots,
    );
    // 全局设置：跟随书籍/章节切换、跟随重启，不再被 route 的 State 重置。
    final showThumbnailStrip = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.readSetting.showThumbnailStrip,
    );
    // 底栏的胶卷与进度条跟着阅读方向镜像：左开（下一页在左）时第 1 页贴在右边，
    // 往左走才是往后翻 —— 与画面上翻页的方向同一套坐标系。
    final rightToLeft = context.select<GlobalSettingCubit, bool>(
      (cubit) => isReverseRowReadMode(cubit.state.readSetting.readMode),
    );
    // 墨水屏：控制条滑动的中间帧只会攒成残影，直接出图。
    final animate = context.select(
      (GlobalSettingCubit cubit) =>
          !cubit.state.eInkSetting.enabled &&
          !cubit.state.readSetting.noAnimation,
    );
    final bottomSafeHeight = context.bottomSafeHeight;

    final coordinator = ReaderSessionCoordinator.instance;
    final localSource = LocalReadSession.instance.currentSource;
    final docs = coordinator.docs;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final isWideLayout = screenWidth >= 840;
          final topMaxWidth = (screenWidth * 0.56)
              .clamp(380.0, 720.0)
              .toDouble();
          final bottomMaxWidth =
              (screenWidth * (screenWidth >= 1200 ? 0.62 : 0.74))
                  .clamp(560.0, 980.0)
                  .toDouble();
          final isCompactLayout =
              screenWidth >= 600 && MediaQuery.sizeOf(context).height <= 600;

          return IgnorePointer(
            ignoring: !showBottomBar,
            child: ExcludeFocus(
              excluding: !showBottomBar,
              child: ReaderChromeTransition(
                visible: showBottomBar,
                animate: animate,
                child: MouseRegion(
                  onEnter: (_) => hoverController?.onEnterBottomBar(),
                  onExit: (_) => hoverController?.onExitBottomBar(),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 6 + bottomSafeHeight),
                    child: videoControls != null
                        ? _buildHostedVideoControls(
                            controls: videoControls,
                            integrated: integrateVideo,
                            visible: showBottomBar,
                            showReaderControls: readerBottomVisible,
                            maxWidth: bottomMaxWidth,
                            isWideLayout: isWideLayout,
                            totalSlots: totalSlots,
                            currentSlot: currentSlot,
                            localSource: localSource,
                            docs: docs,
                            showThumbnailStrip: showThumbnailStrip,
                            rightToLeft: rightToLeft,
                            isCompactLayout: isCompactLayout,
                            topMaxWidth: topMaxWidth,
                          )
                        : isCompactLayout
                        ? _buildCompactControls(
                            maxWidth: bottomMaxWidth,
                            isWideLayout: isWideLayout,
                            totalSlots: totalSlots,
                            currentSlot: currentSlot,
                            localSource: localSource,
                            docs: docs,
                            showThumbnailStrip: showThumbnailStrip,
                            rightToLeft: rightToLeft,
                          )
                        : _buildRegularControls(
                            topMaxWidth: topMaxWidth,
                            bottomMaxWidth: bottomMaxWidth,
                            isWideLayout: isWideLayout,
                            totalSlots: totalSlots,
                            currentSlot: currentSlot,
                            localSource: localSource,
                            docs: docs,
                            showThumbnailStrip: showThumbnailStrip,
                            rightToLeft: rightToLeft,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlButtons({
    required int totalSlots,
    required bool showThumbnailStrip,
  }) => BlocSelector<GlobalSettingCubit, GlobalSettingState, bool>(
    selector: (state) => state.readSetting.bottomBarPinned,
    builder: (context, bottomPinned) => ReaderBottomToolbar(
      previousChapter: jumpChapter.havePrev ? () => _jumpToChapter(true) : null,
      nextChapter: jumpChapter.haveNext ? () => _jumpToChapter(false) : null,
      selectChapter: chapterRefs.isNotEmpty ? _selectJumpChapter : null,
      openSettings: _openSettingsPanel,
      goHome: () => popToRoot(context),
      toggleThumbnails: totalSlots > 1
          ? () => _setThumbnailStripVisible(!showThumbnailStrip)
          : null,
      togglePinned: () => context.read<GlobalSettingCubit>().updateReadSetting(
        (current) =>
            current.copyWith(bottomBarPinned: !current.bottomBarPinned),
      ),
      thumbnailsVisible: showThumbnailStrip && totalSlots > 1,
      pinned: bottomPinned,
    ),
  );

  void _openSettingsPanel() {
    final readerCubit = context.read<ReaderCubit>();
    showReaderSettingsSheet(
      context,
      changePageIndex: (int value) {
        readerCubit.updateCurrentSlot(value);
        readerCubit.updateSliderChanged(0.0);
      },
      onLandscapeChanged: widget.onLandscapeChanged,
      source: widget.from,
      comicId: widget.comicId,
    );
  }

  Future<bool> _bottomButtonDialog(
    BuildContext context,
    String title,
    String content,
  ) async {
    return await showPopupPanel<bool>(
          context: context,
          // 新入口没有 barrierDismissible：原来禁止点外部关闭，现在点外部也会关掉。
          presentation: PopupPresentation.modal,
          builder: (BuildContext context) {
            return PopupPanel(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  child: Text(t.common.cancel),
                  onPressed: () {
                    Navigator.of(context).pop(false); // 返回 false
                  },
                ),
                TextButton(
                  child: Text(t.common.ok),
                  onPressed: () {
                    Navigator.of(context).pop(true); // 返回 true
                  },
                ),
              ],
            );
          },
        ) ??
        false; // 处理返回值为空的情况
  }

  Future<void> _jumpToChapter(bool isPrev) async {
    final dialogMessage = isPrev
        ? t.reader.previousChapter
        : t.reader.nextChapter;
    final result = await _bottomButtonDialog(
      context,
      t.reader.jumpToChapterTitle,
      t.reader.jumpToChapterMessage(chapter: dialogMessage),
    );
    if (!result) return;
    if (!mounted) return;
    jumpChapter.jumpToChapter(context, isPrev);
  }

  Future<void> _selectJumpChapter() async {
    final router = AutoRouter.of(context);
    final initialIndex = jumpChapter.currentChapterIndexIn(chapterRefs);
    final result = await showPopupPanel<UnifiedComicChapterRef?>(
      presentation: PopupPresentation.relative,
      context: context,
      // 新入口没有 barrierDismissible：原来禁止点外部关闭，现在点外部也会关掉。
      builder: (BuildContext context) {
        return _ChapterPickerDialog(
          refs: chapterRefs,
          initialIndex: initialIndex,
          onSelected: (ep) =>
              Navigator.of(context, rootNavigator: false).pop(ep),
        );
      },
    );
    if (result != null && mounted) {
      final chapter = const DownloadChapterAdapter().fromChapterRef(result);
      router.replace(
        ComicReadRoute(
          key: Key(Uuid().v4()),
          comicInfo: widget.comicInfo,
          comicId: comicId,
          type: tempType,
          order: chapter.order,
          chapterId: chapter.id,
          requestId: result.requestId.trim(),
          storageChapterId: chapter.effectiveStorageId,
          logicalKey: chapter.id,
          chapterExtern: Map<String, dynamic>.from(chapter.extern),
          epsNumber: widget.epsNumber,
          from: widget.from,
          stringSelectCubit: context.read<StringSelectCubit>(),
        ),
      );
    }
  }
}

class _ChapterPickerDialog extends StatefulWidget {
  final List<UnifiedComicChapterRef> refs;
  final int initialIndex;
  final ValueChanged<UnifiedComicChapterRef> onSelected;

  const _ChapterPickerDialog({
    required this.refs,
    required this.initialIndex,
    required this.onSelected,
  });

  @override
  State<_ChapterPickerDialog> createState() => _ChapterPickerDialogState();
}

class _ChapterPickerDialogState extends State<_ChapterPickerDialog> {
  // 行高只是估算（章节名可能换行），用于对话框高度与首屏定位；
  // 精确定位靠 _targetKey + ensureVisible。
  static const double _estimatedRowHeight = 52.0;
  static const double _estimatedGroupHeaderHeight = 36.0;
  static const int _maxRevealAttempts = 3;

  GlobalKey? _targetKey;
  late final ScrollController _scrollController;
  int _revealAttempts = 0;

  /// 扁平行：组头（不可点）与章节交错，单组时无组头，与今天一致。
  late final List<_PickerRow> _rows = _buildRows(widget.refs);
  late final int _initialRow = _hasValidInitial
      ? _rows.indexWhere(
          (row) =>
              row is _PickerChapterRow &&
              row.globalIndex == widget.initialIndex,
        )
      : -1;

  bool get _hasValidInitial =>
      widget.initialIndex >= 0 && widget.initialIndex < widget.refs.length;

  static List<_PickerRow> _buildRows(List<UnifiedComicChapterRef> refs) {
    final groups = groupChaptersByTitle<UnifiedComicChapterRef>(
      refs,
      (ref) => ref.groupTitle,
    );
    if (groups.length <= 1) {
      return [
        for (var i = 0; i < refs.length; i++)
          _PickerChapterRow(ref: refs[i], globalIndex: i),
      ];
    }
    final rows = <_PickerRow>[];
    var globalIndex = 0;
    for (final group in groups) {
      rows.add(_PickerGroupRow(title: group.title));
      for (final ref in group.items) {
        rows.add(_PickerChapterRow(ref: ref, globalIndex: globalIndex));
        globalIndex++;
      }
    }
    return rows;
  }

  double _estimatedOffsetForRow(int row) {
    var offset = 0.0;
    for (var i = 0; i < row && i < _rows.length; i++) {
      offset += _rows[i] is _PickerGroupRow
          ? _estimatedGroupHeaderHeight
          : _estimatedRowHeight;
    }
    return offset;
  }

  @override
  void initState() {
    super.initState();
    // 原来是 List.generate(refs.length) 建 N 个 GlobalKey，
    // 全局注册 + 阻碍复用；现在只给当前章节留 1 个。
    if (_initialRow >= 0) {
      _targetKey = GlobalKey();
      _scrollController = ScrollController(
        initialScrollOffset: _estimatedOffsetForRow(_initialRow),
      );
    } else {
      _scrollController = ScrollController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitial());
  }

  /// 直接定位到当前章节（无动画）。目标行还没建出来时先跳到估算位置，
  /// 下一帧再精确定位；超过次数就停在估算位置附近，不死循环。
  void _revealInitial() {
    if (!mounted || _revealAttempts >= _maxRevealAttempts) return;
    _revealAttempts++;
    final key = _targetKey;
    if (key == null || _initialRow < 0) return;
    final targetContext = key.currentContext;
    if (targetContext == null) {
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          _estimatedOffsetForRow(_initialRow).clamp(0.0, max),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitial());
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightStyle = TextButton.styleFrom(
      foregroundColor: colorScheme.onPrimaryContainer,
      backgroundColor: colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    // 定高（按估算行高撑，封顶 60% 屏高）：ListView 高度有界，
    // 不用 shrinkWrap 也能懒加载，只建可视行。
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = screenSize.height * 0.6;
    final listHeight = (_estimatedOffsetForRow(_rows.length) + 16).clamp(
      120.0,
      maxHeight,
    );
    // 桌面端别撑满：最多 440，手机上占 90% 屏宽。
    final listWidth = (screenSize.width * 0.9).clamp(0.0, 440.0).toDouble();

    return PopupPanel(
      title: Text(t.reader.selectChapter),
      content: SizedBox(
        width: listWidth,
        height: listHeight,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _rows.length,
          itemBuilder: (context, i) {
            final row = _rows[i];
            if (row is _PickerGroupRow) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Text(
                  chapterGroupDisplayTitle(
                    row.title,
                    t.comicInfo.untitledGroup,
                  ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }
            final chapterRow = row as _PickerChapterRow;
            final ref = chapterRow.ref;
            final isCurrent = i == _initialRow;
            return Padding(
              key: isCurrent ? _targetKey : null,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: TextButton(
                style: isCurrent ? highlightStyle : null,
                onPressed: () => widget.onSelected(ref),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapterDisplayName(
                          name: ref.name,
                          groupTitle: ref.groupTitle,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      GlyphIcon(
                        AppGlyphs.checkCircle,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          child: Text(t.common.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

sealed class _PickerRow {
  const _PickerRow();
}

/// 组头行（不可点）。单组时无此行。
class _PickerGroupRow extends _PickerRow {
  const _PickerGroupRow({required this.title});

  final String title;
}

/// 章节行，[globalIndex] 对应 refs 下标（用于定位当前章）。
class _PickerChapterRow extends _PickerRow {
  const _PickerChapterRow({required this.ref, required this.globalIndex});

  final UnifiedComicChapterRef ref;
  final int globalIndex;
}

class ChapterNavigationButton extends StatelessWidget {
  final Glyph icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onTap;

  const ChapterNavigationButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return _FrostedCircleIconButton(
      tooltip: tooltip,
      isEnabled: isEnabled,
      onPressed: onTap,
      icon: icon,
      foregroundColor: colorScheme.onSecondaryContainer,
      backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.72),
      disabledBackgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.38,
      ),
    );
  }
}

class FloatingActionIconButton extends StatelessWidget {
  final Glyph icon;
  final String tooltip;
  final bool isEnabled;
  final bool isSelected;
  final VoidCallback onPressed;

  const FloatingActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.isEnabled = true,
    this.isSelected = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    return _FrostedCircleIconButton(
      tooltip: tooltip,
      isEnabled: isEnabled,
      onPressed: onPressed,
      icon: icon,
      filled: isSelected,
      foregroundColor: isSelected
          ? colorScheme.onPrimary
          : colorScheme.onPrimaryContainer,
      backgroundColor: isSelected
          ? colorScheme.primary
          : colorScheme.primaryContainer.withValues(alpha: 0.76),
      disabledBackgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.38,
      ),
    );
  }
}

class _FrostedCircleIconButton extends StatelessWidget {
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onPressed;
  final Glyph icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color disabledBackgroundColor;

  const _FrostedCircleIconButton({
    required this.tooltip,
    required this.isEnabled,
    required this.onPressed,
    required this.icon,
    this.filled = false,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.disabledBackgroundColor,
  });

  /// 选中即填充：开关那颗（钉住）fill 0→1，与顶栏/侧栏同一口径。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return LiquidGlassSurface(
      // 44px 小圆钮：全套面板阴影会重得离谱，按体量收小。
      thickness: LiquidGlassThickness.thick,
      radius: 999,
      shadowScale: 0.3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: isEnabled ? onPressed : null,
        style: IconButton.styleFrom(
          fixedSize: const Size(48, 48),
          shape: const CircleBorder(),
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          disabledForegroundColor: colorScheme.onSurface.withValues(
            alpha: 0.38,
          ),
          disabledBackgroundColor: disabledBackgroundColor,
        ),
        icon: AnimatedGlyph(glyph: icon, filled: filled),
      ),
    );
  }
}
