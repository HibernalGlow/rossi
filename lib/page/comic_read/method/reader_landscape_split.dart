import 'dart:ui' show Size;

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

/// 一次决定好的「哪些条目该拆成两半」，渲染侧与计数侧共用同一份。
///
/// 必须是**一份**而不是两边各算：槽位数由它决定，而槽位数同时是
/// PageView 的 childCount、`ReaderCubit.totalSlots`（进度条分母）、
/// 预取窗口和「切单双页停在同一张图」的锚点映射的输入。两处各算一份判据，
/// 漂移出来的症状是进度条 41/40 或跳页落到别张图 —— 只有画面上看得出来。
class LandscapeSplitPlan {
  const LandscapeSplitPlan({
    required this.enabled,
    required this.direction,
    required this.indexes,
  });

  /// 全关：一个槽位一张整页，所有下游走拆分前的那条路。
  static const LandscapeSplitPlan disabled = LandscapeSplitPlan(
    enabled: false,
    direction: SplitDirection.leftFirst,
    indexes: <int>{},
  );

  final bool enabled;
  final SplitDirection direction;

  /// 要拆的条目下标，索引空间是**行模式显示列表的全局条目下标**
  /// （与 `ReaderSeamlessCubit` 遍历槽位用的是同一个空间）。
  final Set<int> indexes;

  bool get isEmpty => !enabled || indexes.isEmpty;

  bool isSplitAt(int entryIndex) => enabled && indexes.contains(entryIndex);

  /// 给 `context.select` 用的标量指纹。
  ///
  /// 尺寸是一张一页一页解出来的，每次上报都会 emit 新的 `ImageSizeState`；
  /// 直接 select 集合会拿到两个内容相同、身份不同的 `Set`（`Set.==` 是身份比较），
  /// 于是每一页解码都把阅读页整树重建一遍。折成一个整数后，
  /// 只有「哪些页要拆」真的变了才重建。
  int get fingerprint {
    if (!enabled) return 0;
    var hash = direction.index;
    for (final entryIndex in indexes) {
      hash = hash * 31 + entryIndex;
    }
    return hash;
  }
}

/// 按「设置 + 已解出的尺寸」算出该拆哪些条目。
///
/// 尺寸口径（这条决定了首帧会不会乱）：
/// - 只用**真解出来过**的尺寸：`intrinsicCache`（原始像素）优先，其次
///   `sizeCache` 里 `resolvedIndices` 认过的条目；
/// - 两者都没有就不拆。`ImageSizeCubit` 的默认占位是 `defaultWidth × 1.2×defaultWidth`
///   —— 那是个**竖图**比例，拿它判横图会把没解出来的页误判成不拆（正好安全），
///   但任何一次改动占位比例都会把它变成误拆，所以这里显式不碰占位值。
/// - 「横」的判据取 `宽 > 高`（严格大于）：正方形是跨页漫最常见的画法之一，
///   拆它会得到两个 1:2.4 的窄条。
///
/// 条漫（列模式）整条不接，与 `_buildColumnDoublePageImage` 的留空同一口径。
LandscapeSplitPlan buildLandscapeSplitPlan({
  required List<ReadModeEntry> entries,
  required ImageSizeState sizes,
  required ReadSettingState readSetting,
}) {
  if (!readSetting.splitLandscapePages) return LandscapeSplitPlan.disabled;
  if (isColumnReadMode(readSetting.readMode)) {
    return LandscapeSplitPlan.disabled;
  }

  final direction = SplitDirection.resolve(
    settingValue: readSetting.landscapeSplitDirection,
    currentReadMode: readSetting.readMode,
  );

  final indexes = <int>{};
  for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
    final entry = entries[entryIndex];
    if (entry.type != ReadModeEntryType.image) continue;
    final localPageIndex = entry.chapterPageIndex;
    if (localPageIndex == null) continue;

    final cacheIndex = resolveStableSizeCacheIndex(
      chapterOrder: entry.chapterOrder,
      localPageIndex: localPageIndex,
    );
    final size = _knownSize(sizes, cacheIndex);
    if (size == null) continue;
    if (size.width > size.height) indexes.add(entryIndex);
  }

  return LandscapeSplitPlan(
    enabled: true,
    direction: direction,
    indexes: indexes,
  );
}

/// 该页**可信**的尺寸；没解出来过时返回 null。
Size? _knownSize(ImageSizeState sizes, int cacheIndex) {
  final intrinsic = sizes.getIntrinsic(cacheIndex);
  if (intrinsic != null && intrinsic.width > 0 && intrinsic.height > 0) {
    return intrinsic;
  }
  if (!sizes.resolvedIndices.contains(cacheIndex)) return null;
  final cached = sizes.getSizeValue(cacheIndex);
  if (cached.width <= 0 || cached.height <= 0) return null;
  return cached;
}
