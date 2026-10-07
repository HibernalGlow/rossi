import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/service/download/download_task_scheduler.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

DownloadTask _task(String chapterId) {
  final payload = DownloadTaskJson(
    from: 'plugin-a',
    comicId: 'comic/1',
    comicName: '测试漫画',
    chapterRef: DownloadChapterTaskRef(
      chapterId: chapterId,
      title: chapterId,
      order: 1,
    ),
  );
  return DownloadTask()
    ..comicId = payload.comicId
    ..comicName = payload.comicName
    ..isCompleted = false
    ..isDownloading = false
    ..status = ''
    ..taskInfo = payload;
}

void main() {
  test('额度为 0 时不启动任何任务', () {
    expect(
      selectDownloadTasksToStart(
        pendingTasks: [_task('ch-1')],
        runningTaskKeys: const {},
        capacity: 0,
      ),
      isEmpty,
    );
  });

  test('按传入顺序取满额度', () {
    final tasks = [_task('ch-1'), _task('ch-2'), _task('ch-3')];
    final picked = selectDownloadTasksToStart(
      pendingTasks: tasks,
      runningTaskKeys: const {},
      capacity: 2,
    );
    expect(picked.map((task) => task.taskInfo!.chapterRef.chapterId).toList(), [
      'ch-1',
      'ch-2',
    ]);
  });

  test('跳过已在跑的章节', () {
    final tasks = [_task('ch-1'), _task('ch-2')];
    final picked = selectDownloadTasksToStart(
      pendingTasks: tasks,
      runningTaskKeys: {downloadTaskKeyOf(tasks.first)},
      capacity: 2,
    );
    expect(picked.map((task) => task.taskInfo!.chapterRef.chapterId).toList(), [
      'ch-2',
    ]);
  });

  test('同一批里的重复行只启动一次', () {
    final task = _task('ch-1');
    final picked = selectDownloadTasksToStart(
      pendingTasks: [task, task],
      runningTaskKeys: const {},
      capacity: 5,
    );
    expect(picked.length, 1);
  });

  test('取不出 taskKey 的残行不启动', () {
    final broken = DownloadTask()
      ..comicId = ''
      ..comicName = '损坏行'
      ..isCompleted = false
      ..isDownloading = false
      ..status = '';
    final picked = selectDownloadTasksToStart(
      pendingTasks: [broken, _task('ch-1')],
      runningTaskKeys: const {},
      capacity: 5,
    );
    expect(picked.length, 1);
    expect(picked.single.taskInfo, isNotNull);
  });
}
