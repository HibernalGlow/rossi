import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

/// 横长页拆分的**三方同源**钉子。
///
/// 「槽位数」这件事有三处出口：渲染侧（`buildReadModeSinglePageSlots` /
/// `buildReadModeDoublePageSlots`，决定 PageView 有几页）、映射侧
/// （`buildReadModeSlotEntryIndexes`，决定切单双页后停在同一张图）、
/// 计数侧（`getReadModeSlotCount` 闭式公式，决定 `ReaderCubit.totalSlots`
/// 即进度条分母）。三者算法不同，一旦漂移就会出现「进度条走到 41/40」或
/// 「跳页落到别张图」这类只在实机看得见的错。这里把三方按同一组输入对齐，
/// 谁改动其中一处就会红。
void main() {
  Doc doc(int index) => Doc(
    id: 'pic_$index',
    path: 'path_$index',
    originalName: 'pic_$index.jpg',
    fileServer: 'http://server',
  );

  ReadModeEntry entry(int index) => ReadModeEntry.image(
    doc: doc(index),
    chapterId: 'ch_1',
    chapterOrder: 1,
    chapterTitle: 'Chapter 1',
    chapterPageIndex: index,
  );

  List<ReadModeEntry> entriesOf(int count) => [
    for (var i = 0; i < count; i++) entry(i),
  ];

  for (final imageCount in [1, 2, 5, 8]) {
    final entries = entriesOf(imageCount);
    // 空集 = 没开拆分；单个 = 中间一张横图；首张 = 最容易错位的边界；全开 = 上限。
    for (final splitIndexes in [
      <int>{},
      <int>{1},
      <int>{0},
      <int>{0, 2},
      <int>{0, 1, 2, 3, 4, 5, 6, 7},
    ]) {
      if (splitIndexes.any((i) => i >= imageCount)) continue;
      final label = '条目数 $imageCount / 拆分 $splitIndexes';

      for (final doublePage in [false, true]) {
        for (final leadingBlank in [false, true]) {
          test('$label 双页=$doublePage 首页留白=$leadingBlank 三方一致', () {
            bool isLandscape(int index) => splitIndexes.contains(index);

            final rendered = doublePage
                ? buildReadModeDoublePageSlots(
                        entries,
                        insertLeadingBlank: leadingBlank,
                        splitLandscapePages: true,
                        isLandscape: isLandscape,
                      )
                      .map(
                        (slot) => <int>[
                          if (slot.transition != null)
                            slot.transition!.entryIndex
                          else ...[
                            if (slot.left != null) slot.left!.entryIndex,
                            if (slot.right != null) slot.right!.entryIndex,
                          ],
                        ],
                      )
                      .toList()
                : buildReadModeSinglePageSlots(
                    entries,
                    splitLandscapePages: true,
                    isLandscape: isLandscape,
                  ).map((item) => <int>[item.entryIndex]).toList();

            final mapped = buildReadModeSlotEntryIndexes(
              entries,
              enableDoublePage: doublePage,
              insertLeadingBlank: leadingBlank,
              splitLandscapePages: true,
              isLandscape: isLandscape,
            );

            final counted = getReadModeSlotCount(
              imageCount: imageCount,
              enableDoublePage: doublePage,
              insertLeadingBlank: leadingBlank,
              splitCount: splitIndexes.length,
            );

            expect(mapped, equals(rendered), reason: '映射侧与渲染侧的槽位→条目序列必须逐项相同');
            expect(
              counted,
              equals(rendered.length),
              reason: '计数侧的闭式公式与渲染侧槽位数必须相同',
            );
          });
        }
      }
    }
  }

  test('拆分方向决定两半的先后：rightFirst 时先画右半', () {
    final entries = entriesOf(3);

    final leftFirst = buildReadModeSinglePageSlots(
      entries,
      splitLandscapePages: true,
      direction: SplitDirection.leftFirst,
      isLandscape: (index) => index == 1,
    );
    final rightFirst = buildReadModeSinglePageSlots(
      entries,
      splitLandscapePages: true,
      direction: SplitDirection.rightFirst,
      isLandscape: (index) => index == 1,
    );

    expect(leftFirst[1].slice, PageSlice.left);
    expect(leftFirst[2].slice, PageSlice.right);
    expect(rightFirst[1].slice, PageSlice.right);
    expect(rightFirst[2].slice, PageSlice.left);
    // 两半仍是同一个条目 —— 页号与预取都按「哪一页」算，不按半页算。
    expect(rightFirst[1].entryIndex, 1);
    expect(rightFirst[2].entryIndex, 1);
  });

  test('不开拆分时槽位序列与拆分前逐字相同（默认路径零变化）', () {
    final entries = entriesOf(6);
    // 判据即使说「全是横图」，开关关着也不该拆 —— 钉住开关与判据是两个维度。
    final items = buildReadModeSinglePageSlots(
      entries,
      isLandscape: (index) => true,
    );

    expect(items.length, 6);
    expect(items.map((item) => item.entryIndex), [0, 1, 2, 3, 4, 5]);
    expect(items.every((item) => item.slice == PageSlice.full), isTrue);
  });
}
