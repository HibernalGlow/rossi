import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';
import 'package:zephyr/config/global/global_setting.dart';

class InsightBadge extends StatelessWidget {
  const InsightBadge({super.key, required this.text, this.glyph});
  final String text;
  final Glyph? glyph;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: colors.secondaryContainer,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            GlyphIcon(glyph!, size: 16, color: colors.onSecondaryContainer),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 只强调摘要；表格、柱和热力格仍按同一套几何排齐。
class InsightMetric extends StatelessWidget {
  const InsightMetric({
    super.key,
    required this.value,
    required this.label,
    this.highlight = false,
    this.glyph,
  });
  final String value;
  final String label;
  final bool highlight;
  final Glyph? glyph;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(highlight ? 6 : 22),
          bottomRight: const Radius.circular(22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            SizedBox(
              width: 36,
              height: 36,
              child: M3EShapeContainer(
                kind: M3EShapeKind.cookie4Sided,
                color: theme.colorScheme.primary.withValues(alpha: .12),
                child: Center(child: GlyphIcon(glyph!, size: 20, color: color)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 指标在窄卡片里自动换行，宽高不由文本反向修改外层网格。
class InsightMetrics extends StatelessWidget {
  const InsightMetrics({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final count = (constraints.maxWidth / (125 * scale)).floor().clamp(
        1,
        children.length,
      );
      final width = (constraints.maxWidth - (count - 1) * 8) / count;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class InsightFootnote extends StatelessWidget {
  const InsightFootnote({super.key, this.text = '基于最近 500 本漫画的最后阅读记录'});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 图表共用本仓弹簧，数据刷新保留当前位置和速度；减少动画直接落位。
class InsightSpringValue extends StatefulWidget {
  const InsightSpringValue({
    super.key,
    required this.value,
    required this.builder,
  });
  final double value;
  final Widget Function(double value) builder;
  @override
  State<InsightSpringValue> createState() => _InsightSpringValueState();
}

class _InsightSpringValueState extends State<InsightSpringValue>
    with SingleTickerProviderStateMixin {
  late final _value = SpringLensValue(this, widget.value);
  void _update() {
    if (MediaQuery.disableAnimationsOf(context) || eInkInstantRoutes) {
      _value.jumpTo(widget.value);
    } else if (_value.target != widget.value) {
      _value.springTo(widget.value, LensMetrics.settle);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant InsightSpringValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _value,
    builder: (context, _) => widget.builder(_value.value.clamp(0, 1)),
  );
}

/// 图表条目可被鼠标、触摸与键盘读取，详情在图表内显示。
class InsightSelectable extends StatelessWidget {
  const InsightSelectable({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.child,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Widget child;
  @override
  Widget build(BuildContext context) => ActionBubbleTarget(
    enabled: !eInkInstantRoutes,
    corner: 12,
    child: ElasticPress(
      enabled: !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context),
      child: TextButton(
        onPressed: onSelected,
        style:
            TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
                .merge(ElasticPress.buttonStyle)
                .copyWith(
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
        child: Semantics(
          label: label,
          selected: selected,
          child: ExcludeSemantics(child: child),
        ),
      ),
    ),
  );
}
