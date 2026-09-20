part of '../comic_read.dart';

extension _ComicReadViewPart on _ComicReadPageState {
  void _prefetchImagesAroundSlot(int globalSlot, ReadSettingState readSetting) {
    if (isLocalComicSource(widget.from, comicId)) {
      return;
    }
    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final entries = seamlessCubit.resolveImageEntriesForPrefetch(
      globalSlot: globalSlot,
      readSetting: readSetting,
      count: readSetting.preloadImageCount.clamp(2, 10).toInt(),
    );
    unawaited(
      _imagePrefetchController.prefetch(
        entries: entries,
        comicId: comicId,
        from: widget.from,
        count: entries.length,
      ),
    );
  }

  Widget _comicReadAppBar() {
    final cubit = context.read<ReaderCubit>();
    final fullscreenScope = ReaderFullscreenScope.maybeOf(context);
    final isFullscreen = fullscreenScope != null
        ? fullscreenScope.isFullscreen
        : _lifecycleController.isDesktopFullscreen;
    final onToggleFullscreen = fullscreenScope != null
        ? fullscreenScope.onToggleFullscreen
        : (_isDesktopPlatform
            ? () => unawaited(_lifecycleController.toggleDesktopFullscreen())
            : null);

    return ComicReadAppBar(
      title: epInfo.epName,
      from: widget.from,
      comicId: widget.comicId,
      type: widget.type,
      comicInfo: widget.comicInfo,
      isDesktopFullscreen: isFullscreen,
      onToggleFullscreen: onToggleFullscreen,
      changePageIndex: (int value) {
        cubit.updateCurrentSlot(value);
        cubit.updateSliderChanged(0.0);
      },
      onLandscapeChanged: _setReaderLandscape,
      onToggleAutoRead: _toggleAutoReadPaused,
      isAutoReadPaused: () => _autoReadController.isPaused,
    );
  }

  Widget _pageCountWidget() {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final seamlessEnabled = seamlessCubit.isSeamlessEnabled();
    return PageCountWidget(
      epPages: epInfo.epPages,
      getCurrentChapterStartSlot: seamlessEnabled
          ? () => seamlessCubit.currentChapterStartSlot
          : null,
      getCurrentChapterSlotCount: seamlessEnabled
          ? () => seamlessCubit.effectiveCurrentChapterSlotCount()
          : null,
      isTransitionSlot: seamlessEnabled
          ? (globalSlot) =>
                seamlessCubit.isTransitionSlot(globalSlot, readSetting)
          : null,
    );
  }

  /// 视口底边的常驻翻页进度条。
  ///
  /// 章内页码口径与 [_pageCountWidget] **同源**（同一个本章起始槽位、同一个本章
  /// 页数），两颗各自有开关、同时开着时读数一致。
  Widget _readerProgressBarWidget() {
    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final seamlessEnabled = seamlessCubit.isSeamlessEnabled();
    return ReaderProgressBarWidget(
      epPages: epInfo.epPages,
      getCurrentChapterStartSlot: seamlessEnabled
          ? () => seamlessCubit.currentChapterStartSlot
          : null,
      getCurrentChapterSlotCount: seamlessEnabled
          ? () => seamlessCubit.effectiveCurrentChapterSlotCount()
          : null,
    );
  }

  Widget _bottomWidget(BuildContext innerContext) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final seamlessEnabled = seamlessCubit.isSeamlessEnabled();
    // 传构造器而不是造好的 widget：展开缩略图时进度条要**去掉自己的玻璃**
    // 融进同一块面板（见 `chrome/bottom.dart`），形态由父级决定。
    Widget buildSlider(bool embedded) => SliderWidget(
      embedded: embedded,
      observerController: observerController,
      pageController: _pageController,
      getCurrentChapterSlotCount: seamlessEnabled
          ? () => seamlessCubit.effectiveCurrentChapterSlotCount()
          : null,
      mapGlobalToLocalSlot: seamlessEnabled
          ? seamlessCubit.mapGlobalToLocalSlot
          : null,
      mapLocalToGlobalSlot: seamlessEnabled
          ? seamlessCubit.mapLocalToGlobalSlot
          : null,
      isTransitionSlot: seamlessEnabled
          ? (globalSlot) =>
                seamlessCubit.isTransitionSlot(globalSlot, readSetting)
          : null,
      estimateColumnOffset: seamlessEnabled
          ? (context, globalSlot) {
              final imageSizeCubit = context.read<ImageSizeCubit>();
              final viewportWidth = MediaQuery.sizeOf(context).width;
              final contentWidth = getConstrainedImageWidth(
                containerWidth: viewportWidth,
                enableSidePadding: readSetting.sidePaddingEnabled,
                sidePaddingPercent: readSetting.sidePaddingPercent,
              );
              final height = seamlessCubit.estimateColumnHeightBeforeGlobalSlot(
                globalSlot,
                readSetting,
                imageSizeCubit,
                contentWidth,
              );
              return height + getReaderTopOffset(context);
            }
          : null,
    );

    return BottomWidget(
      type: _type,
      comicInfo: comicInfo,
      sliderBuilder: (embedded) => buildSlider(embedded),
      order: widget.order,
      epsNumber: widget.epsNumber,
      comicId: comicId,
      from: widget.from,
      jumpChapter: _jumpChapter,
      onLandscapeChanged: _setReaderLandscape,
      onJumpToSlot: _jumpToGlobalSlot,
    );
  }
}
