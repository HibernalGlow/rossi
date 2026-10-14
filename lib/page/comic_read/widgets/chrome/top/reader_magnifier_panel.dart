import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/model/reader_magnifier.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

// 上下限写在文案里而不是各写一遍数字：这三条是从 `model/reader_magnifier.dart`
// 的常数插出来的，改那边这里跟着动，不会出现「文案说 800、实际钳到 600」。
String get _zoomTooltip => t.reader.loupeZoomRange(
  min: kReaderLoupeZoomPercentMin,
  max: kReaderLoupeZoomPercentMax,
);
String get _sizeTooltip => t.reader.loupeSizeRange(
  min: kReaderLoupeSizeMin.toInt(),
  max: kReaderLoupeSizeMax.toInt(),
);
final String _lockOnTooltip = t.reader.loupeLockedOn;
final String _lockOffTooltip = t.reader.loupeUnlockedFollows;
final String _autoModeTooltip = t.reader.pointerTypeAuto;

/// 顶栏「放大镜」面板。
///
/// 五项各自 `context.select` 单字段，不整份 watch `readSetting`：这条面板挂在顶栏上，
/// 整份订阅会让顶栏每一次无关设置变更都重建一次。
///
/// 倍率与尺寸的上下限不在这里各写一遍数字 —— 走 `model/reader_magnifier.dart`
/// 那份移植的 `normalize*`/`step*`，面板与绘制侧读同一把尺（写两份必然漂移）。
class ReaderMagnifierPanel extends StatelessWidget {
  const ReaderMagnifierPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final enabled = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.magnifierEnabled,
    );
    final mode = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.magnifierMode,
    );
    final zoomPercent = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.magnifierZoomPercent,
    );
    final sizeLogical = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.magnifierSizeLogical,
    );
    final locked = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.magnifierLocked,
    );

    return ReaderToolbarPanelRow(
      children: [
        ReaderToolbarToggleChip(
          icon: AppGlyphs.zoomIn,
          label: t.reader.loupe,
          tooltip: enabled ? t.reader.loupeEnabled : t.reader.loupeTooltip,
          selected: enabled,
          onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
            (s) => s.copyWith(magnifierEnabled: !s.magnifierEnabled),
          ),
        ),
        const ReaderToolbarSeparator(),
        ReaderToolbarLabel(t.reader.scaleLabel),
        _MagnifierStepper(
          icon: AppGlyphs.linearScale,
          label: '$zoomPercent%',
          tooltip: _zoomTooltip,
          enabled: enabled,
          onDecrement: () => _setZoom(context, zoomPercent, -1),
          onIncrement: () => _setZoom(context, zoomPercent, 1),
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('尺寸'),
        _MagnifierStepper(
          icon: AppGlyphs.ring,
          label: '$sizeLogical',
          tooltip: _sizeTooltip,
          enabled: enabled,
          onDecrement: () => _setSize(context, sizeLogical, -1),
          onIncrement: () => _setSize(context, sizeLogical, 1),
        ),
        const ReaderToolbarSeparator(),
        ReaderToolbarLabel(t.reader.trigger),
        ReaderToolbarPill(
          children: [
            for (final value in ReaderMagnifierMode.values)
              ReaderToolbarIconButton(
                icon: _modeIcon(value),
                tooltip: _modeTooltip(value),
                selected: mode == value,
                enabled: enabled,
                onPressed: enabled
                    ? () =>
                          context.read<GlobalSettingCubit>().updateReadSetting(
                            (s) => s.copyWith(magnifierMode: value),
                          )
                    : null,
              ),
          ],
        ),
        const ReaderToolbarSeparator(),
        ReaderToolbarToggleChip(
          icon: locked ? AppGlyphs.lock : AppGlyphs.lockOpen,
          label: t.reader.lockLoupe,
          tooltip: locked ? _lockOnTooltip : _lockOffTooltip,
          selected: locked,
          enabled: enabled,
          onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
            (s) => s.copyWith(magnifierLocked: !s.magnifierLocked),
          ),
        ),
      ],
    );
  }

  void _setZoom(BuildContext context, int percent, int direction) {
    final next = stepReaderLoupeZoomPercent(
      percent.toDouble(),
      direction,
    ).round();
    context.read<GlobalSettingCubit>().updateReadSetting(
      (s) => s.copyWith(magnifierZoomPercent: next),
    );
  }

  void _setSize(BuildContext context, int size, int direction) {
    // 步进 20，落点仍交给 normalizer：上限之外不该悄悄留一个越界值在设置里
    //（这一份要进云同步 JSON，越界值会被别的设备读到）。
    final next = normalizeReaderLoupeSize(
      (size + direction * 20).toDouble(),
    ).round();
    context.read<GlobalSettingCubit>().updateReadSetting(
      (s) => s.copyWith(magnifierSizeLogical: next),
    );
  }

  Glyph _modeIcon(ReaderMagnifierMode mode) => switch (mode) {
    ReaderMagnifierMode.auto => AppGlyphs.themeAuto,
    ReaderMagnifierMode.hover => AppGlyphs.mouse,
    ReaderMagnifierMode.touch => AppGlyphs.touch,
  };

  String _modeTooltip(ReaderMagnifierMode mode) => switch (mode) {
    ReaderMagnifierMode.auto => _autoModeTooltip,
    ReaderMagnifierMode.hover => t.reader.hoverFollowsMouse,
    ReaderMagnifierMode.touch => t.reader.touchHoldToShow,
  };
}

/// 一个「− 值 +」的微调条：与版式面板那条同一形状（胶囊 + 两侧小按钮），
/// 差别只在这里的值带图标与等宽数字。
///
/// 没有复用 `reader_layout_panel.dart` 里那颗 `_Stepper`：它是那份文件的私有件，
/// 而这里要的是「图标 + tabularFigures 的读数」。共用需要先把 `_Stepper` 提成公开件，
/// 那属于碰别人的文件。
class _MagnifierStepper extends StatelessWidget {
  const _MagnifierStepper({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onDecrement,
    required this.onIncrement,
  });

  final Glyph icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tint = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);

    return Tooltip(
      message: tooltip,
      child: ReaderToolbarPill(
        emphasized: true,
        children: [
          _stepButton(AppGlyphs.remove, tint, enabled ? onDecrement : null),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlyphIcon(icon, size: ReaderToolbarMetrics.iconSize, color: tint),
              const SizedBox(width: 4),
              // tabularFigures：倍率从 300% 跳到 400% 时读数不许左右抖。
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          _stepButton(AppGlyphs.add, tint, enabled ? onIncrement : null),
        ],
      ),
    );
  }

  Widget _stepButton(Glyph glyph, Color color, VoidCallback? onTap) => InkWell(
    borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: GlyphIcon(glyph, size: 15, color: color),
    ),
  );
}
