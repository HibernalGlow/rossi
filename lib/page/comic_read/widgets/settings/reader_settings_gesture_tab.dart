part of 'reader_settings_sheet.dart';

class _ReaderSettingsGestureTab extends StatelessWidget {
  final bool isAndroidPhone;

  const _ReaderSettingsGestureTab({required this.isAndroidPhone});

  @override
  Widget build(BuildContext context) {
    return _SettingsTabContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HoverRevealSection(),
          const SizedBox(height: 18),
          const _TapPageTurnModeSection(),
          const SizedBox(height: 18),
          const _WebtoonTapPageTurnSection(),
          const SizedBox(height: 18),
          const _DoubleTapSection(),
          if (isAndroidPhone) const SizedBox(height: 18),
          if (isAndroidPhone) const _VolumeKeyPageTurnSection(),
        ],
      ),
    );
  }
}

class _TapPageTurnModeSection extends StatelessWidget {
  const _TapPageTurnModeSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final mode = globalSettingState.readSetting.tapPageTurnMode;

    return _SettingsSection(
      title: t.reader.pageMode,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SettingsChoiceChip(
              title: t.reader.fullscreen,
              selected: mode == ReaderTapPageTurnMode.fullScreen,
              onTap: () {
                if (mode == ReaderTapPageTurnMode.fullScreen) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    tapPageTurnMode: ReaderTapPageTurnMode.fullScreen,
                  ),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.leftHandMode,
              selected: mode == ReaderTapPageTurnMode.leftHand,
              onTap: () {
                if (mode == ReaderTapPageTurnMode.leftHand) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    tapPageTurnMode: ReaderTapPageTurnMode.leftHand,
                  ),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.rightHandMode,
              selected: mode == ReaderTapPageTurnMode.rightHand,
              onTap: () {
                if (mode == ReaderTapPageTurnMode.rightHand) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    tapPageTurnMode: ReaderTapPageTurnMode.rightHand,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _WebtoonTapPageTurnSection extends StatelessWidget {
  const _WebtoonTapPageTurnSection();

  @override
  Widget build(BuildContext context) {
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: t.reader.webtoonTapPageTurn,
      children: [
        _SettingsSwitchTile(
          title: t.reader.enableWebtoonTapPageTurn,
          subtitle: t.reader.webtoonTapPageTurnSubtitle,
          value: readSetting.tapPageTurnInWebtoon,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(tapPageTurnInWebtoon: value),
            );
          },
        ),
      ],
    );
  }
}

class _DoubleTapSection extends StatelessWidget {
  const _DoubleTapSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.doubleTapAction,
      children: [
        _SettingsSwitchTile(
          title: t.reader.doubleTapZoom,
          subtitle: t.reader.doubleTapZoomSubtitle,
          value: readSetting.doubleTapZoom,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(
                doubleTapZoom: value,
                doubleTapOpenMenu: value ? false : current.doubleTapOpenMenu,
              ),
            );
          },
        ),
        _SettingsSwitchTile(
          title: t.reader.doubleTapOpenMenu,
          subtitle: t.reader.doubleTapOpenMenuSubtitle,
          value: readSetting.doubleTapOpenMenu,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(
                doubleTapOpenMenu: value,
                doubleTapZoom: value ? false : current.doubleTapZoom,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _VolumeKeyPageTurnSection extends StatelessWidget {
  const _VolumeKeyPageTurnSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.volumeKeyPageTurn,
      children: [
        _SettingsSwitchTile(
          title: t.reader.enableVolumeKeyPageTurn,
          subtitle: t.reader.volumeKeyPageTurnSubtitle,
          value: readSetting.volumeKeyPageTurn,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(volumeKeyPageTurn: value),
            );
          },
        ),
        if (readSetting.volumeKeyPageTurn)
          _SettingsSliderCard(
            title: t.reader.webtoonScrollDistance,
            value: readSetting.volumeKeyPageTurnDistancePercent.clamp(10, 100),
            min: 10,
            max: 100,
            divisions: 90,
            suffix: t.reader.screenHeightPercent,
            onChanged: (value) {
              final percent = value.clamp(10, 100);
              globalSettingCubit.updateReadSetting(
                (current) =>
                    current.copyWith(volumeKeyPageTurnDistancePercent: percent),
              );
            },
          ),
      ],
    );
  }
}

class _HoverRevealSection extends StatefulWidget {
  const _HoverRevealSection();

  @override
  State<_HoverRevealSection> createState() => _HoverRevealSectionState();
}

class _HoverRevealSectionState extends State<_HoverRevealSection> {
  bool _previewTopHovered = false;
  bool _previewBottomHovered = false;

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;
    final isEnabled = readSetting.hoverRevealEnabled;

