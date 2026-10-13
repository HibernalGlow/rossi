part of 'bottom.dart';

extension _BottomControlsLayoutPart on _BottomWidgetState {
  Widget _buildRegularControls({
    required double topMaxWidth,
    required double bottomMaxWidth,
    required bool isWideLayout,
    required int totalSlots,
    required int currentSlot,
    required PageSource? localSource,
    required List<Doc> docs,
    required bool showThumbnailStrip,
    required bool rightToLeft,
  }) {
    final showStrip = showThumbnailStrip && totalSlots > 1;

    return AnimatedSize(
      // 展开/收起时让面板「长出来」，而不是整块跳一下。
      duration:
          context.read<GlobalSettingCubit>().state.readSetting.noAnimation ||
              context.read<GlobalSettingCubit>().state.eInkSetting.enabled
          ? Duration.zero
          : ExpressiveMotion.duration(
              context,
              ExpressiveMotion.spatialDuration,
            ),
      curve: ExpressiveMotion.spatialCurve,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWideLayout ? topMaxWidth : double.infinity,
                ),
                child: _buildControlButtons(
                  totalSlots: totalSlots,
                  showThumbnailStrip: showThumbnailStrip,
                ),
              ),
            ),
          ),
          if (totalSlots > 1) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWideLayout ? bottomMaxWidth : double.infinity,
                  ),
                  child: showStrip
                      // 缩略图与进度共用 Expressive 表面，保留两份操作入口。
                      ? Material(
                          color: context.theme.colorScheme.surfaceContainerLow,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(28),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BottomThumbnailStrip(
                                embedded: true,
                                height: _BottomWidgetState._fusedStripHeight,
                                totalPages: totalSlots,
                                currentSlot: currentSlot,
                                comicId: comicId,
                                from: widget.from,
                                localSource: localSource,
                                docs: docs,
                                onSelectPage: _jumpToSlot,
                                rightToLeft: rightToLeft,
                              ),
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 10,
                                endIndent: 10,
                                color: context.theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.4),
                              ),
                              Row(children: [widget.sliderBuilder(true)]),
                            ],
                          ),
                        )
                      : Row(children: [widget.sliderBuilder(false)]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactControls({
    required double maxWidth,
    required bool isWideLayout,
    required int totalSlots,
    required int currentSlot,
    required PageSource? localSource,
    required List<Doc> docs,
    required bool showThumbnailStrip,
    required bool rightToLeft,
  }) {
    // 紧凑横屏（宽 ≥600 且高 ≤600）里按钮与进度条被迫同排，玻璃没法只包住
    // 进度条那一半 —— 强行合并会把按钮也糊进面板。这里让缩略图条保持
    // 独立浮条，只有显隐状态跟着全局设置走。
    final showStrip = showThumbnailStrip && totalSlots > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showStrip) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWideLayout ? maxWidth : double.infinity,
                ),
                child: BottomThumbnailStrip(
                  totalPages: totalSlots,
                  currentSlot: currentSlot,
                  comicId: comicId,
                  from: widget.from,
                  localSource: localSource,
                  docs: docs,
                  onSelectPage: _jumpToSlot,
                  rightToLeft: rightToLeft,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWideLayout ? maxWidth : double.infinity,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    SizedBox(
                      width: totalSlots > 1
                          ? math.min(396, constraints.maxWidth * 0.65)
                          : constraints.maxWidth,
                      child: _buildControlButtons(
                        totalSlots: totalSlots,
                        showThumbnailStrip: showThumbnailStrip,
                      ),
                    ),
                    if (totalSlots > 1) ...[
                      const SizedBox(width: 12),
                      widget.sliderBuilder(false),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHostedVideoControls({
    required ReaderVideoControls controls,
    required bool integrated,
    required bool visible,
    required bool showReaderControls,
    required double maxWidth,
    required bool isWideLayout,
    required int totalSlots,
    required int currentSlot,
    required PageSource? localSource,
    required List<Doc> docs,
    required bool showThumbnailStrip,
    required bool rightToLeft,
    required bool isCompactLayout,
    required double topMaxWidth,
  }) {
    if (!integrated) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controls.visible || controls.pinned || controls.panelsOpen.value)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: controls.builder(false, visible),
                ),
              ),
            ),
          if (showReaderControls) ...[
            const SizedBox(height: 8),
            if (isCompactLayout)
              _buildCompactControls(
                maxWidth: maxWidth,
                isWideLayout: isWideLayout,
                totalSlots: totalSlots,
                currentSlot: currentSlot,
                localSource: localSource,
                docs: docs,
                showThumbnailStrip: showThumbnailStrip,
                rightToLeft: rightToLeft,
              )
            else
              _buildRegularControls(
                topMaxWidth: topMaxWidth,
                bottomMaxWidth: maxWidth,
                isWideLayout: isWideLayout,
                totalSlots: totalSlots,
                currentSlot: currentSlot,
                localSource: localSource,
                docs: docs,
                showThumbnailStrip: showThumbnailStrip,
                rightToLeft: rightToLeft,
              ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWideLayout ? maxWidth : double.infinity,
          ),
          child: Material(
            key: const ValueKey('reader-video-bottom-bar'),
            color: context.theme.colorScheme.surfaceContainerLow,
            elevation: 3,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  key: const ValueKey('reader-video-toolbar'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _buildControlButtons(
                    totalSlots: totalSlots,
                    showThumbnailStrip: showThumbnailStrip,
                  ),
                ),
                controls.builder(true, visible),
                if (showThumbnailStrip && totalSlots > 1)
                  BottomThumbnailStrip(
                    embedded: true,
                    height: _BottomWidgetState._fusedStripHeight,
                    totalPages: totalSlots,
                    currentSlot: currentSlot,
                    comicId: comicId,
                    from: widget.from,
                    localSource: localSource,
                    docs: docs,
                    onSelectPage: _jumpToSlot,
                    rightToLeft: rightToLeft,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
