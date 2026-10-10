import 'dart:math' as math;

/// MD3 栅格断点分类。
///
/// 参考 Material Design 3 规范：
/// - Compact: 宽度 < 480dp，对应 4 列栅格
/// - Medium: 480dp <= 宽度 <= 840dp，对应 8 列栅格
/// - Expanded: 宽度 > 840dp，对应 12 列栅格
enum WorkspaceGridBand {
  compact(columns: 4),
  medium(columns: 8),
  expanded(columns: 12);

  final int columns;

  const WorkspaceGridBand({required this.columns});

  static WorkspaceGridBand of(double width) {
    if (width < 480) {
      return WorkspaceGridBand.compact;
    } else if (width <= 840) {
      return WorkspaceGridBand.medium;
    } else {
      return WorkspaceGridBand.expanded;
    }
  }
}

/// 解析卡片的跨度列数（跨轴占用单元格数量）。
///
/// [widthSpan]: 卡片自身声明的逻辑宽度跨度 (1..4)：
/// - 1: 微卡 / 紧凑单元 (在 Compact 下占 2 列，Medium 下占 2 列，Expanded 下占 3 列，即 ~25%)
/// - 2: 半宽 / 半行 (在 Compact 下占 2 列 (50%)，Medium 下占 4 列 (50%)，Expanded 下占 6 列 (50%))
/// - 3: 3/4 宽 (在 Compact 下占 4 列 (100%)，Medium 下占 6 列 (75%)，Expanded 下占 8 列 (~66%))
/// - 4: 全宽 / 整行 (在任意断点下占满整行当前所有可用列)
int resolveCrossAxisCellCount({
  required int widthSpan,
  required WorkspaceGridBand band,
}) {
  final span = widthSpan.clamp(1, 4);
  switch (band) {
    case WorkspaceGridBand.compact:
      if (span <= 2) return 2;
      return 4;
    case WorkspaceGridBand.medium:
      if (span == 1) return 2;
      if (span == 2) return 4;
      if (span == 3) return 6;
      return 8;
    case WorkspaceGridBand.expanded:
      if (span == 1) return 3;
      if (span == 2) return 6;
      if (span == 3) return 8;
      return 12;
  }
}

/// 网格单位高度基准（单个高度跨度对应的高度，单位 dp）。
const double workspaceDefaultUnitHeight = 96.0;

/// 折叠状态下卡片的主轴高度（标题栏紧凑高度，单位 dp）。
const double workspaceCollapsedHeight = 44.0;

/// 计算网格跨轴单元步长。
double gridStride({
  required double crossAxisExtent,
  required int crossAxisCount,
  required double crossAxisSpacing,
}) {
  return (crossAxisExtent + crossAxisSpacing) / crossAxisCount;
}

/// 网格几何布局结果槽位。
class GridSlot {
  final int crossAxisIndex;
  final double mainAxisOffset;

  const GridSlot(this.crossAxisIndex, this.mainAxisOffset);

  @override
  String toString() => 'GridSlot(col: $crossAxisIndex, offset: $mainAxisOffset)';
}

/// 网格几何打包总览。
class GridGeometry {
  final double stride;
  final List<GridSlot> slots;
  final double mainAxisExtent;

  const GridGeometry({
    required this.stride,
    required this.slots,
    required this.mainAxisExtent,
  });
}

/// 二维紧凑贪心网格打包算法。
GridGeometry packGridSlots({
  required List<int> crossAxisCellCounts,
  required List<double> mainAxisExtents,
  required int crossAxisCount,
  required double crossAxisExtent,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
}) {
  assert(crossAxisCellCounts.length == mainAxisExtents.length);
  final stride = gridStride(
    crossAxisExtent: crossAxisExtent,
    crossAxisCount: crossAxisCount,
    crossAxisSpacing: crossAxisSpacing,
  );
  final frontiers = List<double>.filled(crossAxisCount, 0.0);
  final slots = <GridSlot>[];

  for (int i = 0; i < crossAxisCellCounts.length; i++) {
    final cellCount = crossAxisCellCounts[i].clamp(1, crossAxisCount);
    final slot = _findBestSlot(frontiers, cellCount, crossAxisCount);
    slots.add(slot);
    final nextOffset =
        slot.mainAxisOffset + mainAxisExtents[i] + mainAxisSpacing;
    for (int j = 0; j < cellCount; j++) {
      frontiers[slot.crossAxisIndex + j] = nextOffset;
    }
  }

  final maxOffset = slots.isEmpty ? 0.0 : frontiers.reduce(math.max);
  final totalMainAxisExtent = slots.isEmpty
      ? 0.0
      : math.max(0.0, maxOffset - mainAxisSpacing);

  return GridGeometry(
    stride: stride,
    slots: slots,
    mainAxisExtent: totalMainAxisExtent,
  );
}

GridSlot _findBestSlot(
  List<double> frontiers,
  int cellCount,
  int totalColumns,
) {
  var bestCol = 0;
  var minOffset = double.infinity;

  for (int col = 0; col <= totalColumns - cellCount; col++) {
    var currentOffset = 0.0;
    for (int k = 0; k < cellCount; k++) {
      if (frontiers[col + k] > currentOffset) {
        currentOffset = frontiers[col + k];
      }
    }
    if (currentOffset < minOffset - 0.001) {
      minOffset = currentOffset;
      bestCol = col;
    }
  }

  return GridSlot(bestCol, minOffset.isFinite ? minOffset : 0.0);
}
