import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

/// 中央阅读画板占位（在泳道模式作为主栏，在四边栏模式作为全屏背景）
class ReaderCanvasPlaceholder extends StatelessWidget {
  final WorkspaceMode mode;
  final VoidCallback onToggleMode;

  const ReaderCanvasPlaceholder({
    super.key,
    required this.mode,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdges = mode == WorkspaceMode.edges;

    return Container(
      decoration: BoxDecoration(
        color: isEdges ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest,
        borderRadius: isEdges ? BorderRadius.zero : BorderRadius.circular(16),
        border: isEdges
            ? null
            : Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 背景暗纹与阅读器指示线
          CustomPaint(
            size: Size.infinite,
            painter: _GridBackgroundPainter(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.1),
            ),
          ),
          // 模拟漫画双页展示
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMangaPageMockup(context, 'Page 12 (Left)'),
                    const SizedBox(width: 12),
                    _buildMangaPageMockup(context, 'Page 13 (Right)'),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  isEdges
                      ? '【沉浸四边栏模式】全屏阅读中 · 边缘悬停或点击四周呼出卡片'
                      : '【泳道工作区模式】管理与预览工作台',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEdges
                      ? '中央为 100% 满屏渲染；鼠标靠近屏幕左边即可滑出书架，靠近右边滑出设置'
                      : '各列支持拖拽分栏线调整宽度，点击栏顶折叠为紧凑条或切换 Solo 独占',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onToggleMode,
                  icon: Icon(isEdges ? Icons.view_column_rounded : Icons.fullscreen_rounded),
                  label: Text(isEdges ? '切回多列泳道模式' : '切入沉浸四边栏模式'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMangaPageMockup(BuildContext context, String pageLabel) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      height: 230,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 40, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            pageLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
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
