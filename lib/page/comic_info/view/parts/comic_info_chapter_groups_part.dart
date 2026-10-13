part of '../comic_info.dart';

// 沿用 Breeze 的章节分组和吸顶实现，宿主保留章节状态所有权。
extension _ComicInfoChapterGroupsPart on _ComicInfoState {
  void _toggleGroup(String groupKey) {
    _updateChapterGroups(() {
      if (_collapsedGroups.contains(groupKey)) {
        _collapsedGroups.remove(groupKey);
      } else {
        _collapsedGroups.add(groupKey);
      }
    });
  }

  Future<void> _onChapterAction(
    BuildContext context,
    DownloadChapter chapter,
    bool downloadAllowed,
  ) async {
    if (!downloadAllowed) {
      _showDownloadDisabledToast('');
      return;
    }
    final status = _dlController.statusOf(chapter);
    switch (status) {
      case ChapterDownloadStatus.notDownloaded:
      case ChapterDownloadStatus.failed:
        await _dlController.downloadSingle(context, chapter);
        break;
      case ChapterDownloadStatus.queued:
      case ChapterDownloadStatus.downloading:
        await _dlController.cancelChapter(context, chapter);
        break;
      case ChapterDownloadStatus.downloaded:
        final wholeDeleted = await _dlController.deleteSingle(context, chapter);
        if (wholeDeleted && _type == ComicEntryType.download) {
          if (context.mounted) actionBack(context);
        }
        break;
    }
  }

  // 选中态/下载态不在这里读取，行内各自订阅 selectionCubit / statusCubit。
  // [doc] 与 [chapter] 一一对应（同一下标），[index] 为组内下标，
  // [displayTotal] 为组内总数（扁平路径传 null，即今天的行为）。
  Widget _buildEpisodeRow(
    BuildContext context, {
    required DownloadChapter chapter,
    required Ep doc,
    required int index,
    required int? displayTotal,
    required dynamic allInfo,
    required int epsLength,
    required bool downloadAllowed,
    required String downloadDisabledReason,
  }) {
    return EpButtonWidget(
      key: ValueKey(chapter.id),
      doc: doc,
      chapter: chapter,
      controller: _dlController,
      allInfo: allInfo,
      epsLength: epsLength,
      displayTotal: displayTotal,
      type: _type,
      comicId: _comicId,
      from: widget.from,
      index: index,
      isReversed: _isReversed,
      downloadAllowed: downloadAllowed,
      downloadDisabledReason: downloadDisabledReason,
      onAction: () => _onChapterAction(context, chapter, downloadAllowed),
      onToggleSelect: () => _dlController.toggleSelect(chapter.id),
      onEnterSelect: () {
        if (!downloadAllowed) {
          _showDownloadDisabledToast(downloadDisabledReason);
          return;
        }
        _dlController.enterSelection(chapter.id);
      },
    );
  }

  void _showDownloadDisabledToast(String reason) {
    final trimmed = reason.trim();
    showInfoToast(trimmed.isNotEmpty ? trimmed : t.comicInfo.downloadForbidden);
  }

