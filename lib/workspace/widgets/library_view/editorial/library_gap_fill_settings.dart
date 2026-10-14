import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_settings_controls.dart';

/// 「空隙填充」：先选总口径，再对**每一项**单独开关。
///
/// 子开关只在当前口径下真能改变输出时才出现 —— 选了「不填充」还留着一颗
/// 「随机图形」开关，那颗就是装饰品。
class LibraryGapFillChoices extends StatelessWidget {
  const LibraryGapFillChoices({
    super.key,
    required this.value,
    required this.onChanged,
    required this.shapesEnabled,
    required this.onShapesChanged,
    required this.widgets,
    required this.widgetToggles,
    required this.onWidgetChanged,
  });

  final LibraryGapFill value;
  final ValueChanged<LibraryGapFill> onChanged;

  final bool shapesEnabled;
  final ValueChanged<bool> onShapesChanged;

  /// 本面墙的完整套件（含被关掉的那些，否则再也打不开）。
  final List<LibraryGapWidgetSpec> widgets;

  /// 单项开关表；缺键 = 开。
  final Map<String, bool> widgetToggles;
  final void Function(String id, bool enabled) onWidgetChanged;

  bool get _showsShapes => value == LibraryGapFill.both;

  bool get _showsWidgets =>
      value == LibraryGapFill.both || value == LibraryGapFill.widgets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('空隙填充', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final mode in LibraryGapFill.values)
                ElasticButton(
                  enabled: !MediaQuery.disableAnimationsOf(context),
                  child: ChoiceChip(
                    label: Text(mode.label),
                    selected: mode == value,
                    side: BorderSide.none,
                    shape: mode == value ? AppShape.xl : AppShape.md,
                    selectedColor: scheme.secondaryContainer,
                    backgroundColor: scheme.surfaceContainerHigh,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      onChanged(mode);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            switch (value) {
              LibraryGapFill.off => '不规则轮廓之间保留空白。',
              LibraryGapFill.shapes => '用随机的 Expressive 轮廓与图标补满空隙。',
              LibraryGapFill.widgets => '只插入尺寸相符的汇总小组件，同一款可以重复。',
              LibraryGapFill.both => '小组件每面墙各出现一次，其余空隙用随机图形补。',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (_showsShapes || _showsWidgets) ...[
            const SizedBox(height: 10),
            if (_showsShapes)
              LibrarySettingsToggle(
                label: '随机图形',
                selected: shapesEnabled,
                onChanged: onShapesChanged,
              ),
            if (_showsWidgets) ...[
              if (_showsShapes) const SizedBox(height: 8),
              Text(
                '小组件',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final spec in widgets)
                    LibrarySettingsToggle(
                      key: ValueKey('gap-widget-${spec.id}'),
                      label: spec.label,
                      selected: widgetToggles[spec.id] ?? true,
                      onChanged: (next) => onWidgetChanged(spec.id, next),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
