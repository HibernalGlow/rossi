part of 'spring_lens_bar.dart';

class _Slot extends StatefulWidget {
  const _Slot({
    required this.index,
    required this.tab,
    required this.axis,
    required this.extent,
    required this.crossAxisAlignment,
    required this.lens,
    required this.hoverAt,
    required this.lift,
    required this.selected,
    required this.semanticContainer,
    required this.onTap,
    this.tintColor,
    required this.slots,
    required this.corner,
  });

  final LensSlots slots;
  final double? corner;

  /// 本格在宿主列表里的下标。染色判据读它。
  final int index;

  final SpringLensTab tab;
  final Axis axis;
  final double extent;
  final CrossAxisAlignment crossAxisAlignment;
  final SpringLensValue lens;
  final ValueListenable<double?> hoverAt;
  final SpringLensValue lift;
  final bool selected;
  final bool semanticContainer;
  final VoidCallback onTap;

  /// 选中时是否把这一格的**内容整个**染成这个色。`null` = 不动内容色（默认）。
  ///
  /// 慎用：染色走的是 `BlendMode.srcIn`，那是**替换**而不是叠加 ——
  /// 内容原本的颜色（字色、图标色）会被盖掉。2026-10-11 之前这里写死
  /// `colorScheme.primary`，于是书架那排 tab 选中的字被染成了粉色，
  /// 而改造前它是普通的 `textColor`（用户截图报出来的就是这一处）。
  final Color? tintColor;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> with SingleTickerProviderStateMixin {
  late final SpringLensValue _parallax = SpringLensValue(this, 0);

  @override
  void initState() {
    super.initState();
    widget.hoverAt.addListener(_followPointer);
  }

  @override
  void didUpdateWidget(covariant _Slot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverAt != widget.hoverAt) {
      oldWidget.hoverAt.removeListener(_followPointer);
      widget.hoverAt.addListener(_followPointer);
    }
    _followPointer();
  }

  @override
  void dispose() {
    widget.hoverAt.removeListener(_followPointer);
    _parallax.dispose();
    super.dispose();
  }

  void _followPointer() {
    final hoverAt = widget.hoverAt.value;
    // 内容视差：指针在这一格附近时，底下内容追过去一点点（比lens 追得少）。
    final offset = hoverAt == null ? 0.0 : hoverAt - widget.index;
    final target = offset.abs() > 0.5
        ? 0.0
        : offset * LensMetrics.hoverParallax;
    if (target != _parallax.target) {
      _parallax.springTo(target, LensMetrics.hover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final content = _MotionTransform(
      lens: widget.lens,
      lift: widget.lift,
      parallax: _parallax,
      color: widget.tintColor,
      horizontal: horizontal,
      index: widget.index,
      slots: widget.slots,
      corner: widget.corner,
      child: widget.tab.child,
    );

    Widget slot = horizontal
        ? SizedBox(width: widget.extent, child: content)
        : SizedBox(height: widget.extent, child: content);

    // 点击走**这一格自己的**识别器，而不是外层那个 `Listener`：外层要同时
    // 接拖动跟手与悬停。两者的分工靠「谁在命中路径上」：
    //
    // - 外层那个 `Listener` 在 Stack **最上**（`translucent`）——它必须收得到
    //   `onPointerMove`，否则拖动跟手整个失效；
    // - `translucent` 仍会**终止**命中，所以这一格不能是 `opaque`
    //   （`opaque` 自己也会终止），否则底下的点击到不了它。
    //
    // `translucent` 在这里已经够了：这一格的内容（Text/Icon）本身会命中，
    // `Listener` 仍然收得到指针。
    slot = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      child: slot,
    );

    // 有 tooltip 才包：给一个空 message 的 Tooltip 会挡住鼠标。
    if (widget.tab.tooltip != null) {
      slot = Tooltip(message: widget.tab.tooltip!, child: slot);
    }
    if (widget.semanticContainer) {
      slot = Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.tab.semanticLabel,
        excludeSemantics: widget.tab.semanticLabel != null,
        onTap: widget.onTap,
        child: slot,
      );
    }
    return slot;
  }
}

