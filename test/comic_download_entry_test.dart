import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/download/download_chapter_gate.dart';

void main() {
  group('下载入口单击去向', () {
    test('既无下载记录也无下载任务：单击直接下载整本', () {
      expect(
        resolveComicDownloadEntryAction(
          hasDownloadRecord: false,
          hasDownloadTask: false,
        ),
        ComicDownloadEntryAction.downloadAll,
      );
    });

    test('已有下载记录：单击进章节选择页（管理已有下载）', () {
      expect(
        resolveComicDownloadEntryAction(
          hasDownloadRecord: true,
          hasDownloadTask: false,
        ),
        ComicDownloadEntryAction.openChapterPicker,
      );
    });

    test('已有下载任务（排队/下载中/暂停/失败）：单击进章节选择页', () {
      expect(
        resolveComicDownloadEntryAction(
          hasDownloadRecord: false,
          hasDownloadTask: true,
        ),
        ComicDownloadEntryAction.openChapterPicker,
      );
    });
  });

  group('整本下载任务（单章节任务模型：一章一个任务）', () {
    const chapters = [
      DownloadChapter(
        id: 'ch-1',
        displayName: '第 1 话',
        order: 1,
        extern: {},
        images: [],
      ),
      DownloadChapter(
        id: 'ch-2',
        displayName: '第 2 话',
        order: 2,
        requestId: 'req-2',
        storageId: 'store-2',
        extern: {'k': 'v'},
        images: [],
      ),
    ];

    test('没有章节时不构造任务', () {
      expect(
        buildDownloadAllTasks(
          from: 'plugin-a',
          comicId: 'comic/1',
          comicName: '测试漫画',
          chapters: const [],
        ),
        isEmpty,
      );
    });

    test('每个章节各一个任务，key 精确到章且互不相同', () {
      final tasks = buildDownloadAllTasks(
        from: 'plugin-a',
        comicId: 'comic/1',
        comicName: '测试漫画',
        chapters: chapters,
      );

      expect(tasks.length, 2);
      expect(tasks.map((task) => task.taskKey).toList(), [
        'plugin-a:comic/1:ch-1',
        'plugin-a:comic/1:ch-2',
      ]);
    });

    test('requestId / storageId 缺失时按 id 兜底', () {
      final tasks = buildDownloadAllTasks(
        from: 'plugin-a',
        comicId: 'comic/1',
        comicName: '测试漫画',
        chapters: chapters,
      );

      final first = tasks.first.chapterRef;
      expect(first.chapterId, 'ch-1');
      expect(first.logicalKey, 'ch-1');
      expect(first.title, '第 1 话');
      expect(first.order, 1);
      expect(first.requestId, 'ch-1');
      expect(
        first.storageChapterId,
        md5.convert(utf8.encode('ch-1')).toString(),
      );

      final second = tasks.last.chapterRef;
      expect(second.chapterId, 'ch-2');
      expect(second.requestId, 'req-2');
      expect(second.storageChapterId, 'store-2');
      expect(second.extern, {'k': 'v'});
    });
  });

  group('下载按钮/角标的视觉状态', () {
    ComicDownloadVisualState stateOf({
      bool isDownloading = false,
      bool isCompleted = false,
      String stateCode = 'none',
      bool hasRecord = false,
    }) {
      return resolveComicDownloadVisualState(
        isDownloading: isDownloading,
        isCompleted: isCompleted,
        stateCode: stateCode,
        hasRecord: hasRecord,
      );
    }

    test('正在下载优先于「已完成」与落盘记录', () {
      expect(
        stateOf(
          isDownloading: true,
          isCompleted: true,
          stateCode: 'running',
          hasRecord: true,
        ),
        ComicDownloadVisualState.downloading,
      );
    });

    test('暂停与出错各有独立状态，不被当成「没下过」', () {
      expect(stateOf(stateCode: 'paused'), ComicDownloadVisualState.paused);
      expect(stateOf(stateCode: 'failed'), ComicDownloadVisualState.failed);
    });

    test('任务已完成、或只剩落盘记录，都算「已完成」', () {
      expect(
        stateOf(isCompleted: true, stateCode: 'done'),
        ComicDownloadVisualState.completed,
      );
      // 任务被清理但文件还在的情况。
      expect(stateOf(hasRecord: true), ComicDownloadVisualState.completed);
    });

    test('三者皆无时是「没下过」（单击即下载整本）', () {
      expect(stateOf(), ComicDownloadVisualState.notDownloaded);
    });
  });

  group('整本下载入队前的章节闸门', () {
    const all = [
      DownloadChapter(
        id: 'ch-1',
        displayName: '第 1 话',
        order: 1,
        extern: {},
        images: [],
      ),
      DownloadChapter(
        id: 'ch-2',
        displayName: '第 2 话',
        order: 2,
        extern: {},
        images: [],
      ),
      DownloadChapter(
        id: 'ch-3',
        displayName: '第 3 话',
        order: 3,
        extern: {},
        images: [],
      ),
    ];

    DownloadEnqueuePlan plan({
      required Set<String> downloadedIds,
      bool forceRedownload = false,
    }) => planComicDownloadAllTasks(
      from: 'plugin_a',
      comicId: 'comic_1',
      comicName: '测试漫画',
      chapters: all,
      downloadedIds: downloadedIds,
      forceRedownload: forceRedownload,
    );

    test('批量默认跳过本地已有的章，只补缺的那几章', () {
      final result = plan(downloadedIds: {'ch-2'});

      expect(result.tasks.map((task) => task.chapterRef.chapterId), [
        'ch-1',
        'ch-3',
      ]);
      expect(result.skippedDownloaded, 1);
    });

    test('整本都已下载时一条都不入队（过去这条路径会重复建任务）', () {
      final result = plan(downloadedIds: {'ch-1', 'ch-2', 'ch-3'});

      expect(result.isEmpty, isTrue);
      expect(result.skippedDownloaded, 3);
    });

    test('forceRedownload 是用户主动重取：已下载的章照样入队', () {
      final result = plan(
        downloadedIds: {'ch-1', 'ch-2', 'ch-3'},
        forceRedownload: true,
      );

      expect(result.tasks, hasLength(3));
      expect(result.skippedDownloaded, 0);
    });

    test('一章都没下过时闸门不改变任何东西（阴性对照）', () {
      final result = plan(downloadedIds: const {});

      expect(result.tasks, hasLength(3));
      expect(result.skippedTotal, 0);
    });
  });

  group('下载最近 N 章', () {
    DownloadChapter chapter(int order) => DownloadChapter(
      id: 'ch-$order',
      displayName: '第 $order 话',
      order: order,
      extern: {},
      images: const [],
    );

    test('按 order 取最新的 N 章，返回仍是正序', () {
      // order 是 0..59：最新的 25 章 = 35..59，不是 36..60。
      final chapters = List.generate(60, chapter);

      final latest = selectLatestDownloadChapters(
        chapters,
        count: kDefaultLatestDownloadCount,
      );

      expect(latest, hasLength(25));
      expect(latest.first.order, 35);
      expect(latest.last.order, 59);
    });

    test('章数不到 N 时整本给出，count 为 0 时一条都不给', () {
      final chapters = List.generate(4, chapter);

      expect(selectLatestDownloadChapters(chapters, count: 25), hasLength(4));
      expect(selectLatestDownloadChapters(chapters, count: 0), isEmpty);
    });

    test('插件没给 order 时退化成取末尾 N 章（显示顺序，不是随机数）', () {
      final chapters = List.generate(
        10,
        (index) => DownloadChapter(
          id: 'ch-$index',
          displayName: '第 $index 话',
          order: 0,
          extern: {},
          images: const [],
        ),
      );

      final latest = selectLatestDownloadChapters(chapters, count: 3);

      expect(latest.map((chapter) => chapter.id), ['ch-7', 'ch-8', 'ch-9']);
    });

    test('最近 N 章里的已下载章同样被闸门跳掉（两处判据要能叠）', () {
      final chapters = List.generate(30, chapter);
      final latest = selectLatestDownloadChapters(chapters, count: 10);

      final plan = planComicDownloadAllTasks(
        from: 'plugin_a',
        comicId: 'comic_1',
        comicName: '测试漫画',
        chapters: latest,
        downloadedIds: {'ch-25'},
      );

      expect(plan.tasks, hasLength(9));
      expect(plan.skippedDownloaded, 1);
      expect(
        plan.tasks.map((task) => task.chapterRef.chapterId),
        isNot(contains('ch-25')),
      );
    });
  });

  // `hasComicDownloadRecord` / `hasComicDownloadTask` 的判据依赖 ObjectBox
  // 动态库；`flutter test` 在本机加载不了 libobjectbox.dylib
  // （与 test/bookshelf/comic_folder_link_service_test.dart 同因），
  // 因此这里不写成必然变红的测试。行为口径由上面纯函数判据 + 调用点分流覆盖。
}
