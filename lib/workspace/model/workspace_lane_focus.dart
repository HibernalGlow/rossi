import 'dart:math' as math;

import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';

// 本文件**刻意不 import Flutter**（不 import `dart:ui`），与
// `workspace_layout_config.dart` / `workspace_strip_metrics.dart` 同一纪律：
// 它的唯一判据是 `dart run test/workspace/lane_focus_check.dart`，
// 而纯 Dart VM 加载不了 `package:flutter/foundation.dart`（`dart:ui` 缺失）。

/// 条带滚动位置的记账（**纯计算**）。
///
/// 契约（neoview `Layout contract` / `Edge reveal and lane focus`）把「显出一条
/// 泳道」定义成**移动条带**，而不是让泳道浮起来盖住别人。于是需要回答两个问题：
///
/// 1. **激活**一条泳道时条带该滚到哪里？—— 契约的要求是「**最小**的水平移动，
///    让这条泳道可用即可」，不是「把它居中」；
/// 2. 在视口边缘驻留（dwell）该揭示到哪？—— 揭示是**让相邻泳道进入视口**，
///    Reader 可以只留一部分。
///
/// 这两件事都不只是「滚到某个位置」：它们决定「用户点了一下之后画面会不会跳」。
/// 把一个已经很顺眼的画面重新居中，就是这个文件最容易犯的错，所以它值得被
/// 单独拎出来用断言钉住，而不是埋在 widget 的 `ScrollController.animateTo` 里。
///
/// ## 为什么宽度要从 [WorkspaceStripMetrics] 里取
///
/// 泳道的**实际**摆出宽度不总等于 `LaneConfig` 里的标称值：折叠态是 44dp、
/// Reader 在 solo 下是整条视口、有富余时富余全给 Reader。任何「另算一份宽度」
/// 的做法都会与条带分叉，于是算出来的滚动位置对不上画出来的东西。
/// 所以这里只接受 [WorkspaceStripMetrics]，把它已经算好的槽位累加成坐标。
class WorkspaceLaneFocusGeometry {
  /// 每条泳道的左边缘（相对条带内容原点）。
  final Map<String, double> start;

  /// 每条泳道的摆出宽度。
  final Map<String, double> width;

  /// 条带内容总宽（含分隔手柄）。
  final double contentWidth;

  const WorkspaceLaneFocusGeometry({
    required this.start,
    required this.width,
    required this.contentWidth,
  });

  /// 从**同一条** [metrics] 派生坐标 —— 顺序与宽度只有一个出处。
  factory WorkspaceLaneFocusGeometry.fromMetrics(WorkspaceStripMetrics metrics) {
    final starts = <String, double>{};
    final widths = <String, double>{};
    var cursor = 0.0;
    for (final slot in metrics.slots) {
      // 手柄也占位：它是「两条泳道之间的缝」，漏掉它整条带会整体左移一点点，
      // 累计到第三条泳道就是肉眼可见的错位。
      cursor += slot.width;
      final laneId = slot.laneId;
      if (laneId == null) continue;
      starts[laneId] = cursor - slot.width;
      widths[laneId] = slot.width;
    }
    return WorkspaceLaneFocusGeometry(
      start: starts,
      width: widths,
      contentWidth: metrics.contentWidth,
    );
  }

  bool containsLane(String laneId) => width.containsKey(laneId);

  double endOf(String laneId) => (start[laneId] ?? 0) + (width[laneId] ?? 0);

  /// 条带能滚的最后一位。内容比视口窄时**没有可滚的余地** —— 返回 0 而不是负数，
  /// 否则调用方一 clamp 就把负偏移当成合法值，画面会向左露白。
  double maxOffset(double viewportWidth) =>
      math.max(0, contentWidth - viewportWidth);

  /// 把 [offset] 收进合法区间。
  double clampOffset(double offset, double viewportWidth) =>
      offset.clamp(0, maxOffset(viewportWidth)).toDouble();

