/// 横长页左右分割数据模型与切分算法。
///
/// 对齐 Rust 侧 `page_split.rs`（M-09 规范），用于在阅读器中将跨页/横长图片
/// 切分为左右两半进行连续或并排展示，同时保持原始 item index 为正本。
library;

/// 分割页面的视口部分。
enum PageSlice {
  /// 未分割或完整页面。
  full,

  /// 画面左半部分。
  left,

  /// 画面右半部分。
  right;

  /// 是否只展示半页。
  bool get isHalf => this == PageSlice.left || this == PageSlice.right;

  /// 在显示空间中的归一化 UV 范围 [minX, minY, maxX, maxY]。
  List<double> get uvRect {
    switch (this) {
      case PageSlice.full:
        return const [0.0, 0.0, 1.0, 1.0];
      case PageSlice.left:
        return const [0.0, 0.0, 0.5, 1.0];
      case PageSlice.right:
        return const [0.5, 0.0, 1.0, 1.0];
    }
  }
}

/// 分割后的阅读先后顺序。
enum SplitDirection {
  /// 先看左半边，再看右半边（从左到右，如现代漫/欧美漫）。
  leftFirst,

  /// 先看右半边，再看左半边（从右到左，如日漫经典排版）。
  rightFirst;

  /// 首次展示的部分。
  PageSlice get first {
    switch (this) {
      case SplitDirection.leftFirst:
        return PageSlice.left;
      case SplitDirection.rightFirst:
        return PageSlice.right;
    }
  }

  /// 第二次展示的部分。
  PageSlice get second {
    switch (this) {
      case SplitDirection.leftFirst:
        return PageSlice.right;
      case SplitDirection.rightFirst:
        return PageSlice.left;
    }
  }

  /// 根据阅读模式判断推荐分割顺序。
  ///
  /// [readMode]: 0 为 Webtoon, 1 为 LTR (左到右), 2 为 RTL (右到左)。
  static SplitDirection fromReadMode(int readMode) {
    if (readMode == 2) {
      return SplitDirection.rightFirst;
    }
    return SplitDirection.leftFirst;
  }

  /// 根据设置配置选项解析分割顺序。
  ///
  /// [settingValue]: 0 为自动跟随阅读模式，1 为强制 LTR，2 为强制 RTL。
  static SplitDirection resolve({
    required int settingValue,
    required int currentReadMode,
  }) {
    switch (settingValue) {
      case 1:
        return SplitDirection.leftFirst;
      case 2:
        return SplitDirection.rightFirst;
      case 0:
      default:
        return fromReadMode(currentReadMode);
    }
  }
}

/// 单个展示步骤（Presentation Step）。
///
/// [sourceIdx] 为原始条目索引，[slice] 决定展示哪一部分。
class PresentationStep {
  final int sourceIdx;
  final PageSlice slice;

  const PresentationStep({required this.sourceIdx, required this.slice});

  const PresentationStep.whole(this.sourceIdx) : slice = PageSlice.full;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresentationStep &&
          runtimeType == other.runtimeType &&
          sourceIdx == other.sourceIdx &&
          slice == other.slice;

  @override
  int get hashCode => sourceIdx.hashCode ^ slice.hashCode;

  @override
  String toString() => 'PresentationStep($sourceIdx, $slice)';
}

/// 将页序列根据分割判定展开为呈现步骤序列。
///
/// [count]: 原始页面数量。
/// [direction]: 分割阅读顺序。
/// [isSplitIdx]: 判断索引为 `idx` 的页面是否需要分割（如宽 > 高的横长图）。
List<PresentationStep> computePresentationSteps({
  required int count,
  required SplitDirection direction,
  required bool Function(int idx) isSplitIdx,
}) {
  final steps = <PresentationStep>[];
  for (var i = 0; i < count; i++) {
    if (isSplitIdx(i)) {
      steps.add(PresentationStep(sourceIdx: i, slice: direction.first));
      steps.add(PresentationStep(sourceIdx: i, slice: direction.second));
    } else {
      steps.add(PresentationStep.whole(i));
    }
  }
  return steps;
}

/// 查找指定原始页码在展示步骤中首次出现的步进索引（用于从目录/书签跳转回落）。
int? findLandingStep(List<PresentationStep> steps, int sourceIdx) {
  for (var i = 0; i < steps.length; i++) {
    if (steps[i].sourceIdx == sourceIdx) {
      return i;
    }
  }
  return null;
}
