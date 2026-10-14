part of '../folder_shelf_page.dart';

extension _FolderShelfContentPart on _FolderShelfPageContentState {
  Widget _buildBody(BuildContext context) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      builder: (context, searchState) {
        return BlocBuilder<FolderShelfBloc, FolderShelfState>(
          builder: (context, state) {
            final keyword = _FolderShelfPageContentState._normalizeSearchText(
              searchState.stateOf(state.mode).keyword,
            );
            // 搜索时只展示漫画，不展示文件夹。
            final filteredFolders = keyword.isEmpty
                ? state.folders
                : <ComicFolder>[];
            final filteredComics = keyword.isEmpty
                ? state.comics
                : state.comics.where((c) {
                    final key = '${c.from.trim()}:${c.id}';
                    final searchText = state.comicSearchTexts[key] ?? '';
                    return searchText.contains(keyword);
                  }).toList();

            final totalCount = filteredFolders.length + filteredComics.length;
            final isInitialLoading = state.isLoading && totalCount == 0;

            if (isInitialLoading) {
              return const Stack(
                children: [
                  BookshelfGridShimmer(),
                  Center(child: BookshelfLoadingView()),
                ],
              );
            }

            if (totalCount == 0) {
              return BookshelfEmptyView(
                onRefresh: () => context.read<FolderShelfBloc>().add(
                  const FolderShelfLoadRequested(),
                ),
              );
            }

            final comicType = _FolderShelfPageContentState._comicEntryTypeOf(
              state.mode,
            );
            final folderSyncIdMap = _buildSyncIdMap(state.mode);
            String folderPathOf(ComicFolder f) =>
                ComicFolderService.folderPath(f, syncIdMap: folderSyncIdMap);

            return RefreshIndicator(
              onRefresh: () async {
                context.read<FolderShelfBloc>().add(
                  const FolderShelfLoadRequested(),
                );
              },
              child: Stack(
                children: [
                  _buildEditorialLibrary(
                    context,
                    state,
                    filteredFolders,
                    filteredComics,
                    folderPathOf: folderPathOf,
                    legacyBuilder: (context) => GridView.builder(
                      // 悬浮物盖在列表上层：子文件夹有面包屑浮栏，留 64px 顶部滚动边距；
                      // 根目录无顶部悬浮物，选择模式无悬浮物，均保持 10。
                      // 右下角按钮 56px + bottom 16：底部留 88，避免挡住最后一行漫画。
                      padding: EdgeInsets.fromLTRB(
                        10,
                        state.selectionMode ? 10 : (state.isRoot ? 10 : 64),
                        10,
                        88,
                      ),
                      gridDelegate: buildComicSimplifyEntryGridDelegate(),
                      itemCount: totalCount,
                      itemBuilder: (context, index) {
                        if (index < filteredFolders.length) {
                          final folder = filteredFolders[index];
                          final folderPath = folderPathOf(folder);
                          final isSelected = state.selectedFolderPaths.contains(
                            folderPath,
                          );
                          return FolderShelfItem(
                            key: ValueKey('folder-${folder.uniqueKey}'),
                            folder: folder,
                            selectionMode: state.selectionMode,
                            isSelected: isSelected,
                            onTap: state.selectionMode
                                ? () => context.read<FolderShelfBloc>().add(
                                    FolderShelfToggleFolderSelection(
                                      folderPath,
                                    ),
                                  )
                                : () => context.read<FolderShelfBloc>().add(
                                    FolderShelfEnterFolder(folderPath),
                                  ),
                            onLongPress: state.selectionMode
                                ? (details) =>
                                      context.read<FolderShelfBloc>().add(
                                        FolderShelfToggleFolderSelection(
                                          folderPath,
                                        ),
                                      )
                                : (details) => _showFolderActions(
                                    context,
                                    folder,
                                    folderPath,
                                    details.globalPosition,
                                  ),
                            onSecondaryTapDown: state.selectionMode
                                ? null
                                : (details) => _showFolderActions(
                                    context,
                                    folder,
                                    folderPath,
                                    details.globalPosition,
                                  ),
                          );
                        }
                        final comicIndex = index - filteredFolders.length;
                        final comic = filteredComics[comicIndex];
                        final comicUniqueKey =
                            '${comic.from.trim()}:${comic.id}';
                        final isComicSelected = state.selectedComicKeys
                            .contains(comicUniqueKey);
                        return ComicSimplifyEntry(
                          key: ValueKey('comic-${comic.from}:${comic.id}'),
                          info: comic,
                          type: comicType,
                          selectionMode: state.selectionMode,
                          isSelected: isComicSelected,
                          unread: state.unreadComicKeys.contains(
                            comicUniqueKey,
                          ),
                          refresh: () => context.read<FolderShelfBloc>().add(
                            const FolderShelfLoadRequested(),
                          ),
                          onTapOverride: state.selectionMode
                              ? (info) => context.read<FolderShelfBloc>().add(
                                  FolderShelfToggleComicSelection(
                                    '${info.from.trim()}:${info.id}',
                                  ),
                                )
                              : null,
                          onLongPressOverride: state.selectionMode
                              ? (info, details) =>
                                    context.read<FolderShelfBloc>().add(
                                      FolderShelfToggleComicSelection(
                                        '${info.from.trim()}:${info.id}',
                                      ),
                                    )
                              : (info, details) => _showComicActions(
                                  context,
                                  info,
                                  details.globalPosition,
                                ),
                          onSecondaryTapDown: state.selectionMode
                              ? null
                              : (info, details) => _showComicActions(
                                  context,
                                  info,
                                  details.globalPosition,
                                ),
                        );
                      },
                    ),
                  ),
                  if (state.isLoading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  _buildSelectionBar(context, state),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionBar(BuildContext context, FolderShelfState state) {
    return Positioned(
      // 移动端 body 的 padding.bottom 就是 Dock 的实际占位（`extendBody` 由
      // Scaffold 写进来，见 navigation_bar.dart 的 `_buildDockLayout`）；
      // 裸 Positioned 不认这个留位，要自己加，否则整条被胶囊压在下面。
      bottom: 8 + MediaQuery.paddingOf(context).bottom,
      left: 8,
      right: 8,
      child: IgnorePointer(
        ignoring: !state.selectionMode,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: state.selectionMode ? Offset.zero : const Offset(0, 1.0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: state.selectionMode ? 1 : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: t.common.cancel,
                            onPressed: () => context
                                .read<FolderShelfBloc>()
                                .add(const FolderShelfExitSelectionMode()),
                            icon: const GlyphIcon(AppGlyphs.close),
                          ),
                          Text(
                            t.bookshelf.selectedCount(
                              count: state.selectedCount,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => context
                                .read<FolderShelfBloc>()
                                .add(const FolderShelfSelectAll()),
                            child: Text(t.common.selectAll),
                          ),
                          if (state.mode != ShelfPageMode.history)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: t.bookshelf.moveTo,
                              onPressed: state.hasSelection
                                  ? () => _showTargetFolderDialog(
                                      context,
                                      onConfirmed: (targets) {
                                        context.read<FolderShelfBloc>().add(
                                          FolderShelfMoveSelected(targets),
                                        );
                                      },
                                    )
                                  : null,
                              icon: const GlyphIcon(AppGlyphs.folderCopy),
                            ),
                          if (state.mode != ShelfPageMode.history)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: t.bookshelf.copyTo,
                              onPressed: state.hasSelection
                                  ? () => _showTargetFolderDialog(
                                      context,
                                      onConfirmed: (targets) {
                                        context.read<FolderShelfBloc>().add(
                                          FolderShelfCopySelected(targets),
                                        );
                                      },
                                    )
                                  : null,
                              icon: const GlyphIcon(AppGlyphs.folderCopy),
                            ),
                          if (state.mode == ShelfPageMode.download)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: t.bookshelf.batchExport,
                              onPressed: state.hasSelection
                                  ? () => _batchExportSelected(context, state)
                                  : null,
                              icon: const GlyphIcon(AppGlyphs.arrowUp),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: t.common.delete,
                            onPressed: state.hasSelection
                                ? () => _confirmDeleteSelected(context)
                                : null,
                            icon: const GlyphIcon(AppGlyphs.delete),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
