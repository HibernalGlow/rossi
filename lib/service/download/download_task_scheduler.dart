import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_task_repository.dart';

/// 从待处理任务里挑出本轮要启动的任务。
///
/// 按传入顺序（调用方已按 id 升序）取，跳过：已在跑的、taskKey 取不出的、
/// 以及同一批里重复的行；最多 [capacity] 个。调度占位与挑选分离，调用方
/// 拿返回值后必须同步把 key 记进「正在跑」集合，避免重复启动。
List<DownloadTask> selectDownloadTasksToStart({
  required Iterable<DownloadTask> pendingTasks,
  required Set<String> runningTaskKeys,
  required int capacity,
}) {
  if (capacity <= 0) return const [];
  final picked = <DownloadTask>[];
  final seen = <String>{};
  for (final task in pendingTasks) {
    final key = downloadTaskKeyOf(task);
    if (key.isEmpty || runningTaskKeys.contains(key) || !seen.add(key)) {
      continue;
    }
    picked.add(task);
    if (picked.length >= capacity) break;
  }
  return picked;
}
