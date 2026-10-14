part of 'reader_settings_sheet.dart';

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

    return SettingsSection(
      title: t.reader.hoverReveal,
      icon: AppGlyphs.mouse,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.hoverRevealEnabled,
              subtitle: t.reader.hoverRevealEnabledSubtitle,
              value: isEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(hoverRevealEnabled: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: isEnabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildNeoViewAreaPreview(context, readSetting),
                  ),
                  SettingsSwitchTile(
                    title: t.reader.hoverRevealTop,
                    subtitle: t.reader.hoverAreaTopHint.replaceAll(
                      '{height}',
                      '${readSetting.hoverTriggerAreaTop}',
                    ),
                    value: readSetting.hoverRevealTop,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(hoverRevealTop: value),
                      );
                    },
                  ),
                  SettingsAnimatedCollapse(
                    isExpanded: readSetting.hoverRevealTop,
                    child: SettingsSliderCard(
                      title: t.reader.hoverTriggerAreaTop,
                      value: readSetting.hoverTriggerAreaTop.clamp(10, 120),
                      min: 10,
                      max: 120,
                      divisions: 110,
                      suffix: 'px',
                      onChanged: (value) {
                        globalSettingCubit.updateReadSetting(
                          (current) =>
                              current.copyWith(hoverTriggerAreaTop: value),
                        );
                      },
                    ),
                  ),
                  SettingsSwitchTile(
                    title: t.reader.hoverRevealBottom,
                    subtitle: t.reader.hoverAreaBottomHint.replaceAll(
                      '{height}',
                      '${readSetting.hoverTriggerAreaBottom}',
                    ),
                    value: readSetting.hoverRevealBottom,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(hoverRevealBottom: value),
                      );
                    },
                  ),
                  SettingsAnimatedCollapse(
                    isExpanded: readSetting.hoverRevealBottom,
                    child: SettingsSliderCard(
                      title: t.reader.hoverTriggerAreaBottom,
                      value: readSetting.hoverTriggerAreaBottom.clamp(10, 120),
                      min: 10,
                      max: 120,
                      divisions: 110,
                      suffix: 'px',
                      onChanged: (value) {
                        globalSettingCubit.updateReadSetting(
                          (current) =>
                              current.copyWith(hoverTriggerAreaBottom: value),
                        );
                      },
                    ),
                  ),
                  SettingsSliderCard(
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
                  SettingsSwitchTile(
                    title: t.reader.hoverShowVisualIndicator,
                    subtitle: t.reader.hoverShowVisualIndicatorSubtitle,
                    value: readSetting.hoverShowVisualIndicator,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) =>
                            current.copyWith(hoverShowVisualIndicator: value),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
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
              GlyphIcon(AppGlyphs.eye, size: 16, color: primaryColor),
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
                      GlyphIcon(
                        AppGlyphs.book,
                        size: 30,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.reader.neoviewViewportDemo,
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
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
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                            width: readSetting.hoverShowVisualIndicator ? 2 : 1,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        readSetting.hoverRevealTop
                            ? t.reader.topRevealPx(
                                px: readSetting.hoverTriggerAreaTop,
                              )
                            : t.reader.alreadyDisabled,
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: readSetting.hoverRevealTop
                              ? primaryColor
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
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
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                            width: readSetting.hoverShowVisualIndicator ? 2 : 1,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        readSetting.hoverRevealBottom
                            ? t.reader.bottomRevealPx(
                                px: readSetting.hoverTriggerAreaBottom,
                              )
                            : t.reader.alreadyDisabled,
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: readSetting.hoverRevealBottom
                              ? primaryColor
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
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

class _CenterTapSection extends StatelessWidget {
  const _CenterTapSection();
  @override
  Widget build(BuildContext context) {
    final effective = context.watchTargetReadSetting();
    return _SettingsSwitchTile(
      title: t.reader.centerTapToggleBars,
      subtitle: t.reader.centerTapToggleBarsSubtitle,
      value: effective.centerTapToggleBars,
      onChanged: (value) => context.updateEffectiveReadSetting(
        effective,
        (current) => current.copyWith(
          centerTapToggleBars: value,
          doubleTapOpenMenu:
              !value && !current.doubleTapOpenMenu && !current.doubleTapZoom
              ? true
              : current.doubleTapOpenMenu,
        ),
      ),
    );
  }
}