/// 内容在 lens 底下时染上选中色、并且按下时放大一点。
///
/// 与 `navigation_dock.dart` 里那个 `_LensTint` 同一套做法（clip 出 lens 的形状、
/// lens 内外的色分开画），只是这里把「lens 落在第几格」换成了弹簧的连续位置。
class _MotionTransform extends SingleChildRenderObjectWidget {
  const _MotionTransform({
    required this.lens,
    required this.lift,
    required this.parallax,
    required this.color,
    required this.horizontal,
    required this.index,
    required this.slots,
    required this.corner,
    super.child,
  });

  final LensSlots slots;
  final double? corner;
  final SpringLensValue lens;
  final ValueListenable<double> lift;
  final ValueListenable<double> parallax;

  /// `null` = 不染色（内容保持自己的颜色）。
  final Color? color;

  final bool horizontal;

  /// 宿主里的下标：染色前用它判「lens 现在压不压着我」。
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMotionTransform(
      lens: lens,
      lift: lift,
      parallax: parallax,
      color: color,
      horizontal: horizontal,
      index: index,
      slots: slots,
      corner: corner,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMotionTransform renderObject,
  ) {
    renderObject
      ..lens = lens
      ..lift = lift
      ..parallax = parallax
      ..color = color
      ..horizontal = horizontal
      ..index = index
      ..slots = slots
      ..corner = corner;
  }
}

class _RenderMotionTransform extends RenderProxyBox {
  _RenderMotionTransform({
    required this._lens,
    required this._lift,
    required this._parallax,
    required this._color,
    required this._horizontal,
    required this._index,
    required this._slots,
    required this._corner,
  });

  // 每格保留自己的绘制层；透镜经过别处时不连带重画整条页签。
  @override
  bool get isRepaintBoundary => true;

  // 比较可见变化而不是全局弹簧位置，未被透镜覆盖的静止图标无需重画。
  ({double scale, double shift, Rect? tint})? _paintedVisual;

  ({double scale, double shift, Rect? tint}) get _visual {
    final emphasis = (1 - (_lens.value - _index).abs()).clamp(0.0, 1.0);
    final scale = 1 + LensMetrics.magnify * emphasis * _lift.value;
    final shift = _parallax.value * size.longestSide;
    Rect? tint;
    if (_color != null && !size.isEmpty) {
      final geometry = _slots.resolvedTo(size);
      if (geometry != null && !geometry.isEmpty) {
        final rect =
            lensRect(
              slots: geometry,
              position: _lens.value,
              velocity: _lens.velocity,
              lift: _lift.value,
            ).translate(
              _horizontal ? -geometry.startOf(_index) : 0,
              _horizontal ? 0 : -geometry.startOf(_index),
            );
        final bounds = Offset.zero & size;
        final motion = _transform;
        final content = motion == null
            ? bounds
            : MatrixUtils.transformRect(motion, bounds);
        if (rect.overlaps(content)) tint = rect;
      }
    }
    return (scale: scale, shift: shift, tint: tint);
  }

  void _onMotionChanged() {
    if (!hasSize || _paintedVisual != _visual) markNeedsPaint();
  }

  final LayerHandle<ColorFilterLayer> _tint = LayerHandle<ColorFilterLayer>();
  final LayerHandle<TransformLayer> _motion = LayerHandle<TransformLayer>();
  final LayerHandle<TransformLayer> _insideMotion =
      LayerHandle<TransformLayer>();
  final LayerHandle<ClipPathLayer> _outside = LayerHandle<ClipPathLayer>();
  final LayerHandle<ClipPathLayer> _inside = LayerHandle<ClipPathLayer>();

  LensSlots _slots;
  set slots(LensSlots value) {
    if (identical(value, _slots)) return;
    _slots = value;
    markNeedsPaint();
  }

  double? _corner;
  set corner(double? value) {
    if (value == _corner) return;
    _corner = value;
    markNeedsPaint();
  }

  SpringLensValue _lens;
  set lens(SpringLensValue value) {
    if (value == _lens) return;
    if (attached) {
      _lens.removeListener(_onMotionChanged);
      value.addListener(_onMotionChanged);
    }
    _lens = value;
    markNeedsPaint();
  }

  ValueListenable<double> _lift;
  set lift(ValueListenable<double> value) {
    if (value == _lift) return;
    if (attached) {
      _lift.removeListener(_onMotionChanged);
      value.addListener(_onMotionChanged);
    }
    _lift = value;
    markNeedsPaint();
  }

