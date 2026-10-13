part of 'reader_settings_sheet.dart';

/// 上游阅读设置之外，Rossi 阅读器仍消费的全局选项。
class _ReaderReadExtras extends StatelessWidget {
  const _ReaderReadExtras();

  @override
  Widget build(BuildContext context) {
    final setting = context.watchTargetReadSetting();
    return _settingsToggleGroup([
      _SettingsSwitchTile(
        title: t.reader.readingDirectionToggleSetting,
        subtitle: setting.readMode == 0
            ? t.reader.readingDirectionToggleDisabled
            : (setting.readMode == 2
                  ? t.reader.readingDirectionToggleLeftOpen
                  : t.reader.readingDirectionToggleRightOpen),
        value: setting.readingDirectionToggle,
        onChanged: (value) => context.updateEffectiveReadSetting(
          setting,
          (current) => current.copyWith(readingDirectionToggle: value),
        ),
      ),
      if (setting.readMode != 0)
        _SettingsSwitchTile(
          title: t.reader.swipePreview,
          subtitle: t.reader.swipePreviewSubtitle,
          value: setting.swipePreviewEnabled,
          onChanged: (value) => context.updateEffectiveReadSetting(
            setting,
            (current) => current.copyWith(swipePreviewEnabled: value),
          ),
        ),
      _SettingsSwitchTile(
        title: t.reader.readWhileDownloading,
        subtitle: t.reader.readWhileDownloadingSubtitle,
        value: setting.readWhileDownloading,
        onChanged: (value) => context.updateEffectiveReadSetting(
          setting,
          (current) => current.copyWith(readWhileDownloading: value),
        ),
      ),
    ]);
  }
}

/// 复用上游的背景写入路由，补充 Rossi 的自适应背景与压暗幅度。
class _ReaderAmbientSettings extends StatelessWidget {
  const _ReaderAmbientSettings();

  @override
  Widget build(BuildContext context) {
    final setting = context.watchTargetReadSetting();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in [
              ReaderBackgroundMode.adaptive,
              ReaderBackgroundMode.adaptiveEdge,
            ])
              _SettingsChoiceChip(
                title: mode == ReaderBackgroundMode.adaptive
                    ? t.reader.adaptive
                    : t.reader.adaptiveEdge,
                selected: setting.readerBackgroundMode == mode,
                onTap: () => context.updateEffectiveReadSetting(
                  setting,
                  (current) => current.copyWith(readerBackgroundMode: mode),
                ),
              ),
          ],
        ),
        if (setting.readerAmbientEnabled) ...[
          const SizedBox(height: 10),
          _SettingsNoticeCard(text: t.reader.ambientDimSubtitle),
          const SizedBox(height: 10),
          _SettingsSliderCard(
            title: t.reader.ambientDim,
            value: setting.readerAmbientDimPercent.clamp(
              readerAmbientDimPercentMin,
              readerAmbientDimPercentMax,
            ),
            min: readerAmbientDimPercentMin,
            max: readerAmbientDimPercentMax,
            divisions: readerAmbientDimPercentMax - readerAmbientDimPercentMin,
            suffix: '%',
            onChanged: (value) => context.updateEffectiveReadSetting(
              setting,
              (current) => current.copyWith(readerAmbientDimPercent: value),
            ),
          ),
        ],
      ],
    );
  }
}
