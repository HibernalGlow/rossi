import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/widgets/library_image_geometry.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_jump_card.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_panel_controller.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_row_anchor.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_search_card.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

export 'package:zephyr/workspace/widgets/cards/page_list_jump_card.dart';
export 'package:zephyr/workspace/widgets/cards/page_list_panel_controller.dart';
export 'package:zephyr/workspace/widgets/cards/page_list_search_card.dart';

part 'parts/page_list_card_content_part.dart';

/// 工作区页面导航展示栏小组件（Page List Display Card）。
///
/// 在工作区面板网格中（`isStandalone: false`），作为无常驻标题栏的 MD3 Expressive 小组件，
/// 专注渲染中间的缩略图/详细/紧凑列表或原图展墙，并与 [PageListSearchCard]、[PageListJumpCard]
/// 共享 [PageListPanelController]，默认全宽且自动撑满面板剩余可视高度。
///
/// 当 `isStandalone: true` 时（供独立挂载与单测环境使用），内联组合搜索栏、展示区与跳转栏。
class PageListCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final PageListPanelController? controller;

  const PageListCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
    this.controller,
  });

  @override
  State<PageListCard> createState() => _PageListCardState();
}

class _PageListCardState extends State<PageListCard> {
  final ScrollController _scrollController = ScrollController();

  PageListPanelController? _localController;
  PageListPanelController get _ctrl =>
      widget.controller ?? _localController ?? PageListPanelController.instance;

  int _lastFollowedSlot = -1;
  int _pendingFollowSlot = -1;
  bool _followScheduled = false;
  int _lastFollowSignal = 0;

  /// 缩略图模式一行几列。网格的 `crossAxisCount` 与滚动定位必须共用这一个数，
  /// 否则「第几行」两边各算各的，居中就会落到隔壁行上。
  static const int _gridCrossAxisCount = 3;

  int get _itemsPerRow =>
      _ctrl.viewMode == PageListViewMode.thumbnails ? _gridCrossAxisCount : 1;

