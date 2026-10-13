import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/radial/radial_focus_geometry.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

class RadialFocusSurface extends StatefulWidget {
  const RadialFocusSurface({super.key, required this.data});
  final RayMenuPresentation data;
  @override
  State<RadialFocusSurface> createState() => RadialFocusSurfaceState();
}

class RadialFocusSurfaceState extends State<RadialFocusSurface>
    with TickerProviderStateMixin {
  late final _x = SpringLensValue(this, 0);
  late final _y = SpringLensValue(this, 0);
  late final _panX = SpringLensValue(this, 0);
  late final _panY = SpringLensValue(this, 0);
  late final _strength = SpringLensValue(this, 0);
  late final _lift = SpringLensValue(this, 0);
  late final _highlightX = SpringLensValue(this, 0);
  late final _highlightY = SpringLensValue(this, 0);
  late final _highlightSize = SpringLensValue(this, 0);
  late final _highlightAlpha = SpringLensValue(this, 0);
  late final _movement = Listenable.merge([_x, _y, _panX, _panY, _strength]);
  late final _motion = Listenable.merge([
    _movement,
    _lift,
    _highlightX,
    _highlightY,
    _highlightSize,
    _highlightAlpha,
  ]);
  RadialFocusGeometry? _geometry;
  bool _positioned = false;
  bool _pointerInput = false;
  bool _pressed = false;

  Offset get _focus => Offset(_x.value, _y.value);
  Offset get _pan => Offset(_panX.value, _panY.value);
  bool get _reduced =>
      eInkInstantRoutes || MediaQuery.disableAnimationsOf(context);
  Rect _rect(RayMenuSlot slot) => _geometry!.rectFor(
    slot,
    focus: _focus,
    pan: _pan,
    strength: _strength.value,
  );

  @override
  void initState() {
    super.initState();
    _movement.addListener(_updateHighlight);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshGeometry();
  }

  void _refreshGeometry() {
    _geometry = RadialFocusGeometry(
      widget.data,
      textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
    );
    if (!_positioned) {
      _x.jumpTo(_geometry!.origin.dx);
      _y.jumpTo(_geometry!.origin.dy);
    }
  }

  @override
  void didUpdateWidget(RadialFocusSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshGeometry();
    final selected = widget.data.selected;
    if (selected != oldWidget.data.selected) {
      if (!_pointerInput && selected != null) {
        final point =
            _geometry!.origin +
            _geometry!.centers[selected]! * _geometry!.overviewScale;
        _targetFocus(point);
      }
      _updateHighlight();
    }
    _pointerInput = false;
  }

  void _target(
    SpringLensValue value,
    double target, {
    bool press = false,
    bool effects = false,
  }) {
    if (value.target == target) return;
    if (_reduced) {
      value.jumpTo(target);
    } else {
      value.springTo(
        target,
        effects
            ? LensMetrics.fade
            : press
            ? LensMetrics.press
            : LensMetrics.hover,
      );
    }
  }

  void _targetFocus(Offset point) {
    if (!_positioned) {
      _positioned = true;
      _x.jumpTo(point.dx);
      _y.jumpTo(point.dy);
    } else {
      _target(_x, point.dx);
      _target(_y, point.dy);
    }
    final pan = _geometry!.panFor(point);
    _target(_panX, pan.dx);
    _target(_panY, pan.dy);
    _target(_strength, 1);
  }

  void observe(Offset point, PointerEvent event) {
    _pointerInput = true;
    if (_geometry == null) return;
    // 点击期间冻结聚焦几何，避免按下到松手之间目标被动画移走。
    if (event is PointerDownEvent) {
      // jumpTo 当前值会停下 ticker；仅不更新目标仍会让已有弹簧继续移动。
      for (final value in [_x, _y, _panX, _panY, _strength]) {
        value.jumpTo(value.value);
      }
      _pressed = true;
      _target(_lift, 1, press: true);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pressed = false;
      _target(_lift, 0, press: true);
    } else if (!_pressed || event is PointerMoveEvent) {
      _targetFocus(point);
    }
  }

  RayMenuSlot? hitTest(Offset point) => _geometry?.hitTest(
    point,
    focus: _focus,
    pan: _pan,
    strength: _strength.value,
  );

  void _updateHighlight() {
    final selected = widget.data.selected;
    if (selected == null || _geometry?.centers.containsKey(selected) != true) {
      _target(_highlightAlpha, 0, effects: true);
      return;
    }
    final rect = _rect(selected);
    if (_highlightSize.value == 0) {
      _highlightX.jumpTo(rect.center.dx);
      _highlightY.jumpTo(rect.center.dy);
      _highlightSize.jumpTo(rect.width);
    } else {
      _target(_highlightX, rect.center.dx);
      _target(_highlightY, rect.center.dy);
      _target(_highlightSize, rect.width);
    }
    _target(_highlightAlpha, 1, effects: true);
  }

  @override
  void dispose() {
    _movement.removeListener(_updateHighlight);
    for (final value in [
      _x,
      _y,
      _panX,
      _panY,
      _strength,
      _lift,
      _highlightX,
      _highlightY,
      _highlightSize,
      _highlightAlpha,
    ]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final scheme = Theme.of(context).colorScheme;
    final geometry = _geometry!;
    final slots = geometry.centers.keys
        .where((slot) => slot.item != null || data.editEmpty)
        .toList();
    // 聚焦项最后绘制，瞬时的弹簧交接也不会把标签盖住。
    if (data.selected != null && slots.remove(data.selected)) {
      slots.add(data.selected!);
    }
    final contents = {
      for (final slot in slots)
        slot: Semantics(
          key: ValueKey(
            slot.item == null
                ? 'ray-empty:${slot.ring}:${slot.index}'
                : 'ray-item:${slot.item!.id}',
          ),
          button: true,
          enabled: slot.selectable || (data.editEmpty && slot.item == null),
          selected: slot == data.selected,
          label: slot.item?.label ?? '+',
          onTap: slot.selectable || (data.editEmpty && slot.item == null)
              ? () {
                  data.onSelected(slot);
                }
              : null,
          child: ExcludeSemantics(
            child: SizedBox.square(
              key: ValueKey('radial-slot:${slot.ring + 1}:${slot.index}'),
              dimension: geometry.buttonSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: slot == data.selected
                      ? Colors.transparent
                      : scheme.surfaceContainerHighest.withValues(
                          alpha: slot.item != null && !slot.selectable ? .5 : 1,
                        ),
                  borderRadius: BorderRadius.circular(
                    geometry.cornerRadius(
                      Rect.fromLTWH(
                        0,
                        0,
                        geometry.buttonSize,
                        geometry.buttonSize,
                      ),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconTheme(
                    data: IconThemeData(
                      color: slot == data.selected
                          ? scheme.onSecondaryContainer
                          : slot.item != null && !slot.selectable
                          ? scheme.onSurfaceVariant.withValues(alpha: .5)
                          : scheme.onSurface,
                      size: 26,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        slot.item?.icon ??
                            GlyphIcon(
                              slot.item == null
                                  ? AppGlyphs.add
                                  : AppGlyphs.touch,
                              size: 24,
                            ),
                        const SizedBox(height: 3),
                        Flexible(
                          child: Text(
                            slot.item?.label ?? '+',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: data.style.textStyle.copyWith(
                              color: slot == data.selected
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    };
    return ClipRect(
      child: ColoredBox(
        color: data.style.scrim,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final rects = {for (final slot in slots) slot: _rect(slot)};
            return Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  height: geometry.footerHeight - 12,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: scheme.surfaceContainerHigh,
                          shape: const StadiumBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Text(
                            data.selected?.item?.label ?? data.centerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: data.style.textStyle.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned.fromRect(
                  rect: Rect.fromCenter(
                    center: Offset(_highlightX.value, _highlightY.value),
                    width: math.max(
                      0,
                      _highlightSize.value *
                          (1 +
                              (_highlightX.velocity.abs() / 1800).clamp(
                                0,
                                .12,
                              ) +
                              _lift.value * LensMetrics.pressGrowth),
                    ),
                    height: math.max(
                      0,
                      _highlightSize.value *
                          (1 + _lift.value * LensMetrics.pressGrowth),
                    ),
                  ),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _highlightAlpha.value.clamp(0, 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(
                            geometry.cornerRadius(
                              Rect.fromLTWH(
                                0,
                                0,
                                _highlightSize.value,
                                _highlightSize.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final slot in slots)
                  Positioned(
                    left: rects[slot]!.center.dx - geometry.buttonSize / 2,
                    top: rects[slot]!.center.dy - geometry.buttonSize / 2,
                    width: geometry.buttonSize,
                    height: geometry.buttonSize,
                    child: Transform.scale(
                      scale: rects[slot]!.width / geometry.buttonSize,
                      child: contents[slot],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