  /// 章节区顶层 slivers：单组走扁平 Sliver，多组直接展开
  /// （组头 pinned + 组内容），后组吸顶时自然顶掉前组。
  ///
  /// 组头/组内容各自包一层 SliverLayoutBuilder 算内容宽度（断点与水平边距），
  /// 与其它区共用 `_constrainedSliver` 逻辑，不再经 `SliverMainAxisGroup` 中转。
  List<Widget> _buildEpisodeSlivers({
    required BuildContext context,
    required List<dynamic> displayEps,
    required bool showDownloadUi,
    required dynamic allInfo,
    required int epsLength,
    required String downloadDisabledReason,
  }) {
    // adapt 带元素级缓存：displayEps 引用不变时直接复用，不重建 DownloadChapter。
    final chapters = _dlController.adaptEps(displayEps);
    if (chapters.isEmpty) {
      return [
        _constrainedSliver(
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 18),
              child: Text(
                t.comicInfo.noChapters,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ];
    }

    // 多组时按下标切段（displayEps 已全局排序，组顺序=首次出现顺序，
    // 倒序开关翻转的是整条 displayEps，即全局翻转）。
    final indexGroups = _groupDisplayIndices(displayEps);
    if (indexGroups.length <= 1) {
      return [
        _FlatEpisodeSliver(
          chapters: chapters,
          displayEps: displayEps,
          rowBuilder: (context, chapter, doc, index) => _buildEpisodeRow(
            context,
            chapter: chapter,
            doc: doc,
            index: index,
            displayTotal: null,
            allInfo: allInfo,
            epsLength: epsLength,
            downloadAllowed: showDownloadUi,
            downloadDisabledReason: downloadDisabledReason,
          ),
        ),
      ];
    }

    final slivers = <Widget>[];
    for (var g = 0; g < indexGroups.length; g++) {
      final indices = indexGroups[g].items;
      final groupKey = indexGroups[g].title;
      final expanded = !_collapsedGroups.contains(groupKey);
      final groupChapters = [for (final i in indices) chapters[i]];
      slivers.add(
        // 用 flutter_sticky_header 的 SliverStickyHeader：header 与内容绑在
        // 同一个 render object 里，顶替由库原生处理。注意库不做组间间距，
        // 由本组内容底部统一留 12（见 _GroupEpisodeSliver），组头自身不再加
        // topPadding——header 内部留白会参与吸顶高度，导致顶替错位。
        SliverStickyHeader(
          header: _ChapterGroupHeaderBar(
            title: chapterGroupDisplayTitle(
              indexGroups[g].title,
              t.comicInfo.untitledGroup,
            ),
            countLabel: t.comicInfo.groupEpisodeCount(count: indices.length),
            onDownloadGroup: showDownloadUi
                ? () => _downloadGroup(context, groupChapters)
                : null,
            onToggle: () => _toggleGroup(groupKey),
            expanded: expanded,
          ),
          // 折叠组内容传 null：库只留吸顶头，章节行 widget 都不建。
          sliver: expanded
              ? _GroupEpisodeSliver(
                  chapters: chapters,
                  displayEps: displayEps,
                  indices: indices,
                  rowBuilder: (context, chapter, doc, index) =>
                      _buildEpisodeRow(
                        context,
                        chapter: chapter,
                        doc: doc,
                        index: index,
                        displayTotal: indices.length,
                        allInfo: allInfo,
                        epsLength: epsLength,
                        downloadAllowed: showDownloadUi,
                        downloadDisabledReason: downloadDisabledReason,
                      ),
                )
              : null,
        ),
      );
    }
    return slivers;
  }

  /// 组头“下载本组”：只下可下载子集（未下载/失败），空则 toast 提示。
  Future<void> _downloadGroup(
    BuildContext context,
    List<DownloadChapter> groupChapters,
  ) {
    return _dlController.downloadChapters(context, groupChapters);
  }

  /// 按下标分组：返回与 displayEps 对齐的下标组。
  List<ChapterGroup<int>> _groupDisplayIndices(List<dynamic> displayEps) {
    return groupChaptersByTitle<int>(
      List<int>.generate(displayEps.length, (i) => i),
      (i) {
        final ep = displayEps[i] as Ep;
        return resolveChapterGroupTitle(groupTitle: ep.groupTitle);
      },
    );
  }
}

/// 章节网格断点（按内容宽度算）：<560 单列，<720 一列、<960 两列，
/// ≥960 按 320 maxExtent 网格。与今天扁平路径同一份规则。
SliverGridDelegate episodeGridDelegateFor(double contentWidth) {
  if (contentWidth >= 960) {
    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 320,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: EpButtonWidget.fixedHeight,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: contentWidth >= 720 ? 2 : 1,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    mainAxisExtent: EpButtonWidget.fixedHeight,
  );
}

typedef EpisodeRowBuilder =
    Widget Function(
      BuildContext context,
      DownloadChapter chapter,
      Ep doc,
      int index,
    );

/// 扁平章节 sliver（单组/老数据）：内部按内容宽度选单列/网格，只建可视行。
class _FlatEpisodeSliver extends StatelessWidget {
  const _FlatEpisodeSliver({
    required this.chapters,
    required this.displayEps,
    required this.rowBuilder,
  });

