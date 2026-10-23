import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/page/comic_info/cubit/episode_download_status_cubit.dart';
import 'package:zephyr/page/comic_info/cubit/episode_read_mark_cubit.dart';
import 'package:zephyr/page/comic_info/cubit/episode_selection_cubit.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_marker.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/icons/icons.dart';

class EpButtonWidget extends StatelessWidget {
  static const double fixedHeight = 56;

  final Ep doc;
  final DownloadChapter chapter;
  final EpisodeDownloadController controller;

  /// 章节阅读标记控制器（与下载控制器平级的那一半，共用同一份选中态）。
  final EpisodeReadMarkController readController;
  final dynamic allInfo;
  final int epsLength;

  /// 组内总数：分组显示时行号按组内 1..N 编排（null 时回退 [epsLength]，
  /// 即今天的扁平行为）。阅读器用的总章节数仍走 [epsLength]。
  final int? displayTotal;
  final ComicEntryType type;
  final String comicId;
  final String from;
  final int index;
  final bool isReversed;

  /// 下载是否被插件允许；为 false 时仍显示下载按钮，点击后由调用方弹出禁用原因。
  final bool downloadAllowed;
  final String downloadDisabledReason;
  final VoidCallback? onAction;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onEnterSelect;

  /// 「标记至此为已读」的范围由外层算（外层才有完整显示列表与倒序方向）。
  final VoidCallback? onMarkThroughRead;

  const EpButtonWidget({
    super.key,
    required this.doc,
    required this.chapter,
    required this.controller,
    required this.readController,
    required this.allInfo,
    required this.epsLength,
    this.displayTotal,
    required this.type,
    required this.comicId,
    required this.from,
    required this.index,
    required this.isReversed,
    this.downloadAllowed = true,
    this.downloadDisabledReason = '',
    this.onAction,
    this.onToggleSelect,
    this.onEnterSelect,
    this.onMarkThroughRead,
  });

