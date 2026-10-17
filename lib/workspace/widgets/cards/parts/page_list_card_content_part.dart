part of '../page_list_card.dart';

extension _PageListContentPart on _PageListCardState {
  /// 构建中间展示区的列表/网格/展墙主体。
  ///
  /// 始终挂载 [LibraryEditorialCanvas]（即使尚未打开书本或搜索无匹配项，也经由
  /// `legacyBuilder` 呈现空态），确保顶部「搜索栏」小组件中的 [LibraryPresentationButton]
  /// 随时都能通过 `_ctrl.canvasKey.currentState` 呼出展墙设置或长按切换展墙模式。
  Widget _buildViewportList({
    required ReaderSessionCoordinator coordinator,
    required int currentSlot,
    required int totalSlots,
    bool hasSession = true,
  }) {
    final theme = Theme.of(context);
    // 格子里的页序要跟阅读画面上的一致：阅读器开了页面排序时，
    // 按页表下标取会让「第 N 格」显示成另一页，点下去跳过去的却是画面那一页。
    final docs = hasSession ? coordinator.orderedDocs : const <Doc>[];
    final query = _ctrl.searchQuery;

    // 过滤页面列表
    final List<int> filteredIndices = [];
    if (hasSession) {
      for (int i = 0; i < totalSlots; i++) {
        if (query.isEmpty) {
          filteredIndices.add(i);
        } else {
          final pageNumStr = '${i + 1}';
          final name = i < docs.length
              ? docs[i].originalName.toLowerCase()
              : '';
          if (pageNumStr.contains(query) || name.contains(query)) {
            filteredIndices.add(i);
          }
        }
      }
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: LibraryEditorialCanvas(
        key: _ctrl.canvasKey,
        scope: 'reader-pages',
        standalone: true,
        initialPresentation: const LibraryPresentation(
          editorial: false,
          hero: false,
          weight: LibraryWeight.imageShape,
        ),
        viewToken: _ctrl.viewMode,
        entries: [
          for (final pageIndex in filteredIndices)
            LibraryEntry(
              key: 'page:$pageIndex',
              title: '#${pageIndex + 1}',
              source: pageIndex,
              preserveMedia: true,
              media:
                  (
                    context, {
                    required width,
                    required height,
                    required radius,
                    required fit,
                  }) => ReaderThumbnailWidget(
                    index: pageIndex,
                    doc: pageIndex < docs.length ? docs[pageIndex] : null,
                    localSource: coordinator.localSource,
                    comicId: coordinator.comicId ?? '',
                    from: coordinator.from ?? '',
                    width: width,
                    height: height,
                    fit: BoxFit.contain,
                    borderRadius: radius,
                  ),
            ),
        ],
        onPresentationChanged: (value) {
          _ctrl.setPageEditorial(value.editorial);
        },
        onTap: (entry) => coordinator.jumpTo(entry.source! as int),
        cardBuilder: (_, entry, tap) => _buildThumbnailGridTile(
          coordinator: coordinator,
          pageIndex: entry.source! as int,
          doc: (entry.source! as int) < docs.length
              ? docs[entry.source! as int]
              : null,
          isActive: entry.source == currentSlot,
        ),
        legacyBuilder: (_) {
          if (!hasSession) {
            return _buildEmptyContent();
          }
          if (filteredIndices.isEmpty) {
            return Center(
              child: Text(
                t.workspace.noMatchingPages,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return _buildContentByMode(
            coordinator: coordinator,
            filteredIndices: filteredIndices,
            currentSlot: currentSlot,
            docs: docs,
          );
        },
      ),
    );
  }

  /// 独立挂载模式（`isStandalone: true`）：组合搜索工具条 + 中间展示区 + 底部跳转条。
  Widget _buildStandaloneActiveContent({
    required ReaderSessionCoordinator coordinator,
    required int currentSlot,
    required int totalSlots,
  }) {
    final listWidget = _buildViewportList(
      coordinator: coordinator,
      currentSlot: currentSlot,
      totalSlots: totalSlots,
    );

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageListSearchToolbar(controller: _ctrl),
          const SizedBox(height: 8),
          Expanded(child: listWidget),
          const SizedBox(height: 8),
          PageListJumpToolbar(
            coordinator: coordinator,
            controller: _ctrl,
            currentSlot: currentSlot,
            totalSlots: totalSlots,
          ),
        ],
      ),
    );
  }
}
