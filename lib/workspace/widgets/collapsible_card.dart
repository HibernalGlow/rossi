import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/theme_shape.dart';

/// 通用可折叠卡片组件外壳（支持泳道与边栏中 100% 复用）
///
/// 轨道上关于「位置」的三个动作 —— 上移 / 下移 / 收起 —— 都由宿主
/// （面板 / 抽屉）通过 [onMoveUp] / [onMoveDown] / [onHide] 传进来。
/// 卡片自己不需要知道自己在第几位，也不需要知道有没有下家。
class CollapsibleCard extends StatelessWidget {
  final String cardId;
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? contentPadding;

  /// 在所属面板里上移 / 下移。`null` = 已经在头/尾（菜单项置灰）。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// 把这张卡从当前面板收起来（可从面板标题行的「已收起」入口恢复）。
  final VoidCallback? onHide;

  const CollapsibleCard({
    super.key,
    required this.cardId,
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    this.trailing,
    required this.child,
    this.margin,
    this.contentPadding,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // MD3 的 filled 卡片靠**容器色**分层，不描边、不投影；圆角跟主题的形状档走。
    final radius = themeRadius(context, fallback: 12);

    // 卡片可直接挂在泳道/抽屉里，由自身提供与应用同库的 Material。
    // 用 Material 绘制背景并裁剪，保证标题栏和内容的墨水反馈也在圆角内。
    return Padding(
      padding:
          margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trailing != null) ...[
                      trailing!,
                      const SizedBox(width: 8),
                    ],
                    if (onMoveUp != null ||
                        onMoveDown != null ||
                        onHide != null)
                      _buildTrackMenu(context),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding:
                    contentPadding ??
                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: child,
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              firstCurve: Curves.easeOutQuad,
              secondCurve: Curves.easeOutQuad,
              sizeCurve: Curves.easeInOutCubic,
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片在轨道上的位置菜单（上移 / 下移 / 收起）。
  ///
  /// 放在卡片的**标题栏里**而不是卡内：这几个动作改的是「卡片在面板里的位置」，
  /// 与卡片内容无关；收进一个菜单也让标题栏在窄泳道里不至于被按钮挤爆。
  Widget _buildTrackMenu(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: '卡片位置',
      onSelected: (value) {
        switch (value) {
          case 'up':
            onMoveUp?.call();
          case 'down':
            onMoveDown?.call();
          case 'hide':
            onHide?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'up',
          enabled: onMoveUp != null,
          child: const _TrackMenuItem(
            icon: Icons.arrow_upward_rounded,
            label: '上移',
          ),
        ),
        PopupMenuItem<String>(
          value: 'down',
          enabled: onMoveDown != null,
          child: const _TrackMenuItem(
            icon: Icons.arrow_downward_rounded,
            label: '下移',
          ),
        ),
        if (onHide != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'hide',
            child: _TrackMenuItem(
              icon: Icons.visibility_off_outlined,
              label: '从该面板收起',
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
      // 走 PopupMenuButton 的 IconButton 形态：自带 32px 命中区与墨水反馈，
      // 而不是一个裸 Icon 贴在标题栏里（自定义 child 会丢掉这些）。
      icon: const Icon(Icons.more_vert_rounded),
      iconSize: 18,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        minimumSize: const Size(32, 32),
      ),
    );
  }
}

class _TrackMenuItem extends StatelessWidget {
  const _TrackMenuItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          // MD3 菜单项正文是 labelLarge（14），不是压小的 12。
          style: theme.textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}
