import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';

/// 单选排序 / 筛选轨：文字的实测宽度与选中气泡共用同一份槽位。
class SpringChoiceBar<T> extends StatelessWidget {
  const SpringChoiceBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<({T value, String label})> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final style = DefaultTextStyle.of(context).style
        .merge(Theme.of(context).textTheme.labelLarge)
        .copyWith(color: scheme.onSurfaceVariant);
    final widths = <double>[];
    for (final option in options) {
      final painter = TextPainter(
        text: TextSpan(text: option.label, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      widths.add(painter.width + 32);
      painter.dispose();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(ControlShape.trackCorner),
        ),
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 40,
          child: SpringLensBar(
            lensCorner: ControlShape.corner,
            tabs: [
              for (final option in options)
                SpringLensTab(
                  semanticLabel: option.label,
                  child: Center(child: Text(option.label, style: style)),
                ),
            ],
            tabSizes: widths,
            selectedIndex: options
                .indexWhere((option) => option.value == value)
                .clamp(0, options.length - 1),
            onSelected: (index) => onChanged(options[index].value),
            tintColor: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
