import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

import 'test_helper.dart';

const _repo = DownloadTaskRepository();

/// 造一行单章节下载任务，形状与库里真实行一致（payload 直接写进 dbTaskInfoStr）。
DownloadTask _row({
  required String chapterKey,
  required String stateCode,
  required bool isCompleted,
  bool isDownloading = false,
  int completedImages = 0,
  int totalImages = 0,
}) {
  final payload = DownloadTaskJson(
    from: 'plugin_a',
    comicId: 'comic_1',
    comicName: '测试漫画',
    chapterRef: DownloadChapterTaskRef(
      chapterId: chapterKey,
      logicalKey: chapterKey,
      title: chapterKey,
    ),
    stateCode: stateCode,
    completedImages: completedImages,
    totalImages: totalImages,
  );
  return DownloadTask()
    ..comicId = payload.comicId
    ..comicName = payload.comicName
    ..status = stateCode
    ..isCompleted = isCompleted
    ..isDownloading = isDownloading
    ..dbTaskInfoStr = jsonEncode(payload.toJson());
}

String? _stateCodeOf(DownloadTask task) => _repo.readPayload(task)?.stateCode;

void main() {
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  setUp(() => objectbox.downloadTaskBox.removeAll());

  group('下载任务批量操作', () {
    test('全部暂停把没暂停的都落进暂停态，已暂停的不动', () async {
      objectbox.downloadTaskBox.putMany([
        _row(chapterKey: 'queued', stateCode: 'queued', isCompleted: false),
        _row(chapterKey: 'failed', stateCode: 'failed', isCompleted: false),
        _row(
          chapterKey: 'paused',
          stateCode: 'paused',
          isCompleted: false,
          isDownloading: false,
        ),
      ]);

      expect(await DownloadQueueManager.instance.pauseAllTasks(), 2);

      final byKey = {
        for (final task in objectbox.downloadTaskBox.getAll())
          _repo.readPayload(task)?.chapterRef.logicalKey: _stateCodeOf(task),
      };
      expect(byKey, {
        'queued': 'paused',
        'failed': 'paused',
        'paused': 'paused',
      });
      // 暂停是断点保留，不是取消：行必须还在队列里。
      expect(
        objectbox.downloadTaskBox.getAll().map((task) => task.isCompleted),
        everyElement(isFalse),
      );
    });

    test('全部取消摘掉排队与暂停的行，已完成的历史行不受影响', () async {
      objectbox.downloadTaskBox.putMany([
        _row(chapterKey: 'queued', stateCode: 'queued', isCompleted: false),
        _row(chapterKey: 'paused', stateCode: 'paused', isCompleted: false),
        _row(chapterKey: 'done', stateCode: 'completed', isCompleted: true),
      ]);

      expect(await DownloadQueueManager.instance.cancelAllTasks(), 2);

      final left = objectbox.downloadTaskBox.getAll();
      expect(
        left.map((task) => _repo.readPayload(task)?.chapterRef.logicalKey),
        ['done'],
      );
    });

    test('全部开始只作用于暂停态的行，失败行仍等「重试」', () async {
      objectbox.downloadTaskBox.putMany([
        _row(chapterKey: 'paused', stateCode: 'paused', isCompleted: false),
        _row(chapterKey: 'failed', stateCode: 'failed', isCompleted: false),
      ]);

      expect(await DownloadQueueManager.instance.resumeAllTasks(), 1);

      String? codeOf(String logicalKey) {
        final task = objectbox.downloadTaskBox.getAll().firstWhere(
          (task) =>
              _repo.readPayload(task)?.chapterRef.logicalKey == logicalKey,
        );
        return _stateCodeOf(task);
      }

      // 放回队列后调度器会立刻认领它，这里只断言「不再是暂停态」。
      expect(codeOf('paused'), isNot('paused'));
      expect(codeOf('failed'), 'failed');
    });

    test('重试失败项只重排队失败那一行，暂停行留在原地（阴性对照）', () async {
      objectbox.downloadTaskBox.putMany([
        _row(
          chapterKey: 'failed',
          stateCode: 'failed',
          isCompleted: false,
          completedImages: 7,
          totalImages: 20,
        ),
        _row(
          chapterKey: 'paused',
          stateCode: 'paused',
          isCompleted: false,
          completedImages: 5,
          totalImages: 20,
        ),
      ]);

      expect(await DownloadQueueManager.instance.retryAllFailedTasks(), 1);

      DownloadTask row(String logicalKey) =>
          objectbox.downloadTaskBox.getAll().firstWhere(
            (task) =>
                _repo.readPayload(task)?.chapterRef.logicalKey == logicalKey,
          );

      // 与单行重试同一套语义：脱离失败态、已完成图片清零，从头重跑。
      final retried = _repo.readPayload(row('failed'))!;
      expect(retried.stateCode, isNot('failed'));
      expect(retried.completedImages, 0);
      // 暂停的断点不该被批量重试顺手扔掉。
      final untouched = _repo.readPayload(row('paused'))!;
      expect(untouched.stateCode, 'paused');
      expect(untouched.completedImages, 5);
    });
  });
}
