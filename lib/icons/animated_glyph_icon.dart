// 本仓新增（2026-10-10）。FlClash 的 `AnimatedGlyph` 只包一层 `GlyphIcon`，
// 颜色与尺寸都只能从 `IconTheme` 里来；详情页的操作磁贴之类「图标色是角色色、
// 不走 IconButton」的场合够不着。这一份把 [GlyphIcon] 的 `size` / `color` 透传
// 出去，fill 动画的口径与 `AnimatedGlyph` 完全一致（350ms + 弹跳）。
import 'dart:math' as math;

import 'package:zephyr/icons/glyph.dart';
import 'package:zephyr/icons/glyph_icon.dart';
import 'package:material_ui/material_ui.dart';

const _fillDuration = Duration(milliseconds: 350);
const _popScale = 0.1;

class AnimatedGlyphIcon extends StatefulWidget {
  const AnimatedGlyphIcon(
    this.glyph, {
    super.key,
    required this.filled,
    this.size,
    this.color,
  });

  final Glyph glyph;
  final bool filled;
  final double? size;
  final Color? color;

  @override
  State<AnimatedGlyphIcon> createState() => _AnimatedGlyphIconState();
}

class _AnimatedGlyphIconState extends State<AnimatedGlyphIcon>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _fillDuration,
    value: widget.filled ? 1 : 0,
  );
  late final CurvedAnimation _fill = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: _fillDuration,
  );
  late final Listenable _animation = Listenable.merge([_fill, _pop]);

  @override
  void didUpdateWidget(covariant AnimatedGlyphIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filled == widget.filled) {
      return;
    }
    if (widget.filled) {
      _controller.forward();
      if (!_pop.isAnimating) {
        _pop.forward(from: 0);
      }
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _controller.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final pop = _pop.isAnimating
            ? math.sin(math.pi * _pop.value) * _popScale
            : 0.0;
        return Transform.scale(
          scale: 1 + pop,
          child: GlyphIcon(
            widget.glyph,
            fill: _fill.value,
            size: widget.size,
            color: widget.color,
          ),
        );
      },
    );
  }
}
