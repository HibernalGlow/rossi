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
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/page/download/widgets/chapter_select_tile.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/comments/widgets/title.dart';

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
  final Map<String, bool> _selected = {};

  /// 本地已下载的章节 id，用于行内标记与默认勾选。
  final Set<String> _downloadedIds = {};
  late UnifiedComicDownload? comicDownloadInfo;

  void _toggleSelection(String selectionKey) {
    setState(() {
      _selected[selectionKey] = !(_selected[selectionKey] ?? false);
    });
  }

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

    for (final chapter in _chapters) {
      _selected[chapter.id] = false;
    }

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

    // 上游在这里无条件勾 `_chapters.first` 以省掉一次手动选择。本仓不改顺序，
    // `_chapters` 保持图源返回的顺序，所以 `first` 并不保证是第一话；且这页在本仓
    // 只从「已有下载 → 补章节」和「长按 → 自己挑」两个入口进来，勾已下载的那一话
    // 等于把 FAB 变成重下。折中：勾「第一个还没下载过的」，同样点一下就能开下。
    for (final chapter in _chapters) {
      if (!_downloadedIds.contains(chapter.id)) {
        _selected[chapter.id] = true;
        break;
      }
    }
  }

  // 判断是否所有章节都被选中
  bool get isAllSelected {
    return _chapters.every((chapter) => _selected[chapter.id] == true);
  }

  // 切换全选或取消全选
  void toggleSelectAll() {
    setState(() {
      final newState = !isAllSelected;
      for (final chapter in _chapters) {
        _selected[chapter.id] = newState;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScrollableTitle(text: downloadInfo.title),
        actions: [
          // 动态切换全选/取消全选按钮
          IconButton(
            icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
            onPressed: toggleSelectAll,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
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
                  selected: _selected[chapter.id] ?? false,
                  downloaded: _downloadedIds.contains(chapter.id),
                  onTap: () => _toggleSelection(chapter.id),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.download),
        label: Text(t.download.startDownload),
        onPressed: () {
          logger.d("开始下载");
          download();
        },
      ),
    );
  }

  Future<void> download() async {
    final selectedChapters = _chapters
        .where((chapter) => _selected[chapter.id] == true)
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
    try {
      await startDownloadTasks(tasks);
      if (!mounted) return;
      showInfoToast(t.download.taskStarted);
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
