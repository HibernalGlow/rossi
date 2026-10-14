import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_presentation.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';

/// 章节阅读状态的纯策略层测试。
///
/// 只依赖 `chapter_read_state.dart` / `chapter_read_presentation.dart` 与
/// `DownloadChapter`，不引入 ObjectBox、页面组件、`main.dart` —— 这个工作树里
/// 常有别人的在途改动让整个 app 编不过（那时 `loading … failed` 分不清是谁的红），
/// 所以这一档要保持能被单独编译。
/// 状态级（`ComicFollowState` 的徽标闸门）的同款门禁在
/// `chapter_read_follow_stats_test.dart`。

ChapterReadStateModel _model({
  int bookmarkOrder = 0,
  Map<String, ChapterMark> marks = const {},
}) {
  return ChapterReadStateModel(bookmarkOrder: bookmarkOrder, marks: marks);
}

DownloadChapter _chapter(String id, {int order = 0}) {
  return DownloadChapter(
    id: id,
    displayName: id,
    order: order,
    extern: const {},
    images: const [],
  );
}

/// 本功能之前的未读算法（前缀基线），逐字抄自旧 `unreadChapterCount`。
///
/// 期望值不许再调被测函数，所以这里是硬写的。
int _legacyPrefixUnread({
  required int detected,
  required int bookmarkOrder,
  required int followBaseline,
}) {
  final readBaseline = bookmarkOrder > followBaseline
      ? bookmarkOrder
      : followBaseline;
  return (detected - readBaseline).clamp(0, detected);
}