  final List<DownloadChapter> chapters;
  final List<dynamic> displayEps;
  final EpisodeRowBuilder rowBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = _constrainedHorizontalPadding(
          constraints.crossAxisExtent,
        );
        final contentWidth =
            constraints.crossAxisExtent - horizontalPadding * 2;
        final padding = EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
          top: 12,
          bottom: 12,
        );
        if (contentWidth < 560) {
          return SliverPadding(
            padding: padding,
            sliver: SliverList.builder(
              itemCount: chapters.length,
              itemBuilder: (context, i) {
                final chapter = chapters[i];
                return Padding(
                  key: ValueKey('pad:${chapter.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: rowBuilder(context, chapter, displayEps[i] as Ep, i),
                );
              },
            ),
          );
        }
        return SliverPadding(
          padding: padding,
          sliver: SliverGrid.builder(
            itemCount: chapters.length,
            gridDelegate: episodeGridDelegateFor(contentWidth),
            itemBuilder: (context, i) =>
                rowBuilder(context, chapters[i], displayEps[i] as Ep, i),
          ),
        );
      },
    );
  }
}

/// 单组章节 sliver：无外层边距（组头已占位），行列规则与扁平路径一致。
class _GroupEpisodeSliver extends StatelessWidget {
  const _GroupEpisodeSliver({
    required this.chapters,
    required this.displayEps,
    required this.indices,
    required this.rowBuilder,
  });

  final List<DownloadChapter> chapters;
  final List<dynamic> displayEps;
  final List<int> indices;
  final EpisodeRowBuilder rowBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = _constrainedHorizontalPadding(
          constraints.crossAxisExtent,
        );
        final contentWidth =
            constraints.crossAxisExtent - horizontalPadding * 2;
        // 组内容左右对齐组头：组头包了 _constrainedSliver（水平 padding），
        // 这里补同样的左右 padding；底部留 12 与下组头 topPadding 呼应。
        final padding = EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
          bottom: 12,
        );
        if (contentWidth < 560) {
          return SliverPadding(
            padding: padding,
            sliver: SliverList.builder(
              itemCount: indices.length,
              itemBuilder: (context, j) {
                final i = indices[j];
                final chapter = chapters[i];
                return Padding(
                  key: ValueKey('pad:${chapter.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: rowBuilder(context, chapter, displayEps[i] as Ep, j),
                );
              },
            ),
          );
        }
        return SliverPadding(
          padding: padding,
          sliver: SliverGrid.builder(
            itemCount: indices.length,
            gridDelegate: episodeGridDelegateFor(contentWidth),
            itemBuilder: (context, j) {
              final i = indices[j];
              return rowBuilder(context, chapters[i], displayEps[i] as Ep, j);
            },
          ),
        );
      },
    );
  }
}

class _ChapterGroupHeaderBar extends StatelessWidget {
  const _ChapterGroupHeaderBar({
    required this.title,
    required this.countLabel,
    required this.onDownloadGroup,
    required this.onToggle,
    required this.expanded,
  });

  final String title;
  final String countLabel;
  final VoidCallback? onDownloadGroup;
  final VoidCallback onToggle;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    // 与章节内容区同一套居中：全宽 Container 下 Center + 最大内容宽约束，
    // 窄屏下左右 20，宽屏下与章节行左右对齐。吸顶时整条背景不断层。
    // 注意：普通 LayoutBuilder（不是 SliverLayoutBuilder）是 RenderBox，
    // 可以放在 header 里。
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = _constrainedHorizontalPadding(
          constraints.maxWidth,
        );
        return Container(
          color: context.theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - horizontalPadding * 2).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              // 整行可点展开/折叠；下载按钮自己拦截手势，不冒泡。
              child: InkWell(
                onTap: onToggle,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: context.textColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: title,
                              style: context.theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: ' · $countLabel',
                              style: context.theme.textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.textColor.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onDownloadGroup != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t.comicInfo.downloadGroup,
                        onPressed: onDownloadGroup,
                        icon: const Icon(Icons.download_outlined, size: 20),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
