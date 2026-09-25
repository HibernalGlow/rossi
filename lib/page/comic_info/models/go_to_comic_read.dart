import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/config/router/router.gr.dart' show ComicReadRoute;

import 'package:zephyr/page/comic_info/models/read_launch_adapter.dart';

/// 从详情页的「开始阅读」进阅读器。
///
/// 「有没有读过」在这里是问 [StringSelectCubit] —— 详情页就是从那套选择态里
/// 拿到当前章节的，所以它非空即代表「带着进度进来」。
/// 封面卡上的「直接阅读」按钮没有这个 Cubit，走 [pushComicReadRoute]，
/// 并把「有没有读过」按 ObjectBox 的历史记录来回答。
void goToComicRead(
  BuildContext context,
  String comicId,
  ComicEntryType type,
  dynamic allInfo,
  String from,
) {
  pushComicReadRoute(
    context,
    allInfo: allInfo,
    comicId: comicId,
    from: from,
    isDownload:
        type == ComicEntryType.download ||
        type == ComicEntryType.historyAndDownload,
    hasHistory: context.read<StringSelectCubit>().state.isNotEmpty,
    stringSelectCubit: context.read<StringSelectCubit>(),
  );
}

/// 起读的唯一解析口径：章节目录、续读章节、eps 数、路由参数都在这里算一次。
///
/// [allInfo] 可以是插件详情（`PluginComicDetailSource`）或下载记录
/// （`UnifiedComicDownload`），两者的章节解析都由
/// [resolveUnifiedComicChapters] 负责，所以两条路的续读语义完全一致。
/// 在线入口还会统一查库：目标章节已下载就直接读本地，见下面的 `readInfo` 分支。
void pushComicReadRoute(
  BuildContext context, {
  required dynamic allInfo,
  required String comicId,
  required String from,
  required bool isDownload,
  required bool hasHistory,
  required StringSelectCubit stringSelectCubit,
}) {
  final historyForChapter = objectbox.unifiedHistoryBox
      .query(UnifiedComicHistory_.uniqueKey.equals('$from:$comicId'))
      .build()
      .findFirst();
  final chapter = _resolveChapter(allInfo, from, historyForChapter);

  // 在线入口统一查库：目标章节已下载则直接读本地，不再看来源 type。
  dynamic readInfo = allInfo;
  var readIsDownload = isDownload;
  var readComicId = '';
  DownloadChapter? readChapter = chapter;
  var readEpsCount = 0;
  if (!isDownload && chapter != null) {
    const repository = DownloadTaskRepository();
    final local =
        repository.findDownloadedChapter(
          from: from,
          comicId: comicId,
          chapterKey: chapter.id,
        ) ??
        repository.findDownloadedChapter(
          from: from,
          comicId: comicId,
          chapterKey: chapter.effectiveRequestId,
        );
    final record = local == null
        ? null
        : repository.findDownloadRecord(from, comicId);
    if (local != null && record != null) {
      readInfo = record;
      readIsDownload = true;
      readComicId = record.comicId;
      readChapter = local;
      readEpsCount = resolveStoredDownloadChapters(record).length;
    }
  }
  if (!readIsDownload) {
    readEpsCount = resolveReadEpsCount(allInfo, from, isDownload: false);
    readComicId = resolveReadComicId(allInfo, from, isDownload: false);
  } else if (readInfo == allInfo) {
    readEpsCount = resolveReadEpsCount(allInfo, from, isDownload: true);
    readComicId = resolveReadComicId(allInfo, from, isDownload: true);
  }
  final typeVal = hasHistory
      ? (readIsDownload
            ? ComicEntryType.historyAndDownload
            : ComicEntryType.history)
      : (readIsDownload ? ComicEntryType.download : ComicEntryType.normal);
  final orderVal = readChapter?.order ?? _resolveInitialOrder(readInfo, from);

  context.pushRoute(
    ComicReadRoute(
      comicId: readComicId,
      order: orderVal,
      chapterId: readChapter?.id ?? '',
      requestId: readChapter?.effectiveRequestId ?? '',
      storageChapterId: readChapter?.effectiveStorageId ?? '',
      logicalKey: readChapter?.id ?? '',
      chapterExtern: ChapterExtern.from(
        readChapter?.extern ?? const <String, dynamic>{},
      ),
      epsNumber: readEpsCount,
      from: from,
      type: typeVal,
      comicInfo: readInfo,
      stringSelectCubit: stringSelectCubit,
    ),
  );
}

DownloadChapter? _resolveChapter(
  dynamic allInfo,
  String from,
  UnifiedComicHistory? history,
) {
  final chapterRefs = resolveUnifiedComicChapters(allInfo, from);
  if (chapterRefs.isEmpty) {
    return null;
  }

  const adapter = DownloadChapterAdapter();
  const matcher = DownloadChapterMatcher();
  final chapters = chapterRefs.map(adapter.fromChapterRef).toList();

  if (history != null) {
    // 优先按 history.chapterId 匹配（可能是 logicalKey / id / requestId）。
    final chapterId = (history.chapterId).trim();
    if (chapterId.isNotEmpty) {
      final matched = matcher.find(chapters, chapterId);
      if (matched != null) {
        return matched;
      }
    }

    // 再按 history.chapterOrder 匹配。
    if (history.chapterOrder > 0) {
      final matched = matcher.findByOrder(chapters, history.chapterOrder);
      if (matched != null) {
        return matched;
      }
    }

    // 兼容老数据：chapterOrder 曾经被当 chapterId 用。
    final matched = matcher.find(chapters, history.chapterOrder.toString());
    if (matched != null) {
      return matched;
    }
  }

  return chapters.first;
}

int _resolveInitialOrder(dynamic allInfo, String from) {
  final chapters = resolveUnifiedComicChapters(allInfo, from);
  if (chapters.isEmpty) {
    return 1;
  }
  return chapters.first.order;
}
