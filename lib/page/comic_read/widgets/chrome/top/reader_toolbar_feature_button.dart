import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';

/// 阅读增强的统一入口。触控区域固定，形状跟随项目的弹簧选中态。
class ReaderToolbarFeatureButton extends StatefulWidget {
  const ReaderToolbarFeatureButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.detail,
    this.selected = false,
    this.busy = false,
    this.failed = false,
    this.showLabel = true,
    this.showSelection = true,
    this.shape,
  });

  final Glyph icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final String? detail;
  final bool selected;
  final bool busy;
  final bool failed;
  final bool showLabel;
  final bool showSelection;
  final ExpressiveButtonShape? shape;

  @override
  State<ReaderToolbarFeatureButton> createState() =>
      _ReaderToolbarFeatureButtonState();
}

class _ReaderToolbarFeatureButtonState extends State<ReaderToolbarFeatureButton>
    with SingleTickerProviderStateMixin {
  late final _selection = SpringLensValue(this, widget.selected ? 1 : 0);
  late final _states = WidgetStatesController()..addListener(_syncSelection);

  void _syncSelection() {
    final target =
        widget.selected || _states.value.contains(WidgetState.pressed)
        ? 1.0
        : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _selection.jumpTo(target);
    } else if (_selection.target != target) {
      _selection.springTo(target, LensMetrics.settle);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant ReaderToolbarFeatureButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelection();
  }

  @override
  void dispose() {
    _states.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = widget.failed
        ? scheme.onErrorContainer
        : widget.selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: MergeSemantics(
        child: Semantics(
          selected: widget.selected,
          child: GestureDetector(
            onLongPressStart: widget.onLongPressStart == null
                ? null
                : (_) => widget.onLongPressStart!(),
            onLongPressEnd: widget.onLongPressEnd == null
                ? null
                : (_) => widget.onLongPressEnd!(),
            onLongPressCancel: widget.onLongPressEnd,
            child: ActionBubbleTarget(
              corner: 24,
              child: ElasticButton(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: ListenableBuilder(
                  listenable: _selection,
                  builder: (context, _) => FilledButton.tonal(
                    statesController: _states,
                    onPressed: widget.onPressed,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      maximumSize: const Size(double.infinity, 48),
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: widget.failed
                          ? scheme.errorContainer
                          : Color.lerp(
                              scheme.surfaceContainerHigh,
                              scheme.secondaryContainer,
                              _selection.value.clamp(0, 1),
                            ),
                      foregroundColor: fg,
                      animationDuration: Duration.zero,
                      shape: widget.shape == null
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                24 - 8 * _selection.value,
                              ),
                            )
                          : ExpressiveMorphBorder(
                              from: widget.shape!,
                              to: widget.shape!.pressedShape,
                              progress: _selection.value,
                            ),
                    ).merge(ElasticPress.buttonStyle),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.busy &&
                            !MediaQuery.disableAnimationsOf(context))
                          SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: fg,
                            ),
                          )
                        else
                          GlyphIcon(widget.icon, size: 20),
                        if (widget.showLabel) ...[
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: fg,
                                ),
                              ),
                              if (widget.detail != null)
                                Text(
                                  widget.detail!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: fg,
                                  ),
                                ),
                            ],
                          ),
                          if (widget.selected && widget.showSelection) ...[
                            const SizedBox(width: 6),
                            const GlyphIcon(AppGlyphs.check, size: 16),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
