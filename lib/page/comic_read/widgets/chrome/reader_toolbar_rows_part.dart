part of 'app_bar.dart';

/// 主行与常驻二级工具栏共用原入口、状态与回调。
extension _ReaderToolbarRows on _ComicReadAppBarState {
  Widget _buildPrimaryToolbar({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderToolbarTier tier,
    required bool secondaryRow,
    required ReaderFitMode fitMode,
    required String? bookTitle,
    required bool showDownloadEntry,
    required double availableWidth,
  }) {
    // 让位分两级：中档以下「视图三项 + 下载」让出主行，宽档以下再搭上
    // 「钉住 + 全屏」。让出去的那一组住第二行（窗高够）或「更多」菜单，
    // 两个落点互斥。neo 占位的那五颗**永远**在菜单里，主行不为它们让宽度。
    final inlineView = tier.keepsViewControlsInline;
    final inlineWindow = tier.keepsWindowControlsInline;
    // 超分芯片的让位判断按「没有下载那颗时的可用宽度」算：两者互斥，
    // 一起记账会把芯片压成永远不写文字的哑巴。
    final chipWidth = availableWidth - (showDownloadEntry ? 44 : 0);

    // 手机先保住标题；中档控件摊开时单独给标题一行。
    // 其余宽度将增强入口与标题并排，减少工具栏占用的阅读高度。
    if (availableWidth < 520 ||
        (tier != ReaderToolbarTier.narrow && availableWidth < 1100)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                ReaderToolbarIconButton(
                  icon: AppGlyphs.arrowBack,
                  tooltip: t.common.back,
                  onPressed: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildTitle(context, bookTitle: bookTitle)),
                ReaderToolbarIconButton(
                  icon: AppGlyphs.sliders,
                  expressiveShape: ExpressiveButtonShape.cookie4Sided,
                  tooltip: t.reader.settings,
                  onPressed: () => showReaderSettingsSheet(
                    context,
                    changePageIndex: widget.changePageIndex,
                    onLandscapeChanged: widget.onLandscapeChanged,
                    source: widget.from,
                    comicId: widget.comicId,
                  ),
                ),
                _ReaderToolbarOverflowButton(
                  items: _buildOverflowItems(
                    context,
                    readSetting: readSetting,
                    cubit: cubit,
                    fitMode: fitMode,
                    inlineView: inlineView,
                    inlineWindow: inlineWindow,
                    secondaryRow: secondaryRow,
                    isAutoScrollPaused:
                        widget.isAutoReadPaused?.call() ?? false,
                    showDownloadEntry: showDownloadEntry,
                    bookTitle: bookTitle,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Wrap(
              // 与组内同一个数：这一行原本用 8，而组里（超分那颗自成一小组）是 4，
              // 于是同一行并排两种间距。整行统一成一条等宽带。
              spacing: ReaderToolbarMetrics.gapWithinGroup,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                if (inlineView)
                  ReaderToolbarGroup(
                    children: [
                      for (final panel in kReaderPrimaryToolbarPanels)
                        ReaderToolbarIconButton(
                          icon: _readerPanelIcon(panel, fitMode),
                          tooltip:
                              '${_readerPanelLabel(panel, fitMode)}（点击展开面板）',
                          selected: _expandedPanel == panel,
                          onPressed: () => _togglePanel(panel),
                        ),
                      if (showDownloadEntry) _buildDownloadEntry(bookTitle),
                    ],
                  ),
                _buildLayoutGroup(
                  context,
                  readSetting: readSetting,
                  cubit: cubit,
                  tier: tier,
                ),
                ReaderUpscaleStatusChip(availableWidth: chipWidth),
                ReaderTranslatedPageChip(availableWidth: chipWidth),
                ReaderOnlineTranslatedPageChip(availableWidth: chipWidth),
                if (inlineWindow && widget.onToggleFullscreen != null)
                  ReaderToolbarIconButton(
                    icon: widget.isDesktopFullscreen
                        ? AppGlyphs.fullscreenExit
                        : AppGlyphs.fullscreen,
                    tooltip: widget.isDesktopFullscreen
                        ? t.reader.exitFullscreen
                        : t.reader.enterFullscreen,
                    onPressed: widget.onToggleFullscreen,
                  ),
                if (inlineWindow)
                  ReaderToolbarIconButton(
                    icon: AppGlyphs.pin,
                    tooltip: readSetting.topBarPinned
                        ? t.reader.unpinTopBar
                        : t.reader.pinTopBar,
                    selected: readSetting.topBarPinned,
                    onPressed: () => cubit.updateReadSetting(
                      (s) => s.copyWith(topBarPinned: !s.topBarPinned),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height: ReaderToolbarMetrics.rowHeight,
        child: Row(
          children: [
            // 导航
            ReaderToolbarIconButton(
              icon: AppGlyphs.arrowBack,
              tooltip: t.common.back,
              onPressed: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 8),

            // 标题：这一行唯一的弹性项，所以「谁先让位」的答案就是它先省略到 0。
            Expanded(child: _buildTitle(context, bookTitle: bookTitle)),

            // 视图组：三块二级面板的入口。
            if (inlineView) ...[
              const SizedBox(width: ReaderToolbarMetrics.gapBetweenGroups),
              ReaderToolbarGroup(
                children: [
                  for (final panel in kReaderPrimaryToolbarPanels)
                    ReaderToolbarIconButton(
                      icon: _readerPanelIcon(panel, fitMode),
                      tooltip: '${_readerPanelLabel(panel, fitMode)}（点击展开面板）',
                      selected: _expandedPanel == panel,
                      onPressed: () => _togglePanel(panel),
                    ),
                ],
              ),
            ],

            // 版式组。
            _buildLayoutGroup(
              context,
              readSetting: readSetting,
              cubit: cubit,
              tier: tier,
            ),
            const SizedBox(width: ReaderToolbarMetrics.gapBetweenGroups),

            // 末尾这一段：增强（下载、当前页超分与翻译）+ 窗口（全屏、钉住）+ 更多 + 设置。
            //
            // **一条组，不是两条**：这些控件全是同一档 48 的图标钮，分成两组就
            // 意味着中间那条 12 的组间距，而组内是 4 —— 钉住（窗口组的第一颗）与
            // 它左边那颗的间距就永远比它的邻居宽。增强入口始终可见；自动滚屏沿用原菜单入口。
            ReaderToolbarGroup(
              children: [
                if (showDownloadEntry && inlineView)
                  _buildDownloadEntry(bookTitle),
                // 这三颗自己决定画不画（画不画取决于当前图源/呈现器，父层判不了），
                // 所以套 [ReaderToolbarOptionalSlot]：不画的时候连组内那 4 一起归零，
                // 这一段才是**每两颗都只差 4** 的图标带。
                ReaderToolbarOptionalSlot(
                  gap: ReaderToolbarMetrics.gapWithinGroup,
                  child: ReaderUpscaleStatusChip(availableWidth: chipWidth),
                ),
                ReaderToolbarOptionalSlot(
                  gap: ReaderToolbarMetrics.gapWithinGroup,
                  child: ReaderTranslatedPageChip(availableWidth: chipWidth),
                ),
                ReaderToolbarOptionalSlot(
                  gap: ReaderToolbarMetrics.gapWithinGroup,
                  child: ReaderOnlineTranslatedPageChip(
                    availableWidth: chipWidth,
                  ),
                ),
                // 自动滚屏按用户口径放**二级**：主行不画它，入口与开/关状态
                // 在「更多」菜单的第一项（所有档位都在那里）。
                if (inlineWindow && widget.onToggleFullscreen != null)
                  ReaderToolbarIconButton(
                    icon: widget.isDesktopFullscreen
                        ? AppGlyphs.fullscreenExit
                        : AppGlyphs.fullscreen,
                    tooltip: widget.isDesktopFullscreen
                        ? t.reader.exitFullscreen
                        : t.reader.enterFullscreen,
                    onPressed: widget.onToggleFullscreen,
                  ),
                // 钉住顶栏（neo 的 edge `pinned`）：钉住之后这一条不再被
                // 「点中间收起」或指针离开边缘收走；取消钉住立刻交还给那两套自动收起。
                if (inlineWindow)
                  ReaderToolbarIconButton(
                    icon: AppGlyphs.pin,
                    tooltip: readSetting.topBarPinned
                        ? t.reader.unpinTopBar
                        : t.reader.pinTopBar,
                    selected: readSetting.topBarPinned,
                    onPressed: () => cubit.updateReadSetting(
                      (s) => s.copyWith(topBarPinned: !s.topBarPinned),
                    ),
                  ),
                _ReaderToolbarOverflowButton(
                  items: _buildOverflowItems(
                    context,
                    readSetting: readSetting,
                    cubit: cubit,
                    fitMode: fitMode,
                    inlineView: inlineView,
                    inlineWindow: inlineWindow,
                    secondaryRow: secondaryRow,
                    isAutoScrollPaused:
                        widget.isAutoReadPaused?.call() ?? false,
                    showDownloadEntry: showDownloadEntry,
                    bookTitle: bookTitle,
                  ),
                ),
                ReaderToolbarIconButton(
                  icon: AppGlyphs.sliders,
                  expressiveShape: ExpressiveButtonShape.cookie4Sided,
                  tooltip: t.reader.settings,
                  onPressed: () => showReaderSettingsSheet(
                    context,
                    changePageIndex: widget.changePageIndex,
                    onLandscapeChanged: widget.onLandscapeChanged,
                    // 顶栏这个入口也在阅读页里：带上本漫身份，否则「启用本漫画设置」不会出现。
                    source: widget.from,
                    comicId: widget.comicId,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 第二行：这一档从主行让出去的那几组，原样搬来常驻。
  ///
  /// 这里**不新造控件**：视图三项、下载、全屏、钉住用的就是主行那一份构造与
  /// 同一套回调，所以「在第二行点钉住」和「在主行点钉住」是同一件事、同一个状态。
  /// 外层 [ReaderToolbarPanelRow] 走 `Wrap`（spacing 4）：窄到放不下就换行摊开，
  /// 既不折成溢出菜单，也不会挤黄黑斜纹。
  ///
  /// 让位的「两批」只决定**谁搬到这一行**，不决定间距：以前这里按批次插了一条
  /// [ReaderToolbarMetrics.gapBetweenGroups]（12）的组间距，而 `Wrap` 自己已经在
  /// 它两边各加了 4 —— 于是这一行上「视图三项」与「全屏/钉住」之间是 20，别的
  /// 相邻颗是 4。所以这一行摊平成一条等宽带。
  Widget _buildSecondaryToolbar({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderToolbarTier tier,
    required ReaderFitMode fitMode,
    required String? bookTitle,
    required bool showDownloadEntry,
  }) {
    final children = <Widget>[
      // 让位的第一批：三块面板的入口 + 下载。条件与主行那颗 `if (inlineView)`
      // 严格同源，两边不会一处画一处不画。
      if (!tier.keepsViewControlsInline)
        for (final panel in kReaderPrimaryToolbarPanels)
          ReaderToolbarIconButton(
            icon: _readerPanelIcon(panel, fitMode),
            tooltip: '${_readerPanelLabel(panel, fitMode)}（点击展开面板）',
            selected: _expandedPanel == panel,
            onPressed: () => _togglePanel(panel),
          ),
      if (!tier.keepsViewControlsInline && showDownloadEntry)
        _buildDownloadEntry(bookTitle),
      // 让位的第二批：全屏 + 钉住。
      if (!tier.keepsWindowControlsInline && widget.onToggleFullscreen != null)
        ReaderToolbarIconButton(
          icon: widget.isDesktopFullscreen
              ? AppGlyphs.fullscreenExit
              : AppGlyphs.fullscreen,
          tooltip: widget.isDesktopFullscreen
              ? t.reader.exitFullscreen
              : t.reader.enterFullscreen,
          onPressed: widget.onToggleFullscreen,
        ),
      if (!tier.keepsWindowControlsInline)
        ReaderToolbarIconButton(
          icon: AppGlyphs.pin,
          tooltip: readSetting.topBarPinned
              ? t.reader.unpinTopBar
              : t.reader.pinTopBar,
          selected: readSetting.topBarPinned,
          onPressed: () => cubit.updateReadSetting(
            (s) => s.copyWith(topBarPinned: !s.topBarPinned),
          ),
        ),
    ];

    if (children.isEmpty) return const SizedBox.shrink();

    return ReaderToolbarPanelRow(floating: true, children: children);
  }
}
