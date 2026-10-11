import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

export 'expressive_shape.dart' show ExpressiveButtonShape;

/// 按用途选择轮廓；打开和按压时形变，触控区域始终保持原尺寸。
class ExpressiveIconButton extends StatefulWidget {
  const ExpressiveIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 40,
    this.activeTurns = .125,
    this.activeGlyph,
    this.shape = ExpressiveButtonShape.roundedSquare,
  });
  final Glyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final double activeTurns;
  final Glyph? activeGlyph;
  final ExpressiveButtonShape shape;

  @override
  State<ExpressiveIconButton> createState() => _ExpressiveIconButtonState();
}

class _ExpressiveIconButtonState extends State<ExpressiveIconButton> {
  late final WidgetStatesController _states;

  @override
  void initState() {
    super.initState();
    // 预置禁用态，避免 IconButton 挂载期间向已监听的祖先同步发通知。
    _states = WidgetStatesController({
      if (widget.onPressed == null) WidgetState.disabled,
    });
  }

  @override
  void didUpdateWidget(covariant ExpressiveIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.onPressed == null) != (widget.onPressed == null)) {
      _states.update(WidgetState.disabled, widget.onPressed == null);
      if (widget.onPressed == null) _states.update(WidgetState.pressed, false);
    }
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<WidgetState>>(
      valueListenable: _states,
      builder: (context, states, child) {
        final button = _buildButton(
          context,
          scheme,
          states.contains(WidgetState.pressed),
        );
        return MediaQuery.disableAnimationsOf(context)
            ? button
            : ElasticButton(enabled: widget.onPressed != null, child: button);
      },
    );
  }

  Widget _buildButton(BuildContext context, ColorScheme scheme, bool pressed) {
    final button = TweenAnimationBuilder<double>(
      tween: Tween(
        end: widget.active
            ? 2
            : pressed
            ? 1
            : 0,
      ),
      duration: ExpressiveMotion.duration(
        context,
        ExpressiveMotion.spatialDuration,
      ),
      curve: ExpressiveMotion.spatialCurve,
      builder: (context, value, child) => IconButton(
        statesController: _states,
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        style: ButtonStyle(
          fixedSize: WidgetStatePropertyAll(Size.square(widget.size)),
          minimumSize: WidgetStatePropertyAll(Size.square(widget.size)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // 路径进度由同一条动画控制，避免 ButtonStyle 再叠一层形状插值。
          animationDuration: Duration.zero,
          shape: WidgetStatePropertyAll(
            expressiveButtonBorder(widget.shape, value, widget.size),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerHighest;
            }
            if (widget.active || states.contains(WidgetState.pressed)) {
              return scheme.primary;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return scheme.secondaryContainer;
            }
            return scheme.primaryContainer;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: .38);
            }
            if (widget.active || states.contains(WidgetState.pressed)) {
              return scheme.onPrimary;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return scheme.onSecondaryContainer;
            }
            return scheme.onPrimaryContainer;
          }),
        ).merge(ElasticPress.buttonStyle),
        icon: Transform.rotate(
          angle:
              ((value - 1).clamp(0.0, 1.0)) * widget.activeTurns * 6.283185307,
          child: GlyphIcon(
            widget.active && widget.activeGlyph != null
                ? widget.activeGlyph!
                : widget.glyph,
            size: widget.size >= 56 ? 24 : 20,
          ),
        ),
      ),
    );
    return button;
  }
}
