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

    if (availableWidth < 600) {
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
                    inlineView: false,
                    inlineWindow: false,
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
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                _buildLayoutGroup(
                  context,
                  readSetting: readSetting,
                  cubit: cubit,
                  tier: tier,
                ),
                ReaderUpscaleStatusChip(availableWidth: chipWidth),
                ReaderTranslatedPageChip(availableWidth: chipWidth),
                ReaderOnlineTranslatedPageChip(availableWidth: chipWidth),
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
              const ReaderToolbarSeparator(),
              ReaderToolbarGroup(
                children: [
                  for (final panel in ReaderToolbarPanel.values)
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
            // 窄档这一组只剩一颗循环按钮，标题本身就是分隔，不再补第二条线
            // ——每少一条线就是 13px 留给书名。
            if (tier.expandsLayoutGroup)
              const ReaderToolbarSeparator()
            else
              const SizedBox(width: ReaderToolbarMetrics.gapBetweenGroups),

            // 增强组：下载 / 超分状态 / 自动滚屏。
            //
            // 这一组**永不折叠**：超分那颗既是状态显示也是开关，用户口径是
            // 「最常用的那一档」，收进菜单就等于看不见了。而且它与下载互斥
            // （下载只在在线图源出现，超分芯片只在本地 GPU 会话出现），
            // 这一组的最坏情况就是「芯片 + 滚屏」，比视图三项窄得多。
            ReaderToolbarGroup(
              children: [
                if (showDownloadEntry && inlineView)
                  _buildDownloadEntry(bookTitle),
                ReaderUpscaleStatusChip(availableWidth: chipWidth),
                ReaderTranslatedPageChip(availableWidth: chipWidth),
                ReaderOnlineTranslatedPageChip(availableWidth: chipWidth),
                // 自动滚屏按用户口径放**二级**：主行不画它，入口与开/关状态
                // 在「更多」菜单的第一项（所有档位都在那里）。
              ],
            ),

            // 窗口组 + 更多。
            const ReaderToolbarSeparator(),
            ReaderToolbarGroup(
              children: [
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
  /// 外层 [ReaderToolbarPanelRow] 走 `Wrap`：窄到放不下就换行摊开，既不折成
  /// 溢出菜单，也不会挤黄黑斜纹。
  Widget _buildSecondaryToolbar({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required ReaderToolbarTier tier,
    required ReaderFitMode fitMode,
    required String? bookTitle,
    required bool showDownloadEntry,
  }) {
    final children = <Widget>[];

    // 整节为空时连它前面那条分隔线一起省掉：这一行是按档位凑出来的，
    // 中档就只有窗口那一节，不该凭空多一条没有左边的线。
    void addSection(List<Widget> section) {
      if (section.isEmpty) return;
      if (children.isNotEmpty) children.add(const ReaderToolbarSeparator());
      children.addAll(section);
    }

    // 让位的第一批：三块面板的入口 + 下载。条件与主行那颗 `if (inlineView)`
    // 严格同源，两边不会一处画一处不画。
    addSection([
      if (!tier.keepsViewControlsInline)
        ReaderToolbarGroup(
          children: [
            for (final panel in ReaderToolbarPanel.values)
              ReaderToolbarIconButton(
                icon: _readerPanelIcon(panel, fitMode),
                tooltip: '${_readerPanelLabel(panel, fitMode)}（点击展开面板）',
                selected: _expandedPanel == panel,
                onPressed: () => _togglePanel(panel),
              ),
          ],
        ),
      if (!tier.keepsViewControlsInline && showDownloadEntry)
        _buildDownloadEntry(bookTitle),
    ]);

    // 让位的第二批：全屏 + 钉住。
    addSection([
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
    ]);

    return ReaderToolbarPanelRow(children: children);
  }
}
