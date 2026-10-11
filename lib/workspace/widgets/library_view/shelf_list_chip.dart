import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 连续列表轨内的单选项。选中时圆角轻微变化，长列表名有上限。
class ShelfListChip extends StatelessWidget {
  const ShelfListChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final motion = ExpressiveMotion.duration(
      context,
      ExpressiveMotion.spatialDuration,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ElasticButton(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 14 : 12),
          duration: motion,
          curve: ExpressiveMotion.spatialCurve,
          builder: (context, radius, child) => ChoiceChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            selected: selected,
            showCheckmark: false,
            shape: AppShape.all(radius),
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            backgroundColor: scheme.surfaceContainer,
            selectedColor: scheme.secondaryContainer,
            chipAnimationStyle: ChipAnimationStyle(
              selectAnimation: AnimationStyle(
                duration: motion,
                curve: Curves.easeOut,
              ),
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            side: BorderSide.none,
            onSelected: (_) => onTap(),
          ),
        ),
      ),
    );
  }
}
