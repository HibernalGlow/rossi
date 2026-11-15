import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/comic_read_chapter_repository.dart';
import 'package:zephyr/service/reader/reader_history_service.dart';

import 'test_helper.dart';

void main() {
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  tearDown(TestObjectBoxHelper.cleanComicFolderBoxes);

  test('按漫画隔离查询，重复标记同一章不新增记录', () {
    final repo = ComicReadChapterRepository.instance;

    repo.markRead(
      source: 'src',
      comicId: 'c1',
      chapterId: 'ch1',
      chapterTitle: '第 1 话',
      chapterOrder: 1,
    );
    repo.markRead(
      source: 'src',
      comicId: 'c1',
      chapterId: 'ch2',
      chapterTitle: '第 2 话',
      chapterOrder: 2,
    );
    repo.markRead(
      source: 'src',
      comicId: 'c2',
      chapterId: 'ch1',
      chapterTitle: '另一本第 1 话',
      chapterOrder: 1,
    );

    expect(repo.readChapterIds(source: 'src', comicId: 'c1'), {'ch1', 'ch2'});
    expect(repo.readChapterIds(source: 'src', comicId: 'c2'), {'ch1'});
    expect(repo.readChapterIds(source: 'other', comicId: 'c1'), isEmpty);
    expect(objectbox.comicReadChapterBox.count(), 3);

    repo.markRead(
      source: 'src',
      comicId: 'c1',
      chapterId: 'ch1',
      chapterTitle: '第 1 话（重读）',
      chapterOrder: 1,
    );

    expect(objectbox.comicReadChapterBox.count(), 3);
    expect(repo.readChapterIds(source: 'src', comicId: 'c1'), {'ch1', 'ch2'});
  });

  test('写入后按漫画 key 通知详情页刷新', () async {
    final repo = ComicReadChapterRepository.instance;
    final change = repo.changes.first;
    repo.markRead(
      source: 'src',
      comicId: 'c3',
      chapterId: 'ch1',
      chapterTitle: '第 1 话',
      chapterOrder: 1,
    );
    expect(await change, 'src:c3');
  });

  test('阅读器就绪时把当前章节写入已读', () async {
    final service = ReaderHistoryService.instance;
    await service.loadHistory(
      source: 'src',
      comicId: 'c9',
      comicInfo: const NormalComicAllInfo(
        comicInfo: ComicInfo(
          id: 'c9',
          title: '测试漫画',
          titleMeta: [],
          description: '',
          cover: ComicImage(id: 'cover', url: 'url', name: 'cover'),
          metadata: [],
        ),
        eps: [],
        recommend: [],
      ),
    );
    service.startPeriodicSave(
      () => HistorySnapshot(
        pageIndex: 1,
        chapterOrder: 1,
        epInfo: NormalComicEpInfo(epId: 'ch9', epName: '第 9 话'),
      ),
    );
    service.markLoaded();
    service.markCurrentChapterRead();
    service.stop();

    expect(
      ComicReadChapterRepository.instance.readChapterIds(
        source: 'src',
        comicId: 'c9',
      ),
      {'ch9'},
    );
  });

  test('周期保存通过 runAsync 写入历史', () async {
    final service = ReaderHistoryService.instance;
    await service.loadHistory(
      source: 'src',
      comicId: 'c10',
      comicInfo: const NormalComicAllInfo(
        comicInfo: ComicInfo(
          id: 'c10',
          title: '后台写入测试',
          titleMeta: [],
          description: '',
          cover: ComicImage(id: 'cover', url: 'url', name: 'cover'),
          metadata: [],
        ),
        eps: [],
        recommend: [],
      ),
    );
    service.startPeriodicSave(
      () => HistorySnapshot(
        pageIndex: 4,
        chapterOrder: 2,
        epInfo: NormalComicEpInfo(epId: 'ch10', epName: '第 10 话'),
      ),
    );
    service.markLoaded();

    try {
      UnifiedComicHistory? history;
      for (var i = 0; i < 40 && history == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final matches = objectbox.unifiedHistoryBox
            .getAll()
            .where((item) => item.uniqueKey == 'src:c10')
            .toList();
        if (matches.isNotEmpty) history = matches.first;
      }
      expect(history, isNotNull);
      expect(history?.pageIndex, 4);
    } finally {
      service.stop();
    }
  });
}