  ValueListenable<double> _parallax;
  set parallax(ValueListenable<double> value) {
    if (value == _parallax) return;
    if (attached) {
      _parallax.removeListener(_onMotionChanged);
      value.addListener(_onMotionChanged);
    }
    _parallax = value;
    markNeedsPaint();
  }

  Color? _color;
  set color(Color? value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  bool _horizontal;
  set horizontal(bool value) {
    if (value == _horizontal) return;
    _horizontal = value;
    markNeedsPaint();
  }

  /// 宿主里的下标 —— 染色前用它判「lens 现在压不压着我」。
  int _index;
  set index(int value) {
    if (value == _index) return;
    _index = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _lens.addListener(_onMotionChanged);
    _lift.addListener(_onMotionChanged);
    _parallax.addListener(_onMotionChanged);
    _onMotionChanged();
  }

  @override
  void detach() {
    _lens.removeListener(_onMotionChanged);
    _lift.removeListener(_onMotionChanged);
    _parallax.removeListener(_onMotionChanged);
    super.detach();
  }

  @override
  void dispose() {
    _tint.layer = null;
    _motion.layer = null;
    _insideMotion.layer = null;
    _outside.layer = null;
    _inside.layer = null;
    super.dispose();
  }

  /// 放大 + 视差平移，叠在一起是一个 Matrix4。静止时返回 null（不建层）。
  Matrix4? get _transform {
    final emphasis = (1 - (_lens.value - _index).abs()).clamp(0.0, 1.0);
    final scale = 1 + LensMetrics.magnify * emphasis * _lift.value;
    final shift = _parallax.value * size.longestSide;
    if (scale == 1 && shift == 0) return null;
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx * (1 - scale) + (_horizontal ? shift : 0),
      center.dy * (1 - scale) + (_horizontal ? 0 : shift),
      0,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final motion = _transform;
    if (motion != null) transform.multiply(motion);
  }

  void _paintMoved(
    PaintingContext context,
    Offset offset,
    Matrix4? motion,
    LayerHandle<TransformLayer> handle,
  ) {
    if (motion == null) {
      handle.layer = null;
      super.paint(context, offset);
      return;
    }
    handle.layer = context.pushTransform(
      needsCompositing,
      offset,
      motion,
      super.paint,
      oldLayer: handle.layer,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _paintedVisual = _visual;
    final motion = _transform;
    final tint = _color;
    final bounds = Offset.zero & size;
    final content = motion == null
        ? bounds
        : MatrixUtils.transformRect(motion, bounds);
    final geometry = _slots.resolvedTo(size)!;
    final lensBounds =
        lensRect(
          slots: geometry,
          position: _lens.value,
          velocity: _lens.velocity,
          lift: _lift.value,
        ).translate(
          _horizontal ? -geometry.startOf(_index) : 0,
          _horizontal ? 0 : -geometry.startOf(_index),
        );
    if (tint == null || !lensBounds.overlaps(content)) {
      _outside.layer = null;
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
      _paintMoved(context, offset, motion, _motion);
      return;
    }
    // 与 Dock 相同：透镜内外分别绘制，避免整格跳色或叠画重影。
    final lens = _lensPath(lensBounds, _corner);
    final reach = content.expandToInclude(bounds).inflate(16);
    _outside.layer = context.pushClipPath(
      needsCompositing,
      offset,
      reach,
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(reach)
        ..addPath(lens, Offset.zero),
      (context, offset) => _paintMoved(context, offset, motion, _motion),
      oldLayer: _outside.layer,
    );
    _inside.layer = context.pushClipPath(
      needsCompositing,
      offset,
      lensBounds,
      lens,
      (context, offset) {
        final filter = ColorFilter.mode(tint, BlendMode.srcIn);
        if (needsCompositing) {
          _tint.layer = context.pushColorFilter(
            offset,
            filter,
            (context, offset) =>
                _paintMoved(context, offset, motion, _insideMotion),
            oldLayer: _tint.layer,
          );
        } else {
          _tint.layer = null;
          context.canvas.saveLayer(
            lensBounds.shift(offset),
            Paint()..colorFilter = filter,
          );
          _paintMoved(context, offset, motion, _insideMotion);
          context.canvas.restore();
        }
      },
      oldLayer: _inside.layer,
    );
  }
}
