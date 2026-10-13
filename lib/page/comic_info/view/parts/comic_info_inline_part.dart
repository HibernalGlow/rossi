// ignore_for_file: invalid_use_of_protected_member
part of '../comic_info.dart';

extension _ComicInfoInlinePart on _ComicInfoState {
  Widget
  _buildInlineDetails() => BlocBuilder<GetComicInfoBloc, GetComicInfoState>(
    builder: (context, state) {
      if (state.status != GetComicInfoStatus.success || state.allInfo == null) {
        return ComicInlineDetailsSurface(
          onClose: widget.onClose!,
          operations: state.status == GetComicInfoStatus.failure
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.comicInfo.loadFailedWithError(error: state.result)),
                    TextButton.icon(
                      onPressed: _reloadInline,
                      icon: const GlyphIcon(AppGlyphs.refresh),
                      label: Text(t.searchResult.retry),
                    ),
                  ],
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LinearProgressIndicator(),
                ),
        );
      }
      final info = state.allInfo!;
      comicInfoDyn = state.comicInfo;
      _currentInfo = info;
      _comicId = state.comicId ?? _comicId;
      _title = info.comicInfo.title;
      if (!_cloudFavoriteStateOverridden) _isCloudCollected = info.isFavourite;
      _syncLocalCollectStatus(info);
      initHistory(context, _comicId, widget.from, chapters: info.eps);
      final allowDownload =
          info.allowDownload || _type == ComicEntryType.download;
      _dlController.attach(
        from: widget.from,
        comicId: _comicId,
        comicTitle: _title,
        allowDownload: allowDownload,
      );
      final eps = _resolveDisplayEps(info.eps);
      final chapters = _dlController.adaptEps(eps);
      final capability = ComicPreviewCapability.fromInfo(info);
      final showPreview =
          _type != ComicEntryType.download && capability.enabled;
      final content = ComicInlineDetailsSurface(
        onClose: widget.onClose!,
        operations: ComicOperationWidget(
          key: ValueKey('inline-actions:${widget.from}:$_comicId'),
          normalInfo: info,
          from: widget.from,
          comicInfo: comicInfoDyn,
          collectionTargetId: widget.collectionTargetId,
          collectionTargetName: widget.collectionTargetName,
          inline: true,
        ),
        tools: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BlocSelector<ComicFollowCubit, ComicFollowState, bool>(
              selector: (state) => state.isFollowing(widget.from, _comicId),
              builder: (_, following) => TextButton.icon(
                onPressed: () => _toggleFollow(following),
                icon: AnimatedGlyph(glyph: AppGlyphs.bell, filled: following),
                label: Text(
                  following ? t.comicInfo.unfollow : t.comicInfo.follow,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _reloadInline,
              icon: const GlyphIcon(AppGlyphs.refresh),
              label: const Text('刷新信息'),
            ),
            if (_type == ComicEntryType.download)
              TextButton.icon(
                onPressed: _handleExport,
                icon: const GlyphIcon(AppGlyphs.download),
                label: Text(t.comicInfo.exportComic),
              ),
            TextButton.icon(
              onPressed:
                  context
                      .watch<GlobalSettingCubit>()
                      .state
                      .cloudFavoritePreferred
                  ? _toggleLocalCollectFromMenu
                  : _toggleCloudCollectFromMenu,
              icon: const GlyphIcon(AppGlyphs.star),
              label: Text(
                context.watch<GlobalSettingCubit>().state.cloudFavoritePreferred
                    ? t.comicInfo.collectToLocal
                    : t.comicInfo.collectToCloud,
              ),
            ),
          ],
        ),
        metadata:
            info.comicInfo.metadata.isEmpty &&
                info.comicInfo.creator.name.trim().isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (info.comicInfo.creator.name.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CreatorInfoWidget(
                        creator: info.comicInfo.creator,
                        from: widget.from,
                        imageKey: _comicId,
                      ),
                    ),
                  for (final metadata in info.comicInfo.metadata)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AllChipWidget(
                        comicId: _comicId,
                        metadata: metadata,
                        from: widget.from,
                        inline: true,
                      ),
                    ),
                ],
              ),
        description: info.comicInfo.description.trim().isEmpty
            ? null
            : _DescriptionCard(
                description: convertChineseForDisplay(
                  info.comicInfo.description,
                ),
              ),
        preview: showPreview ? const ComicInlinePreview() : null,
        chapters: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlocBuilder<EpisodeSelectionCubit, int>(
              bloc: _dlController.selectionCubit,
              builder: (_, _) =>
                  BlocBuilder<
                    EpisodeDownloadStatusCubit,
                    EpisodeDownloadStatusState
                  >(
                    bloc: _dlController.statusCubit,
                    builder: (_, _) => _SelectionActionBar(
                      controller: _dlController,
                      isDownloadType: _type == ComicEntryType.download,
                      inline: true,
                      onClose: widget.onClose,
                    ),
                  ),
            ),
            ComicInlineChapterBoard(
              key: ValueKey('inline-chapters:${widget.from}:$_comicId'),
              count: eps.length,
              reversed: _isReversed,
              onReverse: _toggleOrder,
              itemBuilder: (context, index) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ((index == 0 ||
                          (eps[index] as Ep).groupTitle !=
                              (eps[index - 1] as Ep).groupTitle) &&
                      (eps[index] as Ep).groupTitle.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        (eps[index] as Ep).groupTitle,
                        style: context.theme.textTheme.labelLarge,
                      ),
                    ),
                  _buildEpisodeRow(
                    context,
                    chapter: chapters[index],
                    doc: eps[index] as Ep,
                    index: index,
                    displayTotal: null,
                    allInfo: comicInfoDyn,
                    epsLength: info.eps.length,
                    downloadAllowed: allowDownload,
                    downloadDisabledReason: info.allowDownloadReason,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      if (!showPreview) return content;
      return BlocProvider(
        key: ValueKey('inline-preview:${widget.from}:$_comicId'),
        create: (_) => ComicPreviewBloc(
          comicId: _comicId,
          from: widget.from,
          capability: capability,
          extern: widget.extern ?? const <String, dynamic>{},
        )..add(const LoadComicPreview()),
        child: content,
      );
    },
  );

  void _reloadInline() => context.read<GetComicInfoBloc>().add(
    GetComicInfoEvent(
      comicId: _comicId,
      from: widget.from,
      type: _type,
      extern: widget.extern,
    ),
  );
}
