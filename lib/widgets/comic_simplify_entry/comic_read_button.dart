import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_info/models/read_entry_placement.dart';

/// 封面正中间的「直接阅读」按钮：点它就不进详情页，直接起读。
///
/// 语义与详情页的「开始阅读」一致（调用方给的动作通常是
/// `startComicQuickRead`）：有阅读记录就续读，没有就从第一章开始。
///
/// 显示方式按平台分岔：
/// - **触屏**没有悬停可依赖，常显；
/// - **桌面**悬停在卡片上才浮出，否则整屏封面都扣一个圆圈。
///
/// 外层是 [MouseRegion] + [HitTestBehavior.translucent]：它要铺满封面才收得到
/// 「悬停在卡片上」这件事，但半透明命中让卡片的点击 / 长按照样落到下层手势上。
/// 隐藏的按钮再用 [IgnorePointer] 兜住，免得太透明却仍然吃点击。
///
/// 因此调用方一律用 `Positioned.fill` 把它压在封面 Stack 的最上层（标题渐变之上）。
/// 「该不该画」由调用方的显示策略决定（卡片族走 `ComicCardBadgePolicy`）；
/// 本组件只按 [size] 的口径决定画多大、以及格子太小时干脆不画。
class ComicReadButton extends StatefulWidget {
  const ComicReadButton({super.key, required this.onTap, this.size});

  /// 起读动作。返回的 Future 结束前按钮保持转圈，所以远程漫画回源那一次
  /// （`startComicQuickRead` 的第 3 条路）看得见进度，也不会被连点重复触发。
  final Future<void> Function() onTap;

  /// 圆圈直径。null 表示按所在盒子的短边自己算 —— 库视图的格子多大只有布局时才知道。
  final double? size;

  @override
  State<ComicReadButton> createState() => _ComicReadButtonState();
}

class _ComicReadButtonState extends State<ComicReadButton> {
  bool _hovered = false;

  /// 远程漫画要先回源问一次插件详情，转圈表示「正在起读」，同时挡住连点。
  bool _busy = false;

  /// 桌面端悬停才浮出；触屏端常显。忙的时候一律显形，否则进度圈看不见。
  bool get _revealed => shouldRevealComicReadButton(
    hasPointer: comicInfoPlatformHasPointer(defaultTargetPlatform),
    hovered: _hovered,
    busy: _busy,
  );

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final diameter = widget.size ??
            comicReadButtonSize(side.isFinite ? side : _unknownBoxSide);
        // 自动定径时，盒子短边不够就把整颗按钮让出去：44 的封面槽上摆一个
        // 26 的圆圈等于盖住半张封面，那种档位的卡片本身就该整行可点。
        if (widget.size == null && (!side.isFinite || side < _minBoxSide)) {
          return const SizedBox.shrink();
        }
        return _buildReveal(context, diameter);
      },
    );
  }

  Widget _buildReveal(BuildContext context, double diameter) {
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) {
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: IgnorePointer(
        ignoring: !_revealed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _revealed ? 1 : 0,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            // 只靠透明度浮出会显得「闪了一下」，配一点缩放像按钮弹出来。
            scale: _revealed ? 1 : 0.82,
            child: Center(child: _buildCircle(context, diameter)),
          ),
        ),
      ),
    );
  }

  Widget _buildCircle(BuildContext context, double diameter) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(diameter),
        onTap: _onTap,
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            color: colorScheme.scrim.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.onInverseSurface.withValues(alpha: 0.85),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.scrim.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _busy
              ? Padding(
                  padding: EdgeInsets.all(diameter * 0.26),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.onInverseSurface,
                    ),
                  ),
                )
              : Icon(
                  Icons.play_arrow_rounded,
                  size: diameter * 0.62,
                  color: colorScheme.onInverseSurface,
                ),
        ),
      ),
    );
  }

  /// 自动定径的最小盒子短边。
  static const double _minBoxSide = 56;

  /// 盒子无界时的兜底直径口径（与库视图的格子兜底同一数量级）。
  static const double _unknownBoxSide = 120;
}

/// 封面按钮此刻该不该显形。
///
/// 判据是「有没有指针」（与详情页阅读入口同一口径）而不是「是不是桌面」：
/// 有指针才悬停得到，触屏没有 hover 这一说，只能常显。
/// [busy] 优先于一切 —— 远程漫画回源那一次要看得见进度，
/// 何况进度圈一旦出现就说明按钮已经被点过，收起它等于把反馈吞掉。
bool shouldRevealComicReadButton({
  required bool hasPointer,
  required bool hovered,
  required bool busy,
}) => busy || !hasPointer || hovered;

/// 封面按钮的尺寸口径：约占封面短边的三分之一，夹在 26~44。
///
/// 各处共用它，免得网格卡与横滑卡各挑一个数、同一屏里两个大小。
double comicReadButtonSize(double coverShortSide) =>
    math.min(44.0, math.max(26.0, coverShortSide * 0.32));
