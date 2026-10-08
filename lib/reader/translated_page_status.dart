import 'package:zephyr/reader/translated_page_controller.dart';

/// 顶栏「译」芯片该显示成什么 —— **纯函数**，与 widget 分开，因为这张表就是判据本身。
///
/// 抄的是超分那边的做法（`super_resolution_status.dart`）：芯片最容易出的错不是画不出来，
/// 而是**状态说错** —— 把「这一页没翻译」显示成「译文页」，或者反过来把失败显示成空闲。
/// 那类错在 widget 测试里要点好几层才能触发，在这张表上是一行 `expect`。
enum TranslatedPageChipState {
  /// 这一页没翻译，可以点。
  off,

  /// 这一页正在生成。
  building,

  /// 这一页正显示成品页，再点回原图。
  showing,

  /// 成品页已经注入，但「原图对比」旁路正把它挡着 —— 画面上是原图。
  ///
  /// 单列是因为它两头都不像：说「译文页」是在谎报画面（那正是这次修的事），
  /// 说「译文失败」又在指控一个其实已经成功的操作，而且会诱使用户反复重点、
  /// 每一页都重跑十几秒。
  blockedByOriginalPreview,

  /// 上一次尝试失败了，带原因。
  failed,
}

/// [phase]/[phaseIndex] 来自控制器（它只记最后一次操作的那一页），
/// [owned]/[index] 是「当前页归不归译文管」与当前页号。
///
/// [bypassed] 是呈现器的「原图对比」旁路状态。归属要说的是**画面上**是不是译文页，
/// 而旁路开着时那一条轨按设计不参显，所以归属成立、显示却不成立 —— 这两件事
/// 必须在这里分开，否则芯片会在每一页上都写成「译文页」。
///
/// 关键在 `phaseIndex == index` 这个条件：控制器是**全局一份**状态，
/// 用户翻走之后，旧页的「生成中 / 失败」不能继续顶在新页上 ——
/// 那等于让新页替旧页挨骂。
TranslatedPageChipState translatedPageChipState({
  required TranslatedPagePhase phase,
  required int phaseIndex,
  required int index,
  required bool owned,
  bool bypassed = false,
}) {
  if (owned) {
    if (bypassed) {
      return TranslatedPageChipState.blockedByOriginalPreview;
    }
    return TranslatedPageChipState.showing;
  }
  if (phaseIndex != index) return TranslatedPageChipState.off;
  return switch (phase) {
    TranslatedPagePhase.building => TranslatedPageChipState.building,
    TranslatedPagePhase.failed => TranslatedPageChipState.failed,
    TranslatedPagePhase.showing => TranslatedPageChipState.showing,
    TranslatedPagePhase.off => TranslatedPageChipState.off,
  };
}

/// 点击该做什么。同样是纯函数：UI 只负责照做，不自己判断。
enum TranslatedPageTap { wait, toggle }
TranslatedPageTap translatedPageTapFor(TranslatedPageChipState state) =>
    switch (state) {
      TranslatedPageChipState.building => TranslatedPageTap.wait,
      // 「被原图对比挡住」也照点：这一页确实归译文管，点它就是把译文关掉，
      // 与「译文页」的语义一致（旁路开着时关译文同样走得通）。
      TranslatedPageChipState.blockedByOriginalPreview ||
      TranslatedPageChipState.off ||
      TranslatedPageChipState.failed ||
      TranslatedPageChipState.showing => TranslatedPageTap.toggle,
    };

/// 「译文页」这一态下的第二维：中文是怎么上屏的。
///
/// 为什么芯片非得说这一维：叠层这一档的全部理由是**中文不烤进像素**，
/// 于是画面上的中文是「盖」上去的一层，不是烤进像素的；底图换哪一张、要不要占轨，
/// 由控制器按 `overlayNeedsBase` 那一维决定（今天恒占 —— 见 §4 那 0/121 的量数）。
/// 芯片只说「译文页」，用户就分不清自己手里那张到底是「两者都在」还是
/// 「译文把超分挤掉了」，而这两种画面在他眼里长得几乎一样。
enum TranslatedPageDisplay { baked, overlay }

/// 判据只有一条：**控制器有没有给这一页登记图层档名**。
///
/// 这一维不另起一本账是有意的 —— `TranslatedPageOverlay` 画的正是
/// `TranslatedPageController.overlayLabelFor(index)`，所以「画面上有没有那层字」
/// 与「芯片说是不是叠层」由同一个值决定，不会出现芯片说叠层而画面上是烤进像素的字
/// （或者反过来）。
///
/// 两类叠层页都算 [overlay]：每框都有填色的那一页（不占轨）与需要补擦字底图的那一页
/// （占轨）—— 两者都是「底图 + 上面盖字」，区别只在底图从哪来，芯片不必展开到那一层。
TranslatedPageDisplay translatedPageDisplayOf({required String? overlayLabel}) =>
    overlayLabel == null
        ? TranslatedPageDisplay.baked
        : TranslatedPageDisplay.overlay;
