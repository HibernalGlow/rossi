part of '../folder_shelf_page.dart';

extension _FolderShelfEditorialPart on _FolderShelfPageContentState {
  Widget _buildEditorialLibrary(
    BuildContext context,
    FolderShelfState state,
    List<ComicFolder> folders,
    List<ComicSimplifyEntryInfo> comics, {
    required String Function(ComicFolder) folderPathOf,
    required WidgetBuilder legacyBuilder,
  }) {
    // 选择态继续使用原有卡片与网格，避免将信息展开混入批量操作手势。
    if (state.selectionMode) return legacyBuilder(context);
    final histories = {
      for (final h in objectbox.unifiedHistoryBox.getAll())
        if (!h.deleted) h.uniqueKey: h,
    };
    final type = _FolderShelfPageContentState._comicEntryTypeOf(state.mode);
    final entries = <LibraryEntry>[
      for (final folder in folders)
        LibraryEntry(
          key: 'folder:${folder.uniqueKey}',
          title: folder.name,
          source: folder,
          section: '收藏夹',
          badge: const GlyphIcon(AppGlyphs.folder, size: 48),
        ),
      for (final comic in comics)
        _editorialComic(comic, state, histories, type),
    ];
    return LibraryEditorialCanvas(
      key: _canvasKey,
      scope: 'home:${state.mode.name}',
      entries: entries,
      standalone: true,
      padding: EdgeInsets.fromLTRB(10, state.isRoot ? 10 : 64, 10, 88),
      legacyBuilder: legacyBuilder,
      legacyFocusBuilder: (context, expandedDetails, toggle, onCoverTap) =>
          LayoutBuilder(
            builder: (context, constraints) => LibraryLegacyFocus(
              count: entries.length,
              columns: (constraints.maxWidth / 150).floor().clamp(1, 8),
              extent: 230,
              padding: EdgeInsets.fromLTRB(10, state.isRoot ? 10 : 64, 10, 88),
              details: {
                for (var i = 0; i < entries.length; i++)
                  if (expandedDetails.containsKey(entries[i].key))
                    i: expandedDetails[entries[i].key]!,
              },
              itemBuilder: (context, index) {
                final row = entries[index];
                if (row.source case final ComicFolder folder) {
                  return FolderShelfItem(
                    folder: folder,
                    selectionMode: false,
                    isSelected: false,
                    onTap: () => context.read<FolderShelfBloc>().add(
                      FolderShelfEnterFolder(folderPathOf(folder)),
                    ),
                    onLongPress: (details) => _showFolderActions(
                      context,
                      folder,
                      folderPathOf(folder),
                      details.globalPosition,
                    ),
                    onSecondaryTapDown: (details) => _showFolderActions(
                      context,
                      folder,
                      folderPathOf(folder),
                      details.globalPosition,
                    ),
                  );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ComicSimplifyEntry(
                      info: row.source! as ComicSimplifyEntryInfo,
                      type: type,
                      onTapOverride: (_) => onCoverTap(row),
                      onLongPressOverride: (info, details) => _showComicActions(
                        context,
                        info,
                        details.globalPosition,
                      ),
                      onSecondaryTapDown: (info, details) => _showComicActions(
                        context,
                        info,
                        details.globalPosition,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: IconButton.filledTonal(
                        tooltip: '展开信息',
                        onPressed: () => toggle(row),
                        icon: const GlyphIcon(AppGlyphs.info),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      onTap: (row) {
        if (row.source case final ComicFolder folder) {
          context.read<FolderShelfBloc>().add(
            FolderShelfEnterFolder(folderPathOf(folder)),
          );
        } else if (row.source case final ComicSimplifyEntryInfo comic) {
          ComicSimplifyEntry(info: comic, type: type).openDetails(context);
        }
      },
      // 文件夹始终导航；书本根据展墙偏好展开或沿用原详情导航。
      canShowDetail: (row) => row.source is ComicSimplifyEntryInfo,
      detailBuilder: (context, row, close) {
        final comic = row.source! as ComicSimplifyEntryInfo;
        return LibraryBookDetails(
          entry: row,
          comicId: comic.id,
          from: comic.source.trim().isEmpty ? comic.from : comic.source,
          type: type,
          onClose: close,
        );
      },
      wrapCard: (context, row, tile) => GestureDetector(
        onLongPressStart: (details) {
          if (row.source case final ComicFolder folder) {
            _showFolderActions(
              context,
              folder,
              folderPathOf(folder),
              details.globalPosition,
            );
          } else {
            _showComicActions(
              context,
              row.source! as ComicSimplifyEntryInfo,
              details.globalPosition,
            );
          }
        },
        onSecondaryTapDown: (details) {
          if (row.source case final ComicFolder folder) {
            _showFolderActions(
              context,
              folder,
              folderPathOf(folder),
              details.globalPosition,
            );
          } else {
            _showComicActions(
              context,
              row.source! as ComicSimplifyEntryInfo,
              details.globalPosition,
            );
          }
        },
        child: tile,
      ),
    );
  }

  LibraryEntry _editorialComic(
    ComicSimplifyEntryInfo comic,
    FolderShelfState state,
    Map<String, UnifiedComicHistory> histories,
    ComicEntryType type,
  ) {
    final key = '${comic.from.trim()}:${comic.id}';
    final history = histories[key];
    final unread = state.unreadComicKeys.contains(key);
    final from = comic.source.trim().isEmpty ? comic.from : comic.source;
    late final LibraryEntry row;
    row = LibraryEntry(
      key: key,
      title: comic.title,
      tags: comic.tags,
      source: comic,
      reading: history != null,
      timestamp: history?.lastReadAt,
      section: unread
          ? '未读作品'
          : history != null
          ? '正在阅读'
          : '藏书',
      subtitle: history == null
          ? comic.tags.take(3).join(' · ')
          : '${history.chapterTitle} · 第 ${history.pageIndex + 1} 页',
      metaText: unread
          ? '未读'
          : history != null
          ? '继续阅读'
          : '',
      onRead: () => startComicQuickRead(context, comicId: comic.id, from: from),
      media:
          (
            context, {
            required width,
            required height,
            required radius,
            required fit,
          }) => ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              width: width,
              height: height,
              child: ComicSimplifyEntry(
                info: comic,
                type: type,
                roundedCorner: false,
                showReadAction: false,
                showTitle: false,
                unread: unread,
                refresh: () => context.read<FolderShelfBloc>().add(
                  const FolderShelfLoadRequested(),
                ),
                onTapOverride: (_) {
                  final slot = LibraryInlineDetailScope.maybeOf(context);
                  if (slot != null) {
                    slot.onCoverTap();
                  } else {
                    _canvasKey.currentState?.handleCoverTap(row);
                  }
                },
                onLongPressOverride: (info, details) =>
                    _showComicActions(context, info, details.globalPosition),
                onSecondaryTapDown: (info, details) =>
                    _showComicActions(context, info, details.globalPosition),
              ),
            ),
          ),
    );
    return row;
  }
}
