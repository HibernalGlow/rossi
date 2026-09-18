import 'package:material_ui/material_ui.dart';

/// 边缘滑出抽屉容器面板。
///
/// 内容交给调用方 —— 现在两个抽屉装的是**同一套面板宿主**
/// （`LanePanelHost`），于是四边栏模式与泳道模式用的是同一份面板注册表、
/// 同一个图标轨、同一批卡片：「这张卡属于哪个面板」永远只有一处可改。
class EdgeDrawerPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final Widget child;

  /// 同样停在**顶栏**的面板页签条（左右抽屉各一条）——
  /// 与泳道模式用的是同一个控件、同一份面板注册表。
  final Widget? panelTabs;

  final double width;

  const EdgeDrawerPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
    this.panelTabs,
    this.width = 340.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
          left: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        children: [
          // Drawer Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (panelTabs != null) ...[
                  panelTabs!,
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭边栏 (Close)',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Drawer Content
          Expanded(child: child),
        ],
      ),
    );
  }
}
