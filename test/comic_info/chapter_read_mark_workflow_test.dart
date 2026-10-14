// 状态级（真库读写）的章节标记工作流测试。
//
// 这一档要证明的是「标记落进 `ComicChapterReadMark`，而书签行一个字段都不动」
// —— 只有真 ObjectBox 才证得了，所以它必须走全 app 闭包。
// 纯算式那一份不依赖实体，在 `chapter_read_state_test.dart`。
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/chapter_read_mark_service.dart';

import '../test_helper.dart';

const _source = 'test';
const _comicId = '1';
const _comicKey = 'test:1';

DownloadChapter _chapter(int order, {String? id}) {
  return DownloadChapter(
    id: id ?? 'c$order',
    displayName: '第 $order 话',
    order: order,
    extern: const {},
    images: const [],
  );
}

/// 书签行 = 实际读到哪里。由阅读器写，标记流程一概不许碰。
void _seedBookmark(int chapterOrder, {int pageIndex = 7}) {
  final now = DateTime.utc(2026, 10, 13, 12);
  objectbox.unifiedHistoryBox.put(
    UnifiedComicHistory(
      uniqueKey: _comicKey,
      source: _source,
      comicId: _comicId,
      title: 't',
      description: '',
      cover: '',
      creator: '',
      titleMeta: '[]',
      metadata: '[]',
      chapterId: 'c$chapterOrder',
      chapterTitle: '第 $chapterOrder 话',
      chapterOrder: chapterOrder,
      pageIndex: pageIndex,
      createdAt: now,
      lastReadAt: now,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    ),
  );
}

ComicChapterReadMark? _row(String chapterId) {
  for (final row in objectbox.comicChapterReadMarkBox.getAll()) {
    if (row.chapterId == chapterId) return row;
  }
  return null;
}

int _liveRowCount() =>
    objectbox.comicChapterReadMarkBox.getAll().where((e) => !e.deleted).length;

