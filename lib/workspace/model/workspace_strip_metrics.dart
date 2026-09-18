import 'package:zephyr/workspace/model/workspace_layout_config.dart';

// 本文件**刻意不 import Flutter**（不 import `dart:ui`），见
// `workspace_layout_config.dart` 顶部的说明：这段几何的唯一判据是
// `dart run test/workspace/strip_metrics_check.dart`。

/// 泳道条带里的一个槽位：要么是一条泳道，要么是两条泳道之间的分隔手柄。
class WorkspaceStripSlot {
  /// 泳道 id；`null` 表示分隔手柄。
  final String? laneId;

  /// 摆放宽度。
  final double width;

  /// 这条泳道是否处于折叠（44dp 紧凑轨）状态。手柄恒为 `false`。
  final bool collapsed;

  /// 手柄两侧的泳道 id（泳道槽位为 `null`）。
  ///
  /// 手柄必须自己记住它分开的是哪两条泳道：拖拽回调要按「一对泳道」改比例，
  /// 让调用方再从条带顺序里反推「上一个/下一个」等于把这份记账复制一遍。
  final String? beforeLaneId;
  final String? afterLaneId;

  const WorkspaceStripSlot.lane(String id, this.width, {this.collapsed = false})
    : laneId = id,
      beforeLaneId = null,
      afterLaneId = null;

  const WorkspaceStripSlot.resizer(
    this.width, {
    required String before,
    required String after,
  }) : laneId = null,
       collapsed = false,
       beforeLaneId = before,
       afterLaneId = after;

  bool get isResizer => laneId == null;

  @override
  String toString() => isResizer
      ? 'resizer(${width}px, $beforeLaneId→$afterLaneId)'
      : '$laneId(${width}px${collapsed ? ', collapsed' : ''})';
}

/// 水平泳道条带的宽度分配结果（**纯计算**，不碰 widget）。
///
/// 为什么要单独拎出来：这段几何是**唯一一处「算错了不会有编译错误、
/// 只会让界面多一条黄黑斜纹」**的逻辑。Flutter 的溢出提示
/// （`rendering/debug_overflow_indicator.dart`）会把溢出容器的右侧 10%
/// 涂成斜纹、并在右端竖着写一行 `RIGHT OVERFLOWED BY n PIXELS`，
/// 看上去像界面装饰而不是报错。
///
/// 2026-09-18 就是这么中招的：截图里右侧那条「黄色装饰」实测宽 161px、
/// 占窗口（1625 宽）的 9.9%，把右端那行旋转文字转正读到的是
/// **`RIGHT OVERFLOWED BY 16 PIXELS`** —— 16 = 条带左右内边距之和。
/// 成因是富余按**视口宽**算（`viewportWidth - total`），而 `Row` 拿到的
/// 可用宽是**扣掉内边距**的 `availableWidth`，于是富余多算了 16px，
/// `Row` 被撑出容器。所以这里 [resolve] 收两个宽度，且**不变量是
/// `contentWidth <= availableWidth`**（除非 `needsScroll`）。
class WorkspaceStripMetrics {
  final List<WorkspaceStripSlot> slots;

  /// 所有槽位宽度之和。**[needsScroll] 为假时它 ≤ 可用宽度**。
  final double contentWidth;

  /// 装不下，需要整条带横向滚动。
  final bool needsScroll;

  /// 条带的内边距（左右各一份）。它是**可用宽与视口宽之差**。
  static const double defaultPadding = 8.0;

  /// 泳道之间分隔手柄的宽度（neoview 的 `RESIZER_WIDTH`）。
  ///
  /// 放在这里而不是 widget 里：手柄宽度直接参与条带的宽度分配，
  /// 而判据（纯 Dart 脚本）加载不了 widget —— 两个常量必须同源。
  /// `LaneResizer.width` 引用本值。
  static const double defaultResizerWidth = 10.0;

  /// 亚像素容差：差值在这个量级内就从**阅读器**身上抹平，不走滚动。
  ///
  /// 不能只判断 `spare > 0` 就收手：那样当条带比可用宽只多 0.3px 时，
  /// `needsScroll` 为假、`Row` 却仍然溢出——Flutter 判溢出用的是
  /// `overflow.right > 0.0`，**没有容差**，于是照样画斜纹。
  /// 也就是说「不滚动的判据」必须比「溢出告警的判据」更严：这里把
  /// 小到看不见的差值直接吃掉，让 `contentWidth` 精确等于可用宽。
  static const double fitTolerance = 0.5;

  const WorkspaceStripMetrics({
    required this.slots,
    required this.contentWidth,
    required this.needsScroll,
  });