  @override
  Widget build(BuildContext context) {
    // 不依赖插件返回的 order，按当前显示位置自主计算序号：
    // 正序从上到下 1..N，倒序从下到上 N..1。分组时 N 为组内总数。
    // 标题只在外层 build 算一次（带 FFI 缓存），选中/进度变化只走内层监听，
    final numberTotal = displayTotal ?? epsLength;
    final displayNumber = isReversed ? numberTotal - index : index + 1;
    final rawTitle = doc.name.trim();
    final title = rawTitle.isEmpty
        ? t.comicInfo.episodeFallback(index: displayNumber)
        : convertChineseForDisplay(rawTitle);
    final episodeLabel = t.comicInfo.episodeLabel(index: displayNumber);

    // RepaintBoundary 把进度圈动画隔离在行内；选中态只听 selectionCubit，
    // 下载进度 tick 不会重建标题/背景整行。
    return RepaintBoundary(
      child: BlocBuilder<EpisodeSelectionCubit, int>(
        bloc: controller.selectionCubit,
        builder: (context, _) {
          final selectionMode = controller.selectionMode;
          final selected = controller.selectedIds.contains(chapter.id);
          final colorScheme = context.theme.colorScheme;
          return InkWell(
            onTap: selectionMode ? onToggleSelect : () => _openRead(context),
            onLongPress: onEnterSelect,
            child: Container(
              width: double.infinity,
              height: fixedHeight,
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : context.theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.6),
                        width: 1,
                      )
                    : null,
              ),
              child: Row(
                children: [
                  // 前导槽位：多选时是选中勾，平时是阅读标记。两者占同一个
                  // 32+12 的槽，进/出多选不会让标题左右跳。
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: selectionMode
                        ? SizedBox.square(
                            dimension: 32,
                            child: Center(
                              child: GlyphIcon(
                                selected
                                    ? AppGlyphs.checkCircle
                                    : AppGlyphs.ring,
                                color: selected
                                    ? colorScheme.primary
                                    : context.textColor.withValues(alpha: 0.5),
                                size: 20,
                              ),
                            ),
                          )
                        : EpisodeReadMarker(
                            controller: readController,
                            chapter: chapter,
                            onMarkThroughRead: onMarkThroughRead,
                          ),
                  ),
                  Text(
                    episodeLabel,
                    style: context.theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EpisodeTitle(
                      readController: readController,
                      chapter: chapter,
                      title: title,
                    ),
                  ),
                  _EpisodeTrailing(
                    controller: controller,
                    chapter: chapter,
                    downloadAllowed: downloadAllowed,
                    onAction: onAction,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openRead(BuildContext context) {
    final chapter = const DownloadChapterAdapter().fromEp(doc);
    // 在线入口统一查库：该章已下载则直接读本地，不再看来源 type。
    if (type == ComicEntryType.normal || type == ComicEntryType.history) {
      final local = const DownloadTaskRepository().findDownloadedChapter(
        from: from,
        comicId: comicId,
        chapterKey: chapter.id,
      );
      final record = local == null
          ? null
          : const DownloadTaskRepository().findDownloadRecord(from, comicId);
      if (local != null && record != null) {
        context.pushRoute(
          ComicReadRoute(
            comicInfo: record,
            comicId: record.comicId,
            type: type == ComicEntryType.history
                ? ComicEntryType.historyAndDownload
                : ComicEntryType.download,
            order: local.order,
            chapterId: local.id,
            requestId: local.effectiveRequestId,
            storageChapterId: local.effectiveStorageId,
            logicalKey: local.id,
            chapterExtern: ChapterExtern.from(local.extern),
            epsNumber: resolveStoredDownloadChapters(record).length,
            from: from,
            stringSelectCubit: context.read<StringSelectCubit>(),
          ),
        );
        return;
      }
    }
    final resolvedType = type == ComicEntryType.history
        ? ComicEntryType.normal
        : type;
    final chapterExtern = Map<String, dynamic>.from(doc.extern);
    context.pushRoute(
      ComicReadRoute(
        comicInfo: allInfo,
        comicId: comicId,
        type: resolvedType,
        order: chapter.order,
        chapterId: chapter.id,
        requestId: chapter.effectiveRequestId,
        storageChapterId: chapter.effectiveStorageId,
        logicalKey: chapter.id,
        chapterExtern: enrichEpisodeChapterExtern(doc, chapterExtern),
        epsNumber: epsLength,
        from: from,
        stringSelectCubit: context.read<StringSelectCubit>(),
      ),
    );
  }

  ChapterExtern enrichEpisodeChapterExtern(
    Ep episode,
    ChapterExtern chapterExtern,
  ) {
    return chapterExtern;
  }
}

/// 章节标题：颜色按阅读状态走，与左侧标记共用同一份解析结果。
///
/// 只订阅自己这一章，别章标记变化不重建标题。
class _EpisodeTitle extends StatelessWidget {
  const _EpisodeTitle({
    required this.readController,
    required this.chapter,
    required this.title,
  });

  final EpisodeReadMarkController readController;
  final DownloadChapter chapter;
  final String title;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      EpisodeReadMarkCubit,
      EpisodeReadMarkState,
      ChapterReadState
    >(
      bloc: readController.cubit,
      selector: (state) =>
          state.model.stateOf(chapterId: chapter.id, order: chapter.order),
      builder: (context, readState) {
        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: episodeTitleColor(context, readState),
          ),
        );
      },
    );
  }
}

/// 标题取色（纯函数，四档互不相同）。
///
/// 读到过与已标已读都淡色，但淡一档不同：人为判决比推断更「确定」，
/// 压得更暗；已标未读反而用主色 —— 那是用户显式说「我还没读」，要跳出来。
Color episodeTitleColor(BuildContext context, ChapterReadState state) {
  final textColor = context.textColor;
  switch (state) {
    case ChapterReadState.unread:
      return textColor;
    case ChapterReadState.inferredRead:
      return textColor.withValues(alpha: 0.55);
    case ChapterReadState.manualRead:
      return textColor.withValues(alpha: 0.40);
    case ChapterReadState.manualUnread:
      return context.theme.colorScheme.primary;
  }
}

/// 章节行右侧下载角标：独立监听下载状态，进度 tick 时只重建
/// 这个 32x32 槽位，不重建整行标题/背景。
class _EpisodeTrailing extends StatelessWidget {
  const _EpisodeTrailing({
    required this.controller,
    required this.chapter,
    required this.downloadAllowed,
    this.onAction,
  });

  final EpisodeDownloadController controller;
  final DownloadChapter chapter;
  final bool downloadAllowed;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (!downloadAllowed) {
      // 不允许下载时显示静态按钮，无需订阅，点击后由 onAction 弹出禁用原因。
      return _slot(context, const GlyphIcon(AppGlyphs.download, size: 20));
    }
    // 只订阅自己这一章的 (status, progress)：别的章节进度变化时不重建。
    return BlocSelector<
      EpisodeDownloadStatusCubit,
      EpisodeDownloadStatusState,
      (ChapterDownloadStatus, double?)
    >(
      bloc: controller.statusCubit,
      selector: (state) => (state.statusOf(chapter), state.progressOf(chapter)),
      builder: (context, selected) {
        final status = selected.$1;
        switch (status) {
          case ChapterDownloadStatus.notDownloaded:
            return _slot(
              context,
              const GlyphIcon(AppGlyphs.download, size: 20),
            );
          case ChapterDownloadStatus.queued:
            return _slot(
              context,
              const GlyphIcon(AppGlyphs.hourglass, size: 20),
            );
          case ChapterDownloadStatus.downloading:
            return _slot(
              context,
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: selected.$2,
                ),
              ),
            );
          case ChapterDownloadStatus.failed:
            return _slot(
              context,
              GlyphIcon(
                AppGlyphs.error,
                size: 20,
                color: context.theme.colorScheme.error,
              ),
            );
          case ChapterDownloadStatus.downloaded:
            return _slot(
              context,
              GlyphIcon(
                AppGlyphs.checkCircle,
                size: 20,
                color: context.theme.colorScheme.primary,
              ),
            );
        }
      },
    );
  }

  // 行内容高度只有 32（56-上下 padding），IconButton 默认最小 40 会被纵向
  // 挤压，里面的进度圈会被压成椭圆。这里统一用 32x32 正方形槽位，保证不变形。
  Widget _slot(BuildContext context, Widget child) {
    return InkWell(
      onTap: onAction,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox.square(dimension: 32, child: Center(child: child)),
    );
  }
}
