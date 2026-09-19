import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

/// 缩略图槽的构造器：由**数据源**提供，尺寸与圆角由布局决定。
///
/// 必须是个带尺寸的构造器而不是现成的 Widget —— 同一张封面在紧凑列表里是
/// 20x30，在封面网格里要铺满，而 `CoverWidget` 与
/// `FileManagerThumbnailWidget` 都拿宽高去决定请求多大尺寸的缩略图。
typedef LibraryMediaBuilder =
    Widget Function(
      BuildContext context, {
      required double width,
      required double height,
      required BorderRadius radius,
      required BoxFit fit,
    });

/// 条目下方可单独点击的子行。文件管理器拿它显示穿透出来的子文件名，
/// 书签与历史不用填。
class LibrarySubLine {
  const LibrarySubLine({
    required this.label,
    required this.icon,
    this.onTap,
    this.onDoubleTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
}

/// 一个能被全部六种视图渲染的条目 —— 共享视图层的「行」契约。
///
/// 刻意不含任何文件系统语义：文件管理器、书签、历史各自把自己那个实体
/// 映射成它，行渲染只有一份。
class LibraryEntry {
  const LibraryEntry({
    required this.key,
    required this.title,
    this.subtitle,
    this.tertiary,
    this.metaText,
    this.media,
    this.badge,
    this.thumbModes = const {
      LibraryViewMode.coverList,
      LibraryViewMode.mosaicList,
      LibraryViewMode.coverGrid,
      LibraryViewMode.mosaicGrid,
    },
    this.subLines = const [],
    this.detailCells = const [],
    this.overlayText,
    this.trailing,
    this.source,
  });

  /// 列表项的稳定标识（ObjectBox 用 uniqueKey，文件用 path）。
  final String key;

  /// 造出这一行的原始实体。行渲染不需要它，但点击事件需要：
  /// 文件管理器要拿回 `FileManagerEntry` 才能开档案，书签要拿回
  /// `UnifiedComicFavorite` 才能跳详情。
  final Object? source;
  final String title;

  /// 第二行：文件是「类型 · 大小 · 日期」，书签是作者，历史是进度。
  final String? subtitle;

  /// 第三行，只有横幅视图用得上。
  final String? tertiary;

  /// 行尾的定宽小字（大小 / 来源）。紧凑列表与封面网格会画它。
  final String? metaText;

  final LibraryMediaBuilder? media;

  /// 语义图标。没有缩略图的模式（以及 media 为空的条目）退化到它。
  final Widget? badge;

  /// 哪些模式真的画缩略图。文件管理器把紧凑列表与详细信息排除在外 ——
  /// 那两档一行几十个条目，逐个取缩略图不值当；书签只有几百条，全画。
  final Set<LibraryViewMode> thumbModes;

  final List<LibrarySubLine> subLines;

  /// 详细信息视图的列文本，顺序与宿主 `columns` 对齐。
  final List<String> detailCells;

  /// 封面网格右下角的计数角标（子项数）。
  final String? overlayText;

  final Widget? trailing;

  bool wantsThumb(LibraryViewMode mode) =>
      media != null && thumbModes.contains(mode);
}
