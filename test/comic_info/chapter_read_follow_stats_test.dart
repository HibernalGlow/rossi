import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_state.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';

/// 追更页状态级的阅读统计测试：`ComicFollowState.hasUnreadUpdate` /
/// `unreadChapterCount` 在有人为标记之后必须怎么算。
///
/// 纯算式那一份（不引入 ObjectBox，任何时候都能单独编译）在
/// `chapter_read_state_test.dart`；这一份要多导入 `object_box/model.dart`，
/// 因为 `ComicFollow` / `UnifiedComicHistory` 是实体类。
///
/// 核心是下面那条「遍历参数空间」的恒等断言：**没有人为标记的用户，看到的
/// 未读数和红点一个都不许变**。这就是需求里「别把追更统计弄乱」的机器门禁。

/// 本功能之前的两份公式，逐字抄自旧 `comic_follow_state.dart`。
/// 期望值不许再调被测函数，所以这里硬写。
bool _legacyHasUnreadUpdate(ComicFollow follow, UnifiedComicHistory? history) {
  if (!follow.hasUpdate ||
      follow.detectedChapterCount <= follow.lastChapterCount) {
    return false;
  }
  if (history == null || history.chapterOrder <= 0) {
    return true;
  }
  return history.chapterOrder < follow.detectedChapterCount;
}

int _legacyUnreadChapterCount(
  ComicFollow follow,
  UnifiedComicHistory? history,
) {
  if (!_legacyHasUnreadUpdate(follow, history)) return 0;
  final readChapterOrder = history?.chapterOrder ?? 0;
  final readBaseline = readChapterOrder > follow.lastChapterCount
      ? readChapterOrder
      : follow.lastChapterCount;
  return (follow.detectedChapterCount - readBaseline).clamp(
    0,
    follow.detectedChapterCount,
  );
}

ComicFollow _follow({
  int detected = 10,
  int lastChapterCount = 0,
  bool hasUpdate = true,
}) {
  final now = DateTime.utc(2026, 10, 13, 12);
  return ComicFollow(
    uniqueKey: 'test:1',
    source: 'test',
    comicId: '1',
    title: 't',
    description: '',
    cover: '',
    creator: '',
    titleMeta: '[]',
    metadata: '[]',
    lastChapterCount: lastChapterCount,
    detectedChapterCount: detected,
    detectedChapterTitle: '',
    hasUpdate: hasUpdate,
    updateTime: now,
    deleted: false,
    createdAt: now,
    updatedAt: now,
    schemaVersion: 1,
  );
}

UnifiedComicHistory _history(int chapterOrder) {
  final now = DateTime.utc(2026, 10, 13, 12);
  return UnifiedComicHistory(
    uniqueKey: 'test:1',
    source: 'test',
    comicId: '1',
    title: 't',
    description: '',
    cover: '',
    creator: '',
    titleMeta: '[]',
    metadata: '[]',
    chapterId: 'c$chapterOrder',
    chapterTitle: 'ch $chapterOrder',
    chapterOrder: chapterOrder,
    pageIndex: 1,
    createdAt: now,
    lastReadAt: now,
    updatedAt: now,
    deleted: false,
    schemaVersion: 2,
  );
}

ComicFollowState _state({
  required ComicFollow follow,
  int? bookmarkOrder,
  Map<String, ChapterMark> marks = const {},
}) {
  return ComicFollowState(
    items: [follow],
    histories: bookmarkOrder == null
        ? const {}
        : {follow.uniqueKey: _history(bookmarkOrder)},
    chapterMarks: {follow.uniqueKey: marks},
  );
}

void main() {
  group('没有人为标记时，追更统计逐位不变', () {
    test('遍历 detected / 书签 / 基线 / 有无更新，与改动前的两份公式相同', () {
      for (var detected = 0; detected <= 12; detected++) {
        for (var last = 0; last <= 12; last++) {
          for (final hasUpdate in [true, false]) {
            final follow = _follow(
              detected: detected,
              lastChapterCount: last,
              hasUpdate: hasUpdate,
            );
            // 「没有历史行」和书签序号 0..14 都要一致。
            for (final bookmarkOrder in <int?>[
              null,
              ...List<int>.generate(15, (i) => i),
            ]) {
              final state = _state(
                follow: follow,
                bookmarkOrder: bookmarkOrder,
              );
              final history = bookmarkOrder == null
                  ? null
                  : _history(bookmarkOrder);
              final reason =
                  'detected=$detected last=$last update=$hasUpdate bookmark=$bookmarkOrder';
              expect(
                state.hasUnreadUpdate(follow),
                _legacyHasUnreadUpdate(follow, history),
                reason: reason,
              );
              expect(
                state.unreadChapterCount(follow),
                _legacyUnreadChapterCount(follow, history),
                reason: reason,
              );
            }
          }
        }
      }
    });

    test('updateCount 也只在同样那批漫画上计数', () {
      final withUpdate = _follow(detected: 10, lastChapterCount: 4);
      final state = _state(follow: withUpdate, bookmarkOrder: 6);
      expect(state.updateCount, 1);
      expect(state.visibleItems.length, 1);
    });
  });

  group('人为标记只修正既有窗口，不发明「有更新」', () {
    test('基线之后标已读 ⇒ 未读数减，红点跟着灭', () {
      final follow = _follow(detected: 10, lastChapterCount: 5);
      final marks = {
        for (var i = 6; i <= 10; i++)
          'c$i': ChapterMark(markedRead: true, order: i),
      };
      final state = _state(follow: follow, bookmarkOrder: 5, marks: marks);
      expect(state.unreadChapterCount(follow), 0);
      expect(state.hasUnreadUpdate(follow), isFalse);
    });

    test('没在更新窗口里时标未读不亮徽标，但那一章在详情页显示成未读', () {
      final follow = _follow(
        detected: 10,
        lastChapterCount: 10,
        hasUpdate: false,
      );
      final state = _state(
        follow: follow,
        bookmarkOrder: 10,
        marks: {'c2': const ChapterMark(markedRead: false, order: 2)},
      );
      expect(state.hasUnreadUpdate(follow), isFalse);
      expect(state.unreadChapterCount(follow), 0);
      // 详情页那一章走的是同一份标记表，显示成「已标记未读」。
      final detail = ChapterReadStateModel(
        bookmarkOrder: 10,
        marks: state.marksFor(follow),
      );
      expect(
        detail.stateOf(chapterId: 'c2', order: 2),
        ChapterReadState.manualUnread,
      );
      expect(detail.stateOf(chapterId: 'c9', order: 9), ChapterReadState.inferredRead);
    });

    test('标未读把更新窗口内的未读数字加回来', () {
      final follow = _follow(detected: 10, lastChapterCount: 5);
      final state = _state(
        follow: follow,
        bookmarkOrder: 5,
        marks: {
          'c2': const ChapterMark(markedRead: false, order: 2),
          'c8': const ChapterMark(markedRead: true, order: 8),
        },
      );
      // 前缀未读 5，减掉标已读的 8、9、10 里的 8（+1），加回基线内标未读的 2。
      expect(state.unreadChapterCount(follow), 5 - 1 + 1);
    });

    test('没有历史行时，标记仍然生效', () {
      final follow = _follow(detected: 4, lastChapterCount: 0);
      final state = _state(
        follow: follow,
        bookmarkOrder: null,
        marks: {
          'c1': const ChapterMark(markedRead: true, order: 1),
          'c2': const ChapterMark(markedRead: true, order: 2),
        },
      );
      expect(state.unreadChapterCount(follow), 2);
    });
  });
}