  @override
  void initState() {
    super.initState();
    if (widget.isStandalone && widget.controller == null) {
      _localController = PageListPanelController();
    }
    _lastFollowSignal = _ctrl.followSignal;
    _ctrl.addListener(_onPanelControllerChanged);
    ReaderSessionCoordinator.instance.addListener(_onCoordinatorUpdate);
    // 打开面板时当前页往往已经在几百页开外，而那一下进度通知早在卡片建出来之前就
    // 发完了 —— 补一次居中，不然「跟着进度」只剩「从下一页开始才跟」。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _followCurrent(force: true),
    );
  }

  @override
  void didUpdateWidget(PageListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.isStandalone != widget.isStandalone) {
      final oldCtrl =
          oldWidget.controller ??
          _localController ??
          PageListPanelController.instance;
      oldCtrl.removeListener(_onPanelControllerChanged);
      if (widget.isStandalone && widget.controller == null) {
        _localController ??= PageListPanelController();
      } else {
        _localController?.dispose();
        _localController = null;
      }
      _lastFollowSignal = _ctrl.followSignal;
      _ctrl.addListener(_onPanelControllerChanged);
    }
    // 折叠状态下内容不展开，展开这一下按真实的可见高度重新居中。
    if (!oldWidget.isExpanded && widget.isExpanded) {
      _followCurrent(force: true);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onPanelControllerChanged);
    _localController?.dispose();
    ReaderSessionCoordinator.instance.removeListener(_onCoordinatorUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPanelControllerChanged() {
    if (!mounted) return;
    if (_ctrl.followSignal != _lastFollowSignal) {
      _lastFollowSignal = _ctrl.followSignal;
      _followCurrent(force: _ctrl.forceFollow);
    }
    setState(() {});
  }

  void _onCoordinatorUpdate() {
    if (!_ctrl.followProgress) return;
    _followCurrent();
  }

  /// 跟随到当前页。有搜索过滤时列表只剩命中项，槽位和行号已经不再一一对应，
  /// 所以这时候不跟（跟了会滚到隔壁页）。
  ///
  /// [force] 给换视图模式、展开面板、初次建卡这三处用 —— 槽位没变，但可视区或
  /// 行的排布变了，不重算就会停在一个对不上号的位置。
  void _followCurrent({bool force = false}) {
    final coordinator = ReaderSessionCoordinator.instance;
    if (!coordinator.hasActiveSession || _ctrl.searchQuery.isNotEmpty) return;
    _scheduleFollow(coordinator.currentSlot, force: force);
  }

  void _scheduleFollow(int slot, {required bool force}) {
    if (!mounted) return;
    if (!force && slot == _lastFollowedSlot) return;
    _pendingFollowSlot = slot;
    if (_followScheduled) return;
    _followScheduled = true;
    // 量几何要等这一帧布局完成：动画本身有 260ms，延后一帧看不出来，而在布局
    // 途中读渲染树则可能拿到上一帧的可视区尺寸。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      _followTo(_pendingFollowSlot);
    });
  }

  /// 把 [slot] 所在的那一行滚到可视区正中。
  ///
  /// 量不出几何（还没布局好）时不动记账，下一次进度通知会再试一次。
  void _followTo(int slot) {
    if (!mounted || slot < 0) return;
    if (_ctrl.pageEditorial) {
      _ctrl.canvasKey.currentState?.revealEntry('page:$slot');
      _lastFollowedSlot = slot;
      return;
    }
    if (!_scrollController.hasClients) return;
    final anchor = PageListRowAnchor.measure(
      _scrollController.position,
      itemIndex: slot,
      itemsPerRow: _itemsPerRow,
    );
    if (anchor == null) return;
    _lastFollowedSlot = slot;
    _scrollController.animateTo(
      anchor.centeredOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = ReaderSessionCoordinator.instance;

    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final hasSession = coordinator.hasActiveSession;
        final totalPages = coordinator.totalSlots;
        final currentSlot = coordinator.currentSlot;

        if (widget.isStandalone) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: hasSession
                ? _buildStandaloneActiveContent(
                    coordinator: coordinator,
                    currentSlot: currentSlot,
                    totalSlots: totalPages,
                  )
                : _buildEmptyContent(),
          );
        }

        return CollapsibleCard(
          cardId: WorkspaceCardRegistry.pageList,
          title: '页面导航',
          icon: AppGlyphs.cardMedium,
          expressive: true,
          scrollContent: false,
          margin: EdgeInsets.zero,
          contentPadding: const EdgeInsets.all(6),
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          trailing: hasSession
              ? InfoCardCounter('${currentSlot + 1} / $totalPages')
              : const InfoCardCounter('空闲'),
          child: hasSession
              ? _buildViewportList(
                  coordinator: coordinator,
                  currentSlot: currentSlot,
                  totalSlots: totalPages,
                )
              : _buildEmptyContent(),
        );
      },
    );
  }

  Widget _buildEmptyContent() {
    final theme = Theme.of(context);
    final emptyWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(
          AppGlyphs.openBook,
          size: 38,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 10),
        Text(
          '打开书本后显示页面导航',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Center(child: emptyWidget);
  }

  Widget _buildContentByMode({
    required ReaderSessionCoordinator coordinator,
    required List<int> filteredIndices,
    required int currentSlot,
    required List<Doc> docs,
  }) {
    switch (_ctrl.viewMode) {
      case PageListViewMode.thumbnails:
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _gridCrossAxisCount,
            childAspectRatio: 0.68,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: filteredIndices.length,
          itemBuilder: (context, i) {
            final pageIndex = filteredIndices[i];
            final isActive = pageIndex == currentSlot;
            final doc = pageIndex < docs.length ? docs[pageIndex] : null;

            return _buildThumbnailGridTile(
              coordinator: coordinator,
              pageIndex: pageIndex,
              doc: doc,
              isActive: isActive,
            );
          },
        );

      case PageListViewMode.details:
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(4),
          itemCount: filteredIndices.length,
          itemBuilder: (context, i) {
            final pageIndex = filteredIndices[i];
            final isActive = pageIndex == currentSlot;
            final doc = pageIndex < docs.length ? docs[pageIndex] : null;

            return _buildDetailRow(
              coordinator: coordinator,
              pageIndex: pageIndex,
              doc: doc,
              isActive: isActive,
            );
          },
        );

      case PageListViewMode.list:
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(4),
          itemCount: filteredIndices.length,
          itemBuilder: (context, i) {
            final pageIndex = filteredIndices[i];
            final isActive = pageIndex == currentSlot;
            final doc = pageIndex < docs.length ? docs[pageIndex] : null;

            return _buildCompactListRow(
              coordinator: coordinator,
              pageIndex: pageIndex,
              doc: doc,
              isActive: isActive,
            );
          },
        );
    }
  }

  Widget _buildThumbnailGridTile({
    required ReaderSessionCoordinator coordinator,
    required int pageIndex,
    required Doc? doc,
    required bool isActive,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => coordinator.jumpTo(pageIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: isActive ? 2.0 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Builder(
                  builder: (context) {
                    final scale =
                        LibraryImageGeometryScope.maybeOf(
                          context,
                        )?.imageScale ??
                        1;
                    return Center(
                      child: FractionallySizedBox(
                        widthFactor: scale,
                        heightFactor: scale,
                        child: ReaderThumbnailWidget(
                          index: pageIndex,
                          doc: doc,
                          localSource: coordinator.localSource,
                          comicId: coordinator.comicId ?? '',
                          from: coordinator.from ?? '',
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    color: Colors.black.withValues(alpha: 0.72),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '#${pageIndex + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isActive
                                ? theme.colorScheme.primaryContainer
                                : Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required ReaderSessionCoordinator coordinator,
    required int pageIndex,
    required Doc? doc,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final name = doc?.originalName ?? '页面 ${pageIndex + 1}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isActive
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 2,
          ),
          leading: SizedBox(
            width: 42,
            height: 56,
            child: ReaderThumbnailWidget(
              index: pageIndex,
              doc: doc,
              localSource: coordinator.localSource,
              comicId: coordinator.comicId ?? '',
              from: coordinator.from ?? '',
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            '#${pageIndex + 1}  $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? theme.colorScheme.primary : null,
            ),
          ),
          trailing: isActive
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                )
              : null,
          onTap: () => coordinator.jumpTo(pageIndex),
        ),
      ),
    );
  }

  Widget _buildCompactListRow({
    required ReaderSessionCoordinator coordinator,
    required int pageIndex,
    required Doc? doc,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final name = doc?.originalName ?? '页面 ${pageIndex + 1}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => coordinator.jumpTo(pageIndex),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isActive
              ? theme.colorScheme.secondaryContainer
              : Colors.transparent,
          child: Row(
            children: [
              Text(
                '#${pageIndex + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isActive
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (isActive)
                GlyphIcon(
                  AppGlyphs.checkCircle,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
