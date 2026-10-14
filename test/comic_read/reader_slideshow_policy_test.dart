import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/model/reader_slideshow.dart';

/// 结束策略与「帧没就位就别说推进过了」这两条判据是放映最容易写错的地方，
/// 而且它们是纯函数 —— 不需要 Widget、不需要计时器就能钉死。
void main() {
  group('decideReaderSlideshowTick', () {
    test('章内每一拍都推进', () {
      expect(
        decideReaderSlideshowTick(
          atChapterEnd: false,
          frameReady: true,
          hasNextChapter: true,
          endAction: ReaderSlideshowEndAction.stop,
        ),
        ReaderSlideshowTick.advance,
      );
    });

    test('非章末但帧没就位时是 hold，不是 advance', () {
      // 阳性对照：判据顺序写反（先看章末）时这条仍然会过，
      // 所以另配下面那条「章末 + 帧没就位」的用例。
      expect(
        decideReaderSlideshowTick(
          atChapterEnd: false,
          frameReady: false,
          hasNextChapter: true,
          endAction: ReaderSlideshowEndAction.loopChapter,
        ),
        ReaderSlideshowTick.hold,
      );
    });

    test('章末且帧没就位时仍先 hold：不许在未解出的最后一页上直接停表', () {
      expect(
        decideReaderSlideshowTick(
          atChapterEnd: true,
          frameReady: false,
          hasNextChapter: false,
          endAction: ReaderSlideshowEndAction.stop,
        ),
        ReaderSlideshowTick.hold,
      );
    });

    test('三种结束策略各走各的', () {
      ReaderSlideshowTick decide(ReaderSlideshowEndAction action, {bool hasNext = true}) {
        return decideReaderSlideshowTick(
          atChapterEnd: true,
          frameReady: true,
          hasNextChapter: hasNext,
          endAction: action,
        );
      }

      expect(
        decide(ReaderSlideshowEndAction.stop),
        ReaderSlideshowTick.stop,
      );
      expect(
        decide(ReaderSlideshowEndAction.loopChapter),
        ReaderSlideshowTick.loopToChapterStart,
      );
      expect(
        decide(ReaderSlideshowEndAction.nextChapter),
        ReaderSlideshowTick.advance,
      );
      // 没有下一章时不许退化成静默循环，也不许停在「推进」上被下游夹成一页不动。
      expect(
        decide(ReaderSlideshowEndAction.nextChapter, hasNext: false),
        ReaderSlideshowTick.stop,
      );
    });

    test('循环本章不会因为「已在章末」而反复重排：判据只看当前是否章末', () {
      // 宿主跳回第一格之后再问一次，此时 atChapterEnd 为假，应回到正常推进。
      expect(
        decideReaderSlideshowTick(
          atChapterEnd: false,
          frameReady: true,
          hasNextChapter: false,
          endAction: ReaderSlideshowEndAction.loopChapter,
        ),
        ReaderSlideshowTick.advance,
      );
    });
  });

  group('间隔与推进距离的上下限', () {
    test('间隔收到 800~15000，非正与超界都不被放过', () {
      expect(normalizeReaderSlideshowIntervalMs(0), kReaderSlideshowIntervalMinMs);
      expect(normalizeReaderSlideshowIntervalMs(-500), kReaderSlideshowIntervalMinMs);
      expect(normalizeReaderSlideshowIntervalMs(999999), kReaderSlideshowIntervalMaxMs);
      expect(normalizeReaderSlideshowIntervalMs(4000), 4000);
    });

    test('条漫推进距离收到 30~100 百分比', () {
      expect(
        normalizeReaderSlideshowColumnStepPercent(0),
        kReaderSlideshowColumnStepMinPercent,
      );
      expect(
        normalizeReaderSlideshowColumnStepPercent(100),
        kReaderSlideshowColumnStepMaxPercent,
      );
      expect(normalizeReaderSlideshowColumnStepPercent(140), 100);
      expect(normalizeReaderSlideshowColumnStepPercent(65), 65);
    });
  });
}
