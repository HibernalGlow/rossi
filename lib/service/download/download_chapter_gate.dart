import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

/// 所有批量下载入口共用的那道闸：这一章本地是不是已经有了，还要不要再建任务。
///
/// 判据只此一份：三键匹配（`id / requestId / order`）落在
/// [DownloadChapterMatcher] 上，章节身份怎么算落在 [DownloadChapterAdapter] 上，
/// 这里只负责「拿落盘记录的 id 集合去问那两个已有的判据」。此前详情页自己写了
/// 一套三键匹配、整本入口（`startComicDownloadAll`）**完全不判** —— 已下完的章节
/// 照样重新建任务、重新请求章节信息、重新走一遍收尾，只是图片层会复用一部分文件。
/// 匹配宽度不一致会让「跳过已下载」在不同入口给出不同结果，所以收成唯一一份。
///
/// 默认策略是**跳过已下载**；强制重新下载必须是调用方显式说出来的动作
/// （`forceRedownload: true`），因为那是用户主动动作，不是批量默认。
///
/// 「已经在队列里」不在这里判：`DownloadQueueManager.addTask` 已按 chapterKey
/// 对未完成任务判重（失败残留还会自动重排队），在这儿再写一套只会漂移。

/// 落盘记录里已下载的章节 id 集合；没有记录时为空集。
Set<String> downloadedChapterIdsOf(UnifiedComicDownload? record) {
  if (record == null) return const <String>{};
  return resolveDownloadChapters(record).map((chapter) => chapter.id).toSet();
}

const _chapterMatcher = DownloadChapterMatcher();

/// 章节模型版的身份匹配（详情页章节行用）：三个 key 任一命中即算已下载。
bool downloadChapterIsDownloaded({
  required Set<String> downloadedIds,
  required DownloadChapter chapter,
}) {
  return downloadedIds.any(
    (target) => _chapterMatcher.matches(chapter, target),
  );
}

/// 任务版身份匹配：先把任务里的 `chapterRef` 归一成章节模型，再走同一条判据。
///
/// 归一而不是另写一份，是因为 `chapterRef` 与落盘记录里的 `id` 用的不是同一套
/// 优先序（logicalKey > chapterId > requestId）；两边都过 [DownloadChapterAdapter]
/// 才不会「同一章在两个入口算出不同身份」。
bool downloadTaskIsDownloaded({
  required Set<String> downloadedIds,
  required DownloadTaskJson task,
}) {
  return downloadChapterIsDownloaded(
    downloadedIds: downloadedIds,
    chapter: const DownloadChapterAdapter().fromTaskRef(task.chapterRef),
  );
}

/// 一次入队决定的结果：真正要建的任务，以及两类被去掉的数量。
class DownloadEnqueuePlan {
  const DownloadEnqueuePlan({
    required this.tasks,
    required this.skippedDownloaded,
    required this.skippedDuplicate,
  });

  /// 通过闸门的任务，保持调用方给定的章节顺序。
  final List<DownloadTaskJson> tasks;

  /// 因「本地已有」被跳过的章数。
  final int skippedDownloaded;

  /// 同一批里重复出现的章数（同一 taskKey 只留第一条）。
  final int skippedDuplicate;

  bool get isEmpty => tasks.isEmpty;

  int get skippedTotal => skippedDownloaded + skippedDuplicate;
}

/// 入队前的统一筛选：跳过本地已下载的章，并对同一批去重。
///
/// [forceRedownload] 为真时「已下载」这一条不判（用户明确要重取损坏图片/
/// 更新内容），但批内去重照做 —— 同一章在一批里出现两次永远不是用户想要的。
DownloadEnqueuePlan planDownloadEnqueue(
  List<DownloadTaskJson> tasks, {
  required Set<String> downloadedIds,
  bool forceRedownload = false,
}) {
  final kept = <DownloadTaskJson>[];
  final seenKeys = <String>{};
  var skippedDownloaded = 0;
  var skippedDuplicate = 0;

  for (final task in tasks) {
    if (!seenKeys.add(task.taskKey)) {
      skippedDuplicate++;
      continue;
    }
    if (!forceRedownload &&
        downloadTaskIsDownloaded(downloadedIds: downloadedIds, task: task)) {
      skippedDownloaded++;
      continue;
    }
    kept.add(task);
  }

  return DownloadEnqueuePlan(
    tasks: kept,
    skippedDownloaded: skippedDownloaded,
    skippedDuplicate: skippedDuplicate,
  );
}
