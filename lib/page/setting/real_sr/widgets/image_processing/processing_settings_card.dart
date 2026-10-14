import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_disclosure.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';

/// 裁边与降噪共用的 MD3E 分组：强调标题、色彩容器、胶囊状态与渐进高级设置。
class ProcessingSettingsCard extends StatelessWidget {
  const ProcessingSettingsCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    required this.children,
  });
  final String title;
  final String description;
  final IconData icon;
  final String status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: ShapeDecoration(
                  color: colors.secondaryContainer,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  status,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ProcessingAdvancedDisclosure extends StatefulWidget {
  const ProcessingAdvancedDisclosure({
    super.key,
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;
  @override
  State<ProcessingAdvancedDisclosure> createState() =>
      _ProcessingAdvancedDisclosureState();
}

class _ProcessingAdvancedDisclosureState
    extends State<ProcessingAdvancedDisclosure> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        button: true,
        expanded: _expanded,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 56,
          title: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: AnimatedRotation(
            turns: _expanded ? .5 : 0,
            duration: ExpressiveMotion.duration(
              context,
              ExpressiveMotion.spatialDuration,
            ),
            curve: ExpressiveMotion.spatialCurve,
            child: const Icon(Icons.expand_more),
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _expanded = !_expanded);
          },
        ),
      ),
      if (MediaQuery.disableAnimationsOf(context) ||
          !(SettingsPresentationScope.maybeOf(context)?.animate ?? true))
        _expanded ? widget.child : const SizedBox.shrink()
      else
        SettingsAnimatedCollapse(
          isExpanded: _expanded,
          showDivider: false,
          child: widget.child,
        ),
    ],
  );
}

/// 滑动只更新预览值；松手后保存一次，避免逐帧触发重新检测和模型推理。
class ProcessingSlider extends StatefulWidget {
  const ProcessingSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.labelOf,
    required this.onChanged,
    this.description,
  });
  final String title;
  final String? description;
  final int value;
  final int min;
  final int max;
  final String Function(int) labelOf;
  final ValueChanged<int> onChanged;
  @override
  State<ProcessingSlider> createState() => _ProcessingSliderState();
}

class _ProcessingSliderState extends State<ProcessingSlider> {
  int? _dragging;
  @override
  void didUpdateWidget(covariant ProcessingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.labelOf(value),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        if (widget.description != null)
          Text(
            widget.description!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        SizedBox(
          height: 56,
          child: Slider(
            value: value.clamp(widget.min, widget.max).toDouble(),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            label: widget.labelOf(value),
            semanticFormatterCallback: (v) =>
                '${widget.title} ${widget.labelOf(v.round())}',
            onChanged: (v) => setState(() => _dragging = v.round()),
            onChangeEnd: (v) {
              HapticFeedback.lightImpact();
              widget.onChanged(v.round());
            },
          ),
        ),
      ],
    );
  }
}

ButtonStyle processingActionStyle() => FilledButton.styleFrom(
  minimumSize: const Size(48, 48),
  shape: const StadiumBorder(),
);
