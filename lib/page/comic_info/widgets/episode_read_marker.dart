import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_info/cubit/episode_read_mark_cubit.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_presentation.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 章节行前导的「阅读标记」槽位。
///
/// 与右侧下载角标同一套做法：只订阅自己这一章的状态，别章标记变化不重建整列表。
/// 本体是 32x32 槽位，与多选态的选中勾共用外层那份「32 + 右 12」占位，
/// 进/出多选不会让标题左右跳（见 `eps.dart` 的前导槽）。
///
/// 四个状态各自有独立长相，因为「读到过」和「我标过已读」是两件事，
/// 用户必须能一眼分开（口径见 `docs/chapter-read-state.md`）：
///
/// - 未读：淡空圈
/// - 读到过：淡细勾 —— 没有封圈，因为它不是人为判决
/// - 已标记已读：封圈勾
/// - 已标记未读：高亮空圈 —— 显式把推断的已读拉回来
class EpisodeReadMarker extends StatelessWidget {
  const EpisodeReadMarker({
    super.key,
    required this.controller,
    required this.chapter,
    this.onMarkThroughRead,
  });

  final EpisodeReadMarkController controller;
  final DownloadChapter chapter;

  /// 「标记至此为已读」：由行所在的那一层提供，因为只有它拿得到完整显示列表与倒序方向。
  final VoidCallback? onMarkThroughRead;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      EpisodeReadMarkCubit,
      EpisodeReadMarkState,
      ChapterReadState
    >(
      bloc: controller.cubit,
      selector: (state) =>
          state.model.stateOf(chapterId: chapter.id, order: chapter.order),
      builder: (context, readState) {
        final visual = readMarkerVisual(readState);
        final scheme = context.theme.colorScheme;
        final color = visual.primary
            ? scheme.primary.withValues(alpha: visual.alpha)
            : context.textColor.withValues(alpha: visual.alpha);
        // triggerMode 必须是 manual：Tooltip 默认长按触发，会把「长按开菜单」抢走。
        // 桌面端仍然靠 hover 出提示，不需要那个默认触发。
        return Tooltip(
          message: readStateLabel(readState),
          triggerMode: TooltipTriggerMode.manual,
          child: InkWell(
            onTap: () => controller.toggle(chapter),
            onLongPress: () => showChapterReadMenu(
              context,
              chapter: chapter,
              readState: readState,
              controller: controller,
              onMarkThroughRead: onMarkThroughRead,
            ),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: GlyphIcon(visual.glyph, size: 20, color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 长按标记槽位弹出的阅读状态面板：逐章的四个动作都在这一处。
Future<void> showChapterReadMenu(
  BuildContext context, {
  required DownloadChapter chapter,
  required ChapterReadState readState,
  required EpisodeReadMarkController controller,
  VoidCallback? onMarkThroughRead,
}) async {
  final action = await showPopupPanel<_ReadMenuAction>(
    context: context,
    presentation: PopupPresentation.relative,
    builder: (dialogContext) => PopupPanel(
      title: Text(t.comicInfo.readStateMenu),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${chapter.displayName} · ${readStateLabel(readState)}',
            style: context.theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            t.comicInfo.readStateMenuHint,
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: context.textColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          _ReadMenuRow(
            glyph: AppGlyphs.checkCircle,
            label: t.comicInfo.markRead,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ReadMenuAction.markRead),
          ),
          _ReadMenuRow(
            glyph: AppGlyphs.ring,
            label: t.comicInfo.markUnread,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ReadMenuAction.markUnread),
          ),
          if (onMarkThroughRead != null)
            _ReadMenuRow(
              glyph: AppGlyphs.checkDouble,
              label: t.comicInfo.markThroughRead,
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_ReadMenuAction.markThroughRead),
            ),
          _ReadMenuRow(
            glyph: AppGlyphs.clearAll,
            label: t.comicInfo.clearReadMark,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ReadMenuAction.clearMark),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t.common.cancel),
        ),
      ],
    ),
  );

  switch (action) {
    case _ReadMenuAction.markRead:
      controller.markRead([chapter]);
      break;
    case _ReadMenuAction.markUnread:
      controller.markUnread([chapter]);
      break;
    case _ReadMenuAction.markThroughRead:
      onMarkThroughRead?.call();
      break;
    case _ReadMenuAction.clearMark:
      controller.clearMarks([chapter]);
      break;
    case null:
      break;
  }
}

enum _ReadMenuAction { markRead, markUnread, markThroughRead, clearMark }

class _ReadMenuRow extends StatelessWidget {
  const _ReadMenuRow({
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            GlyphIcon(glyph, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