  /// 按泳道性质分配宽度。三条不变量（neoview 契约）：
  ///
  /// 1. **面板泳道是绝对像素、不按窗口宽夹取**；阅读器泳道是**视口比例**
  ///    （`viewportWidth × widthRatio`）—— 所以比例要乘**视口宽**；
  /// 2. 有富余宽度时**富余全部给阅读器**（中央弹性填充）；
  /// 3. 装不下时各自保持存储宽度、**整条带横向滚动**（泳道之间永不重叠）。
  ///
  /// [availableWidth] 必须是**扣掉条带内边距之后**的宽度。它与
  /// [viewportWidth] 是两个不同的量，不能互相顶替 —— 用视口宽算富余，
  /// 富余就多算一份内边距，`Row` 被撑出容器，界面上多一条黄黑斜纹。
  ///
  /// [soloLaneId] 是**独占**（neoview：Reader solo）的那条泳道：它这一档的
  /// 生效宽度是**整条可用宽**，于是「独占」不再是另一套版式（原先它是
  /// `Row[折叠轨, Expanded(solo), 折叠轨]` 的独立分支），而是**同一条条带上的
  /// 一个宽度**。这一点是「显出一条泳道靠移动条带」的前提：只有同一条条带，
  /// 边缘驻留的**揭示**才有东西可滚 —— 独立分支里的 `Expanded` 根本滚不动，
  /// 于是揭示无从实现。
  ///
  /// **只在该泳道同时也是激活泳道时才传它**（契约：solo 的生效宽度以
  /// 「Reader 泳道处于激活态」为前提；激活别的泳道会让 Reader 变回常规宽度，
  /// 但不清除 solo 偏好 —— 重新点回 Reader 时才恢复独占呈现）。
  factory WorkspaceStripMetrics.resolve({
    required WorkspaceLayoutConfig layout,
    required double viewportWidth,
    required double availableWidth,
    required double resizerWidth,
    String? soloLaneId,
  }) {
    // 1. 每条泳道先按自己的计量单位算宽度
    final widths = <String, double>{};
    final collapsed = <String, bool>{};
    for (final laneId in layout.laneOrder) {
      final lane = layout.lanes[laneId];
      if (lane == null) continue;
      final isCollapsed = lane.collapsed;
      // 独占泳道：撑满可用宽（折叠态优先 —— 折叠是用户更明确的意图）。
      final isSolo = laneId == soloLaneId && !isCollapsed;
      widths[laneId] = isCollapsed
          ? WorkspaceLayoutConfig.collapsedLaneWidth
          : isSolo
          ? availableWidth
          : lane.resolveWidth(viewportWidth);
      collapsed[laneId] = isCollapsed;
    }

    // 1b. 手柄数**必须按「画手柄的那条规则」来数**，不能按「可见泳道数 − 1」。
    //     两者在折叠泳道**夹在中间**时不等价：左(未折叠) / 中(折叠) / 右(未折叠)
    //     画出来是「左 + 折叠轨 + 右」，**一个手柄都没有**（折叠轨旁边不放手柄），
    //     但「可见泳道数 − 1」会算出 1。多算的这一份会把 `contentWidth` 报大、
    //     让条带在还放得下的时候就横向滚动（更糟的是它与槽位之和不再相等，
    //     而槽位之和才是真正的占位宽度）。
    var resizerCount = 0;
    String? previousLane;
    for (final laneId in layout.laneOrder) {
      if (!widths.containsKey(laneId)) continue;
      final isCollapsed = collapsed[laneId]!;
      if (previousLane != null &&
          !isCollapsed &&
          collapsed[previousLane] == false) {
        resizerCount++;
      }
      previousLane = laneId;
    }

    var contentWidth = resizerWidth * resizerCount;
    for (final width in widths.values) {
      contentWidth += width;
    }

    // 2. 富余给阅读器 —— 按**可用宽度**算。
    //
    //    阅读器泳道是唯一的弹性泳道，所以亚像素级的差也由它吸收：
    //    正差值就是「富余」（有多少吃多少），小的负差值（条带比可用宽
    //    只多一丁点）也把它吃掉，好过为 0.3px 去画一条斜纹。
    //    只有真的装不下（差值小于 −[fitTolerance]）才交给横向滚动。
    //    吸收后 `contentWidth` 等于可用宽**是赋出来的、不是加出来的** ——
    //    累加出来的浮点尾数正好是溢出告警的触发条件（它容差为 0）。
    final spare = availableWidth - contentWidth;
    final readerWidth = widths[LaneId.reader];
    final readerIsElastic =
        (readerWidth ?? 0) > 0 && collapsed[LaneId.reader] == false;
    if (readerIsElastic && spare >= -fitTolerance && readerWidth! + spare > 0) {
      widths[LaneId.reader] = readerWidth + spare;
      contentWidth = availableWidth;
    }

    // 3. 到了这里「要不要滚」就是纯粹的二选一，没有容差灰色地带：
    //    不滚动 ⇒ 槽位之和 ≤ 可用宽 ⇒ `Row` 不可能溢出。
    final needsScroll = contentWidth > availableWidth;

    // 4. 按顺序拼装：泳道 + 相邻泳道之间的分隔手柄。
    //    柄的判定与 1b 必须**逐字同源**，否则 `contentWidth` 与槽位之和会分叉。
    final slots = <WorkspaceStripSlot>[];
    String? previous;
    for (final laneId in layout.laneOrder) {
      final width = widths[laneId];
      if (width == null) continue;
      final isCollapsed = collapsed[laneId]!;
      if (previous != null && !isCollapsed && collapsed[previous] == false) {
        slots.add(
          WorkspaceStripSlot.resizer(
            resizerWidth,
            before: previous,
            after: laneId,
          ),
        );
      }
      slots.add(
        WorkspaceStripSlot.lane(laneId, width, collapsed: isCollapsed),
      );
      previous = laneId;
    }

    return WorkspaceStripMetrics(
      slots: slots,
      contentWidth: contentWidth,
      needsScroll: needsScroll,
    );
  }
}
