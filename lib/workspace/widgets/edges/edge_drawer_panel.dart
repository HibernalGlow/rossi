import 'package:material_ui/material_ui.dart';

/// 边缘滑出抽屉容器面板
class EdgeDrawerPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final List<Widget> children;
  final double width;

  const EdgeDrawerPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.children,
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
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭边栏 (Close)',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Drawer Cards
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
