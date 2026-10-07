import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

import 'test_helper.dart';

const _repo = DownloadTaskRepository();

/// 造一行下载任务。直接写 [DownloadTask.dbTaskInfoStr]，绕开瞬态 payload 缓存，
/// 这样非法 JSON 也能塞进去（跨进程残留里就可能有这种行）。
DownloadTask _row({
  required String chapterKey,
  required String status,
  required bool isCompleted,
  bool isDownloading = false,
  String stateCode = 'running',
  String? payloadJsonOverride,
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
  );
  return DownloadTask()
    ..comicId = payload.comicId
    ..comicName = payload.comicName
    ..status = status
    ..isCompleted = isCompleted
    ..isDownloading = isDownloading
    ..dbTaskInfoStr =
        payloadJsonOverride ?? jsonEncode(payload.toJson());
}

void main() {
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  setUp(() => objectbox.downloadTaskBox.removeAll());

  group('取消残留行清理', () {
    test('上次进程留下的「取消中」行被摘掉并回传 taskKey', () {
      objectbox.downloadTaskBox.put(
        _row(chapterKey: 'ch1', status: '取消中...', isCompleted: true),
      );

      expect(_repo.removeCancelledTaskRecords(), ['plugin_a:comic_1:ch1']);
      expect(objectbox.downloadTaskBox.getAll(), isEmpty);
    });

    test('payload 已标 cancelled 时，状态文字被后续进度覆盖也照样摘掉', () {
      objectbox.downloadTaskBox.put(
        _row(
          chapterKey: 'ch2',
          status: '当前章节下载进度: 42%',
          isCompleted: true,
          stateCode: 'cancelled',
        ),
      );

      expect(_repo.removeCancelledTaskRecords(), ['plugin_a:comic_1:ch2']);
    });

    test('英文状态下同样被识别', () {
      objectbox.downloadTaskBox.put(
        _row(chapterKey: 'ch3', status: 'Cancelling...', isCompleted: true),
      );

      expect(_repo.removeCancelledTaskRecords(), ['plugin_a:comic_1:ch3']);
    });

    test('正常完成与失败/暂停的行都不被误删（判据的阴性对照）', () {
      objectbox.downloadTaskBox.putMany([
        _row(
          chapterKey: 'done',
          status: '当前章节下载进度: 100%',
          isCompleted: true,
          stateCode: 'completed',
        ),
        _row(
          chapterKey: 'failed',
          status: '下载失败',
          isCompleted: false,
          stateCode: 'failed',
        ),
        _row(
          chapterKey: 'paused',
          status: '已暂停',
          isCompleted: false,
          stateCode: 'paused',
        ),
      ]);

      expect(_repo.removeCancelledTaskRecords(), isEmpty);
      expect(objectbox.downloadTaskBox.getAll(), hasLength(3));
    });

    test('未完成的行不在本次清理范围内', () {
      objectbox.downloadTaskBox.put(
        _row(
          chapterKey: 'pending',
          status: '取消中...',
          isCompleted: false,
          isDownloading: true,
        ),
      );

      expect(_repo.removeCancelledTaskRecords(), isEmpty);
      expect(objectbox.downloadTaskBox.getAll(), hasLength(1));
    });

    test('payload 损坏时仍按状态文字摘掉，taskKey 回退到 comicId', () {
      objectbox.downloadTaskBox.put(
        _row(
          chapterKey: 'broken',
          status: '取消中...',
          isCompleted: true,
          payloadJsonOverride: '{not json',
        ),
      );

      expect(_repo.removeCancelledTaskRecords(), ['comic_1']);
      expect(objectbox.downloadTaskBox.getAll(), isEmpty);
    });

    test('启动入口 resetStuckTasks 会把残留行摘掉，且临时文件清理失败也不影响', () {
      // 与库里真实那行同形状：取消态只落在 status，payload 还停在 running。
      objectbox.downloadTaskBox.put(
        _row(chapterKey: 'ch9', status: '取消中...', isCompleted: true),
      );
      // 下载中的未完成行是重启要保住的。
      objectbox.downloadTaskBox.put(
        _row(
          chapterKey: 'live',
          status: '当前章节下载进度: 0%',
          isCompleted: false,
          isDownloading: true,
        ),
      );

      // flutter test 下 path_provider 通道不可用，清理临时文件必然抛；
      // 这一步不能把启动兜底带崩，删行必须已经同步完成。
      DownloadQueueManager.instance.resetStuckTasks();

      expect(objectbox.downloadTaskBox.getAll(), hasLength(1));
      final live = objectbox.downloadTaskBox.getAll().single;
      expect(live.isDownloading, isFalse);
      expect(_repo.readPayload(live)?.stateCode, 'queued');
    });
  });
}
