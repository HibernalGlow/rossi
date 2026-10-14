import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';

/// 章节多选时浮出的操作条：全选 / 批量改阅读状态 / 批量下载 / 批量删除。
///
/// 从 `comic_info` 的 part 里抽成独立组件，是为了让「批量修改阅读状态」这条入口
/// 能被真控制器 + 真库测到（part 内的私有类在测试里构造不出来），不是为了复用。
///
/// 选中态仍然只有 [controller] 一份（`selectedIds` / `selectionCubit`）；
/// [readController] 只负责落标记表，不参与选中模型。
class EpisodeSelectionActionBar extends StatelessWidget {
  const EpisodeSelectionActionBar({
    super.key,
    required this.controller,
    required this.readController,
    required this.isDownloadType,
    this.inline = false,
    this.onClose,
  });

  final EpisodeDownloadController controller;
  final EpisodeReadMarkController readController;
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
                        // 批量改阅读状态：与「下载/删除」平级的另一组多选动作。
                        // 不受插件下载能力限制 —— 标记是本地事实，插件禁不禁下载都一样。
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.comicInfo.markRead,
                          onPressed: selected.isEmpty
                              ? null
                              : () => readController.markRead(selected),
                          icon: const GlyphIcon(AppGlyphs.checkCircle),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.comicInfo.markUnread,
                          onPressed: selected.isEmpty
                              ? null
                              : () => readController.markUnread(selected),
                          icon: const GlyphIcon(AppGlyphs.ring),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t.comicInfo.download,
                          onPressed:
                              !controller.allowDownload || downloadable.isEmpty
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
                          onPressed:
                              !controller.allowDownload || deletable.isEmpty
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
