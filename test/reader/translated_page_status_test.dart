/// 顶栏「译」芯片状态表的验证。
///
/// 芯片最容易出的不是画不出来，而是**状态说错**：新页替旧页挨骂、
/// 旧页的「生成中」一直顶在新页上。这些在 widget 树里要点好几层才能触发，
/// 在这张表上是一行 `expect`。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/reader/translated_page_status.dart';

void main() {
  TranslatedPageChipState state({
    required TranslatedPagePhase phase,
    required int phaseIndex,
    int index = 4,
    bool owned = false,
    bool degraded = false,
  }) => translatedPageChipState(
    phase: phase,
    phaseIndex: phaseIndex,
    index: index,
    owned: owned,
    degraded: degraded,
  );

  test('这一页归译文管就是 showing，不管控制器停在哪个阶段', () {
    // 翻回一张早已生成好的页时，控制器里可能还是 off / 别页的失败 ——
    // 但归属表说「这一页显示的是成品页」，那才是画面上的事实。
    for (final phase in TranslatedPagePhase.values) {
      expect(
        state(phase: phase, phaseIndex: 99, owned: true),
        TranslatedPageChipState.showing,
        reason: '$phase 时旧页的归属不该被盖掉',
      );
    }
  });

  test('别的页在生成 / 失败，不许顶到当前页脸上', () {
    expect(
      state(phase: TranslatedPagePhase.building, phaseIndex: 3),
      TranslatedPageChipState.off,
    );
    expect(
      state(phase: TranslatedPagePhase.failed, phaseIndex: 3),
      TranslatedPageChipState.off,
    );
  });

  test('当前页自己的阶段照实显示', () {
    expect(
      state(phase: TranslatedPagePhase.building, phaseIndex: 4),
      TranslatedPageChipState.building,
    );
    expect(
      state(phase: TranslatedPagePhase.failed, phaseIndex: 4),
      TranslatedPageChipState.failed,
    );
    expect(
      state(phase: TranslatedPagePhase.showing, phaseIndex: 4),
      TranslatedPageChipState.showing,
    );
    expect(
      state(phase: TranslatedPagePhase.off, phaseIndex: 4),
      TranslatedPageChipState.off,
    );
  });

  test('只有「生成中」把点击变成提示，其余都能点', () {
    expect(
      translatedPageTapFor(TranslatedPageChipState.building),
      TranslatedPageTap.wait,
    );
    for (final s in [
      TranslatedPageChipState.off,
      TranslatedPageChipState.showing,
      TranslatedPageChipState.failed,
    ]) {
      expect(translatedPageTapFor(s), TranslatedPageTap.toggle, reason: '$s');
    }
  });
}
