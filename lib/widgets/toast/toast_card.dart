// 提示条（toast）的卡片本体：图标 + 标题 + 正文 + 关闭按钮 + 倒计时进度条。
//
// 卡片只负责「长什么样 / 什么时候自动关」，位置、堆叠、进出场由
// `toast_overlay.dart` 的宿主统一处理。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/theme/status_accent.dart';
import 'package:zephyr/util/toast/toast_style.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// 提示条类型。
///
/// 对外仍然从 `package:zephyr/widgets/toast.dart` 导出，历史调用点不受影响。
enum ToastType { info, success, warning, error }

/// 成功 / 警告没有 M3 角色，走 `statusAccent` 那套「固定色相、按亮度取色调」。
Color _toastAccentColor(BuildContext context, ToastType type) {
  final scheme = Theme.of(context).colorScheme;
  switch (type) {
    case ToastType.info:
      return scheme.primary;
    case ToastType.success:
      return statusAccent(context, StatusHue.success);
    case ToastType.warning:
      return statusAccent(context, StatusHue.warning);
    case ToastType.error:
      return scheme.error;
  }
}

IconData _toastIcon(ToastType type) {
  switch (type) {
    case ToastType.info:
      return Icons.info_outline;
    case ToastType.success:
      return Icons.check_circle_outline;
    case ToastType.warning:
      return Icons.warning_amber_outlined;
    case ToastType.error:
      return Icons.error_outline;
  }
}

class ToastCard extends StatefulWidget {
  const ToastCard({
    super.key,
    required this.type,
    required this.message,
    required this.spec,
    required this.onDismiss,
    this.title,
  });

  final ToastType type;
  final String message;
  final ToastOverlaySpec spec;
  final VoidCallback onDismiss;
  final String? title;

  @override
  State<ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<ToastCard>
    with SingleTickerProviderStateMixin {
  /// 倒计时同时驱动「自动关闭」与进度条 —— 两者天然同步，
  /// 不会出现「进度条还在走、提示已经被关掉」这种错位。
  /// 常驻提示（`duration == 0`）没有这个控制器。
  AnimationController? _countdown;

  @override
  void initState() {
    super.initState();
    final duration = widget.spec.duration;
    if (duration > Duration.zero) {
      _countdown = AnimationController(vsync: this, duration: duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onDismiss();
          }
        })
        ..forward();
    }
  }

  @override
  void dispose() {
    _countdown?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final scheme = Theme.of(context).colorScheme;
    final accent = _toastAccentColor(context, widget.type);
    final radius = BorderRadius.circular(14);

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spec.showIcon) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(_toastIcon(widget.type), size: 19, color: accent),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title != null && widget.title!.isNotEmpty) ...[
                      Text(
                        widget.title!,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    // 长消息在这里自然换行，不再截断、也不再退化成对话框。
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (spec.showClose) ...[
                const SizedBox(width: 6),
                _ToastCloseButton(onPressed: widget.onDismiss),
              ],
            ],
          ),
        ),
        if (spec.showsCountdown && _countdown != null)
          AnimatedBuilder(
            animation: _countdown!,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 1 - _countdown!.value,
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(color: accent.withValues(alpha: 0.55)),
                ),
              ),
            ),
          ),
      ],
    );

    // 宽度与最小高度约束对两种材质一视同仁，套在卡片本体外面。
    content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 48, maxWidth: spec.maxWidth),
      child: content,
    );

    if (spec.liquidGlass) {
      // 玻璃走全仓统一的液态玻璃材质（提示条属于「浮层卡片」档）。
      // 不透明度缩进材质里 —— 别用 `Opacity` 包 BackdropFilter，
      // 那会把已经模糊好的背景再罩一层雾，还会多一次 saveLayer。
      content = LiquidGlassSurface(
        thickness: LiquidGlassThickness.regular,
        borderRadius: radius,
        opacity: spec.opacity,
        child: content,
      );
    } else {
      content = Opacity(
        opacity: spec.opacity,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: radius,
            // MD3 的 elevated 面靠容器色 + 投影分层，不再叠一圈描边
            //（玻璃那条分支由 LiquidGlassSurface 自己给边缘）。
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: content,
        ),
      );
    }

    // 悬停时先暂停倒计时，让用户来得及读完；移开再接着走。
    if (_countdown != null) {
      content = MouseRegion(
        onEnter: (_) => _countdown?.stop(),
        onExit: (_) => _countdown?.forward(),
        child: content,
      );
    }

    // 不透明度已在两种材质分支内各自处理（玻璃缩进材质、实色套 Opacity），
    // 这里不能再包一层，否则玻璃会变成双层衰减。
    return content;
  }
}

class _ToastCloseButton extends StatelessWidget {
  const _ToastCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 提示条挂在 Overlay 上，头顶**没有** Material 祖先，
    // 所以这里用 GestureDetector 而不是 InkResponse（后者会断言失败）。
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close,
            size: 15,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
