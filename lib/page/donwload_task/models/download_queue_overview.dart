import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_task_repository.dart';

/// 队列剩余工作量：一行摘要，不是一堆计数器。
///
/// 只统计**未完成**的任务（页面拿到的就是 `isCompleted == false` 那批），
/// 所以「还剩几章」与「已下几页」说的是这一批还要跑多少，不把历史完成行算进来。
class DownloadQueueOverview {
  const DownloadQueueOverview({
    required this.remainingTasks,
    required this.running,
    required this.paused,
    required this.failed,
    required this.completedImages,
    required this.totalImages,
  });

  /// 未完成的任务（章）数。
  final int remainingTasks;

  final int running;
  final int paused;
  final int failed;

  /// 已完成图片数与已声明的图片总数；总数为 0 表示插件还没报过章节页数。
  final int completedImages;
  final int totalImages;

  /// 有没有可显示的页级进度：只有 `totalImages > 0` 时那句「已下 x/y 页」才为真。
  bool get hasPageProgress => totalImages > 0;
}

/// 逐行读 payload 汇总队列。payload 读不出来的残留行只算进 `remainingTasks`，
/// 不参与页数与状态计数 —— 它们的状态本来就不可知，别把猜的数当读数。
DownloadQueueOverview summarizeDownloadQueue(List<DownloadTask> tasks) {
  const repository = DownloadTaskRepository();
  var running = 0;
  var paused = 0;
  var failed = 0;
  var completedImages = 0;
  var totalImages = 0;

  for (final task in tasks) {
    final payload = repository.readPayload(task);
    if (payload == null) continue;
    if (task.isDownloading) {
      running++;
    } else {
      switch (payload.stateCode) {
        case 'paused':
          paused++;
        case 'failed':
          failed++;
        default:
          break;
      }
    }
    final total = payload.totalImages;
    if (total <= 0) continue;
    totalImages += total;
    completedImages += payload.completedImages.clamp(0, total);
  }

  return DownloadQueueOverview(
    remainingTasks: tasks.length,
    running: running,
    paused: paused,
    failed: failed,
    completedImages: completedImages,
    totalImages: totalImages,
  );
}
