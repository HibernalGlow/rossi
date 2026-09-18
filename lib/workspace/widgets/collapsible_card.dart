import 'package:material_ui/material_ui.dart';

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
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: 6),
                  ],
                  if (onMoveUp != null || onMoveDown != null || onHide != null)
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
              padding: contentPadding ??
                  const EdgeInsets.only(left: 12, right: 12, bottom: 12),
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
          child: const _TrackMenuItem(icon: Icons.arrow_upward_rounded, label: '上移'),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          Icons.more_vert_rounded,
          size: 16,
          color: theme.colorScheme.outline,
        ),
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
        Icon(icon, size: 16, color: color ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