void main() {
  group('章节状态解析：实际读到 vs 人为标记', () {
    test('没标记时只由书签推断', () {
      final model = _model(bookmarkOrder: 5);
      expect(
        model.stateOf(chapterId: 'a', order: 3),
        ChapterReadState.inferredRead,
      );
      expect(
        model.stateOf(chapterId: 'b', order: 5),
        ChapterReadState.inferredRead,
      );
      expect(model.stateOf(chapterId: 'c', order: 6), ChapterReadState.unread);
    });

    test('人为标已读压过「其实没读到」', () {
      final model = _model(
        bookmarkOrder: 2,
        marks: {'z': const ChapterMark(markedRead: true, order: 80)},
      );
      expect(
        model.stateOf(chapterId: 'z', order: 80),
        ChapterReadState.manualRead,
      );
      // 书签并没有读到这里 —— 两套事实必须分开的原因就在这行断言里。
      expect(model.bookmarkOrder, 2);
    });

    test('人为标未读把推断的已读显式拉回来', () {
      final model = _model(
        bookmarkOrder: 5,
        marks: {'a': const ChapterMark(markedRead: false, order: 3)},
      );
      expect(
        model.stateOf(chapterId: 'a', order: 3),
        ChapterReadState.manualUnread,
      );
      expect(model.stateOf(chapterId: 'a', order: 3).isRead, isFalse);
    });

    test('标记按 chapterId 命中，不靠序号', () {
      final model = _model(
        marks: {'x': const ChapterMark(markedRead: true, order: 1)},
      );
      expect(model.stateOf(chapterId: 'y', order: 1), ChapterReadState.unread);
      expect(model.hasMark('x'), isTrue);
      expect(model.hasMark('y'), isFalse);
    });

    test('序号不可信的章（0 或负）不猜成已读', () {
      final model = _model(bookmarkOrder: 9);
      expect(model.stateOf(chapterId: 'a', order: 0), ChapterReadState.unread);
      expect(model.stateOf(chapterId: 'b', order: -1), ChapterReadState.unread);
    });
  });

  group('追更统计：没有人为标记时一个数字都不许变', () {
    test('遍历参数空间，与改动前的前缀算法逐位相同', () {
      for (var detected = 0; detected <= 14; detected++) {
        for (var bookmarkOrder = 0; bookmarkOrder <= 16; bookmarkOrder++) {
          for (var followBaseline = 0; followBaseline <= 16; followBaseline++) {
            expect(
              unreadChapterCountWithMarks(
                detectedChapterCount: detected,
                bookmarkOrder: bookmarkOrder,
                followBaseline: followBaseline,
                marks: const {},
              ),
              _legacyPrefixUnread(
                detected: detected,
                bookmarkOrder: bookmarkOrder,
                followBaseline: followBaseline,
              ),
              reason:
                  'detected=$detected bookmark=$bookmarkOrder baseline=$followBaseline',
            );
          }
        }
      }
    });
  });

  group('追更徽标：闸门 + 统计整体与改动前逐位相同', () {
    // 下面两份是改动前 `ComicFollowState` 里的判断，逐字翻成纯参数版本：
    // hasUpdate 与「检测章数 > 上次看到的章数」是那道「有没有更新」的闸，
    // 闸里再用前缀基线算未读数。期望值一律硬写，不调被测函数。
    bool legacyHasUnread({
      required bool hasUpdate,
      required int detected,
      required int last,
      required int? bookmarkOrder,
    }) {
      if (!hasUpdate || detected <= last) return false;
      if (bookmarkOrder == null || bookmarkOrder <= 0) return true;
      return bookmarkOrder < detected;
    }

    int legacyUnreadCount({
      required bool hasUpdate,
      required int detected,
      required int last,
      required int? bookmarkOrder,
    }) {
      if (!legacyHasUnread(
        hasUpdate: hasUpdate,
        detected: detected,
        last: last,
        bookmarkOrder: bookmarkOrder,
      )) {
        return 0;
      }
      final order = bookmarkOrder ?? 0;
      final baseline = order > last ? order : last;
      return (detected - baseline).clamp(0, detected);
    }

    int countWithMarks({
      required bool hasUpdate,
      required int detected,
      required int last,
      required int? bookmarkOrder,
    }) => followUnreadChapterCount(
      hasUpdate: hasUpdate,
      detectedChapterCount: detected,
      lastChapterCount: last,
      bookmarkOrder: bookmarkOrder ?? 0,
      marks: const {},
    );

    test('遍历 hasUpdate / 检测章数 / 基线 / 书签（含无历史行），全部相同', () {
      for (final hasUpdate in [true, false]) {
        for (var detected = 0; detected <= 12; detected++) {
          for (var last = 0; last <= 12; last++) {
            for (final bookmarkOrder in <int?>[
              null,
              ...List<int>.generate(15, (i) => i),
            ]) {
              final reason =
                  'hasUpdate=$hasUpdate detected=$detected last=$last bookmark=$bookmarkOrder';
              expect(
                countWithMarks(
                      hasUpdate: hasUpdate,
                      detected: detected,
                      last: last,
                      bookmarkOrder: bookmarkOrder,
                    ) >
                    0,
                legacyHasUnread(
                  hasUpdate: hasUpdate,
                  detected: detected,
                  last: last,
                  bookmarkOrder: bookmarkOrder,
                ),
                reason: '红点亮灭与改动前不一致：$reason',
              );
              expect(
                countWithMarks(
                  hasUpdate: hasUpdate,
                  detected: detected,
                  last: last,
                  bookmarkOrder: bookmarkOrder,
                ),
                legacyUnreadCount(
                  hasUpdate: hasUpdate,
                  detected: detected,
                  last: last,
                  bookmarkOrder: bookmarkOrder,
                ),
                reason: '未读章数与改动前不一致：$reason',
              );
            }
          }
        }
      }
    });

    test('没有更新窗口时，再多人为标未读也不亮红点', () {
      final marks = <String, ChapterMark>{
        for (var i = 1; i <= 4; i++) 'c$i': ChapterMark(markedRead: false, order: i),
      };
      expect(
        followUnreadChapterCount(
          hasUpdate: false,
          detectedChapterCount: 10,
          lastChapterCount: 10,
          bookmarkOrder: 10,
          marks: marks,
        ),
        0,
      );
      expect(
        followUnreadChapterCount(
          hasUpdate: true,
          detectedChapterCount: 10,
          lastChapterCount: 10,
          bookmarkOrder: 10,
          marks: marks,
        ),
        0,
        reason: '检测章数没超过基线就没有更新窗口，标记不得凭空造出未读',
      );
    });

    test('更新窗口内，标已读往下减、标未读往上加，都夹在 0..检测章数', () {
      final base = followUnreadChapterCount(
        hasUpdate: true,
        detectedChapterCount: 10,
        lastChapterCount: 5,
        bookmarkOrder: 5,
        marks: const {},
      );
      expect(base, 5);

      final markedRead = <String, ChapterMark>{
        for (var i = 6; i <= 8; i++) 'c$i': ChapterMark(markedRead: true, order: i),
      };
      expect(
        followUnreadChapterCount(
          hasUpdate: true,
          detectedChapterCount: 10,
          lastChapterCount: 5,
          bookmarkOrder: 5,
          marks: markedRead,
        ),
        2,
      );

      final markedUnread = <String, ChapterMark>{
        for (var i = 1; i <= 2; i++) 'c$i': ChapterMark(markedRead: false, order: i),
      };
      expect(
        followUnreadChapterCount(
          hasUpdate: true,
          detectedChapterCount: 10,
          lastChapterCount: 5,
          bookmarkOrder: 5,
          marks: markedUnread,
        ),
        7,
      );
    });
  });

  group('追更统计：人为标记只做窗口内修正', () {
    test('基线之后标已读 ⇒ 未读数按标记减少', () {
      final marks = {
        'c6': const ChapterMark(markedRead: true, order: 6),
        'c7': const ChapterMark(markedRead: true, order: 7),
        'c8': const ChapterMark(markedRead: true, order: 8),
      };
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: 10,
          bookmarkOrder: 5,
          followBaseline: 5,
          marks: marks,
        ),
        2,
      );
    });

    test('基线之内标未读 ⇒ 未读数加回来', () {
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: 10,
          bookmarkOrder: 5,
          followBaseline: 5,
          marks: {'c3': const ChapterMark(markedRead: false, order: 3)},
        ),
        6,
      );
    });

    test('基线之内标已读、以及超出检测章数的标记都不起作用', () {
      final marks = {
        'c4': const ChapterMark(markedRead: true, order: 4),
        'c11': const ChapterMark(markedRead: false, order: 11),
      };
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: 10,
          bookmarkOrder: 5,
          followBaseline: 5,
          marks: marks,
        ),
        5,
      );
    });

    test('全标未读不超过检测章数，全标已读不会变负', () {
      const detected = 6;
      final unreadAll = <String, ChapterMark>{
        for (var i = 1; i <= detected; i++)
          'c$i': ChapterMark(markedRead: false, order: i),
      };
      final readAll = <String, ChapterMark>{
        for (var i = 1; i <= detected; i++)
          'c$i': ChapterMark(markedRead: true, order: i),
      };
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: detected,
          bookmarkOrder: 3,
          followBaseline: 0,
          marks: unreadAll,
        ),
        detected,
      );
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: detected,
          bookmarkOrder: 3,
          followBaseline: 0,
          marks: readAll,
        ),
        0,
      );
    });

    test('检测章数为 0 时不产生未读', () {
      expect(
        unreadChapterCountWithMarks(
          detectedChapterCount: 0,
          bookmarkOrder: 0,
          followBaseline: 0,
          marks: {'c1': const ChapterMark(markedRead: false, order: 1)},
        ),
        0,
      );
    });
  });

  group('「至此」的范围按显示列表算', () {
    final chapters = [
      _chapter('a', order: 1),
      _chapter('b', order: 2),
      _chapter('c', order: 3),
    ];

    test('正序取目标之前（含目标）', () {
      expect(
        chaptersThrough(
              displayChapters: chapters,
              targetId: 'b',
              displayReversed: false,
            )
            .map((e) => e.id)
            .toList(),
        ['a', 'b'],
      );
    });

    test('倒序显示时「此前」在数组另一头', () {
      // 倒序显示 = [c(3), b(2), a(1)]；以 b 为界「此前」是序号不比 b 大的 a、b。
      expect(
        chaptersThrough(
              displayChapters: chapters.reversed.toList(),
              targetId: 'b',
              displayReversed: true,
            )
            .map((e) => e.id)
            .toList(),
        ['b', 'a'],
      );
    });

    test('目标不在列表里就什么都不标', () {
      expect(
        chaptersThrough(
          displayChapters: chapters,
          targetId: 'zzz',
          displayReversed: false,
        ),
        isEmpty,
      );
    });
  });

  group('四个状态在 UI 上必须互不相同', () {
    test('标记视觉三元组两两不同', () {
      final visuals = ChapterReadState.values.map(readMarkerVisual).toList();
      final keys = visuals
          .map((v) => '${v.glyph.hashCode}|${v.alpha}|${v.primary}')
          .toList();
      expect(keys.toSet().length, ChapterReadState.values.length);
    });

    test('只有人为两档用主色', () {
      expect(readMarkerVisual(ChapterReadState.manualRead).primary, isTrue);
      expect(readMarkerVisual(ChapterReadState.manualUnread).primary, isTrue);
      expect(readMarkerVisual(ChapterReadState.inferredRead).primary, isFalse);
      expect(readMarkerVisual(ChapterReadState.unread).primary, isFalse);
    });

    test('读到过与已标已读是两档，符号必须不同', () {
      expect(
        readMarkerVisual(ChapterReadState.inferredRead).glyph,
        isNot(readMarkerVisual(ChapterReadState.manualRead).glyph),
      );
    });

    test('四档各有一句人话', () {
      final labels = ChapterReadState.values.map(readStateLabel).toList();
      expect(labels.every((label) => label.isNotEmpty), isTrue);
      expect(labels.toSet().length, ChapterReadState.values.length);
    });
  });
}
