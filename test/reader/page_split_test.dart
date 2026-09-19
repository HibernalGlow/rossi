import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

void main() {
  group('M-09 PageSplit Data Models & Algorithm', () {
    test('PageSlice basic properties and uvRect', () {
      expect(PageSlice.full.isHalf, isFalse);
      expect(PageSlice.left.isHalf, isTrue);
      expect(PageSlice.right.isHalf, isTrue);

      expect(PageSlice.full.uvRect, equals([0.0, 0.0, 1.0, 1.0]));
      expect(PageSlice.left.uvRect, equals([0.0, 0.0, 0.5, 1.0]));
      expect(PageSlice.right.uvRect, equals([0.5, 0.0, 1.0, 1.0]));
    });

    test('SplitDirection first and second slices', () {
      expect(SplitDirection.leftFirst.first, equals(PageSlice.left));
      expect(SplitDirection.leftFirst.second, equals(PageSlice.right));

      expect(SplitDirection.rightFirst.first, equals(PageSlice.right));
      expect(SplitDirection.rightFirst.second, equals(PageSlice.left));
    });

    test('SplitDirection resolution from readMode and settingValue', () {
      expect(SplitDirection.fromReadMode(0), equals(SplitDirection.leftFirst));
      expect(SplitDirection.fromReadMode(1), equals(SplitDirection.leftFirst));
      expect(SplitDirection.fromReadMode(2), equals(SplitDirection.rightFirst));

      // 0: auto
      expect(
        SplitDirection.resolve(settingValue: 0, currentReadMode: 1),
        equals(SplitDirection.leftFirst),
      );
      expect(
        SplitDirection.resolve(settingValue: 0, currentReadMode: 2),
        equals(SplitDirection.rightFirst),
      );

      // 1: forced LTR
      expect(
        SplitDirection.resolve(settingValue: 1, currentReadMode: 2),
        equals(SplitDirection.leftFirst),
      );

      // 2: forced RTL
      expect(
        SplitDirection.resolve(settingValue: 2, currentReadMode: 1),
        equals(SplitDirection.rightFirst),
      );
    });

    test('computePresentationSteps with vertical and landscape images', () {
      // 3 pages: page 0 is portrait, page 1 is landscape, page 2 is portrait
      final isLandscape = [false, true, false];

      // LTR split
      final stepsLtr = computePresentationSteps(
        count: 3,
        direction: SplitDirection.leftFirst,
        isSplitIdx: (idx) => isLandscape[idx],
      );

      expect(stepsLtr.length, equals(4));
      expect(stepsLtr[0].sourceIdx, equals(0));
      expect(stepsLtr[0].slice, equals(PageSlice.full));
      expect(stepsLtr[1].sourceIdx, equals(1));
      expect(stepsLtr[1].slice, equals(PageSlice.left));
      expect(stepsLtr[2].sourceIdx, equals(1));
      expect(stepsLtr[2].slice, equals(PageSlice.right));
      expect(stepsLtr[3].sourceIdx, equals(2));
      expect(stepsLtr[3].slice, equals(PageSlice.full));

      // RTL split
      final stepsRtl = computePresentationSteps(
        count: 3,
        direction: SplitDirection.rightFirst,
        isSplitIdx: (idx) => isLandscape[idx],
      );

      expect(stepsRtl.length, equals(4));
      expect(stepsRtl[1].sourceIdx, equals(1));
      expect(stepsRtl[1].slice, equals(PageSlice.right));
      expect(stepsRtl[2].sourceIdx, equals(1));
      expect(stepsRtl[2].slice, equals(PageSlice.left));

      // Split disabled (all false)
      final stepsDisabled = computePresentationSteps(
        count: 3,
        direction: SplitDirection.leftFirst,
        isSplitIdx: (_) => false,
      );
      expect(stepsDisabled.length, equals(3));
      expect(stepsDisabled.every((s) => s.slice == PageSlice.full), isTrue);
    });

    test('findLandingStep maps source index to presentation step', () {
      final isLandscape = [false, true, false];
      final steps = computePresentationSteps(
        count: 3,
        direction: SplitDirection.leftFirst,
        isSplitIdx: (idx) => isLandscape[idx],
      );

      expect(findLandingStep(steps, 0), equals(0));
      expect(findLandingStep(steps, 1), equals(1)); // first step of page 1
      expect(findLandingStep(steps, 2), equals(3));
      expect(findLandingStep(steps, 99), isNull);
    });
  });

  group('ReadMode Slot Generation with Landscape Splitting', () {
    ReadModeEntry makeEntry(int index) {
      return ReadModeEntry.image(
        doc: Doc(
          id: 'pic_$index',
          path: 'path_$index',
          originalName: 'pic_$index.jpg',
          fileServer: 'http://server',
        ),
        chapterId: 'ch_1',
        chapterOrder: 1,
        chapterTitle: 'Chapter 1',
        chapterPageIndex: index,
      );
    }

    test('buildReadModeSinglePageSlots splits landscape entries', () {
      final entries = [makeEntry(0), makeEntry(1), makeEntry(2)];

      // Entry 1 is landscape
      final slots = buildReadModeSinglePageSlots(
        entries,
        splitLandscapePages: true,
        direction: SplitDirection.leftFirst,
        isLandscape: (idx) => idx == 1,
      );

      expect(slots.length, equals(4));
      expect(slots[0].entryIndex, equals(0));
      expect(slots[0].slice, equals(PageSlice.full));

      expect(slots[1].entryIndex, equals(1));
      expect(slots[1].slice, equals(PageSlice.left));

      expect(slots[2].entryIndex, equals(1));
      expect(slots[2].slice, equals(PageSlice.right));

      expect(slots[3].entryIndex, equals(2));
      expect(slots[3].slice, equals(PageSlice.full));
    });

    test('buildReadModeDoublePageSlots handles landscape splitting', () {
      final entries = [makeEntry(0), makeEntry(1), makeEntry(2)];

      // Entry 1 is landscape, split into left & right
      final slots = buildReadModeDoublePageSlots(
        entries,
        splitLandscapePages: true,
        direction: SplitDirection.leftFirst,
        isLandscape: (idx) => idx == 1,
      );

      // 0 (portrait) -> paired with 1.left
      // 1.right -> paired with 2 (portrait)
      // Total 2 double page slots: [0, 1L], [1R, 2]
      expect(slots.length, equals(2));
      expect(slots[0].left?.entryIndex, equals(0));
      expect(slots[0].right?.entryIndex, equals(1));
      expect(slots[0].right?.slice, equals(PageSlice.left));

      expect(slots[1].left?.entryIndex, equals(1));
      expect(slots[1].left?.slice, equals(PageSlice.right));
      expect(slots[1].right?.entryIndex, equals(2));
    });
  });
}
