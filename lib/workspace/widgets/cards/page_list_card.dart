import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

enum PageListViewMode { thumbnails, details, list }

/// 工作区页面列表卡片（Page List Card / 页面导航）。
///
/// 参考 NeoView `PageNavigationCard` 设计，支持 3 种展示模式、搜索过滤、
/// 跟随阅读进度自动滚动、缩略图预览及精准跳转。
class PageListCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const PageListCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<PageListCard> createState() => _PageListCardState();
}

class _PageListCardState extends State<PageListCard> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _jumpPageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  PageListViewMode _viewMode = PageListViewMode.thumbnails;
  bool _followProgress = true;
  String _searchQuery = '';
  int _lastFollowedSlot = -1;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim().toLowerCase();
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
        });
      }
    });

    ReaderSessionCoordinator.instance.addListener(_onCoordinatorUpdate);
  }

  @override
  void dispose() {
    ReaderSessionCoordinator.instance.removeListener(_onCoordinatorUpdate);
    _searchController.dispose();
    _jumpPageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCoordinatorUpdate() {
    final coordinator = ReaderSessionCoordinator.instance;
    if (_followProgress &&
        coordinator.hasActiveSession &&
        _searchQuery.isEmpty &&
        coordinator.currentSlot != _lastFollowedSlot) {
      _lastFollowedSlot = coordinator.currentSlot;
      _scrollToPosition(coordinator.currentSlot);
    }
  }

  void _scrollToPosition(int position) {
    if (!_scrollController.hasClients) return;
    double itemHeight;
    int itemsPerRow = 1;

    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        itemHeight = 136.0;
        itemsPerRow = 3;
        break;
      case PageListViewMode.details:
        itemHeight = 72.0;
        itemsPerRow = 1;
        break;
      case PageListViewMode.list:
        itemHeight = 38.0;
        itemsPerRow = 1;
        break;
    }

    final rowIndex = position ~/ itemsPerRow;
    final targetOffset = (rowIndex * itemHeight) - 100.0;
    final clamped = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToPageInput() {
    final text = _jumpPageController.text.trim();
    final pageNumber = int.tryParse(text);
    final coordinator = ReaderSessionCoordinator.instance;
    if (pageNumber != null &&
        pageNumber >= 1 &&
        pageNumber <= coordinator.totalSlots) {
      coordinator.jumpTo(pageNumber - 1);
      FocusScope.of(context).unfocus();
    }
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
                ? _buildActiveContent(
                    coordinator: coordinator,
                    currentSlot: currentSlot,
                    totalSlots: totalPages,
                  )
                : _buildEmptyContent(),
          );
        }

        return CollapsibleCard(
          cardId: WorkspaceCardRegistry.pageList,
          title: '页面导航 (${hasSession ? "$totalPages P" : "空闲"})',
          icon: Icons.view_carousel_rounded,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          trailing: hasSession
              ? Text(
                  '${currentSlot + 1} / $totalPages',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : null,
          child: hasSession
              ? _buildActiveContent(
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
        Icon(
          Icons.auto_stories_outlined,
          size: 38,
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 10),
        Text(
          '打开书本后显示页面导航',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
    if (widget.isStandalone) {
      return Center(child: emptyWidget);
    }
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: emptyWidget,
    );
  }

  Widget _buildActiveContent({
    required ReaderSessionCoordinator coordinator,
    required int currentSlot,
    required int totalSlots,
  }) {
    final theme = Theme.of(context);
    final docs = coordinator.docs;

    // 过滤页面列表
    final List<int> filteredIndices = [];
    for (int i = 0; i < totalSlots; i++) {
      if (_searchQuery.isEmpty) {
        filteredIndices.add(i);
      } else {
        final pageNumStr = '${i + 1}';
        final name = i < docs.length ? docs[i].originalName.toLowerCase() : '';
        if (pageNumStr.contains(_searchQuery) || name.contains(_searchQuery)) {
          filteredIndices.add(i);
        }
      }
    }

    final listWidget = Material(
      color: theme.colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: filteredIndices.isEmpty
          ? Center(
              child: Text(
                '没有匹配的页面',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            )
          : _buildContentByMode(
              coordinator: coordinator,
              filteredIndices: filteredIndices,
              currentSlot: currentSlot,
              docs: docs,
            ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部工具栏：搜索框、跟随阅读进度、模式切换
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '搜索页码或文件名...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 跟随进度按钮
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: _followProgress ? '正在跟随阅读进度' : '已暂停跟随阅读进度',
                style: IconButton.styleFrom(
                  backgroundColor: _followProgress
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : null,
                  foregroundColor: _followProgress
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                onPressed: () {
                  setState(() {
                    _followProgress = !_followProgress;
                  });
                },
                icon: const Icon(Icons.gps_fixed_rounded),
              ),
              // 模式切换
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '视图模式',
                onPressed: _cycleViewMode,
                icon: Icon(_getViewModeIcon()),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 页面主体列表/网格（独占模式下撑满高度，聚合模式下最大 440）
          widget.isStandalone
              ? Expanded(child: listWidget)
              : ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 440,
                    minHeight: 180,
                  ),
                  child: listWidget,
                ),

          const SizedBox(height: 8),
          // 底部快捷跳转栏
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: currentSlot.toDouble().clamp(
                      0.0,
                      (totalSlots - 1).clamp(0, 999999).toDouble(),
                    ),
                    min: 0,
                    max: (totalSlots - 1).clamp(0, 999999).toDouble(),
                    onChanged: (value) {
                      coordinator.jumpTo(value.round());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 52,
                height: 28,
                child: TextField(
                  controller: _jumpPageController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    hintText: '页码',
                    hintStyle: const TextStyle(fontSize: 10),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onSubmitted: (_) => _jumpToPageInput(),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: _jumpToPageInput,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('跳转', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _cycleViewMode() {
    setState(() {
      switch (_viewMode) {
        case PageListViewMode.thumbnails:
          _viewMode = PageListViewMode.details;
          break;
        case PageListViewMode.details:
          _viewMode = PageListViewMode.list;
          break;
        case PageListViewMode.list:
          _viewMode = PageListViewMode.thumbnails;
          break;
      }
    });
  }

  IconData _getViewModeIcon() {
    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        return Icons.grid_view_rounded;
      case PageListViewMode.details:
        return Icons.view_agenda_rounded;
      case PageListViewMode.list:
        return Icons.view_list_rounded;
    }
  }

  Widget _buildContentByMode({
    required ReaderSessionCoordinator coordinator,
    required List<int> filteredIndices,
    required int currentSlot,
    required List<Doc> docs,
  }) {
    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
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
                ReaderThumbnailWidget(
                  index: pageIndex,
                  doc: doc,
                  localSource: coordinator.localSource,
                  comicId: coordinator.comicId ?? '',
                  from: coordinator.from ?? '',
                  fit: BoxFit.cover,
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
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: SizedBox(
          width: 42,
          height: 56,
          child: ReaderThumbnailWidget(
            index: pageIndex,
            doc: doc,
            localSource: coordinator.localSource,
            comicId: coordinator.comicId ?? '',
            from: coordinator.from ?? '',
            fit: BoxFit.cover,
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Row(
            children: [
              Text(
                '#${pageIndex + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              if (isActive)
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
