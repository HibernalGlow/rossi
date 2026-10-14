part of 'download_queue_manager.dart';

/// 「优先下载这一章」：把某一行挪到本轮启动顺序的最前面。
///
/// 只改排序意图，不动任务状态 —— 与暂停/恢复/重试那几件不同，这里没有状态迁移，
/// 所以也不碰 payload。那张表落在设备本地的 SharedPreferences
/// （[DownloadTaskPinStore]），队列里已经没有了的 key 会在每次写入前被
/// [prunePinnedKeys] 清掉，不留僵尸置顶。
extension DownloadQueuePriorityTaskOps on DownloadQueueManager {
  /// 队首在前的置顶 chapterKey 列表；页面用它把行排成与调度同一个顺序。
  List<String> pinnedTaskKeys() => _pinnedTaskKeys;

  /// 把这一行排到队首。返回 false 表示那一行已经不在队列里了（没有可置顶的对象）。
  Future<bool> pinTaskFirst(int taskId) => _rewritePinOrder(taskId, pin: true);

  /// 取消某一行的置顶（同一颗按钮再点一次）。
  Future<bool> unpinTask(int taskId) => _rewritePinOrder(taskId, pin: false);

  Future<bool> _rewritePinOrder(int taskId, {required bool pin}) async {
    final repository = DownloadQueueManager._taskRepository;
    // 一次遍历同时拿到「这一行在不在」与「还剩哪些 key 值得置顶」：
    // 前者决定这次动作有没有对象，后者用来清掉已经不存在的置顶项。
    DownloadTask? target;
    final queuedKeys = <String>{};
    for (final task in repository.getAll(incompleteOnly: true)) {
      if (task.id == taskId) target = task;
      final key = downloadTaskKeyOf(task);
      if (key.isNotEmpty) queuedKeys.add(key);
    }

    final task = target;
    if (task == null) return false;
    final key = downloadTaskKeyOf(task);
    if (key.isEmpty) return false;

    await _ensurePinnedOrderLoaded();
    final current = _pinnedTaskKeys;
    final next = pin
        ? pinTaskKey(pinnedKeys: current, key: key)
        : [...current.where((existing) => existing != key)];
    await _writePinnedOrder(
      prunePinnedKeys(pinnedKeys: next, queuedKeys: queuedKeys),
    );
    return true;
  }

  /// 读一次置顶表。并发调用里只有第一个真去读，其余可能拿到还没填好的空表 ——
  /// 那只是本轮按入队顺序启动，下一轮就跟上；置顶本身不会丢。
  Future<void> _ensurePinnedOrderLoaded() async {
    if (_pinnedOrderLoaded) return;
    _pinnedOrderLoaded = true;
    _pinnedTaskKeys = await DownloadQueueManager._pinStore.read();
  }

  Future<void> _writePinnedOrder(List<String> keys) async {
    _pinnedTaskKeys = keys;
    await DownloadQueueManager._pinStore.write(keys);
  }
}
