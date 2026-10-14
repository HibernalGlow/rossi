/// 幻灯片（整页驻留放映）的纯判据。
///
/// 计时器与翻页动作分别住在 `controller/reader_slideshow_controller.dart` 与
/// `controller/reader_action_controller.dart`；这里只回答「下一拍该干什么」，
/// 因为结束策略与「页还没出图就别说翻过了」这两条是最容易写错、
/// 也最需要在没有 Widget 的情况下被测的部分。
library;

/// 一章放完之后干什么。
///
/// 档位取自 mImageViewer 的 `SlideshowEndAction`（`settings.rs`），
/// 那里第三档是「换下一个文件夹」，本仓阅读器的对应物是「续到下一章」——
/// 无缝拼接已经把邻章接进来了，所以这一档不需要新机制。
enum ReaderSlideshowEndAction {
  /// 停在章末并关掉放映。
  stop,

  /// 回到本章第一页继续放。
  loopChapter,

  /// 让边界翻页自然把下一章接进来。
  nextChapter,
}

/// 下一拍的动作。
enum ReaderSlideshowTick {
  /// 正常前进一页（条漫则前进一屏）。
  advance,

  /// 这一拍什么都不做：目标页的像素还没到，翻过去只会先看到占位页码。
  ///
  /// 口径照 mImageViewer 的 `current_slideshow_frame_ready`：帧没就位就不推进，
  /// 而不是让放映「翻过了一页却没画出来」。
  hold,

  /// 回到本章第一页。
  loopToChapterStart,

  /// 关掉放映。
  stop,
}

/// 间隔上下限（毫秒）。
///
/// 与自动滚屏那两档刻意分开：幻灯片是「一页停 N 秒」，下限再小就变成了连翻，
/// 上限则要给「念完一页台词」留余地。
const int kReaderSlideshowIntervalMinMs = 800;
const int kReaderSlideshowIntervalMaxMs = 15000;
const int kReaderSlideshowIntervalDefaultMs = 4000;
const int kReaderSlideshowIntervalStepMs = 500;

/// 条漫一拍的推进距离（视口高度百分比）。
const int kReaderSlideshowColumnStepMinPercent = 30;
const int kReaderSlideshowColumnStepMaxPercent = 100;
const int kReaderSlideshowColumnStepDefaultPercent = 100;
const int kReaderSlideshowColumnStepStepPercent = 10;

int normalizeReaderSlideshowIntervalMs(int ms) =>
    ms.clamp(kReaderSlideshowIntervalMinMs, kReaderSlideshowIntervalMaxMs);

int normalizeReaderSlideshowColumnStepPercent(int percent) => percent.clamp(
  kReaderSlideshowColumnStepMinPercent,
  kReaderSlideshowColumnStepMaxPercent,
);

/// 这一拍该干什么。
///
/// 判据顺序是刻意的：**先看帧是否就位**，再看章末。反过来会在「最后一页正在解码」
/// 时先把放映关掉，用户看到的就是「放到最后一页自己停了，而且那一页是空的」。
ReaderSlideshowTick decideReaderSlideshowTick({
  required bool atChapterEnd,
  required bool frameReady,
  required bool hasNextChapter,
  required ReaderSlideshowEndAction endAction,
}) {
  if (atChapterEnd) {
    if (!frameReady) return ReaderSlideshowTick.hold;
    switch (endAction) {
      case ReaderSlideshowEndAction.stop:
        return ReaderSlideshowTick.stop;
      case ReaderSlideshowEndAction.loopChapter:
        return ReaderSlideshowTick.loopToChapterStart;
      case ReaderSlideshowEndAction.nextChapter:
        // 没有下一章可用时不退化成「静默循环」：停下来说明原因，
        // 比让最后一页反复重来更容易看懂。
        return hasNextChapter
            ? ReaderSlideshowTick.advance
            : ReaderSlideshowTick.stop;
    }
  }
  return frameReady ? ReaderSlideshowTick.advance : ReaderSlideshowTick.hold;
}
