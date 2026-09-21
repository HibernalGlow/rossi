import 'package:flutter/material.dart' show Size, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/method/reader_gesture_logic.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';

/// 点击归一化成「哪一格」的判据（绑定表在位时的那一份分区）。
///
/// 盯的是两件事：
/// 1. **几何与改造前一致** —— 左半/正中/右半三档的边界一格都不能挪（挪了就是
///    「点哪儿都翻下一页」那一类老 bug 的复发）；
/// 2. **几何不认识左右手、也不认识阅读方向** —— 这两件事分别写在绑定表与引擎里，
///    采集端要是偷偷掺进去，就有了第二份判定，改绑定就不再生效（判据 E2）。
///
/// 第 2 条用「同一份几何、不同 mode/方向 ⇒ 同一格」来钉。
void main() {
  const viewport = Size(800, 800);

  String? area({
    required double x,
    required double y,
    bool isWebtoon = false,
    bool tapPageTurnInWebtoon = false,
    ReaderTapPageTurnMode mode = ReaderTapPageTurnMode.rightHand,
  }) => ReaderGestureLogic.tapInputAreaFor(
    sample: ReaderTapSample(
      localPosition: Offset(x, y),
      viewportSize: viewport,
    ),
    isWebtoon: isWebtoon,
    tapPageTurnInWebtoon: tapPageTurnInWebtoon,
    mode: mode,
  );

  group('三档的边界', () {
    test('正中那一格（横竖都在中间三分之一）→ middle-center', () {
      expect(area(x: 400, y: 400), TapArea.middleCenter);
      expect(area(x: 267, y: 267), TapArea.middleCenter);
      expect(area(x: 532, y: 532), TapArea.middleCenter);
    });

    test('横向居中但纵向在顶上 ⇒ 仍是翻页，不是上下栏', () {
      // 中心控制区是**正中那一格**（横竖都在中间三分之一），不是整条中轴；
      // 否则「点上部想唤出顶栏」会变成翻页。x=400 在 800 宽里属于右半（`>=` 那一侧）。
      expect(area(x: 400, y: 60), TapArea.middleRight);
      expect(area(x: 400, y: 760), TapArea.middleRight);
      expect(area(x: 399, y: 60), TapArea.middleLeft);
    });

    test('左右按半屏分（不按三分之一）', () {
      expect(area(x: 399, y: 100), TapArea.middleLeft);
      expect(area(x: 400, y: 100), TapArea.middleRight);
      expect(area(x: 1, y: 1), TapArea.middleLeft);
      expect(area(x: 799, y: 1), TapArea.middleRight);
    });

    test('退化视口一律 middle-center（可逆的那一档）', () {
      String? areaWithViewport(Size size, double x, double y) =>
          ReaderGestureLogic.tapInputAreaFor(
            sample: ReaderTapSample(
              localPosition: Offset(x, y),
              viewportSize: size,
            ),
            isWebtoon: false,
            tapPageTurnInWebtoon: false,
            mode: ReaderTapPageTurnMode.rightHand,
          );
      for (final size in const [
        Size(0, 0),
        Size(800, 0),
        Size(0, 800),
        Size(double.infinity, double.infinity),
      ]) {
        expect(
          areaWithViewport(size, 400, 100),
          TapArea.middleCenter,
          reason: '$size 量不出格子，不许落到翻页分支',
        );
      }
    });
  });

  group('几何不认识左右手与方向', () {
    test('leftHand / rightHand 在同一落点上给出**同一格**', () {
      for (final point in const [
        (400.0, 100.0),
        (100.0, 400.0),
        (700.0, 400.0),
      ]) {
        expect(
          area(x: point.$1, y: point.$2, mode: ReaderTapPageTurnMode.leftHand),
          area(x: point.$1, y: point.$2, mode: ReaderTapPageTurnMode.rightHand),
          reason: '哪一侧是前进热区写在绑定表里，不在这里',
        );
      }
    });

    test('fullScreen 档不做空间命中（返回 null 由调用方给语义动作）', () {
      expect(
        area(x: 100, y: 100, mode: ReaderTapPageTurnMode.fullScreen),
        isNull,
      );
      expect(
        area(x: 700, y: 100, mode: ReaderTapPageTurnMode.fullScreen),
        isNull,
      );
      // 但正中那一格仍然留给上下栏：这一档下那是唯一的 chrome 出口。
      expect(
        area(x: 400, y: 400, mode: ReaderTapPageTurnMode.fullScreen),
        TapArea.middleCenter,
      );
    });
  });

  group('条漫', () {
    test('没开「条漫点击翻页」时点哪儿都算中间', () {
      expect(area(x: 100, y: 100, isWebtoon: true), TapArea.middleCenter);
      expect(area(x: 700, y: 700, isWebtoon: true), TapArea.middleCenter);
    });

    test('开了之后按纵向两半分：上半 middle-left、下半 middle-right', () {
      expect(
        area(x: 100, y: 100, isWebtoon: true, tapPageTurnInWebtoon: true),
        TapArea.middleLeft,
      );
      expect(
        area(x: 100, y: 700, isWebtoon: true, tapPageTurnInWebtoon: true),
        TapArea.middleRight,
      );
      // 横向位置不参与判断（条漫没有左右）。
      expect(
        area(x: 700, y: 100, isWebtoon: true, tapPageTurnInWebtoon: true),
        TapArea.middleLeft,
      );
    });
  });

  // ── 与改造前那条路的等价性 ────────────────────────────────────────────────
  //
  // 「格子 → 动作 → 方向 → 哪一档」这三步在真机上是 引擎 + 绑定表 做的；判据宿主没有
  // 原生库，所以这里按 `preset.rs::tap_preset_bindings` 与 `resolve_page_turn` 的
  // 语义把那张表手抄成 `isPageRightCell`。Rust 侧另有
  // `right_hand_preset_binds_right_side_to_page_right` 等判据钉住这张表本身，
  // 两边一起改才不会悄悄分叉。
  group('与改造前的分区函数等价', () {
    bool isPageRightCell(ReaderTapPageTurnMode mode, String cell) =>
        switch (mode) {
          ReaderTapPageTurnMode.rightHand => cell == TapArea.middleRight,
          ReaderTapPageTurnMode.leftHand => cell == TapArea.middleLeft,
          ReaderTapPageTurnMode.fullScreen => true,
        };

    ReaderTapZone legacyZone({
      required double x,
      required double y,
      required ReaderTapPageTurnMode mode,
      required bool rightToLeft,
      bool isWebtoon = false,
      bool tapPageTurnInWebtoon = false,
    }) => ReaderGestureLogic.resolveTapZone(
      sample: ReaderTapSample(
        localPosition: Offset(x, y),
        viewportSize: viewport,
      ),
      isWebtoon: isWebtoon,
      tapPageTurnInWebtoon: tapPageTurnInWebtoon,
      mode: mode,
      rightToLeft: rightToLeft,
    );

    ReaderTapZone viaBinding({
      required double x,
      required double y,
      required ReaderTapPageTurnMode mode,
      required bool rightToLeft,
      bool isWebtoon = false,
      bool tapPageTurnInWebtoon = false,
    }) {
      final cell = ReaderGestureLogic.tapInputAreaFor(
        sample: ReaderTapSample(
          localPosition: Offset(x, y),
          viewportSize: viewport,
        ),
        isWebtoon: isWebtoon,
        tapPageTurnInWebtoon: tapPageTurnInWebtoon,
        mode: mode,
      );
      if (cell == null) return ReaderTapZone.nextPage; // fullScreen → 语义前进
      if (cell == TapArea.middleCenter) {
        return ReaderTapZone.toggleMenu;
      }
      return ReaderGestureLogic.spatialPageTurnIsNext(
            isPageRight: isPageRightCell(mode, cell),
            rightToLeft: rightToLeft,
          )
          ? ReaderTapZone.nextPage
          : ReaderTapZone.previousPage;
    }

    test('三档 × 左右手 × 左右开：两条路结论一样', () {
      const points = [
        (400.0, 400.0), // 正中
        (400.0, 60.0), // 中轴偏上
        (100.0, 400.0), // 左半
        (700.0, 400.0), // 右半
        (1.0, 1.0), // 左上角
        (799.0, 799.0), // 右下角
      ];
      for (final mode in ReaderTapPageTurnMode.values) {
        for (final rightToLeft in [false, true]) {
          for (final point in points) {
            expect(
              viaBinding(
                x: point.$1,
                y: point.$2,
                mode: mode,
                rightToLeft: rightToLeft,
              ),
              legacyZone(
                x: point.$1,
                y: point.$2,
                mode: mode,
                rightToLeft: rightToLeft,
              ),
              reason:
                  '$mode / ${rightToLeft ? '左开' : '右开'} / (${point.$1},${point.$2})',
            );
          }
        }
      }
    });

    test('条漫开了点击翻页后同样等价', () {
      for (final mode in [
        ReaderTapPageTurnMode.leftHand,
        ReaderTapPageTurnMode.rightHand,
        ReaderTapPageTurnMode.fullScreen,
      ]) {
        for (final point in const [
          (100.0, 100.0),
          (100.0, 700.0),
          (400.0, 400.0),
        ]) {
          expect(
            viaBinding(
              x: point.$1,
              y: point.$2,
              mode: mode,
              rightToLeft: false,
              isWebtoon: true,
              tapPageTurnInWebtoon: true,
            ),
            legacyZone(
              x: point.$1,
              y: point.$2,
              mode: mode,
              rightToLeft: false,
              isWebtoon: true,
              tapPageTurnInWebtoon: true,
            ),
            reason: '$mode / (${point.$1},${point.$2})',
          );
        }
      }
    });

    test('验收口径：左开点右半屏=上一页、点左半屏=下一页', () {
      expect(
        viaBinding(
          x: 700,
          y: 400,
          mode: ReaderTapPageTurnMode.rightHand,
          rightToLeft: true,
        ),
        ReaderTapZone.previousPage,
      );
      expect(
        viaBinding(
          x: 100,
          y: 400,
          mode: ReaderTapPageTurnMode.rightHand,
          rightToLeft: true,
        ),
        ReaderTapZone.nextPage,
      );
    });
  });
}
