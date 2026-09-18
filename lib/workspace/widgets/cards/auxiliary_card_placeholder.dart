import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 本地目录树与文件管理卡片占位
class LocalTreeCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const LocalTreeCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'local_tree',
      title: '本地漫画目录 (Folder)',
      icon: Icons.folder_copy_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      trailing: IconButton(
        icon: const Icon(Icons.create_new_folder_outlined, size: 18),
        tooltip: '选择本地文件夹',
        onPressed: () {},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFolderNode(context, '📁 /Users/manga/Volumes', 28, isRoot: true),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: [
                _buildFolderNode(context, '📂 [Manga] Frieren/', 12),
                _buildFolderNode(context, '📂 [Manga] Dungeon Meshi/', 14),
                _buildFolderNode(context, '📂 [Artbook] Illustration/', 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderNode(BuildContext context, String path, int count, {bool isRoot = false}) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isRoot ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count items',
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// 系统/性能监控卡片占位
class SystemMonitorCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const SystemMonitorCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'system_status',
      title: '系统与引擎状态 (Diagnostics)',
      icon: Icons.monitor_heart_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: Column(
        children: [
          _buildMetricRow(context, 'QuickJS 运行时', '在线 (0 异常)', Colors.green),
          _buildMetricRow(context, 'FRB 桥接内存', '18.4 MB (正常)', Colors.teal),
          _buildMetricRow(context, 'GPU 零拷贝通道', 'D3D12/Metal 共享可用', Colors.blue),
          _buildMetricRow(context, '下载队列线程', '活跃 1 / 等待 0', Colors.purple),
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, String key, String val, Color dotColor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(key, style: theme.textTheme.bodySmall),
          ),
          Text(
            val,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