    return _SettingsSection(
      title: t.reader.hoverReveal,
      children: [
        _SettingsSwitchTile(
          title: t.reader.hoverRevealEnabled,
          subtitle: t.reader.hoverRevealEnabledSubtitle,
          value: isEnabled,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(hoverRevealEnabled: value),
            );
          },
        ),
        if (isEnabled) ...[
          _buildNeoViewAreaPreview(context, readSetting),
          _SettingsSwitchTile(
            title: t.reader.hoverRevealTop,
            subtitle: t.reader.hoverAreaTopHint
                .replaceAll('{height}', '${readSetting.hoverTriggerAreaTop}'),
            value: readSetting.hoverRevealTop,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(hoverRevealTop: value),
              );
            },
          ),
          if (readSetting.hoverRevealTop)
            _SettingsSliderCard(
              title: t.reader.hoverTriggerAreaTop,
              value: readSetting.hoverTriggerAreaTop.clamp(10, 120),
              min: 10,
              max: 120,
              divisions: 110,
              suffix: 'px',
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(hoverTriggerAreaTop: value),
                );
              },
            ),
          _SettingsSwitchTile(
            title: t.reader.hoverRevealBottom,
            subtitle: t.reader.hoverAreaBottomHint
                .replaceAll('{height}', '${readSetting.hoverTriggerAreaBottom}'),
            value: readSetting.hoverRevealBottom,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(hoverRevealBottom: value),
              );
            },
          ),
          if (readSetting.hoverRevealBottom)
            _SettingsSliderCard(
              title: t.reader.hoverTriggerAreaBottom,
              value: readSetting.hoverTriggerAreaBottom.clamp(10, 120),
              min: 10,
              max: 120,
              divisions: 110,
              suffix: 'px',
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(hoverTriggerAreaBottom: value),
                );
              },
            ),
          _SettingsSliderCard(
            title: t.reader.hoverHideDelay,
            value: readSetting.hoverHideDelayMs.clamp(100, 2000),
            min: 100,
            max: 2000,
            divisions: 19,
            suffix: 'ms',
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(hoverHideDelayMs: value),
              );
            },
          ),
          _SettingsSwitchTile(
            title: t.reader.hoverShowVisualIndicator,
            subtitle: t.reader.hoverShowVisualIndicatorSubtitle,
            value: readSetting.hoverShowVisualIndicator,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(hoverShowVisualIndicator: value),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildNeoViewAreaPreview(
    BuildContext context,
    ReadSettingState readSetting,
  ) {
    final colorScheme = context.theme.colorScheme;
    final primaryColor = colorScheme.primary;

    final double topHeightNorm =
        (readSetting.hoverTriggerAreaTop / 800.0 * 140.0).clamp(14.0, 42.0);
    final double bottomHeightNorm =
        (readSetting.hoverTriggerAreaBottom / 800.0 * 140.0).clamp(14.0, 42.0);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.preview_rounded,
                size: 16,
                color: primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                t.reader.hoverAreaPreview,
                style: context.theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        size: 30,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'NeoView 视口感应交互示意',
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topHeightNorm,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _previewTopHovered = true),
                    onExit: (_) => setState(() => _previewTopHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: readSetting.hoverRevealTop
                            ? (_previewTopHovered
                                ? primaryColor.withValues(alpha: 0.45)
                                : primaryColor.withValues(alpha: 0.2))
                            : colorScheme.outlineVariant.withValues(alpha: 0.1),
                        border: Border(
                          bottom: BorderSide(
                            color: readSetting.hoverRevealTop
                                ? primaryColor.withValues(
                                    alpha: _previewTopHovered ? 0.9 : 0.5,
                                  )
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.2),
                            width:
                                readSetting.hoverShowVisualIndicator ? 2 : 1,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        readSetting.hoverRevealTop
                            ? '顶部唤出 (${readSetting.hoverTriggerAreaTop}px)'
                            : '已禁用',
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: readSetting.hoverRevealTop
                              ? primaryColor
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: bottomHeightNorm,
                  child: MouseRegion(
                    onEnter: (_) =>
                        setState(() => _previewBottomHovered = true),
                    onExit: (_) =>
                        setState(() => _previewBottomHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: readSetting.hoverRevealBottom
                            ? (_previewBottomHovered
                                ? primaryColor.withValues(alpha: 0.45)
                                : primaryColor.withValues(alpha: 0.2))
                            : colorScheme.outlineVariant.withValues(alpha: 0.1),
                        border: Border(
                          top: BorderSide(
                            color: readSetting.hoverRevealBottom
                                ? primaryColor.withValues(
                                    alpha: _previewBottomHovered ? 0.9 : 0.5,
                                  )
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.2),
                            width:
                                readSetting.hoverShowVisualIndicator ? 2 : 1,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        readSetting.hoverRevealBottom
                            ? '底部唤出 (${readSetting.hoverTriggerAreaBottom}px)'
                            : '已禁用',
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: readSetting.hoverRevealBottom
                              ? primaryColor
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
