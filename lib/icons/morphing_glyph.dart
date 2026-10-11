// 本仓新增（2026-10-11）：把「进度 → glyph」这条**已经在词表里**的口径接到状态开关上。
//
// `AppGlyphs.playPause(t)`（顶点插值 + 绕心旋转）与 `AppGlyphs.sidebar(t)`（分隔线
// 随拖动移动）早就是按进度连续变化的形状，但动作面一直在硬切：
// `playing ? pause : play`、`expanded ? chevronDown : chevronForward`。
// `AnimatedGlyph` 只能插值 `fill` 这一个轴，插不了「两颗不同的 glyph」之间的那一步，
// 所以补这一个驱动件：同一个 controller，两种过渡。
//
//   * [builder]：真正的形状插值，两端由调用方的函数连续变化（playPause 那一类）。
//   * [turns]：同一颗 glyph 绕中心转过 `turns` 圈 —— `chevronDown` 与
//     `chevronForward` 本来就只差 90°，不必再画第二颗，也不该画（词表铁律：
//     同一语义只许一颗图标）。
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/glyph.dart';
import 'package:zephyr/icons/glyph_icon.dart';

const _morphDuration = Duration(milliseconds: 350);

class MorphingGlyph extends StatefulWidget {
  const MorphingGlyph({
    super.key,
    required this.on,
    this.builder,
    this.glyph,
    this.turns = 0.0,
    this.size,
    this.color,
  }) : assert(
         builder != null || glyph != null,
         'builder 与 glyph 至少给一个：前者插值两端的形状，后者配 turns 做旋转',
       );

  /// 状态。`false → 0`，`true → 1`，变化时用 [duration] 走过去。
  final bool on;

  /// 按进度产出形状（0 与 1 就是两端的静态图标）。
  final Glyph Function(double progress)? builder;

  /// 固定形状，配 [turns] 做旋转过渡；与 [builder] 二选一或同时给（则优先 builder）。
  final Glyph? glyph;

  /// 转到 `turns` 圈（0.25 = 90°）。0 表示不转。
  final double turns;

  final double? size;
  final Color? color;

  static const duration = _morphDuration;

  @override
  State<MorphingGlyph> createState() => _MorphingGlyphState();
}

class _MorphingGlyphState extends State<MorphingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MorphingGlyph.duration,
    value: widget.on ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didUpdateWidget(covariant MorphingGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.on == widget.on) {
      return;
    }
    if (widget.on) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 必须挂 AnimatedBuilder：直接读 `_progress.value` 的话 controller 在走
    // 但这一层不重建，图标会钉在起点（测试抓到过）。
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final progress = _progress.value;
        final rendered = widget.builder?.call(progress) ?? widget.glyph!;
        final icon = GlyphIcon(
          rendered,
          size: widget.size,
          color: widget.color,
        );
        if (widget.turns == 0.0) {
          return icon;
        }
        // `GlyphIcon` 在 rtl 下把整颗水平翻过来；镜像之后同一段旋转在屏幕上是反的，
        // 所以角度要跟着符号走，否则 rtl 下「展开」会往回转。
        final mirrored =
            rendered.matchTextDirection &&
            Directionality.of(context) == TextDirection.rtl;
        final sign = mirrored ? -1.0 : 1.0;
        return Transform.rotate(
          angle: sign * widget.turns * progress * 2 * math.pi,
          child: icon,
        );
      },
    );
  }
}
