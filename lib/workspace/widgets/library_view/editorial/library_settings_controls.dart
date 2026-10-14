import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 一组调节共享外轮廓，内部以短圆角连接，避免给每项套独立卡片。
class LibrarySettingsGroup extends StatelessWidget {
  const LibrarySettingsGroup({
    super.key,
    required this.title,
    required this.glyph,
    required this.children,
    this.description,
  });
  final String title;
  final Glyph glyph;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  GlyphIcon(glyph, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
            ),
          ),
          M3EList(
            itemCount: children.length,
            outerRadius: 24,
            innerRadius: 4,
            gap: 2,
            color: theme.colorScheme.surfaceContainerLow,
            padding: EdgeInsets.zero,
            itemBuilder: (_, index) => children[index],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LibrarySettingsSlider extends StatelessWidget {
  const LibrarySettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.percent = false,
    this.unit = '',
  });
  final String label, unit;
  final double value, min, max;
  final bool percent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = percent
        ? '${(value * 100).round()}%'
        : '${value.round()}$unit';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: theme.colorScheme.secondaryContainer,
                ),
                child: Text(
                  display,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: M3ESlider(
              key: ValueKey('library-slider-$label'),
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) * (percent ? 100 : 1)).round(),
              label: display,
              semanticLabel: label,
              semanticFormatterCallback: (_) => display,
              size: M3ESliderSize.xs,
              onChanged: onChanged,
              onChangeEnd: (_) => HapticFeedback.selectionClick(),
            ),
          ),
        ],
      ),
    );
  }
}

class LibrarySettingsToggle extends StatelessWidget {
  const LibrarySettingsToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElasticButton(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: scheme.secondaryContainer,
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        shape: selected ? AppShape.xl : AppShape.md,
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (next) {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
      ),
    );
  }
}
