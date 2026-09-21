import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

/// 某一档视图的列表几何：走 ListView 还是 GridView，以及网格的度量子。
class LibraryListGeometry {
  const LibraryListGeometry({
    required this.isGrid,
    this.maxCrossAxisExtent,
    this.mainAxisExtent,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    this.rowMinHeight,
    this.rowHeight,
  });

  final bool isGrid;
  final double? maxCrossAxisExtent;
  final double? mainAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final double? rowMinHeight;
  final double? rowHeight;
}

/// 缩略图槽的尺寸。[fillsCell] 为真时铺满所在格子（两档网格）。
class LibraryThumbGeometry {
  const LibraryThumbGeometry(
    this.size,
    this.radius,
    this.fit, {
    this.fillsCell = false,
  });

  final Size? size;
  final BorderRadius radius;
  final BoxFit fit;
  final bool fillsCell;
}

/// 详细信息视图的一列。[width] 为空表示按 [flex] 伸展。
///
/// [key] 同时是排序键：宿主点表头时把它交回去。[sortable] 为假时表头只是个
/// 标签，不接点击 —— 有些列（历史的「章节」）根本没有对应的排序字段，
/// 画成能点的样子会让人点了没反应。
class LibraryColumn {
  const LibraryColumn({
    required this.key,
    required this.label,
    this.width,
    this.flex = 1,
    this.alignRight = false,
    this.sortable = true,
  });

  final String key;
  final String label;
  final double? width;
  final int flex;
  final bool alignRight;
  final bool sortable;
}

/// 六档视图的几何。数值全部来自原先 `file_manager_card.dart` 里那六个
/// 私有的 `_build*` 方法，抽出来是为了书签与历史能拿到同一套排版。
class LibraryViewLayout {
  static const double detailsMinWidth = 460;
  static const double detailsColumnGap = 4;

  /// 详细信息视图里标题列的伸展份数。表头与行都读它，改一处即可。
  static const int detailsTitleFlex = 5;

  static LibraryListGeometry list(LibraryViewMode mode) {
    switch (mode) {
      case LibraryViewMode.compact:
        return const LibraryListGeometry(isGrid: false, rowMinHeight: 34);
      case LibraryViewMode.coverList:
        return const LibraryListGeometry(isGrid: false);
      case LibraryViewMode.details:
        return const LibraryListGeometry(isGrid: false, rowHeight: 36);
      case LibraryViewMode.mosaicList:
        return const LibraryListGeometry(
          isGrid: true,
          maxCrossAxisExtent: 320,
          mainAxisExtent: 92,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          padding: EdgeInsets.all(6),
        );
      case LibraryViewMode.coverGrid:
        return const LibraryListGeometry(
          isGrid: true,
          maxCrossAxisExtent: 140,
          mainAxisExtent: 180,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          padding: EdgeInsets.all(6),
        );
      case LibraryViewMode.mosaicGrid:
        return const LibraryListGeometry(
          isGrid: true,
          maxCrossAxisExtent: 110,
          mainAxisExtent: 130,
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
          padding: EdgeInsets.all(6),
        );
    }
  }

  /// 没有缩略图的模式（紧凑列表、详细信息）给一个够小的方寸：
  /// 行高就 34/36，再大就把整行顶高了。
  static LibraryThumbGeometry thumb(LibraryViewMode mode) {
    switch (mode) {
      case LibraryViewMode.compact:
        return const LibraryThumbGeometry(
          Size(20, 30),
          BorderRadius.all(Radius.circular(3)),
          BoxFit.cover,
        );
      case LibraryViewMode.coverList:
        return const LibraryThumbGeometry(
          Size(44, 44),
          BorderRadius.all(Radius.circular(6)),
          BoxFit.cover,
        );
      case LibraryViewMode.mosaicList:
        return const LibraryThumbGeometry(
          Size(88, 92),
          BorderRadius.all(Radius.zero),
          BoxFit.cover,
        );
      case LibraryViewMode.details:
        return const LibraryThumbGeometry(
          Size(18, 26),
          BorderRadius.all(Radius.circular(3)),
          BoxFit.cover,
        );
      case LibraryViewMode.coverGrid:
      case LibraryViewMode.mosaicGrid:
        return const LibraryThumbGeometry(
          null,
          BorderRadius.all(Radius.zero),
          BoxFit.cover,
          fillsCell: true,
        );
    }
  }

  /// 网格档里封面下面那条文字区要多高，才能既放下标题两行又不至于把
  /// `mainAxisExtent` 撑破。封面网格留 46，自由缩略图留 22。
  static double gridCaptionExtent(LibraryViewMode mode) {
    switch (mode) {
      case LibraryViewMode.coverGrid:
        return 46;
      case LibraryViewMode.mosaicGrid:
        return 22;
      default:
        return 0;
    }
  }

  /// 语义图标在每一档里的尺寸。数值照搬原文件管理器卡片的 `_buildSemanticIcon`
  /// 调用点：紧凑与详细信息 16，横幅 13，封面网格 12。
  static double badgeSize(LibraryViewMode mode) {
    switch (mode) {
      case LibraryViewMode.compact:
      case LibraryViewMode.details:
        return 16;
      case LibraryViewMode.mosaicList:
        return 13;
      case LibraryViewMode.coverGrid:
        return 12;
      case LibraryViewMode.coverList:
      case LibraryViewMode.mosaicGrid:
        return 18;
    }
  }
}
