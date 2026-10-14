import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
      title: t.workspace.localComicsEn,
      icon: AppGlyphs.folderCopy,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: FilledButton.tonalIcon(
        onPressed: () => _openLocalPicker(context),
        icon: const GlyphIcon(AppGlyphs.folder, size: 16),
        label: Text(t.workspace.openLocal),
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
                    GlyphIcon(
                      AppGlyphs.bolt,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.workspace.gpuZeroCopyEngine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.workspace.localOpenSupportDesc,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openLocalPicker(context),
                    icon: const GlyphIcon(AppGlyphs.importFile, size: 16),
                    label: Text(t.workspace.pickComicFolderFromDisk),
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
      debugPrint(t.workspace.openLocalComicFailed(error: e));
    }
  }
}
