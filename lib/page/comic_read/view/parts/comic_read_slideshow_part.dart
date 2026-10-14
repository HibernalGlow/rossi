part of '../comic_read.dart';

extension _ComicReadSlideshowPart on _ComicReadPageState {
  /// 每次构建同步放映状态：开关、间隔、结束策略变化都会重配。
  ///
  /// 同步完把控制器那两个位**发布到 [ReaderCubit]**：控制器不是可订阅对象，
  /// 顶栏芯片和屏上指示只读得到的话，暂停了就当场换不了相
  /// （自动滚屏那颗是靠「重建时顺手读一次」蒙的，放映这里给的是真订阅）。
  void _syncSlideshow({
    required ReadSettingState readSetting,
    required int readMode,
  }) {
    _slideshowController.sync(
      enabled: readSetting.slideshowEnabled,
      intervalMs: normalizeReaderSlideshowIntervalMs(
        readSetting.slideshowIntervalMs,
      ),
      decideTick: () => _decideSlideshowTick(readSetting: readSetting),
      onAdvance: () => _actionController.onSlideshowTick(
        columnStepPercent: normalizeReaderSlideshowColumnStepPercent(
          readSetting.slideshowColumnStepPercent,
        ),
      ),
      onLoopToChapterStart: _loopSlideshowToChapterStart,
      onStop: _stopSlideshow,
    );

    final readerCubit = context.read<ReaderCubit>();
    readerCubit.updateSlideshowState(
      running: _slideshowController.isRunning,
      paused: _slideshowController.isPaused,
    );
  }

  /// 仅暂停/继续计时，不改动用户设置项本身（与自动滚屏同一契约）。
  void _toggleSlideshowPaused() {
    final effective = context.readEffectiveReadSetting();
    _slideshowController.togglePaused(
      decideTick: () => _decideSlideshowTick(readSetting: effective),
      onAdvance: () => _actionController.onSlideshowTick(
        columnStepPercent: normalizeReaderSlideshowColumnStepPercent(
          effective.slideshowColumnStepPercent,
        ),
      ),
      onLoopToChapterStart: _loopSlideshowToChapterStart,
      onStop: _stopSlideshow,
      intervalMs: normalizeReaderSlideshowIntervalMs(
        effective.slideshowIntervalMs,
      ),
    );
    context.read<ReaderCubit>().updateSlideshowState(
      running: _slideshowController.isRunning,
      paused: _slideshowController.isPaused,
    );
  }

  /// 屏上驻留指示：放映开着且没被关掉提示时才画。
  Widget _slideshowControlWidget() {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );
    if (!readSetting.slideshowEnabled || !readSetting.slideshowShowProgress) {
      return const Positioned.fill(
        child: IgnorePointer(child: SizedBox.shrink()),
      );
    }
    final slot = context.select((ReaderCubit c) => c.state.currentSlot);
    final running = context.select((ReaderCubit c) => c.state.slideshowRunning);
    final paused = context.select((ReaderCubit c) => c.state.slideshowPaused);
    final seamless = context.read<ReaderSeamlessCubit>();
    return ReaderSlideshowProgress(
      chapterPageNumber: seamless.mapGlobalToLocalSlot(slot) + 1,
      chapterPageTotal: seamless.effectiveCurrentChapterSlotCount(),
      isPaused: paused,
      isRunning: running,
    );
  }

  /// 这一拍该干什么。判据本体是纯函数（`model/reader_slideshow.dart`），
  /// 这里只负责把它要的三个现场事实问出来。
  ReaderSlideshowTick _decideSlideshowTick({
    required ReadSettingState readSetting,
  }) {
    final seamless = context.read<ReaderSeamlessCubit>();
    final readerState = context.read<ReaderCubit>().state;
    final currentSlot = readerState.currentSlot;
    final totalSlots = readerState.totalSlots;

    // 「章末」按**当前章**的槽位范围判，而不是整个已加载范围的末尾：
    // 无缝会把邻章拼进来，用总末尾判的话，策略要到「读完两三章」才生效。
    final chapterEndSlot =
        seamless.currentChapterStartSlot +
        seamless.effectiveCurrentChapterSlotCount() -
        1;
    final atChapterEnd =
        currentSlot >= chapterEndSlot ||
        (totalSlots > 0 && currentSlot >= totalSlots - 1);

    return decideReaderSlideshowTick(
      atChapterEnd: atChapterEnd,
      frameReady: _nextSlideshowFrameReady(
        currentSlot: currentSlot,
        totalSlots: totalSlots,
        readSetting: readSetting,
      ),
      hasNextChapter: seamless.canLoadNextChapter(),
      endAction: readSetting.slideshowEndAction,
    );
  }

  /// 下一格的像素到没到。
  ///
  /// 条漫（readMode 0）恒为 true：那一侧是连续滚动，图没到也只是那一屏里
  /// 有一格还在解，滚动本身不会「跳过头」；横翻才是整槽替换，
  /// 没图就推进等于翻到一页空白占位，然后靠下一拍再补一次 —— 用户看到的
  /// 就是「放映翻了一页而画面上没东西」。
  bool _nextSlideshowFrameReady({
    required int currentSlot,
    required int totalSlots,
    required ReadSettingState readSetting,
  }) {
    if (isColumnReadMode(readSetting.readMode)) return true;
    if (totalSlots > 0 && currentSlot >= totalSlots - 1) return true;

    final seamless = context.read<ReaderSeamlessCubit>();
    final nextEntries = seamless.imageEntriesAtGlobalSlot(
      globalSlot: currentSlot + 1,
      readSetting: readSetting,
    );
    if (nextEntries.isEmpty) return false;
    final imageSizeCubit =
        _imageSizeContext?.read<ImageSizeCubit>() ??
        context.read<ImageSizeCubit>();
    for (final entry in nextEntries) {
      final pageIndex = entry.chapterPageIndex;
      if (pageIndex == null) continue;
      final known = imageSizeCubit.state.getIntrinsic(
        resolveStableSizeCacheIndex(
          chapterOrder: entry.chapterOrder,
          localPageIndex: pageIndex,
        ),
      );
      if (known == null) return false;
    }
    return true;
  }

  /// 循环本章：回到本章第一格继续放。
  void _loopSlideshowToChapterStart() {
    final readSetting = context.readEffectiveReadSetting();
    final seamless = context.read<ReaderSeamlessCubit>();
    final firstSlot = seamless.mapLocalToGlobalSlot(0);
    unawaited(_jumpToGlobalSlot(firstSlot));
    // 跳完仍算「在放」：判据下一拍按第一格重算，章末条件不再成立。
    if (!readSetting.slideshowEnabled) return;
    context.read<ReaderCubit>().updateSlideshowState(
      running: _slideshowController.isRunning,
      paused: _slideshowController.isPaused,
    );
  }

  /// 章末停表：把设置写回 false，让顶栏那颗芯片与屏上指示当场换相。
  void _stopSlideshow() {
    context.read<GlobalSettingCubit>().updateReadSetting(
      (s) => s.copyWith(slideshowEnabled: false),
    );
    context.read<ReaderCubit>().updateSlideshowState(
      running: false,
      paused: false,
    );
    showInfoToast(t.reader.slideshowStoppedAtEnd);
  }
}