  /// **激活** [laneId] 时条带应处的偏移。
  ///
  /// 三条规则，按契约的优先级排列：
  ///
  /// 1. **已经在视口里就一动不动**。契约原话是「minimum horizontal movement
  ///    needed to make the lane usable」—— 一条已经完整可见的泳道所需的最小移动
  ///    是 0。把「居中」当成「聚焦」是最容易犯的错：用户点一条本来就在眼前的
  ///    泳道，画面却横移一下，那不是聚焦、是抖动。
  /// 2. **比视口宽**（Reader 在 solo 下就是）时对齐**最近的那条边**，
  ///    而不是硬对齐左边：从左往右点进来时对齐左边、从右往左点进来时对齐右边，
  ///    移动量才是最小的。
  /// 3. 比视口窄时移动**刚好够它完整可见**的量（右侧被裁就往左推够它，左侧被裁就往右推回来）。
  ///
  /// [keepReaderVisible] 打开时额外约束：Reader 泳道要**留一条窄缝**
  /// （[readerPeekWidth]）在视口里 —— 这样用户点一下那条缝就能回到 solo。
  /// 它是**在最小移动之上**再叠的一层，所以可能把目标泳道挤出去一点；
  /// 契约对此的措辞是「where possible」，即缝优先于「完整可见」。
  double focusOffset({
    required String laneId,
    required double viewportWidth,
    required double currentOffset,
    String? readerLaneId,
    double readerPeekWidth = 0,
    bool keepReaderVisible = false,
  }) {
    if (viewportWidth <= 0) return 0;
    final laneWidth = width[laneId];
    if (laneWidth == null) return clampOffset(currentOffset, viewportWidth);

    final current = clampOffset(currentOffset, viewportWidth);
    final laneStart = start[laneId]!;
    final laneEnd = laneStart + laneWidth;
    final limit = maxOffset(viewportWidth);

    double target;
    if (laneWidth >= viewportWidth) {
      // 对齐最近的边：两个候选只差 (laneWidth - viewportWidth)，
      // 取离当前位置更近的那个 = 移动更少。
      final alignStart = laneStart;
      final alignEnd = laneEnd - viewportWidth;
      target = (alignStart - current).abs() <= (alignEnd - current).abs()
          ? alignStart
          : alignEnd;
    } else if (current <= laneStart && laneEnd <= current + viewportWidth) {
      target = current; // 已完整可见 —— 不动
    } else if (laneStart < current) {
      target = laneStart; // 左边缘被裁：把它右推回视口
    } else {
      target = laneEnd - viewportWidth; // 右边缘被裁：把它左推进视口
    }

    if (keepReaderVisible &&
        readerLaneId != null &&
        readerLaneId != laneId &&
        containsLane(readerLaneId)) {
      final readerWidth = width[readerLaneId]!;
      // 缝不能超过 Reader 自己、也不能超过半个视口 —— 否则「留缝」变成
      // 「视口里全是 Reader 的残影」，目标泳道反而看不见了。
      final peek = math.min(
        readerPeekWidth,
        math.min(readerWidth, viewportWidth / 2),
      );
      final readerStart = start[readerLaneId]!;
      final readerEnd = readerStart + readerWidth;
      if (readerEnd <= laneStart) {
        // Reader 在左边：偏移不能大到把它整条推出视口。
        target = math.min(target, readerEnd - peek);
      } else if (readerStart >= laneEnd) {
        // Reader 在右边：偏移不能小到让它只剩不到一条缝。
        target = math.max(target, readerStart - (viewportWidth - peek));
      }
    }

    return target.clamp(0, limit).toDouble();
  }

  /// 在视口边缘驻留后**揭示** [laneId] 时条带应处的偏移。
  ///
  /// 与 [focusOffset] 的差别是「不保 Reader」：揭示的目的就是把相邻泳道**看全**，
  /// 所以直接把它整条推进视口（对齐它的右边缘），Reader 该被推出多少就推出多少。
  /// 装不下时（比视口还宽的面板泳道）退回对齐它的左边缘。
  double revealOffset({required String laneId, required double viewportWidth}) {
    if (viewportWidth <= 0) return 0;
    final laneWidth = width[laneId];
    if (laneWidth == null) return 0;
    final laneStart = start[laneId]!;
    final laneEnd = laneStart + laneWidth;
    final target = laneWidth >= viewportWidth
        ? laneStart
        : laneEnd - viewportWidth;
    return clampOffset(target, viewportWidth);
  }
}
