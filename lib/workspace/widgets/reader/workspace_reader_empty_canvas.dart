import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

/// 阅读器泳道**空态**：还没打开任何一本时的画板。
///
/// 按 neoview 的契约，中央泳道永远是 Reader —— 空态也只是「Reader 里没有书」，
/// 不是另一种功能位（早期版本这里放过发现页与假的双页画板，都已撤掉）。
/// 空态只做一件事：把一本漫画送进这条泳道。
class WorkspaceReaderEmptyCanvas extends StatefulWidget {
  const WorkspaceReaderEmptyCanvas({super.key});

  @override
  State<WorkspaceReaderEmptyCanvas> createState() =>
      _WorkspaceReaderEmptyCanvasState();
}

class _WorkspaceReaderEmptyCanvasState
    extends State<WorkspaceReaderEmptyCanvas> {
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
    if (!mounted) return;
    setState(() => _latestHistory = history);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 泳道可能被拖到很窄（甚至分屏）—— 一律用滚动兜住，空态永不溢出。
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: ReaderEmptyGridPainter(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 44,
                  color: theme.colorScheme.primary.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 12),
                Text(
                  '阅读器泳道空闲中',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Text(
                    '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；'
                    '点栏顶的独占按钮可让它瞬间撑满视口。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_latestHistory != null)
                      FilledButton.icon(
                        onPressed: () => _resume(_latestHistory!),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          '继续阅读: ${_latestHistory!.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _openLocalPicker,
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('打开本地漫画'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 「继续阅读」：本地漫画直接用文件路径进泳道；
  /// 插件漫画没有章节参数，走上游详情页，再由详情页的「开始阅读」进泳道。
  void _resume(UnifiedComicHistory history) {
    if (isLocalComicSource(history.source, history.comicId)) {
      _openLocal(history.comicId, type: ComicEntryType.history);
      return;
    }
    context.pushRoute(
      ComicInfoRoute(
        comicId: history.comicId,
        from: history.source,
        type: ComicEntryType.normal,
      ),
    );
  }

  Future<void> _openLocalPicker() async {
    try {
      final selected = await showLocalFileTreeSheet(context: context);
      if (selected != null && selected.isNotEmpty && mounted) {
        _openLocal(selected);
      }
    } catch (e) {
      debugPrint('打开本地漫画出错: $e');
    }
  }

  void _openLocal(String path, {ComicEntryType type = ComicEntryType.normal}) {
    context.read<WorkspaceCubit>().openReader(
      WorkspaceReaderTarget(
        comicId: path,
        from: 'local',
        type: type,
        comicInfo: path,
        stringSelectCubit: StringSelectCubit(),
      ),
    );
  }
}

/// 空态背景的暗纹网格（neoview 中央画板的视觉语言）。
class ReaderEmptyGridPainter extends CustomPainter {
  final Color color;

  ReaderEmptyGridPainter({required this.color});

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
  bool shouldRepaint(covariant ReaderEmptyGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
