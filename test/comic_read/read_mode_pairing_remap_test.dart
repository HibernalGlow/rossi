import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/seamless_transition_state.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

/// 「切换单/双页后页数跳回开头」的判据。
///
/// 槽位下标在两种配对下含义不同：第 10 个槽位，单页下是第 11 张图，
/// 双页下是第 21 张图。所以切配对时**只能以图为准**重算位置
/// （[remapReadModeSlotIndexForPairingChange]）—— 早先的做法是直接
/// `changePageIndex(0)` 把槽位清零，那就是用户看到的「页数跳回开头」。
///
/// 这些用例同时钉住两条性质：
/// 1. 重算后的槽位**装着同一张图**（同一个条目下标）；
/// 2. 配对没变时结果是恒等映射（纯重建不该移动阅读位置）。
void main() {
  ReadModeEntry imageEntry(int pageIndex, {int chapterOrder = 1}) =>
      ReadModeEntry.image(
        doc: Doc(
          originalName: 'p$pageIndex.jpg',
          path: '/p$pageIndex.jpg',
          fileServer: '',
          id: 'id$pageIndex',
        ),
        chapterId: 'ch$chapterOrder',
        chapterOrder: chapterOrder,
        chapterTitle: '第 $chapterOrder 话',
        chapterPageIndex: pageIndex,
      );

  ReadModeEntry transitionEntry(int chapterOrder) => ReadModeEntry.transition(
    chapterOrder: chapterOrder,
    chapterTitle: '第 $chapterOrder 话',
    previousChapterOrder: chapterOrder - 1,
    previousChapterTitle: '第 ${chapterOrder - 1} 话',
    transitionStatus: SeamlessTransitionStatus.ready,
  );

  List<ReadModeEntry> imageEntries(int count) =>
      List<ReadModeEntry>.generate(count, (index) => imageEntry(index));

  group('槽位 ↔ 条目映射', () {
    test('单页：一个槽位一个条目', () {
      final entries = imageEntries(4);
      final slots = buildReadModeSlotEntryIndexes(
        entries,
        enableDoublePage: false,
      );
      expect(slots, [
        [0],
        [1],
        [2],
        [3],
      ]);
    });

    test('双页：两两合并，槽位数与 getReadModeSlotCount 同源', () {
      final entries = imageEntries(5);
      expect(
        buildReadModeSlotEntryIndexes(entries, enableDoublePage: true).length,
        getReadModeSlotCount(imageCount: 5, enableDoublePage: true),
      );
      expect(buildReadModeSlotEntryIndexes(entries, enableDoublePage: true), [
        [0, 1],
        [2, 3],
        [4],
      ]);
    });

    test('双页 + 首页留白：每段第一张单独占一个槽位（只有右半张）', () {
      final entries = imageEntries(5);
      expect(
        buildReadModeSlotEntryIndexes(
          entries,
          enableDoublePage: true,
          insertLeadingBlank: true,
        ),
        [
          [0],
          [1, 2],
          [3, 4],
        ],
      );
    });

    test('过渡卡片独占一个槽位，卡片之后的那段重新起一个留白位', () {
      final entries = <ReadModeEntry>[
        imageEntry(0),
        transitionEntry(2),
        imageEntry(0, chapterOrder: 2),
        imageEntry(1, chapterOrder: 2),
      ];
      expect(
        buildReadModeSlotEntryIndexes(
          entries,
          enableDoublePage: true,
          insertLeadingBlank: true,
        ),
        [
          [0], // 留白 | 第 1 话第 1 张
          [1], // 章节过渡卡片
          [2], // 留白 | 第 2 话第 1 张（每段重新起一个留白位）
          [3],
        ],
      );
      expect(
        buildReadModeSlotEntryIndexes(entries, enableDoublePage: true),
        [
          [0],
          [1],
          [2, 3],
        ],
        reason: '不开留白时，卡片后面那两张仍然并排',
      );
    });
  });

  group('切单/双页：位置跟着「同一张图」走', () {
    test('单页第 11 张 → 双页第 6 个槽位（不是回到开头）', () {
      final entries = imageEntries(40);
      // 单页下槽位 10 = 第 11 张图（条目下标 10）。
      final remapped = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 10,
        wasDoublePage: false,
        wasLeadingBlank: false,
        useDoublePage: true,
        useLeadingBlank: false,
      );
      expect(remapped, 5, reason: '双页下条目 10 落在槽位 5（= 10 ~/ 2）');
      expect(
        buildReadModeSlotEntryIndexes(entries, enableDoublePage: true)[remapped],
        contains(10),
      );
    });

    test('双页第 6 个槽位 → 单页第 11 张（停在左页）', () {
      final entries = imageEntries(40);
      final remapped = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 5,
        wasDoublePage: true,
        wasLeadingBlank: false,
        useDoublePage: false,
        useLeadingBlank: false,
      );
      expect(remapped, 10, reason: '双页槽位 5 的左页是条目 10');
    });

    test('阅读到很后面时切配对，绝不落到第 0 槽位', () {
      final entries = imageEntries(200);
      final toDouble = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 150,
        wasDoublePage: false,
        wasLeadingBlank: false,
        useDoublePage: true,
        useLeadingBlank: false,
      );
      final backToSingle = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: toDouble,
        wasDoublePage: true,
        wasLeadingBlank: false,
        useDoublePage: false,
        useLeadingBlank: false,
      );

      expect(toDouble, 75);
      expect(backToSingle, 150, reason: '双页 → 单页应当回到原来那一张');
    });
  });

  group('首页留白：配对整体错一位', () {
    test('双页（无留白）槽位 5 → 打开留白后仍停在左页那张图', () {
      final entries = imageEntries(40);
      // 无留白：槽位 5 = 条目 10、11；有留白：条目 10 落在槽位 5（条目 10、11）。
      final remapped = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 5,
        wasDoublePage: true,
        wasLeadingBlank: false,
        useDoublePage: true,
        useLeadingBlank: true,
      );
      expect(
        buildReadModeSlotEntryIndexes(
          entries,
          enableDoublePage: true,
          insertLeadingBlank: true,
        )[remapped],
        contains(10),
      );
    });

    test('留白开着时切单页：锚点仍是当前槽位的首图', () {
      final entries = imageEntries(40);
      final remapped = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 3,
        wasDoublePage: true,
        wasLeadingBlank: true,
        useDoublePage: false,
        useLeadingBlank: true,
      );
      // 留白下槽位 3 = 条目 5、6（槽位 n 从 n ≥ 1 起是 2n-1、2n）→ 首图条目 5。
      expect(remapped, 5);
    });

    test('单页下留白开关不改变任何东西', () {
      final entries = imageEntries(10);
      final remapped = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 7,
        wasDoublePage: false,
        wasLeadingBlank: false,
        useDoublePage: false,
        useLeadingBlank: true,
      );
      expect(remapped, 7);
    });
  });

  group('退化与边界', () {
    test('配对没变就是恒等映射', () {
      final entries = imageEntries(20);
      for (final doublePage in [false, true]) {
        for (final leadingBlank in [false, true]) {
          for (final slot in [0, 1, 5, 9]) {
            expect(
              remapReadModeSlotIndexForPairingChange(
                entries: entries,
                slotIndex: slot,
                wasDoublePage: doublePage,
                wasLeadingBlank: leadingBlank,
                useDoublePage: doublePage,
                useLeadingBlank: leadingBlank,
              ),
              slot,
              reason: '双页=$doublePage 留白=$leadingBlank 槽位=$slot',
            );
          }
        }
      }
    });

    test('没有条目时给 0，不越界', () {
      expect(
        remapReadModeSlotIndexForPairingChange(
          entries: const <ReadModeEntry>[],
          slotIndex: 5,
          wasDoublePage: false,
          wasLeadingBlank: false,
          useDoublePage: true,
          useLeadingBlank: false,
        ),
        0,
      );
    });

    test('旧槽位越界时夹回合法范围（不抛异常、不越界）', () {
      final entries = imageEntries(6);

      final tooLarge = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: 999,
        wasDoublePage: false,
        wasLeadingBlank: false,
        useDoublePage: true,
        useLeadingBlank: false,
      );
      expect(tooLarge, 2, reason: '夹到最后一页（条目 5）→ 双页槽位 2');

      final negative = remapReadModeSlotIndexForPairingChange(
        entries: entries,
        slotIndex: -5,
        wasDoublePage: true,
        wasLeadingBlank: false,
        useDoublePage: false,
        useLeadingBlank: false,
      );
      expect(negative, 0, reason: '夹到第一页（条目 0）→ 单页槽位 0');
    });
  });
}
