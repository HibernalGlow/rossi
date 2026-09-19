import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';

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

  group('整本下载任务 payload', () {
    test('没有章节时不构造任务', () {
      expect(
        buildDownloadAllTask(
          from: 'plugin-a',
          comicId: 'comic/1',
          comicName: '测试漫画',
          chapters: const [],
        ),
        isNull,
      );
    });

    test('全部章节都进 payload，且 requestId/storageId 缺失时按 id 兜底', () {
      final task = buildDownloadAllTask(
        from: 'plugin-a',
        comicId: 'comic/1',
        comicName: '测试漫画',
        chapters: const [
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
        ],
      );

      expect(task, isNotNull);
      expect(task!.taskKey, 'plugin-a:comic/1');
      expect(task.chapterRefs.length, 2);

      final first = task.chapterRefs.first;
      expect(first.chapterId, 'ch-1');
      expect(first.logicalKey, 'ch-1');
      expect(first.title, '第 1 话');
      expect(first.order, 1);
      expect(first.requestId, 'ch-1');
      expect(
        first.storageChapterId,
        md5.convert(utf8.encode('ch-1')).toString(),
      );

      final second = task.chapterRefs.last;
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

  // `hasComicDownloadRecord` / `hasComicDownloadTask` 的判据依赖 ObjectBox
  // 动态库；`flutter test` 在本机加载不了 libobjectbox.dylib
  // （与 test/bookshelf/comic_folder_link_service_test.dart 同因），
  // 因此这里不写成必然变红的测试。行为口径由上面纯函数判据 + 调用点分流覆盖。
}