void main() {
  // 标记动作会走一次提示条；没有 UI 树时 `NotifyGateway` 自己会把提示丢弃，
  // 但它读 `GlobalKey.currentContext` 需要 binding 已经建起来。
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpisodeReadMarkController controller;
  final chapters = List<DownloadChapter>.generate(6, (i) => _chapter(i + 1));

  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    objectbox.comicChapterReadMarkBox.removeAll();
    objectbox.unifiedHistoryBox.removeAll();
    controller = EpisodeReadMarkController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('读回来才敢显示：初始状态来自书签，不来自标记', () {
    test('attach 后书签序号进模型，标记表为空', () {
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);

      expect(controller.cubit.state.bookmarkOrder, 3);
      expect(controller.cubit.state.marks, isEmpty);
      expect(
        controller.stateOf(chapters[1]),
        ChapterReadState.inferredRead,
      );
      expect(controller.stateOf(chapters[4]), ChapterReadState.unread);
    });

    test('没有书签行时全部算未读', () {
      controller.attach(from: _source, comicId: _comicId);
      expect(controller.cubit.state.bookmarkOrder, 0);
      expect(controller.stateOf(chapters[0]), ChapterReadState.unread);
    });
  });

  group('标记与书签互不污染（本功能的中心不变量）', () {
    test('标已读写标记行，书签行一个字段都没动', () {
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);

      controller.markRead([chapters[5]]);

      final row = _row('c6');
      expect(row, isNotNull);
      expect(row!.markedRead, isTrue);
      expect(row.deleted, isFalse);
      expect(row.uniqueKey, 'test:1:c6');
      expect(row.chapterOrder, 6);
      expect(controller.stateOf(chapters[5]), ChapterReadState.manualRead);

      final bookmark = objectbox.unifiedHistoryBox.getAll().single;
      expect(bookmark.chapterOrder, 3, reason: '标记不许推进实际读到哪里');
      expect(bookmark.pageIndex, 7, reason: '标记不许改页内进度');
      expect(bookmark.chapterId, 'c3');
    });

    test('标未读是存行而不是删行，否则推断会把它洗回已读', () {
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);

      controller.markUnread([chapters[1]]);

      expect(_row('c2')!.markedRead, isFalse);
      expect(controller.stateOf(chapters[1]), ChapterReadState.manualUnread);
      expect(controller.stateOf(chapters[1]).isRead, isFalse);
      expect(objectbox.unifiedHistoryBox.getAll().single.chapterOrder, 3);
    });

    test('清除标记写墓碑而不是物理删，状态退回书签推断', () {
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);
      controller.markUnread([chapters[1]]);

      controller.clearMarks([chapters[1]]);

      final row = _row('c2');
      expect(row, isNotNull, reason: '墓碑必须留着，否则同步对端会把标记复活');
      expect(row!.deleted, isTrue);
      expect(controller.stateOf(chapters[1]), ChapterReadState.inferredRead);
      expect(_liveRowCount(), 0);
      expect(
        ChapterReadMarkService.instance.marksOf(_source, _comicId),
        isEmpty,
      );
    });
  });

  group('四个动作各自落到库里的形状', () {
    test('轻点在已读与未读之间翻转', () {
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);

      // 读到过的章：轻点 ⇒ 人为标未读。
      controller.toggle(chapters[1]);
      expect(_row('c2')!.markedRead, isFalse);

      // 已经是人为未读：再轻点 ⇒ 人为标已读。
      controller.toggle(chapters[1]);
      expect(_row('c2')!.markedRead, isTrue);
      expect(controller.stateOf(chapters[1]), ChapterReadState.manualRead);

      // 没读也没标的章：轻点 ⇒ 人为标已读。
      controller.toggle(chapters[5]);
      expect(_row('c6')!.markedRead, isTrue);
    });

    test('标记至此为已读：按显示列表取前缀，倒序时取另一头', () {
      _seedBookmark(0);
      controller.attach(from: _source, comicId: _comicId);

      controller.markThroughRead(
        target: chapters[2],
        displayChapters: chapters,
        displayReversed: false,
      );
      expect(_liveRowCount(), 3);
      expect(
        ChapterReadMarkService.instance.marksOf(_source, _comicId).keys.toList()
          ..sort(),
        ['c1', 'c2', 'c3'],
      );
      // 书签行还是我塞进去的那一条、还是 0：至此已读只写标记表。
      final bookmarks = objectbox.unifiedHistoryBox.getAll();
      expect(bookmarks.length, 1);
      expect(bookmarks.single.chapterOrder, 0, reason: '至此已读不该写书签');
    });

    test('撤销后再标同一章不会撞 uniqueKey 唯一约束', () {
      // 回归：putMany 按 ObjectBox id 覆盖，另起一条 id=0 的新对象去插同一个
      // uniqueKey（哪怕旧行已经是墓碑）会被唯一约束拦下来直接抛。
      _seedBookmark(3);
      controller.attach(from: _source, comicId: _comicId);

      controller.markRead([chapters[2]]);
      controller.clearMarks([chapters[2]]);
      controller.markRead([chapters[2]]);

      final row = _row('c3')!;
      expect(row.deleted, isFalse);
      expect(row.markedRead, isTrue);
      expect(objectbox.comicChapterReadMarkBox.getAll().length, 1);
      expect(controller.stateOf(chapters[2]), ChapterReadState.manualRead);
    });

    test('墓碑行被重新标记时复用原行，不会留下两条', () {
      _seedBookmark(0);
      controller.attach(from: _source, comicId: _comicId);

      controller.markUnread([chapters[4]]);
      controller.clearMarks([chapters[4]]);
      controller.markUnread([chapters[4]]);

      final rows = objectbox.comicChapterReadMarkBox.getAll();
      expect(rows.length, 1, reason: '同一 uniqueKey 只能有一行');
      expect(rows.single.markedRead, isFalse);
      expect(rows.single.deleted, isFalse);
    });

    test('倒序显示时至此已读覆盖的是序号不比目标大的那些', () {
      _seedBookmark(0);
      controller.attach(from: _source, comicId: _comicId);

      controller.markThroughRead(
        target: chapters[3],
        displayChapters: chapters.reversed.toList(),
        displayReversed: true,
      );
      expect(
        ChapterReadMarkService.instance.marksOf(_source, _comicId).keys.toList()
          ..sort(),
        ['c1', 'c2', 'c3', 'c4'],
      );
    });

    test('批量标已读跳过已经标成同一档的章，不攒新时间戳', () {
      _seedBookmark(0);
      controller.attach(from: _source, comicId: _comicId);
      controller.markRead([chapters[4], chapters[5]]);
      final first = _row('c5')!.updatedAt;
      final rows = _liveRowCount();

      controller.markRead([chapters[4], chapters[5]]);

      expect(_liveRowCount(), rows);
      expect(_row('c5')!.updatedAt, first, reason: '重复批量不该推进 LWW 时间戳');
    });

    test('多选批量就是同一套写入，覆盖选中集', () {
      _seedBookmark(0);
      controller.attach(from: _source, comicId: _comicId);

      controller.markUnread([chapters[0], chapters[2], chapters[3]]);

      final marks = ChapterReadMarkService.instance.marksOf(_source, _comicId);
      expect(marks.length, 3);
      expect(marks.values.every((mark) => !mark.markedRead), isTrue);
    });
  });

  group('范围隔离：一部漫画的标记不串到别处', () {
    test('按 (source, comicId) 查，别的漫画与别的图源都不串', () {
      controller.attach(from: _source, comicId: _comicId);
      controller.markRead([chapters[0]]);

      final other = EpisodeReadMarkController();
      other.attach(from: _source, comicId: '2');
      expect(other.cubit.state.marks, isEmpty);
      other.markRead([_chapter(1)]);
      expect(other.stateOf(_chapter(1)), ChapterReadState.manualRead);

      expect(ChapterReadMarkService.instance.marksOf(_source, _comicId).length, 1);
      expect(
        ChapterReadMarkService.instance
            .marksOf('othersource', _comicId)
            .length,
        0,
      );

      final grouped = ChapterReadMarkService.instance.allMarksByComic();
      expect(grouped.keys, containsAll([_comicKey, 'test:2']));
      other.dispose();
    });

    test('章节 id 里带冒号也不影响命中（uniqueKey 从不被反向切分）', () {
      controller.attach(from: _source, comicId: _comicId);
      final tricky = _chapter(1, id: 'https://host/ch:1');

      controller.markRead([tricky]);

      expect(controller.stateOf(tricky), ChapterReadState.manualRead);
      expect(
        ChapterReadMarkService.instance.marksOf(_source, _comicId).keys,
        ['https://host/ch:1'],
      );
    });
  });
}
