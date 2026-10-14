import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/download/download_chapter_gate.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

DownloadTaskJson _task({
  required String chapterId,
  int order = 0,
  String? logicalKey,
  String? requestId,
}) {
  return DownloadTaskJson(
    from: 'plugin_a',
    comicId: 'comic_1',
    comicName: '测试漫画',
    chapterRef: DownloadChapterTaskRef(
      chapterId: chapterId,
      requestId: requestId ?? chapterId,
      logicalKey: logicalKey ?? chapterId,
      title: chapterId,
      order: order,
    ),
  );
}

DownloadChapter _chapter({
  required String id,
  String? requestId,
  int order = 0,
}) {
  return DownloadChapter(
    id: id,
    requestId: requestId,
    displayName: id,
    order: order,
    extern: const {},
    images: const [],
  );
}

void main() {
  group('章节下载闸门', () {
    test('没有落盘记录时身份集合为空，闸门不拦任何章', () {
      expect(downloadedChapterIdsOf(null), isEmpty);

      final plan = planDownloadEnqueue([
        _task(chapterId: 'ch-1'),
        _task(chapterId: 'ch-2'),
      ], downloadedIds: downloadedChapterIdsOf(null));
      expect(plan.tasks, hasLength(2));
      expect(plan.skippedDownloaded, 0);
    });

    test('身份按 id / 请求 key / order 三键命中任一即算已下载', () {
      const downloadedIds = {'7', '12'};

      expect(
        downloadChapterIsDownloaded(
          downloadedIds: downloadedIds,
          chapter: _chapter(id: '12'),
        ),
        isTrue,
      );
      expect(
        downloadChapterIsDownloaded(
          downloadedIds: downloadedIds,
          chapter: _chapter(id: 'x', requestId: '7'),
        ),
        isTrue,
      );
      expect(
        downloadChapterIsDownloaded(
          downloadedIds: downloadedIds,
          chapter: _chapter(id: 'y', requestId: '', order: 7),
        ),
        isTrue,
      );
      // 阴性对照：三键都不在集合里才算「没下过」。
      expect(
        downloadChapterIsDownloaded(
          downloadedIds: downloadedIds,
          chapter: _chapter(id: '9', requestId: '8', order: 1),
        ),
        isFalse,
      );
    });

    test('批量入队默认跳过本地已有的章，并保持顺序', () {
      final plan = planDownloadEnqueue(
        [
          _task(chapterId: 'ch-1'),
          _task(chapterId: 'ch-2'),
          _task(chapterId: 'ch-3'),
        ],
        downloadedIds: {'ch-2'},
      );

      expect(plan.tasks.map((task) => task.chapterRef.chapterId), [
        'ch-1',
        'ch-3',
      ]);
      expect(plan.skippedDownloaded, 1);
      expect(plan.skippedTotal, 1);
    });

    test('强制重新下载不跳已下载，但同一批里的重复章照样只留一条', () {
      final force = planDownloadEnqueue(
        [_task(chapterId: 'ch-1'), _task(chapterId: 'ch-2')],
        downloadedIds: {'ch-1', 'ch-2'},
        forceRedownload: true,
      );
      expect(force.tasks, hasLength(2));
      expect(force.skippedDownloaded, 0);

      final deduped = planDownloadEnqueue(
        [
          _task(chapterId: 'ch-1'),
          _task(chapterId: 'ch-1'),
          _task(chapterId: 'ch-2'),
        ],
        downloadedIds: const {},
        forceRedownload: true,
      );
      expect(deduped.tasks, hasLength(2));
      expect(deduped.skippedDuplicate, 1);
    });

    test('任务与记录两侧按同一优先序归一身份：logicalKey 命中即算已下载', () {
      // 落盘记录里那一章存的是 logicalKey，任务里的 chapterId 是插件的另一个写法。
      // 两侧都过 DownloadChapterAdapter 归一，所以「同一章」在两个入口算得出同一个身份；
      // 若任务侧只认 chapterId，这一章会被判成没下过并重新建任务。
      expect(
        downloadTaskIsDownloaded(
          downloadedIds: {'plugin-a:12'},
          task: _task(chapterId: '12', logicalKey: 'plugin-a:12'),
        ),
        isTrue,
      );
      // 阴性对照：归一后的身份与集合里没有任何一键相同。
      expect(
        downloadTaskIsDownloaded(
          downloadedIds: {'plugin-a:99'},
          task: _task(chapterId: '12', logicalKey: 'plugin-a:12', order: 3),
        ),
        isFalse,
      );
    });

    test('整批都已下载时结果为空，调用方据此只报「已跳过」', () {
      final plan = planDownloadEnqueue(
        [_task(chapterId: 'ch-1')],
        downloadedIds: {'ch-1'},
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.skippedDownloaded, 1);
    });
  });
}
