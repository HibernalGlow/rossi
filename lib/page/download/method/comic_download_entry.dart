import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「下载」入口单击后的去向。
enum ComicDownloadEntryAction {
  /// 直接下载整本（全部章节），不进章节选择页。
  downloadAll,

  /// 进入章节选择页。
  openChapterPicker,
}

/// 判定「下载」入口单击时应该做什么。
///
/// 口径：**默认直接下载整本**；只有用户「主动点击」时才进章节选择页 ——
/// 也就是这本漫画已经有下载记录或下载任务（此时点击语义变成「管理已有下载」，
/// 进选择页既能补章节，也不会无脑重下一遍）。
///
/// 长按入口不经过本函数：长按始终进章节选择页（见调用方）。
ComicDownloadEntryAction resolveComicDownloadEntryAction({
  required bool hasDownloadRecord,
  required bool hasDownloadTask,
}) {
  if (hasDownloadRecord || hasDownloadTask) {
    return ComicDownloadEntryAction.openChapterPicker;
  }
  return ComicDownloadEntryAction.downloadAll;
}

/// 该漫画是否已有落盘记录（下载完成后写入 `unifiedDownloadBox`）。
bool hasComicDownloadRecord({required String from, required String comicId}) {
  final key = buildDownloadTaskKey(from, comicId);
  final record = objectbox.unifiedDownloadBox
      .query(UnifiedComicDownload_.uniqueKey.equals(key))
      .build()
      .findFirst();
  return record != null;
}

/// 该漫画是否已有下载任务（排队 / 下载中 / 暂停 / 失败 / 已完成）。
bool hasComicDownloadTask({required String from, required String comicId}) {
  return DownloadQueueManager.instance.getTaskByComic(from, comicId) != null;
}

/// 由章节列表构造「整本下载」任务 payload；章节为空时返回 null。
///
/// 这是全仓唯一的整本任务构造点：详情页直接下载、阅读器下载按钮、
/// 章节选择页的「开始下载」都走这里，避免三处字段映射各自漂移。
DownloadTaskJson? buildDownloadAllTask({
  required String from,
  required String comicId,
  required String comicName,
  required List<DownloadChapter> chapters,
}) {
  if (chapters.isEmpty) {
    return null;
  }

  return DownloadTaskJson(
    from: from,
    comicId: comicId,
    comicName: comicName,
    chapterRefs: chapters
        .map(
          (chapter) => DownloadChapterTaskRef(
            chapterId: chapter.id,
            requestId: chapter.effectiveRequestId,
            storageChapterId: chapter.effectiveStorageId,
            logicalKey: chapter.id,
            title: chapter.displayName,
            order: chapter.order,
            extern: Map<String, dynamic>.from(chapter.extern),
          ),
        )
        .toList(),
  );
}

/// 解析本次整本下载可用的章节引用。
///
/// 依次尝试：调用方显式传入 → 从 `comicInfo` 解析 → 回源向插件拉一次详情。
Future<List<UnifiedComicChapterRef>> resolveDownloadChapterRefs({
  required String from,
  required String comicId,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
}) async {
  var resolved = chapterRefs ?? const <UnifiedComicChapterRef>[];
  if (resolved.isEmpty && comicInfo != null) {
    resolved = resolveUnifiedComicChapters(comicInfo, from);
  }
  if (resolved.isEmpty) {
    try {
      final detail = await getComicDetailByPlugin(
        comicId,
        from,
        pluginId: from,
      );
      resolved = resolveUnifiedComicChapters(detail.source, from);
    } catch (e) {
      logger.e('解析章节列表失败: $e');
    }
  }
  return resolved;
}

/// 直接开始整本漫画的下载（全部章节）。
///
/// 返回是否成功排队。失败时已弹出提示，调用方不必重复提示。
Future<bool> startComicDownloadAll({
  required BuildContext context,
  required String from,
  required String comicId,
  required String comicName,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
  bool autoFavorite = true,
}) async {
  if (autoFavorite) {
    await autoFavoriteComicOnDownloadIfEnabled(
      from: from,
      comicId: comicId,
      comicInfo: comicInfo,
      context: context,
    );
  }

  final refs = await resolveDownloadChapterRefs(
    from: from,
    comicId: comicId,
    comicInfo: comicInfo,
    chapterRefs: chapterRefs,
  );
  if (refs.isEmpty) {
    showErrorToast(t.error.operationFailed);
    return false;
  }

  const adapter = DownloadChapterAdapter();
  final task = buildDownloadAllTask(
    from: from,
    comicId: comicId,
    comicName: comicName,
    chapters: refs.map(adapter.fromChapterRef).toList(),
  );
  if (task == null) {
    showErrorToast(t.error.operationFailed);
    return false;
  }

  try {
    await startDownloadTask(task);
    showSuccessToast(t.reader.downloadStartedToast);
    return true;
  } catch (e) {
    showErrorToast(
      t.download.taskStartFailed(error: normalizeSearchErrorMessage(e)),
    );
    return false;
  }
}

/// 下载按钮/角标的视觉状态。
enum ComicDownloadVisualState {
  /// 没下过：点一下直接下载整本。
  notDownloaded,
  downloading,
  paused,
  failed,

  /// 已下过：点一下进章节选择页（管理 / 补章节）。
  completed,
}

/// 单一真源：任务状态 + 落盘记录 → 视觉状态。
///
/// 详情页的下载卡片和列表卡片封面上的下载角标都走这里，
/// 免得两处对「暂停算不算下载中」「记录在但任务没了算什么」各判一套。
ComicDownloadVisualState resolveComicDownloadVisualState({
  required bool isDownloading,
  required bool isCompleted,
  required String stateCode,
  required bool hasRecord,
}) {
  if (isDownloading) return ComicDownloadVisualState.downloading;
  if (stateCode == 'paused') return ComicDownloadVisualState.paused;
  if (stateCode == 'failed') return ComicDownloadVisualState.failed;
  if (isCompleted || hasRecord) return ComicDownloadVisualState.completed;
  return ComicDownloadVisualState.notDownloaded;
}

/// 从列表卡片进「章节选择页」。
///
/// 卡片上只有封面和标题、没有章节数据，所以这里回源问一次插件详情，
/// 拿到章节列表再推 [DownloadRoute]。拉取失败只提示，不推页面。
Future<void> openComicDownloadChapterPicker(
  BuildContext context, {
  required String from,
  required String comicId,
}) async {
  try {
    final detail = await getComicDetailByPlugin(comicId, from, pluginId: from);
    final info = resolveUnifiedDownloadInfo(detail.source, from);
    if (!context.mounted) return;
    context.pushRoute(DownloadRoute(downloadInfo: info));
  } catch (e, s) {
    logger.e('打开章节选择页失败', error: e, stackTrace: s);
    if (context.mounted) {
      showErrorToast(t.error.operationFailed);
    }
  }
}
