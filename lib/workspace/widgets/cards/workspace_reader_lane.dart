import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

/// 工作区中央 Reader 泳道视图（完全对齐 NeoView 中央 Reader Canvas 设计）
class WorkspaceReaderLane extends StatefulWidget {
  final WorkspaceMode mode;
  final VoidCallback onToggleMode;

  const WorkspaceReaderLane({
    super.key,
    required this.mode,
    required this.onToggleMode,
  });

  @override
  State<WorkspaceReaderLane> createState() => _WorkspaceReaderLaneState();
}

class _WorkspaceReaderLaneState extends State<WorkspaceReaderLane> {
  UnifiedComicHistory? _latestHistory;

  @override
  void initState() {
    super.initState();
    _loadLatestHistory();
  }

  void _loadLatestHistory() {
    final history = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending)
        .build()
        .findFirst();
    setState(() => _latestHistory = history);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdges = widget.mode == WorkspaceMode.edges;

    return Container(
      decoration: BoxDecoration(
        color: isEdges ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest,
        borderRadius: isEdges ? BorderRadius.zero : const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 背景微网格（NeoView 经典暗纹）
          CustomPaint(
            size: Size.infinite,
            painter: _GridBackgroundPainter(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
            ),
          ),

          // 2. 阅读器中心画布
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 模拟双页漫画开本视图
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPageFrame(context, 'Left Page (双页跨页)'),
                    const SizedBox(width: 8),
                    _buildPageFrame(context, 'Right Page (主视面)'),
                  ],
                ),
                const SizedBox(height: 20),

                Text(
                  'NeoView 居中阅读器画板 (Center Reader)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    '中央泳道专属于漫画呈现与翻页控制。可从左侧书架挑选漫画就地阅读，点击栏顶 Solo 瞬间全屏专注。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 18),

                // 快速操作条
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_latestHistory != null)
                      FilledButton.icon(
                        onPressed: () {
                          context.pushRoute(
                            ComicInfoRoute(
                              comicId: _latestHistory!.comicId,
                              from: _latestHistory!.source,
                              type: ComicEntryType.normal,
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text('继续阅读: ${_latestHistory!.title}'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _openLocalPicker(context),
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('打开本地漫画'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: widget.onToggleMode,
                      icon: Icon(isEdges ? Icons.view_column_rounded : Icons.fullscreen_rounded, size: 16),
                      label: Text(isEdges ? '切回多列泳道' : '沉浸全屏阅读'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageFrame(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Container(
      width: 145,
      height: 205,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined, size: 36, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
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

class _GridBackgroundPainter extends CustomPainter {
  final Color color;

  _GridBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridBackgroundPainter oldDelegate) => false;
}
