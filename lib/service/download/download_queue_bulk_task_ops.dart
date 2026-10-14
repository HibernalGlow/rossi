part of 'download_queue_manager.dart';

/// 下载任务页标题栏的三个批量操作：全部开始 / 全部暂停 / 全部取消。
///
/// 逐条复用单行任务的那套路径，所以与单行按钮语义完全一致：在跑的任务靠中断
/// 信号收尾（暂停保留断点散图，取消让 worker 删掉本章散图），排队中的任务直接
/// 改状态或摘行。一次批量 = 若干次单行操作，不引入第二套状态迁移。
extension DownloadQueueBulkTaskOps on DownloadQueueManager {
  /// 暂停所有还没暂停的未完成任务，返回真正被暂停的任务数。
  Future<int> pauseAllTasks() async {
    final pausedKeys = <String>{};
    for (final payload in _unfinishedTaskPayloads()) {
      if (payload.stateCode == 'paused') continue;
      if (pausedKeys.add(payload.taskKey)) {
        await _pauseTask(payload.taskKey);
      }
    }
    return pausedKeys.length;
  }

  /// 恢复所有停在暂停态的未完成任务，返回真正被恢复的任务数。
  Future<int> resumeAllTasks() async {
    final resumedKeys = <String>{};
    for (final payload in _unfinishedTaskPayloads()) {
      if (payload.stateCode != 'paused') continue;
      if (resumedKeys.add(payload.taskKey)) {
        await _resumeTask(payload.taskKey);
      }
    }
    return resumedKeys.length;
  }

  /// 取消所有未完成任务：在跑的走中断信号，排队与暂停的当场摘行。
  Future<int> cancelAllTasks() async {
    final tasks = DownloadQueueManager._taskRepository
        .getAll(incompleteOnly: true)
        .toList();
    for (final task in tasks) {
      await _cancelOrRemoveTask(task);
    }
    return tasks.length;
  }

  /// 把队列里所有失败任务重新排队（下载任务页的「重试失败项」）。
  ///
  /// 逐条走单行重试那条路径（状态复位成排队、已完成图片清零、清掉自动重试门），
  /// 所以「只重跑失败的那几章」与逐条点重试的结果一致；排队中与暂停的行不动 ——
  /// 它们本来就没失败，重排会把已经下了一半的进度白扔掉。
  Future<int> retryAllFailedTasks() async {
    final repository = DownloadQueueManager._taskRepository;
    final failedTasks = repository
        .getAll(incompleteOnly: true)
        .where((task) => repository.readPayload(task)?.stateCode == 'failed')
        .toList();
    for (final task in failedTasks) {
      await retryTask(task.id);
    }
    return failedTasks.length;
  }

  /// 未完成任务里 payload 读得出来的那部分；读不出来的行由单条任务的路径跳过。
  List<DownloadTaskJson> _unfinishedTaskPayloads() {
    final repository = DownloadQueueManager._taskRepository;
    return repository
        .getAll(incompleteOnly: true)
        .map(repository.readPayload)
        .whereType<DownloadTaskJson>()
        .toList();
  }
}
