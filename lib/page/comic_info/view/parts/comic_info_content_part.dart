// ignore_for_file: invalid_use_of_protected_member
part of '../comic_info.dart';

extension _ComicInfoContentPart on _ComicInfoState {
  Widget _infoView(
    NormalComicAllInfo normalComicAllInfo, {
    required bool showInlineReadEntry,
  }) {
    final comicInfo = normalComicAllInfo.comicInfo;
    _title = comicInfo.title;
    final clickCoverToStartReading = context
        .watch<GlobalSettingCubit>()
        .state
        .clickCoverToStartReading;

    if (!_loadingComplete) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _loadingComplete = true),
      );
    }

    // 带缓存：bloc 同实例 + 倒序开关不变时零计算，直接复用上次结果。
    final displayEps = _resolveDisplayEps(normalComicAllInfo.eps);
    // 下载类型进来的一定是本地记录（只含已下载章节）；在线页插件允许下载时
    // 才显示章节下载按钮。
    final showDownloadUi =
        normalComicAllInfo.allowDownload || _type == ComicEntryType.download;
    // controller 绑定（key 不变时内部早退，零成本）；漫画切换时清空折叠态。
    _dlController.attach(
      from: widget.from,
      comicId: _comicId,
      comicTitle: comicInfo.title,
      allowDownload: showDownloadUi,
    );
    _readController.attach(from: widget.from, comicId: _comicId);
    final comicKey = '${widget.from}:$_comicId';
    if (_collapsedForComic != comicKey) {
      _collapsedForComic = comicKey;
      _collapsedGroups.clear();
    }
    final previewCapability = ComicPreviewCapability.fromInfo(
      normalComicAllInfo,
    );
    final showPreview =
        _type != ComicEntryType.download && previewCapability.enabled;

    return BlocSelector<StringSelectCubit, String, bool>(
      selector: (state) => state.isNotEmpty,
      builder: (context, hasHistory) {
        final refreshable = RefreshIndicator(
          onRefresh: () async {
            _type = ComicEntryType.normal;
            _isReversed = false;

            context.read<GetComicInfoBloc>().add(
              GetComicInfoEvent(
                comicId: _comicId,
                from: widget.from,
                type: _type,
                extern: widget.extern,
              ),
            );
            setState(() {
              _loadingComplete = false;
            });
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: _constrainedSliver(
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ComicParticularsWidget(
                          comicInfo: comicInfo,
                          from: widget.from,
                          type: _type,
                          onCoverTap: clickCoverToStartReading
                              ? () => _startReading(_type)
                              : null,
                          onContinueRead: hasHistory
                              ? () => _startReading(_type)
                              : null,
                        ),
                        _buildDivider(context),
                        ComicOperationWidget(
                          normalInfo: normalComicAllInfo,
                          from: widget.from,
                          collectionTargetId: widget.collectionTargetId,
                          collectionTargetName: widget.collectionTargetName,
                          comicInfo: comicInfoDyn,
                          hasHistory: hasHistory,
                          // 桌面端：贴上「下载」旁边的那张阅读卡片；
                          // 触摸端为空（悬浮按钮才是它的落点）。
                          onRead: showInlineReadEntry
                              ? () => _startReading(widget.type)
                              : null,
                        ),
                        if (comicInfo.metadata.isNotEmpty ||
                            comicInfo.description.trim().isNotEmpty) ...[
                          _buildDivider(context),
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final meta in comicInfo.metadata) ...[
                                  AllChipWidget(
                                    comicId: comicInfo.id,
                                    metadata: meta,
                                    from: widget.from,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (comicInfo.description.trim().isNotEmpty)
                                  _DescriptionCard(
                                    description: comicInfo.description.let(
                                      convertChineseForDisplay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (comicInfo.creator.name.trim().isNotEmpty ||
                            comicInfo.creator.avatar.url.trim().isNotEmpty) ...[
                          _buildDivider(context),
                          _SectionCard(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: CreatorInfoWidget(
                                  creator: comicInfo.creator,
                                  from: widget.from,
                                  imageKey: comicInfo.id,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // 章节头：标题 + 计数/倒序 badge（虚拟化列表的 header sliver）。
              _constrainedSliver(
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildDivider(context),
                      _EpisodeHeader(
                        title: t.comicInfo.chapterList,
                        trailing: _EpisodeHeaderBadge(
                          label: _chapterCountLabel(displayEps),
                          icon: _isReversed
                              ? AppGlyphs.arrowDown
                              : AppGlyphs.arrowUp,
                          onTap: _toggleOrder,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 章节列表：单组走扁平 Sliver，多组直接展开为多个顶层 sliver
              // （组头 pinned + 组内容），后组吸顶时自然顶掉前组。
              ..._buildEpisodeSlivers(
                context: context,
                displayEps: displayEps,
                showDownloadUi: showDownloadUi,
                allInfo: comicInfoDyn,
                epsLength: normalComicAllInfo.eps.length,
                downloadDisabledReason: normalComicAllInfo.allowDownloadReason,
              ),
              if (normalComicAllInfo.recommend.isNotEmpty &&
                  _resolveRecommendItems(
                    normalComicAllInfo.recommend,
                  ).isNotEmpty)
                _constrainedSliver(
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildDivider(context),
                        _SectionCard(
                          title: t.comicInfo.related,
                          child: RecommendWidget(
                            comicList: _resolveRecommendItems(
                              normalComicAllInfo.recommend,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (showPreview) ...[
                _constrainedSliver(const ComicPreviewSliver()),
              ],
              const SliverPadding(
                padding: EdgeInsets.only(bottom: 180),
                sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          ),
        );

        if (!showPreview) return refreshable;

        return BlocProvider(
          key: ValueKey('preview:${widget.from}:$_comicId'),
          create: (_) => ComicPreviewBloc(
            comicId: _comicId,
            from: widget.from,
            capability: previewCapability,
            extern: widget.extern ?? const <String, dynamic>{},
          )..add(const LoadComicPreview()),
          child: Builder(
            builder: (context) => NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent * 0.9) {
                  context.read<ComicPreviewBloc>().add(
                    const LoadComicPreview(loadMore: true),
                  );
                }
                return false;
              },
              child: refreshable,
            ),
          ),
        );
      },
    );
  }
}
