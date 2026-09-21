import 'package:material_ui/material_ui.dart';

/// 文件管理器的五向导航掌（对齐 NeoView 的 `FolderNavigationPad`）。
///
/// 形状是一个 32×32 的圆角方块，内部按五个**多边形热区**切分：
/// 左＝后退、右＝前进、上＝上一级、下＝主页、中心圆＝刷新。
/// 热区和可见装饰是两套东西 —— 角落的箭头 / 底部的横杠 / 中心的圆点
/// 只是「这里可以点」的提示，真正吃事件的是被 `ClipPath` 裁过的透明按钮。
///
/// 为什么用多边形而不是五个方块按钮：
/// 1. 五个方块按钮在窄卡片上要占 5 个 32px 的宽度，掌形只占 1 个；
/// 2. 中心键被四边包住，手指落点自然收敛到中心，不容易误触。
///
/// 主页键（下区）在 NeoToolbar 里是「单击回主页、右键设为主页」，
/// 这里把右键 / 长按都交给 [onHomeMenu]（弹出「回到主页 / 设为主页 / 清除主页」），
/// 因为触摸端没有右键，而主页的三个动作又都需要入口。
class FileManagerNavigationPad extends StatelessWidget {
  const FileManagerNavigationPad({
    super.key,
    required this.busy,
    required this.loading,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    required this.homeKey,
    required this.homeEnabled,
    required this.atHome,
    required this.hasHome,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.onNavigateUp,
    required this.onGoHome,
    required this.onHomeMenu,
    required this.onRefresh,
  });

  /// 有请求在飞：整掌禁用，避免叠动作。
  final bool busy;

  /// 仅用于中心圆点的呼吸动画（加载中），不影响可用性。
  final bool loading;

  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;

  /// 挂在主页热区上的 key：菜单要按这个热区的位置弹出来。
  final Key homeKey;

  /// 「设置 → 文件管理器 → 启用主页键」。关掉时下区整块消失，
  /// 掌形只剩四个方向 —— 其余导航键不受影响。
  final bool homeEnabled;

  /// 当前就站在主页上（主页热区高亮，且不再提供「回主页」）。
  final bool atHome;

  /// 设过主页 —— 没设过时主页热区点下去是「把当前目录设为主页」。
  final bool hasHome;

  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final VoidCallback onNavigateUp;
  final VoidCallback onGoHome;
  final VoidCallback onHomeMenu;
  final VoidCallback onRefresh;

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final idle = scheme.onSurfaceVariant;

    return SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Stack(
          children: [
            _region(
              context: context,
              key: null,
              points: _leftPoints,
              enabled: canGoBack && !busy,
              tooltip: '后退',
              onTap: onNavigateBack,
            ),
            _region(
              context: context,
              key: null,
              points: _rightPoints,
              enabled: canGoForward && !busy,
              tooltip: '前进',
              onTap: onNavigateForward,
            ),
            _region(
              context: context,
              key: null,
              points: _upPoints,
              enabled: canGoUp && !busy,
              tooltip: '上一级',
              onTap: onNavigateUp,
            ),
            if (homeEnabled)
              _region(
                context: context,
                key: homeKey,
                points: _downPoints,
                enabled: !busy,
                tooltip: hasHome
                    ? (atHome ? '主页（当前）· 右键/长按管理' : '主页 · 右键/长按管理')
                    : '主页：还没设置 · 单击把当前目录设为主页',
                active: atHome,
                onTap: onGoHome,
                onMenu: onHomeMenu,
              ),
            // 中心圆：刷新。压在四片热区之上，且自己带圆角，
            // 所以四片热区在它下面拿不到这一块的事件。
            Center(
              child: Tooltip(
                message: '刷新',
                child: Material(
                  color: scheme.surface,
                  shape: CircleBorder(
                    side: BorderSide(width: 0.5, color: scheme.outlineVariant),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : onRefresh,
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child: Icon(Icons.refresh_rounded, size: 9),
                    ),
                  ),
                ),
              ),
            ),
            // 纯装饰层：不参加命中测试。
            IgnorePointer(
              child: Stack(
                children: [
                  _hint(
                    alignment: Alignment.centerLeft,
                    inset: 2,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 8,
                      color: canGoBack && !busy
                          ? idle
                          : idle.withValues(alpha: 0.25),
                    ),
                  ),
                  _hint(
                    alignment: Alignment.centerRight,
                    inset: 2,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 8,
                      color: canGoForward && !busy
                          ? idle
                          : idle.withValues(alpha: 0.25),
                    ),
                  ),
                  _hint(
                    alignment: Alignment.topCenter,
                    inset: 2,
                    child: Icon(
                      Icons.expand_less_rounded,
                      size: 8,
                      color: canGoUp && !busy
                          ? idle
                          : idle.withValues(alpha: 0.25),
                    ),
                  ),
                  // 底部横杠 = 主页。已站在主页上时用反色，表示「你就是这一档」。
                  if (homeEnabled)
                    _hint(
                      alignment: Alignment.bottomCenter,
                      inset: 4,
                      child: Container(
                        width: 8,
                        height: 2,
                        decoration: BoxDecoration(
                          color: atHome
                              ? scheme.onPrimary
                              : idle.withValues(alpha: busy ? 0.25 : 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一片多边形热区：被裁过的透明按钮。
  ///
  /// `ClipPath` 同时裁剪绘制**和命中测试**，所以压在三角形外面的点击
  /// 不会落到它身上 —— 这正是「五个方向互不抢事件」的根据。
  Widget _region({
    required BuildContext context,
    required Key? key,
    required List<Offset> points,
    required bool enabled,
    required String tooltip,
    bool active = false,
    required VoidCallback onTap,
    VoidCallback? onMenu,
  }) {
    return Positioned.fill(
      child: ClipPath(
        clipper: _PolygonClipper(points),
        child: Material(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              key: key,
              onTap: enabled ? onTap : null,
              onLongPress: enabled && onMenu != null ? onMenu : null,
              onSecondaryTap: enabled && onMenu != null ? onMenu : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint({
    required Alignment alignment,
    required double inset,
    required Widget child,
  }) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              alignment == Alignment.centerLeft ||
                  alignment == Alignment.centerRight
              ? inset
              : 0,
          vertical:
              alignment == Alignment.topCenter ||
                  alignment == Alignment.bottomCenter
              ? inset
              : 0,
        ),
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}

/// NeoView 的五个 `clip-path: polygon(...)`，归一化到 0..1。
const List<Offset> _leftPoints = [
  Offset(0, 0),
  Offset(0.4, 0.3),
  Offset(0.4, 0.7),
  Offset(0, 1),
];
const List<Offset> _rightPoints = [
  Offset(1, 0),
  Offset(0.6, 0.3),
  Offset(0.6, 0.7),
  Offset(1, 1),
];
const List<Offset> _upPoints = [
  Offset(0, 0),
  Offset(1, 0),
  Offset(0.7, 0.4),
  Offset(0.3, 0.4),
];
const List<Offset> _downPoints = [
  Offset(0.3, 0.6),
  Offset(0.7, 0.6),
  Offset(1, 1),
  Offset(0, 1),
];

class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.points);

  final List<Offset> points;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_PolygonClipper oldClipper) =>
      !_samePoints(oldClipper.points, points);

  bool _samePoints(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
