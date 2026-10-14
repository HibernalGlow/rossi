import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_task_order.dart';
import 'package:zephyr/service/download/download_task_repository.dart';

/// 从待处理任务里挑出本轮要启动的任务。
///
/// 顺序交给 [sortDownloadTasksForStart]：置顶的先、其余按传入顺序（调用方已按 id
/// 升序）。跳过：已在跑的、taskKey 取不出的、以及同一批里重复的行；最多
/// [capacity] 个。调度占位与挑选分离，调用方拿返回值后必须同步把 key 记进
/// 「正在跑」集合，避免重复启动。
List<DownloadTask> selectDownloadTasksToStart({
  required Iterable<DownloadTask> pendingTasks,
  required Set<String> runningTaskKeys,
  required int capacity,
  List<String> pinnedKeys = const <String>[],
}) {
  if (capacity <= 0) return const [];

  final tasksByKey = <String, DownloadTask>{};
  final rows = <DownloadTaskOrderRow>[];
  for (final task in pendingTasks) {
    final key = downloadTaskKeyOf(task);
    if (key.isEmpty || runningTaskKeys.contains(key)) continue;
    // 同一章在待处理里出现两次（旧行未清）时以第一条为准，与摘掉重复的行为一致。
    if (tasksByKey.putIfAbsent(key, () => task) != task) continue;
    rows.add((id: task.id, key: key));
  }

  final picked = <DownloadTask>[];
  for (final row in sortDownloadTasksForStart(
    rows: rows,
    pinnedKeys: pinnedKeys,
  )) {
    picked.add(tasksByKey[row.key]!);
    if (picked.length >= capacity) break;
  }
  return picked;
}
