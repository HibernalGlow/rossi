import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/models/download_queue_overview.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

/// 造一行队列里的未完成任务；页数只在插件报过总数时才有意义。
DownloadTask _row({
  required String stateCode,
  bool isDownloading = false,
  int completedImages = 0,
  int totalImages = 0,
}) {
  final payload = DownloadTaskJson(
    from: 'plugin_a',
    comicId: 'comic_1',
    comicName: '测试漫画',
    chapterRef: DownloadChapterTaskRef(
      chapterId: stateCode,
      logicalKey: stateCode,
      title: stateCode,
    ),
    stateCode: stateCode,
    completedImages: completedImages,
    totalImages: totalImages,
  );
  return DownloadTask()
    ..comicId = payload.comicId
    ..status = stateCode
    ..isCompleted = false
    ..isDownloading = isDownloading
    ..dbTaskInfoStr = jsonEncode(payload.toJson());
}

/// 库里真实存在但 payload 读不出来的残留行。
DownloadTask _brokenRow() {
  return DownloadTask()
    ..comicId = 'comic_1'
    ..status = 'running'
    ..isCompleted = false
    ..dbTaskInfoStr = '{';
}

void main() {
  group('队列剩余概览', () {
    test('剩余章数按行数算，状态分档只看 payload 里的状态码', () {
      final overview = summarizeDownloadQueue([
        _row(stateCode: 'running', isDownloading: true),
        _row(stateCode: 'running', isDownloading: true),
        _row(stateCode: 'queued'),
        _row(stateCode: 'paused'),
        _row(stateCode: 'failed'),
      ]);

      expect(overview.remainingTasks, 5);
      expect(overview.running, 2);
      expect(overview.paused, 1);
      expect(overview.failed, 1);
    });

    test('下载中的行落在 running，不看它写的状态码是不是 paused', () {
      // 调度器认领一行后才置 isDownloading，状态码可能还没落笔；
      // 两处不一致时以「正在下」为准，否则概览会把在跑的任务说成暂停。
      final overview = summarizeDownloadQueue([
        _row(stateCode: 'paused', isDownloading: true),
      ]);

      expect(overview.running, 1);
      expect(overview.paused, 0);
    });

    test('页数只在插件报过总数时累加，越界的完成数被夹回总数', () {
      final overview = summarizeDownloadQueue([
        _row(stateCode: 'running', completedImages: 12, totalImages: 30),
        _row(stateCode: 'queued', completedImages: 0, totalImages: 20),
        // 还没请求到章节信息：不贡献总数，也不虚报已下页数。
        _row(stateCode: 'queued'),
        _row(stateCode: 'failed', completedImages: 40, totalImages: 8),
      ]);

      expect(overview.completedImages, 12 + 0 + 8);
      expect(overview.totalImages, 30 + 20 + 8);
      expect(overview.hasPageProgress, isTrue);
    });

    test('一本都没报过页数时 hasPageProgress 为假，界面就不该说「已下 x/y 页」', () {
      final overview = summarizeDownloadQueue([
        _row(stateCode: 'queued'),
        _row(stateCode: 'running', isDownloading: true),
      ]);

      expect(overview.totalImages, 0);
      expect(overview.completedImages, 0);
      expect(overview.hasPageProgress, isFalse);
    });

    test('读不出 payload 的残留行只算进剩余章数，不参与状态与页数', () {
      final overview = summarizeDownloadQueue([
        _brokenRow(),
        _row(stateCode: 'failed', completedImages: 3, totalImages: 10),
      ]);

      // 那行还在队列里，用户要能看到「还有 2 章没跑完」；
      // 但它处于什么状态、下了几页都是不可知的，不能靠猜填进摘要。
      expect(overview.remainingTasks, 2);
      expect(overview.running, 0);
      expect(overview.failed, 1);
      expect(overview.completedImages, 3);
      expect(overview.totalImages, 10);
    });

    test('空队列什么都不说', () {
      final overview = summarizeDownloadQueue(const []);

      expect(overview.remainingTasks, 0);
      expect(overview.running, 0);
      expect(overview.paused, 0);
      expect(overview.failed, 0);
      expect(overview.hasPageProgress, isFalse);
    });
  });
}
