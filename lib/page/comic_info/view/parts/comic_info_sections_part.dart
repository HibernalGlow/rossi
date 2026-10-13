part of '../comic_info.dart';

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: context.theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _EpisodeHeaderBadge extends StatelessWidget {
  const _EpisodeHeaderBadge({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final Glyph icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: context.theme.colorScheme.outlineVariant.withValues(
                alpha: 0.3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlyphIcon(
                icon,
                size: 18,
                color: context.textColor.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.textColor.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final descriptionStyle = context.theme.textTheme.bodyMedium?.copyWith(
      height: 1.65,
      color: context.textColor.withValues(alpha: 0.9),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.comicInfo.description,
            style: context.theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SelectionArea(
            child: Text(
              widget.description,
              style: descriptionStyle,
              maxLines: _expanded ? null : 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.description.length > 90) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: GlyphIcon(
                _expanded ? AppGlyphs.chevronUp : AppGlyphs.chevronDown,
              ),
              label: Text(
                _expanded ? t.comicInfo.collapse : t.comicInfo.expandFullText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 内容区水平边距：与 _ComicInfoState._constrainedSliver 同一份算法，
/// 章节 sliver 自带 SliverLayoutBuilder，用它算出内容宽度后再选单列/网格。
double _constrainedHorizontalPadding(double crossAxisExtent) =>
    ((crossAxisExtent - 1120) / 2).clamp(20.0, double.infinity).toDouble();

/// displayEps（已全局排序）按 groupTitle 切段，组顺序=首次出现顺序。
/// 单组/空组时返回至多一组，调用方走现有扁平路径。
List<ChapterGroup<Ep>> groupDisplayEps(List<dynamic> displayEps) {
  return groupChaptersByTitle<Ep>(
    displayEps.cast<Ep>(),
    (ep) => resolveChapterGroupTitle(groupTitle: ep.groupTitle),
  );
}

/// 章节列表头（标题 + 计数/倒序 badge），与 _SectionCard 的标题区同样式，
/// 虚拟化后作为独立 sliver，列表本体是下面的 _EpisodeBoard。
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: context.theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// 分组吸顶头：组名 + 计数 + 下载本组。背景不透明，吸顶时内容从下方滑过。
///
/// 普通 widget（高度自适应），交给 flutter_sticky_header 的
/// [SliverStickyHeader] 处理吸顶与顶替，不再手写 delegate 高度。
/// 与章节内容区同一套居中（窄屏左右 20，宽屏与章节行对齐）。

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.controller,
    required this.isDownloadType,
    this.inline = false,
    this.onClose,
  });

  final EpisodeDownloadController controller;
  final bool isDownloadType;
  final bool inline;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final chapters = controller.lastChapters;
    final selected = chapters
        .where((c) => controller.selectedIds.contains(c.id))
        .toList();
    final downloadable = controller.downloadableOf(selected);
    final deletable = controller.downloadedOf(selected);
    final allSelected =
        chapters.isNotEmpty && selected.length >= chapters.length;

    final inSelection = controller.selectionMode;
    if (inline && !inSelection) return const SizedBox.shrink();
    final bar = IgnorePointer(
      ignoring: !inSelection,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: inSelection ? Offset.zero : const Offset(0, 1.0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: inSelection ? 1 : 0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.common.cancel,
                          onPressed: controller.exitSelection,
                          icon: const GlyphIcon(AppGlyphs.close),
                        ),
                        Text(
                          t.bookshelf.selectedCount(
                            count: controller.selectedIds.length,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: allSelected
                              ? t.bookshelf.deselectAll
                              : t.common.selectAll,
                          onPressed: chapters.isEmpty
                              ? null
                              : () {
                                  if (allSelected) {
                                    controller.clearSelection();
                                  } else {
                                    controller.selectAll(
                                      chapters.map((c) => c.id),
                                    );
                                  }
                                },
                          icon: GlyphIcon(
                            allSelected
                                ? AppGlyphs.deselect
                                : AppGlyphs.selectAll,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.comicInfo.download,
                          onPressed: downloadable.isEmpty
                              ? null
                              : () async {
                                  await controller.downloadChapters(
                                    context,
                                    selected,
                                  );
                                },
                          icon: const GlyphIcon(AppGlyphs.download),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.common.delete,
                          onPressed: deletable.isEmpty
                              ? null
                              : () async {
                                  final wholeDeleted = await controller
                                      .deleteChapters(context, selected);
                                  if (wholeDeleted) {
                                    controller.exitSelection();
                                    if (isDownloadType && context.mounted) {
                                      if (onClose != null) {
                                        onClose!();
                                      } else {
                                        context.pop();
                                      }
                                    }
                                  }
                                },
                          icon: const GlyphIcon(AppGlyphs.delete),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return inline ? bar : Positioned(bottom: 8, left: 8, right: 8, child: bar);
  }
}

class _ReadActionButton extends StatelessWidget {
  const _ReadActionButton({required this.hasHistory, required this.onPressed});

  final bool hasHistory;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      // 禁用 Hero 动画：详情页从带 FAB 的页面（发现页/书架历史等）push 进来时，
      // 路由过渡收集期新旧路由的默认 FAB tag 会撞车（全库默认 tag 共享同一对象）。
      heroTag: null,
      onPressed: onPressed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: GlyphIcon(
        hasHistory ? AppGlyphs.history : AppGlyphs.book,
        size: 18,
      ),
      label: Text(
        hasHistory ? t.comicInfo.continueRead : t.comicInfo.startRead,
      ),
    );
  }
}
