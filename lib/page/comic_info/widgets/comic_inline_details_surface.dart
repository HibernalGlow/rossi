import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
    this.showBottomCollapse,
    this.bottomActions,
    this.showTopClose = true,
  });

  final VoidCallback onClose;
  final Widget operations;
  final Widget? metadata;
  final Widget? description;
  final Widget? chapters;
  final Widget? preview;
  final Widget? tools;
  final bool? showBottomCollapse;
  final List<Widget>? bottomActions;
  final bool showTopClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasDetails =
        metadata != null ||
        description != null ||
        preview != null ||
        chapters != null;
    final displayBottomCollapse = showBottomCollapse ?? hasDetails;
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
                    t.comicInfo.workTools,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (showTopClose)
                  IconButton(
                    tooltip: t.comicInfo.collapseDetails,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: onClose,
                    icon: const GlyphIcon(AppGlyphs.close),
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
            if (displayBottomCollapse || bottomActions != null) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children:
                    bottomActions ??
                    [
                      FilledButton.tonalIcon(
                        onPressed: onClose,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        icon: const GlyphIcon(AppGlyphs.chevronUp),
                        label: Text(t.comicInfo.collapseDetails),
                      ),
                    ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 固定高度的预览轨道与外层纵向滚动互不争抢；图片由加载器保留原比例。
class ComicInlinePreviewGallery extends StatefulWidget {
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
  State<ComicInlinePreviewGallery> createState() =>
      _ComicInlinePreviewGalleryState();
}

class _ComicInlinePreviewGalleryState extends State<ComicInlinePreviewGallery> {
  /// 预览轨道不参与 `PageStorage` 的滚动位置恢复。
  ///
  /// 原位详情挂在展墙的 `ListView(PageStorageKey(...))` 下面，而这条横向轨道
  /// 自己没有 key —— 于是它和展墙共用同一个恢复标识，初始偏移会读到外层的
  /// 纵向位置并被钳到本轨道的末尾，看起来就是「一开始停在本子最后几页」。
  /// 预览每次展开都应该从第 1 页开始，所以关掉恢复即可；「加载更多」时
  /// 轨道本身不会被重建，已滚到的位置仍然保留。
  final ScrollController _controller = ScrollController(
    keepScrollOffset: false,
  );

  /// 单页宽度 + 间隔，箭头按「一屏三页」翻动。
  static const double _pageExtent = 132 + 8;

  @override
  void initState() {
    super.initState();
    _refreshAfterLayout();
  }

  @override
  void didUpdateWidget(covariant ComicInlinePreviewGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _refreshAfterLayout();
    }
  }

  /// 首次布局后轨道才有 `maxScrollExtent`，补一帧让箭头/进度条拿到真实范围。
  void _refreshAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    _controller.animateTo(
      (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rail = SizedBox(
      height: 184,
      child: ListView.separated(
        controller: _controller,
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: widget.count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 132,
            child: widget.itemBuilder(context, index),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.comicInfo.imagePreview,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.onMore != null)
              TextButton(onPressed: widget.onMore, child: const Text('加载更多')),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.count > 0)
          AnimatedBuilder(
            animation: _controller,
            child: rail,
            builder: (context, child) {
              final position = _controller.hasClients
                  ? _controller.position
                  : null;
              final pixels = position?.pixels ?? 0;
              final max = position?.maxScrollExtent ?? 0;
              return Column(
                children: [
                  Row(
                    children: [
                      _ArrowButton(
                        glyph: AppGlyphs.chevronBack,
                        onPressed: pixels > 0.5
                            ? () => _scrollBy(-3 * _pageExtent)
                            : null,
                      ),
                      Expanded(child: child!),
                      _ArrowButton(
                        glyph: AppGlyphs.chevronForward,
                        onPressed: pixels < max - 0.5
                            ? () => _scrollBy(3 * _pageExtent)
                            : null,
                      ),
                    ],
                  ),
                  if (max > 0)
                    SizedBox(
                      height: 28,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                          showValueIndicator: ShowValueIndicator.never,
                        ),
                        child: Slider(
                          value: pixels.clamp(0.0, max),
                          max: max,
                          onChanged: (value) => _controller.jumpTo(value),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (widget.error != null)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(widget.error!, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (widget.onRetry != null)
                TextButton(onPressed: widget.onRetry, child: const Text('重试')),
            ],
          ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.glyph, this.onPressed});

  final Glyph glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: GlyphIcon(glyph, size: 18),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
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
            t.comicInfo.chapterCount(count: widget.count),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextButton.icon(
            onPressed: widget.onReverse,
            icon: MorphingGlyph(
              on: widget.reversed,
              glyph: AppGlyphs.arrowDown,
              turns: 0.5,
            ),
            label: Text(
              widget.reversed
                  ? t.comicInfo.restoreForwardOrder
                  : t.comicInfo.reverseOrderLabel,
            ),
          ),
        ],
      ),
      if (widget.count == 0)
        Padding(
          padding: EdgeInsets.all(12),
          child: Text(t.comicInfo.noChaptersYet),
        ),
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
            icon: const GlyphIcon(AppGlyphs.chevronDown),
            label: Text(t.comicInfo.showMoreChapters),
          ),
        ),
    ],
  );
}
