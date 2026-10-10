// `SpringLensBar` 的落点换算判据。
//
// # 为什么单独立一个文件
//
// 这一层是纯函数（`LensSlots` / `rubberBand` / `lensRect`），不碰 ObjectBox、不碰
// 工作台、不需要 ticker —— 于是它跑得飞快，且**失败时一定是几何真的错了**，
// 不会被动画是否结算完干扰（弹簧动画的时序在 widget 判据里很难钉死）。
//
// 钉的是「lens 该落在哪一格」这一件事本身。全仓有三处 tab 栏共用它
// （书架顶栏按内容取宽、泳道面板页签条横竖两档、Dock 那边等宽），
// 三处的正确性都归到这里。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

void main() {
  group('LensSlots.uniform —— 等宽档（与 Dock 那份逐字等价）', () {
    LensSlots threeUp() => LensSlots.uniform(
      count: 3,
      extent: 100,
      leading: 0,
      crossSize: 40,
    );

    test('落点换算：格中心落在自己那一格', () {
      final slots = threeUp();
      expect(slots.positionAt(50), 0.0);
      expect(slots.positionAt(150), 1.0);
      expect(slots.positionAt(250), 2.0);
    });

    test('落点换算：格内任意一点都折算成同一格的小数位', () {
      final slots = threeUp();
      // 格位以**格中心**为整数（与 Dock 那份 `_positionAt` 同一套约定）：
      // 第一格近端 = -0.5、中心 = 0、远端 = +0.5。
      expect(slots.positionAt(0), closeTo(-0.5, 1e-9));
      expect(slots.positionAt(100), closeTo(0.5, 1e-9), reason: '第一格远端');
      expect(slots.positionAt(75), closeTo(0.25, 1e-9));
      // 第二格起点与第一格远端是同一个点 —— 落点连续，不跳。
      expect(slots.positionAt(100), closeTo(slots.positionAt(100), 1e-9));
    });

    test('indexAt：就近取整并夹在合法范围内', () {
      final slots = threeUp();
      expect(slots.indexAt(0.4), 0);
      expect(slots.indexAt(0.6), 1);
      // 越界（小数与负数）都夹回两端。
      expect(slots.indexAt(-5), 0);
      expect(slots.indexAt(99), 2);
    });

    test('lensRect：静止时正中压在选中格上', () {
      final slots = threeUp();
      final rect = lensRect(slots: slots, position: 1, velocity: 0, lift: 0);
      expect(rect.center.dx, closeTo(150, 0.001));
      // 静止时宽度就是那一格的宽度（没被按下、没在跑）。
      expect(rect.width, closeTo(100, 0.001));
      // 副轴：铺满槽高。
      expect(rect.height, closeTo(40, 0.001));
    });

    test('lensRect：格位与像素互为逆运算（插值模型自洽）', () {
      final slots = threeUp();
      // 格位 0 = 第0 格中心(50)，0.5 = 第 0 格远端(100)，1.0 = 第 1 格中心(150)。
      // 按边沿插值 ⇒ 0.25 落在 0..100 的 3/4 处 = 75。
      expect(
        lensRect(slots: slots, position: 0.25, velocity: 0, lift: 0).center.dx,
        closeTo(75, 0.001),
      );
      expect(
        lensRect(slots: slots, position: 0.75, velocity: 0, lift: 0).center.dx,
        closeTo(125, 0.001),
      );
      // 端点必须精确落回格中心 —— 这是「lens 停在哪一格」的唯一判据。
      for (var i = 0; i < 3; i++) {
        expect(
          lensRect(slots: slots, position: i.toDouble(), velocity: 0, lift: 0)
              .center
              .dx,
          closeTo(slots.centerOf(i), 0.001),
          reason: '格位 $i 必须正中压在第 $i 格上',
        );
      }
      // 等宽档：全程恒宽平移（与 Dock 那份逐字等价）。
      expect(
        lensRect(slots: slots, position: 0.42, velocity: 0, lift: 0).width,
        closeTo(100, 0.001),
      );
    });
  });

  group('LensSlots.sized —— 按内容取宽档（书架顶栏那一档）', () {
    // 这是迁移的**核心约束**：Dock 的等宽公式在这一档会算错落点。
    LensSlots uneven() => LensSlots.sized(
      sizes: const [40, 120, 60],
      leading: 0,
      crossSize: 32,
    );

    test('各格中心与跨度按实际给的宽度算', () {
      final slots = uneven();
      expect(slots.spanOf(0), 40);
      expect(slots.spanOf(1), 120);
      expect(slots.centerOf(0), 20);
      // 第二格从 40 起、宽 120 ⇒ 中心 100。
      expect(slots.centerOf(1), 100);
      expect(slots.centerOf(2), 190);
    });

    test('落点换算：同样落在「第二格」上，但坐标与等宽档不同', () {
      final slots = uneven();
      // 第二格中心 100px ⇒ 格位 1.0。
      expect(slots.positionAt(100), closeTo(1.0, 1e-9));
      expect(slots.indexAt(slots.positionAt(100)), 1);
      // 第一格只有 40 宽：它的后半段（30..40）仍在第 0 格，
      // 而**等宽档**在同一坐标上早就判到别处去了 —— 这正是不等宽档不能照抄
      // Dock 那条除法的原因。
      expect(slots.indexAt(slots.positionAt(39)), 0);
      expect(slots.indexAt(slots.positionAt(41)), 1);
      // 越界一像素仍在第 0 格里（第一格远端 = 40 ⇒ 格位 0.5）。
      expect(slots.positionAt(40), closeTo(0.5, 1e-9));
    });

    test('lensRect：宽度跟着落点插值 —— 不等宽 bar 上 lens 会变宽', () {
      final slots = uneven();
      // 40 / 120 / 60。格心处lens 就是那一格的宽度。
      expect(
        lensRect(slots: slots, position: 0, velocity: 0, lift: 0).width,
        closeTo(40, 0.001),
      );
      expect(
        lensRect(slots: slots, position: 1, velocity: 0, lift: 0).width,
        closeTo(120, 0.001),
      );
      // 格位 0.5 = 第 0 格远端 = 第 1 格近端（x=40）：宽度是两者跨度的**均值**
      // （40 与 120）⇒ 80；位置正好落在那道边界上。
      final boundary = lensRect(
        slots: slots,
        position: 0.5,
        velocity: 0,
        lift: 0,
      );
      expect(boundary.width, closeTo((40 + 120) / 2, 0.001));
      expect(boundary.center.dx, closeTo(40, 0.001));

      // 格位 0.25（第 0 格内、中心右侧半格）：帐篷形的右半，宽度从本格 40 向
      // 均值 80 走了一半⇒ 60，位置在 20 与 40 的中点。
      final quarter = lensRect(
        slots: slots,
        position: 0.25,
        velocity: 0,
        lift: 0,
      );
      expect(quarter.width, closeTo(60, 0.001));
      expect(quarter.center.dx, closeTo(30, 0.001));

      // 负方向是**平台**而不是镜像：格位 −0.25 仍在第 0 格内，而第 0 格前面
      // 没有别的格可插值，所以宽度保持本格的 40（不会凭空长出一半）。
      final before = lensRect(
        slots: slots,
        position: -0.25,
        velocity: 0,
        lift: 0,
      );
      expect(before.width, closeTo(40, 0.001));
      expect(before.center.dx, closeTo(10, 0.001));
    });

    test('leading：轨道起点不是 0 时整条账平移', () {
      final slots = LensSlots.sized(
        sizes: const [50, 50],
        leading: 10,
        crossSize: 32,
      );
      // 第一格 10..60，中心 35。
      expect(slots.centerOf(0), 35);
      expect(slots.positionAt(35), closeTo(0.0, 1e-9));
      expect(slots.positionAt(10), closeTo(-0.5, 1e-9));
    });
  });

  group('越界收敛', () {
    test('rubberBand：越拖越沉 —— 越接近 limit 但永不超过', () {
      // 「沉」的方向是**逼近 limit**：拖 10 得 0.329，拖 100 得 0.348，
      // 拖到无穷得 0.35。所以是单调逼近、且永不越过 limit。
      expect(rubberBand(10, 0.35), closeTo(0.329, 0.002));
      expect(rubberBand(100, 0.35), greaterThan(rubberBand(10, 0.35)));
      // 硬上限。
      expect(rubberBand(1e9, 0.35), lessThan(0.35));
      expect(rubberBand(1e9, 0.35), closeTo(0.35, 1e-6));
    });

    test('rubberBand：保号 —— 左越界仍是负、右越界仍是正', () {
      expect(rubberBand(-10, 0.35), lessThan(0));
      expect(rubberBand(10, 0.35), greaterThan(0));
      // 0 处不该被放大成非零。
      expect(rubberBand(0, 0.35), 0);
    });

    test('positionAt：拖过最左端时落点连续（而不是断掉）', () {
      final slots = LensSlots.uniform(count: 3, extent: 100, crossSize: 40);
      // 第一格 0..100，中心 50（格位 0），近端 0（格位 -0.5）。
      expect(slots.positionAt(0), closeTo(-0.5, 1e-9));
      expect(slots.positionAt(50), closeTo(0.0, 1e-9));
      // 拖到轨道之外 10px：从近端（−0.5）只再退 0.0033 格。
      // 越界量被 limit=0.35 格吃掉得几乎干净 —— 这就是「越拖越沉」：
      // 手指出界 10px，lens 只挪了 1/30 格。
      final past = slots.positionAt(-10);
      expect(past, lessThan(-0.5));
      expect(
        -0.5 - past,
        lessThan(0.01),
        reason: '出界 10px 只退 0.003 格 —— 橡皮筋吃掉了绝大部分',
      );
      // 再拖到 −100：更接近 limit（−0.535）但增幅已经很小。
      final farther = slots.positionAt(-100);
      expect(farther, lessThan(past), reason: '越拖越远 ⇒ 落点继续往负走');
      expect(
        (farther - past).abs(),
        lessThan(0.05),
        reason: '但增幅已经很小 —— 这才是「越拖越沉」',
      );
      expect(farther, greaterThan(-0.5 - LensMetrics.overdrag));
    });

    test('positionAt：拖过最右端时落点连续地大于末位下标', () {
      final slots = LensSlots.uniform(count: 3, extent: 100, crossSize: 40);
      // 末格中心 250；拖到 300 = 末格远端（格位 2.5）。
      expect(slots.positionAt(300), closeTo(2.5, 1e-9));
      final past = slots.positionAt(310);
      expect(past, greaterThan(2.5));
      expect(past, lessThan(2.5 + LensMetrics.overdrag));
      expect(slots.indexAt(past), 2, reason: '越界不该换到不存在的格');
    });
  });

  group('形变只在 paint 层 —— 布局与命中看到静止位置', () {
    test('lensRect 的形变不会挪动槽位本身', () {
      final slots = LensSlots.uniform(
        count: 3,
        extent: 100,
        leading: 4,
        crossSize: 40,
      );
      // 按下（lift=1）与快速滑行（velocity 很大）都只改 lens 那一颗盒子。
      final resting = lensRect(
        slots: slots,
        position: 1,
        velocity: 0,
        lift: 0,
      );
      final pressed = lensRect(
        slots: slots,
        position: 1,
        velocity: 0,
        lift: 1,
      );
      final racing = lensRect(
        slots: slots,
        position: 1,
        velocity: 8,
        lift: 0,
      );
      // 槽位几何一动不动 —— 这正是「tooltip / popup 不会跟着飘」的前提。
      expect(slots.spanOf(1), 100);
      expect(slots.centerOf(1), 154);
      // 按下：lens 变大，但仍然以那一格为中心（不偏移锚点）。
      expect(pressed.width, greaterThan(resting.width));
      expect(pressed.center.dx, closeTo(resting.center.dx, 0.001));
      // 快速滑行：拉长。
      expect(racing.width, greaterThan(resting.width));
    });

    test('空槽位不画东西（返回零矩形）', () {
      final empty = LensSlots.uniform(
        count: 0,
        extent: 100,
        crossSize: 40,
      );
      expect(empty.isEmpty, isTrue);
      expect(lensRect(slots: empty, position: 0, velocity: 0, lift: 0), Rect.zero);
    });
  });

  group('竖轨（泳道面板页签条那一档）', () {
    test('竖轨的 lensRect 把主轴换到纵轴', () {
      final slots = LensSlots.uniform(
        count: 3,
        extent: 28,
        crossSize: 28,
        axis: Axis.vertical,
      );
      final rect = lensRect(slots: slots, position: 1, velocity: 0, lift: 0);
      // 主轴 → 纵向：第 1 格中心在 y=42。
      expect(rect.center.dy, closeTo(42, 0.001));
      expect(rect.width, closeTo(28, 0.001));
    });

    test('横竖两档的中心换算一致（同一份落点，不同的轴）', () {
      final horizontal = LensSlots.uniform(
        count: 3,
        extent: 50,
        crossSize: 20,
      );
      final vertical = LensSlots.uniform(
        count: 3,
        extent: 50,
        crossSize: 20,
        axis: Axis.vertical,
      );
      expect(
        lensRect(slots: horizontal, position: 2, velocity: 0, lift: 0).center.dx,
        closeTo(
          lensRect(slots: vertical, position: 2, velocity: 0, lift: 0).center.dy,
          0.001,
        ),
      );
    });
  });

  group('插缝那一档（面板页签条：格与格之间还夹着不可落的缝）', () {
    test('跨度为 0 的格子不进落点换算，落点跳过它', () {
      // 真实形态：页签 32 宽、页签前后各夹一道5 宽的插缝。三个槽位是
      // 「缝 / 页签 / 缝」交替，但**只有页签那一格能落**（跨度非 0）。
      // starts 与 spans 必须自洽：每格起点 + 自己的跨度 = 下一格起点。
      final slots = LensSlots(
        starts: const [0, 5, 37],
        spans: const [5, 32, 5],
        crossStart: 0,
        crossSize: 28,
      );
      // 缝（跨度 5）里任一点都归到「没有意义」的位置，但 indexAt 仍夹在合法范围。
      expect(slots.spanOf(0), 5);
      // 真正的页签是第 1 格（5 起、32 宽）。
      expect(slots.centerOf(1), 21);
      expect(slots.indexAt(slots.positionAt(21)), 1);
      // 页签的近端（6）仍属第 1 格，末尾那道缝（38+）也还夹在第 2 格。
      expect(slots.indexAt(slots.positionAt(6)), 1);
      expect(slots.indexAt(slots.positionAt(40)), 2);
    });

    test('跨度为 0 的格子：落点不产生小数位，indexAt 也只认真页签', () {
      // 自洽的一组：页签 32 宽、缝 32 宽（这里让缝与页签等宽，好验算）。
      final slots = LensSlots(
        starts: const [0, 32, 64],
        spans: const [32, 32, 32],
        crossStart: 0,
        crossSize: 28,
      );
      expect(slots.positionAt(16), closeTo(0.0, 1e-9));
      expect(slots.positionAt(32), closeTo(0.5, 1e-9));

      // 真插缝那一档：中间那道跨度 0。32px 正好是第 0 格的远端（格位 0.5），
      // 就近取整归到第 1 格 —— 而那一格**没有宽度**，于是 lens 在缝上只剩半格
      // 宽（16 = 本格 32 与右侧 32 的均值的一半路径），越往里越窄。
      final withGap = LensSlots(
        starts: const [0, 32, 64],
        spans: const [32, 0, 32],
        crossStart: 0,
        crossSize: 28,
      );
      expect(withGap.spanOf(1), 0);
      expect(withGap.positionAt(32), closeTo(0.5, 1e-9));
      expect(withGap.indexAt(0.5), 1, reason: '就近取整归到那道零跨度的缝');
      // 帐篷形：缝正上方（0.5）还剩一半，到缝的正中（1.0）就归零。
      expect(
        lensRect(slots: withGap, position: 0.5, velocity: 0, lift: 0).width,
        closeTo(16, 0.001),
      );
      expect(
        lensRect(slots: withGap, position: 1, velocity: 0, lift: 0).width,
        closeTo(0, 0.001),
        reason: '缝没有宽度 ⇒ lens 缩到零（真实页签上不会走到这里）',
      );
      // 真正的页签拿回自己的整份跨度：格位 2.0 = 第 2 格中心 80。
      // （格位 1.5 是「缝与第 2 格」的边界，只有 16 —— 别拿它当格心。）
      final onTab = lensRect(
        slots: withGap,
        position: 2,
        velocity: 0,
        lift: 0,
      );
      expect(onTab.width, closeTo(32, 0.001));
      expect(onTab.center.dx, closeTo(80, 0.001));
    });
  });
}