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

  /// 这一页显示的是**降级产物**：擦字与回填都做了，但译文一个都没有（端点不可用）。
  /// 单列一个状态是因为它「看着像成功」——不标出来，用户会以为自己已经看到译文了。
  showingOriginal,

  /// 上一次尝试失败了，带原因。
  failed,
}

/// [phase]/[phaseIndex] 来自控制器（它只记最后一次操作的那一页），
/// [owned]/[index] 是「当前页归不归译文管」与当前页号。
///
/// 关键在 `phaseIndex == index` 这个条件：控制器是**全局一份**状态，
/// 用户翻走之后，旧页的「生成中 / 失败」不能继续顶在新页上 ——
/// 那等于让新页替旧页挨骂。
TranslatedPageChipState translatedPageChipState({
  required TranslatedPagePhase phase,
  required int phaseIndex,
  required int index,
  required bool owned,
  bool degraded = false,
}) {
  if (owned) {
    return degraded
        ? TranslatedPageChipState.showingOriginal
        : TranslatedPageChipState.showing;
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
      TranslatedPageChipState.off ||
      TranslatedPageChipState.failed ||
      TranslatedPageChipState.showing ||
      TranslatedPageChipState.showingOriginal => TranslatedPageTap.toggle,
    };
