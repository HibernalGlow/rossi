part of '../video_control_overlay.dart';
// 弹层面板：倍速、音量、字幕、滤镜，以及配套的色点与带标签滑杆

class _RatePanel extends StatelessWidget {
  const _RatePanel({
    required this.snapshot,
    required this.controller,
    required this.labels,
  });

  final ReaderVideoSnapshot snapshot;
  final ReaderVideoController controller;
  final VideoLabels labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Slider(
              min: snapshot.minimumPlaybackRate,
              max: snapshot.maximumPlaybackRate,
              divisions:
                  ((snapshot.maximumPlaybackRate -
                              snapshot.minimumPlaybackRate) /
                          snapshot.playbackRateStep)
                      .round()
                      .clamp(1, 200),
              value: snapshot.playbackRate.clamp(
                snapshot.minimumPlaybackRate,
                snapshot.maximumPlaybackRate,
              ),
              onChanged: (v) => controller.setPlaybackRate(v),
            ),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final preset in kPlaybackRatePresets)
                  ChoiceChip(
                    label: Text('${preset}x'),
                    selected: snapshot.playbackRate == preset,
                    onSelected: (_) => controller.setPlaybackRate(preset),
                  ),
                TextButton(
                  onPressed: controller.toggleSpeed,
                  child: const Text('1x ⇄'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.controller});

  final ReaderVideoController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 200,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: Icon(snapshot.muted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => controller.toggleMute(),
            ),
            Expanded(
              // 步长 5%：上游的 0.05，一格一个可感知的音量变化。
              child: Slider(
                value: snapshot.volume,
                divisions: 20,
                onChanged: (v) => controller.setVolume(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitlePanel extends StatelessWidget {
  const _SubtitlePanel({
    required this.tracks,
    required this.labels,
    required this.style,
    required this.onStyleChanged,
    required this.onSelected,
  });

  final List<VideoMediaTrack> tracks;
  final VideoLabels labels;
  final VideoSubtitleStyle style;
  final ValueChanged<VideoSubtitleStyle>? onStyleChanged;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedId = tracks.where((t) => t.selected).firstOrNull?.id;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              dense: true,
              title: Text(labels.subtitleOff),
              leading: Icon(
                selectedId == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => onSelected(null),
            ),
            for (final track in tracks)
              ListTile(
                dense: true,
                title: Text(track.title),
                subtitle: track.language == null ? null : Text(track.language!),
                leading: Icon(
                  track.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => onSelected(track.id),
              ),
            if (onStyleChanged != null) ...<Widget>[
              const Divider(height: 16),
              _LabeledSlider(
                label: t.video.subSize,
                value: style.sizeEm,
                min: 0.5,
                max: 3,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: v,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: style.backgroundOpacityPercent,
                    bottomPercent: style.bottomPercent,
                  ),
                ),
              ),
              _LabeledSlider(
                label: t.video.subBg,
                value: style.backgroundOpacityPercent.toDouble(),
                min: 0,
                max: 100,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: style.sizeEm,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: v.round(),
                    bottomPercent: style.bottomPercent,
                  ),
                ),
              ),
              _LabeledSlider(
                label: t.video.subBottom,
                value: style.bottomPercent.toDouble(),
                min: 0,
                max: 30,
                onChanged: (v) => onStyleChanged!(
                  VideoSubtitleStyle(
                    sizeEm: style.sizeEm,
                    colorHex: style.colorHex,
                    backgroundOpacityPercent: style.backgroundOpacityPercent,
                    bottomPercent: v.round(),
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final color in const <String>[
                    'ffffff',
                    'ffe066',
                    '7cc4ff',
                    'ff8a8a',
                    'a6e3a1',
                  ])
                    _ColorDot(
                      hex: color,
                      selected: style.colorHex == color,
                      onTap: () => onStyleChanged!(
                        VideoSubtitleStyle(
                          sizeEm: style.sizeEm,
                          colorHex: color,
                          backgroundOpacityPercent:
                              style.backgroundOpacityPercent,
                          bottomPercent: style.bottomPercent,
                        ),
                      ),
                    ),
                  TextButton(
                    // 「大号黄色」预设：上游把它作为一个一键项保留，因为
                    // 白底黑框的老式字幕在浅色页面上几乎读不出来。
                    onPressed: () => onStyleChanged!(
                      const VideoSubtitleStyle(
                        sizeEm: 1.6,
                        colorHex: 'ffe066',
                        backgroundOpacityPercent: 70,
                        bottomPercent: 5,
                      ),
                    ),
                    child: Text(t.video.subLargeYellow),
                  ),
                  TextButton(
                    onPressed: () =>
                        onStyleChanged!(const VideoSubtitleStyle()),
                    child: Text(t.video.reset),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    final color = Color(0xFF000000 | parsed);
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '#$hex',
      isSelected: selected,
      onPressed: onTap,
      style: IconButton.styleFrom(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      icon: CircleAvatar(radius: 12, backgroundColor: color),
      selectedIcon: CircleAvatar(
        radius: 12,
        backgroundColor: color,
        child: Icon(
          Icons.check,
          size: 18,
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.light
              ? Colors.black
              : Colors.white,
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filter,
    required this.labels,
    required this.onChanged,
  });

  final VideoFilterState filter;
  final VideoLabels labels;
  final ValueChanged<VideoFilterState> onChanged;

  @override
  Widget build(BuildContext context) {
    // 0–200%：100 = 原样。上限 200 而不是 100 是 neo 的口径 ——
    // 「增强」需要往上一半的空间，往下只需要一半。
    Widget row(String label, int value, void Function(int) set) =>
        _LabeledSlider(
          label: label,
          value: value.toDouble(),
          min: 0,
          max: 200,
          onChanged: (v) => set(v.round()),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            row(
              t.video.brightness,
              filter.brightness,
              (v) => onChanged(filter.copyWith(brightness: v)),
            ),
            row(
              t.video.contrast,
              filter.contrast,
              (v) => onChanged(filter.copyWith(contrast: v)),
            ),
            row(
              t.video.saturation,
              filter.saturation,
              (v) => onChanged(filter.copyWith(saturation: v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onChanged(VideoFilterState.neutral),
                child: Text(labels.resetFilters),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                value == value.roundToDouble()
                    ? '${value.round()}'
                    : value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
