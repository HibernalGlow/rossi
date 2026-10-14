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
import 'package:zephyr/service/download/download_chapter_gate.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「下载最近 N 章」的默认章数（选择面板里也是这一档被预选中）。
const kDefaultLatestDownloadCount = 25;

/// 选择面板上「下载最近 N 章」可挑的档。
const kLatestDownloadCountChoices = <int>[10, 25, 50];

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

/// 单章节 → 单章节下载任务。
///
/// 上游把任务模型改成「一个任务一章」后，这是全仓唯一的章节任务构造点：
/// 详情页整本下载、阅读器下载按钮、章节选择页的「开始下载」都走这里，
/// 避免多处字段映射各自漂移。
///
/// [taskExtern] 是**调用方**附加的选项（例如详情页胶囊发起的「官方 ZIP 下载」），
/// 会和插件自己的章节 extern 合并后写进任务，最终原样带回插件的 `getChapter`。
/// 同名键以调用方的为准 —— 那是这次点击明确要的表达。
DownloadTaskJson buildChapterDownloadTask({
  required String from,
  required String comicId,
  required String comicName,
  required DownloadChapter chapter,
  Map<String, dynamic>? taskExtern,
}) {
  return DownloadTaskJson(
    from: from,
    comicId: comicId,
    comicName: comicName,
    chapterRef: DownloadChapterTaskRef(
      chapterId: chapter.id,
      requestId: chapter.effectiveRequestId,
      storageChapterId: chapter.effectiveStorageId,
      logicalKey: chapter.id,
      title: chapter.displayName,
      order: chapter.order,
      extern: {...chapter.extern, ...?taskExtern},
    ),
  );
}

/// 「整本下载」= 每个章节一个任务，一次性入队；章节为空时返回空列表。
List<DownloadTaskJson> buildDownloadAllTasks({
  required String from,
  required String comicId,
  required String comicName,
  required List<DownloadChapter> chapters,
  Map<String, dynamic>? taskExtern,
}) {
  return chapters
      .map(
        (chapter) => buildChapterDownloadTask(
          from: from,
          comicId: comicId,
          comicName: comicName,
          chapter: chapter,
          taskExtern: taskExtern,
        ),
      )
      .toList();
}

/// 整本下载在入队前该建的那批任务：先一章一任务，再过统一的章节闸门。
///
/// 抽成纯函数是因为 `startComicDownloadAll` 要 `BuildContext`、toast 与 ObjectBox，
/// 而「第 3 章已经在硬盘上了，到底还建不建任务」这个决定必须能单独问。
DownloadEnqueuePlan planComicDownloadAllTasks({
  required String from,
  required String comicId,
  required String comicName,
  required List<DownloadChapter> chapters,
  required Set<String> downloadedIds,
  bool forceRedownload = false,
  Map<String, dynamic>? taskExtern,
}) {
  return planDownloadEnqueue(
    buildDownloadAllTasks(
      from: from,
      comicId: comicId,
      comicName: comicName,
      chapters: chapters,
      taskExtern: taskExtern,
    ),
    downloadedIds: downloadedIds,
    forceRedownload: forceRedownload,
  );
}

/// 从一批章节里取「最新 N 章」，返回值仍按章节正序排列。
///
/// 排序用 [DownloadChapter.order]（插件给的章节序号）倒序取，够用且不需要额外
/// 拉一次详情；拿不到 order 的插件会全 0，这时退化成按传入顺序取前 N 章 ——
/// 传入顺序本身就是章节表的显示顺序，不是随机数。
List<DownloadChapter> selectLatestDownloadChapters(
  List<DownloadChapter> chapters, {
  required int count,
}) {
  if (count <= 0 || chapters.isEmpty) return const <DownloadChapter>[];
  if (count >= chapters.length) return List.of(chapters);
  final hasOrder = chapters.any((chapter) => chapter.order != 0);
  if (!hasOrder) {
    return chapters.sublist(chapters.length - count);
  }
  final newest = [...chapters]..sort((a, b) => b.order.compareTo(a.order));
  final picked = newest.take(count).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return picked;
}

/// 下载「最近 N 章」：解析章节 → 取最新 N 章 → 过闸门 → 入队。
///
/// 放在入口层而不是页面上，是因为列表卡片那个下载按钮手上没有章节表：
/// 章节解析必须在这条路径里自己兜住（回源拉一次详情），否则这个入口在卡片上
/// 就成了摆设。跳过已下载与批内去重走的是同一道闸门。
Future<bool> startComicDownloadLatest({
  required BuildContext context,
  required String from,
  required String comicId,
  required String comicName,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
  int count = kDefaultLatestDownloadCount,
  bool autoFavorite = true,
  bool forceRedownload = false,
  Map<String, dynamic>? taskExtern,
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
  final chapters = selectLatestDownloadChapters(
    refs.map(adapter.fromChapterRef).toList(),
    count: count,
  );
  if (chapters.isEmpty) {
    showErrorToast(t.error.operationFailed);
    return false;
  }

  final record = const DownloadTaskRepository().findDownloadRecord(
    from,
    comicId,
  );
  final plan = planComicDownloadAllTasks(
    from: from,
    comicId: comicId,
    comicName: comicName,
    chapters: chapters,
    downloadedIds: downloadedChapterIdsOf(record),
    forceRedownload: forceRedownload,
    taskExtern: taskExtern,
  );
  if (plan.isEmpty) {
    showSuccessToast(
      t.download.skippedAlreadyDownloaded(count: plan.skippedDownloaded),
    );
    return true;
  }

  try {
    await startDownloadTasks(plan.tasks);
    showSuccessToast(
      plan.skippedDownloaded > 0
          ? t.download.startedWithSkipped(
              started: plan.tasks.length,
              skipped: plan.skippedDownloaded,
            )
          : t.reader.downloadStartedToast,
    );
    return true;
  } catch (e) {
    showErrorToast(
      t.download.taskStartFailed(error: normalizeSearchErrorMessage(e)),
    );
    return false;
  }
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
  bool forceRedownload = false,
  Map<String, dynamic>? taskExtern,
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
  final chapters = refs.map(adapter.fromChapterRef).toList();
  if (chapters.isEmpty) {
    showErrorToast(t.error.operationFailed);
    return false;
  }

  // 整本下载过去完全不判「本地已有」：已下完的章也会重新建任务、重新请求章节信息。
  // 闸门在入队之前，所以这里的默认策略就是「跳过已下载」；forceRedownload
  // 只在用户明确要重取的那条路径上给（不是批量默认）。
  final record = const DownloadTaskRepository().findDownloadRecord(
    from,
    comicId,
  );
  final plan = planComicDownloadAllTasks(
    from: from,
    comicId: comicId,
    comicName: comicName,
    chapters: chapters,
    downloadedIds: downloadedChapterIdsOf(record),
    forceRedownload: forceRedownload,
    taskExtern: taskExtern,
  );
  if (plan.isEmpty) {
    showSuccessToast(
      t.download.skippedAlreadyDownloaded(count: plan.skippedDownloaded),
    );
    return true;
  }

  try {
    await startDownloadTasks(plan.tasks);
    showSuccessToast(
      plan.skippedDownloaded > 0
          ? t.download.startedWithSkipped(
              started: plan.tasks.length,
              skipped: plan.skippedDownloaded,
            )
          : t.reader.downloadStartedToast,
    );
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
