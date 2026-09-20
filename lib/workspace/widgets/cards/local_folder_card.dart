import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 真实本地漫画目录卡片（支持直接选择本地文件夹并使用 Breeze 原版阅读器/GPU 零拷贝打开）
class LocalFolderCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 卡片在面板轨道上的位置动作，由宿主（面板 / 抽屉）传入。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const LocalFolderCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsibleCard(
      cardId: 'local_folder',
      title: '本地漫画 (Local Manga)',
      icon: Icons.folder_copy_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: FilledButton.tonalIcon(
        onPressed: () => _openLocalPicker(context),
        icon: const Icon(Icons.folder_open_rounded, size: 16),
        label: const Text('打开本地'),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'GPU 零拷贝直通引擎',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '支持 zip, cbz, 文件夹、PDF 及图片打包归档。Rust 侧快速解压并直入 D3D12/Metal 合成链。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openLocalPicker(context),
                    icon: const Icon(
                      Icons.drive_folder_upload_rounded,
                      size: 16,
                    ),
                    label: const Text('从本地磁盘选择漫画文件夹'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocalPicker(BuildContext context) async {
    try {
      final selected = await showLocalFileTreeSheet(context: context);
      if (selected != null && selected.isNotEmpty && context.mounted) {
        context.pushRoute(
          ComicReadRoute(
            comicId: selected,
            order: 0,
            from: 'local',
            epsNumber: 1,
            type: ComicEntryType.normal,
            comicInfo: selected,
            stringSelectCubit: StringSelectCubit(),
          ),
        );
      }
    } catch (e) {
      debugPrint('打开本地漫画出错: $e');
    }
  }
}
