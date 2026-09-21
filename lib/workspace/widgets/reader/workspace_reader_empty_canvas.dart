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
    final scheme = theme.colorScheme;
    final history = _latestHistory;

    // 泳道可能被拖到很窄（甚至分屏）—— 一律用滚动兜住，空态永不溢出。
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.12),
                radius: 0.95,
                colors: [
                  scheme.primary.withValues(alpha: 0.07),
                  scheme.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: ReaderEmptyGridPainter(
              color: scheme.outlineVariant.withValues(alpha: 0.16),
            ),
          ),
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  // 视口内摆得下就正好居中，摆不下才滚动。
                  constraints: BoxConstraints(
                    minHeight: constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : 0,
                  ),
                  child: Center(child: _buildContent(context, history)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, UnifiedComicHistory? history) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 10),
                child: child,
              ),
            ),
            child: _EmptyBadge(
              icon: Icons.auto_stories_outlined,
              iconColor: scheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '阅读器泳道空闲中',
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；'
              '点栏顶的独占按钮可让它瞬间撑满视口。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (history != null) ...[
                FilledButton.icon(
                  onPressed: () => _resume(history),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('继续阅读'),
                ),
                OutlinedButton.icon(
                  onPressed: _openLocalPicker,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('打开本地漫画'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _openLocalPicker,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('打开本地漫画'),
                ),
            ],
          ),
          if (history != null) ...[
            const SizedBox(height: 16),
            _LastReadCaption(text: '上次读到 · ${history.title}'),
          ],
        ],
      ),
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

/// 空态的「状态图标」：MD3 里空态属于 large illustration，
/// 用一层 surfaceContainerHighest 的圆形容器托住，比裸图标更有分量。
class _EmptyBadge extends StatelessWidget {
  const _EmptyBadge({required this.icon, required this.iconColor});

  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.18),
            blurRadius: 36,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Icon(icon, size: 40, color: iconColor),
    );
  }
}

/// 「上次读到 · 书名」：被动说明，不是第三颗按钮，因此压到最弱的层级。
class _LastReadCaption extends StatelessWidget {
  const _LastReadCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 14,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态背景的暗纹网格（neoview 中央画板的视觉语言）。
///
/// 网格从中心向四周淡出：铺满到边缘时，视线会被边缘的线抢走。
class ReaderEmptyGridPainter extends CustomPainter {
  final Color color;

  ReaderEmptyGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..shader = RadialGradient(
        center: const Alignment(0, -0.12),
        radius: 1.15,
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.1, 1],
      ).createShader(Offset.zero & size);

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
