import 'package:material_ui/material_ui.dart';

/// 原位详情的内容布局。封面和书名属于上方被选中的卡片，不在这里重复。
/// 业务宿主提供真实操作、元数据和章节；这里仅负责空间与层级。
class ComicInlineDetailsSurface extends StatelessWidget {
  const ComicInlineDetailsSurface({
    super.key,
    required this.onClose,
    required this.operations,
    this.metadata,
    this.description,
    this.chapters,
    this.preview,
    this.tools,
  });

  final VoidCallback onClose;
  final Widget operations;
  final Widget? metadata;
  final Widget? description;
  final Widget? chapters;
  final Widget? preview;
  final Widget? tools;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '作品工具',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '收起详情',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            operations,
            if (tools != null) ...[const SizedBox(height: 8), tools!],
            if (metadata != null || description != null || preview != null) ...[
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?metadata,
                      if (description != null) ...[
                        if (metadata != null) const SizedBox(height: 16),
                        description!,
                      ],
                    ],
                  );
                  if (constraints.maxWidth >= 760 &&
                      preview != null &&
                      (metadata != null || description != null)) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: text),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: preview!),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      text,
                      if (preview != null) ...[
                        if (metadata != null || description != null)
                          const SizedBox(height: 20),
                        preview!,
                      ],
                    ],
                  );
                },
              ),
            ],
            if (chapters != null) ...[const SizedBox(height: 20), chapters!],
          ],
        ),
      ),
    );
  }
}

/// 固定高度的预览轨道与外层纵向滚动互不争抢；图片由加载器保留原比例。
class ComicInlinePreviewGallery extends StatelessWidget {
  const ComicInlinePreviewGallery({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.onMore,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onMore;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text('画面预览', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (onMore != null)
            TextButton(onPressed: onMore, child: const Text('加载更多')),
        ],
      ),
      const SizedBox(height: 8),
      if (count > 0)
        SizedBox(
          height: 184,
          child: ListView.separated(
            primary: false,
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 132, child: itemBuilder(context, index)),
            ),
          ),
        ),
      if (loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      if (error != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(error!, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
    ],
  );
}

/// 按需增加章节，避免展开一部千章作品就构建整个目录。
class ComicInlineChapterBoard extends StatefulWidget {
  const ComicInlineChapterBoard({
    super.key,
    required this.count,
    required this.itemBuilder,
    required this.onReverse,
    this.reversed = false,
  });
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback onReverse;
  final bool reversed;
  @override
  State<ComicInlineChapterBoard> createState() =>
      _ComicInlineChapterBoardState();
}

class _ComicInlineChapterBoardState extends State<ComicInlineChapterBoard> {
  int _visible = 12;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '章节 · ${widget.count}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextButton.icon(
            onPressed: widget.onReverse,
            icon: Icon(
              widget.reversed
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
            ),
            label: Text(widget.reversed ? '恢复正序' : '倒序'),
          ),
        ],
      ),
      if (widget.count == 0)
        const Padding(padding: EdgeInsets.all(12), child: Text('暂无章节')),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.count && i < _visible; i++)
                SizedBox(width: width, child: widget.itemBuilder(context, i)),
            ],
          );
        },
      ),
      if (_visible < widget.count)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _visible += 24),
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('显示更多章节'),
          ),
        ),
    ],
  );
}
