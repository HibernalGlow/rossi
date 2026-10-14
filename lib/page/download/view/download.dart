import 'dart:async';
import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/download_selection.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/page/download/widgets/chapter_select_tile.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/service/download/download_chapter_gate.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/comments/widgets/title.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class DownloadPage extends StatefulWidget {
  final UnifiedComicDownloadInfo downloadInfo;

  const DownloadPage({super.key, required this.downloadInfo});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  UnifiedComicDownloadInfo get downloadInfo => widget.downloadInfo;
  String get source =>
      (downloadInfo.source.trim().isEmpty ? '' : downloadInfo.source).trim();

  late List<DownloadChapter> _chapters;

  /// 本次要下载哪些章节（与「本地是否已有」分开记，避免勾选态被已下载章节占满）。
  DownloadChapterSelection _selection = const DownloadChapterSelection(
    orderedIds: [],
    downloadedIds: {},
  );

  /// 本地已下载的章节 id，用于行内标记与默认勾选。
  final Set<String> _downloadedIds = {};
  late UnifiedComicDownload? comicDownloadInfo;

  @override
  void initState() {
    super.initState();
    if (source.isEmpty) {
      throw StateError('download source pluginId is required');
    }

    const adapter = DownloadChapterAdapter();
    _chapters = downloadInfo.chapters
        .map((chapter) => adapter.fromOnlineChapter(chapter))
        .toList();

    final query = objectbox.unifiedDownloadBox.query(
      UnifiedComicDownload_.uniqueKey.equals('$source:${downloadInfo.comicId}'),
    );
    comicDownloadInfo = query.build().findFirst();
    if (comicDownloadInfo != null) {
      final storedChapters = resolveDownloadChapters(comicDownloadInfo!);
      const matcher = DownloadChapterMatcher();
      for (final chapter in _chapters) {
        // 只认逻辑身份匹配：纯 order 相等在多分块图源下会把两章算成一章。
        final isDownloaded = storedChapters.any(
          (stored) => matcher.matches(stored, chapter.id),
        );
        if (isDownloaded) _downloadedIds.add(chapter.id);
      }
    }

    _selection = DownloadChapterSelection(
      orderedIds: _chapters.map((chapter) => chapter.id).toList(),
      downloadedIds: {..._downloadedIds},
    );

    // 上游在这里无条件勾 `_chapters.first` 以省掉一次手动选择。本仓不改顺序，
    // `_chapters` 保持图源返回的顺序，所以 `first` 并不保证是第一话；且这页在本仓
    // 只从「已有下载 → 补章节」和「长按 → 自己挑」两个入口进来，勾已下载的那一话
    // 等于把 FAB 变成重下。折中：勾「第一个还没下载过的」，同样点一下就能开下。
    for (final chapter in _chapters) {
      if (!_downloadedIds.contains(chapter.id)) {
        _selection = _selection.toggled(chapter.id);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: ScrollableTitle(text: downloadInfo.title),
        actions: [
          // 跳过已下载：开着时用主色画，行本身也会压暗成禁用态，两处都能读出状态。
          IconButton(
            tooltip: t.download.skipDownloaded,
            icon: GlyphIcon(
              AppGlyphs.block,
              color: _selection.skipDownloaded
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(
              () => _selection = _selection.withSkipDownloaded(
                !_selection.skipDownloaded,
              ),
            ),
          ),
          // 动态切换全选/取消全选按钮
          IconButton(
            tooltip: _selection.isAllSelected
                ? t.reader.deselectAll
                : t.reader.selectAll,
            icon: GlyphIcon(
              _selection.isAllSelected
                  ? AppGlyphs.deselect
                  : AppGlyphs.selectAll,
            ),
            onPressed: () => setState(
              () => _selection = _selection.withAllSelected(
                !_selection.isAllSelected,
              ),
            ),
          ),
          IconButton(
            tooltip: t.reader.invertSelection,
            icon: const GlyphIcon(AppGlyphs.flip),
            onPressed: () => setState(() => _selection = _selection.inverted()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _SelectionSummary(
                selected: _selection.selectedCount,
                total: _chapters.length,
                downloaded: _downloadedIds.length,
                skipDownloaded: _selection.skipDownloaded,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    88,
                  ), // reserved bottom padding for FAB
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = _chapters[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ChapterSelectTile(
                        chapter: chapter,
                        selected: _selection.isSelected(chapter.id),
                        skipped: _selection.isSkipped(chapter.id),
                        downloaded: _downloadedIds.contains(chapter.id),
                        onTap: () => setState(
                          () => _selection = _selection.toggled(chapter.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        icon: const GlyphIcon(AppGlyphs.download),
        label: Text(t.download.startDownload),
        onPressed: () {
          logger.d("开始下载");
          download();
        },
      ),
    );
  }

  Future<void> download() async {
    // 走 selection 的那张表：开着「跳过已下载」时勾选里本来就不含已下载的章。
    final selectedChapters = _selection.orderedSelectedIds
        .map((id) => _chapters.firstWhere((chapter) => chapter.id == id))
        .toList();
    if (selectedChapters.isEmpty) {
      showErrorToast(t.download.selectChaptersPrompt);
      return;
    }
    // 单章节任务模型：每章一个任务，一次性入队由队列串行执行。
    final tasks = selectedChapters
        .map(
          (chapter) => buildChapterDownloadTask(
            from: source,
            comicId: downloadInfo.comicId,
            comicName: downloadInfo.title,
            chapter: chapter,
          ),
        )
        .toList();
    // 与「整本」「详情页多选」同一道闸：判据只此一份，见 download_chapter_gate.dart。
    // 这一页的「跳过已下载」开关就是 forceRedownload 的反面 —— 开着＝跳（勾选里本来
    // 就不含已下载的章），关着＝用户明确要重下那些章，闸门不许替他决定。
    final plan = planDownloadEnqueue(
      tasks,
      downloadedIds: downloadedChapterIdsOf(comicDownloadInfo),
      forceRedownload: !_selection.skipDownloaded,
    );
    if (plan.isEmpty) {
      // 闸把所有章都跳了：这句提示要说「跳过了」，不能照报「任务已启动」。
      if (!mounted) return;
      showInfoToast(
        t.download.skippedAlreadyDownloaded(count: plan.skippedDownloaded),
      );
      return;
    }
    try {
      await startDownloadTasks(plan.tasks);
      if (!mounted) return;
      showInfoToast(
        plan.skippedDownloaded > 0
            ? t.download.startedWithSkipped(
                started: plan.tasks.length,
                skipped: plan.skippedDownloaded,
              )
            : t.download.taskStarted,
      );
      unawaited(
        autoFavoriteComicOnDownloadIfEnabled(
          from: source,
          comicId: downloadInfo.comicId,
          context: context,
        ),
      );
    } catch (e, s) {
      logger.e(e, stackTrace: s);
      showErrorToast(
        t.download.taskStartFailed(error: normalizeSearchErrorMessage(e)),
      );
    }
  }
}

/// 列表上方那一行选择读数：勾了几章、本地有几章、跳过开着没。
///
/// 三个标题栏动作都是「一次改一整片」的，没有这行回读就无从确认按下发生了什么。
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.selected,
    required this.total,
    required this.downloaded,
    required this.skipDownloaded,
  });

  final int selected;
  final int total;
  final int downloaded;
  final bool skipDownloaded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            t.download.selectedCount(selected: selected, total: total),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          if (downloaded > 0)
            Text(
              t.download.downloadedCount(count: downloaded),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (skipDownloaded)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlyphIcon(
                  AppGlyphs.block,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  t.download.skipDownloaded,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
