import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 与 Rust 侧 `FileManagerViewMode` 一一对应的 Dart 视图模式。
///
/// 共享视图层不能直接吃 FRB 的枚举：书签和历史都住在 ObjectBox 里，没有
/// Rust 会话可言。所以这一层只认自己的枚举，文件管理器在适配器里映射一次。
enum LibraryViewMode {
  compact,
  coverList,
  mosaicList,
  details,
  coverGrid,
  mosaicGrid,
}

extension LibraryViewModeX on LibraryViewMode {
  /// 文案与 `FileManagerViewModeX.label` 保持逐字一致：文件卡工具栏的 tooltip
  /// 就是「视图模式：$label」，测试按这个字符串找按钮。
  String get label {
    switch (this) {
      case LibraryViewMode.compact:
        return t.workspace.compactList;
      case LibraryViewMode.coverList:
        return t.workspace.coverList;
      case LibraryViewMode.mosaicList:
        return t.workspace.bannerLabel;
      case LibraryViewMode.details:
        return t.workspace.detailedInformation;
      case LibraryViewMode.coverGrid:
        return t.workspace.coverGrid;
      case LibraryViewMode.mosaicGrid:
        return t.workspace.freeThumbnails;
    }
  }

  /// 图标走本仓自绘 glyph（`lib/icons/`），与侧栏、工具条同一套形状语言。
  /// 六档按「行的密度 × 列的形态」选：紧凑行 → 单列线；封面列表 → 小卡；
  /// 横幅 → 中卡；详细信息 → 多列；网格 → 四宫格；缩略图 → 图库。
  Glyph get icon {
    switch (this) {
      case LibraryViewMode.compact:
        return AppGlyphs.layoutList;
      case LibraryViewMode.coverList:
        return AppGlyphs.cardSmall;
      case LibraryViewMode.mosaicList:
        return AppGlyphs.cardMedium;
      case LibraryViewMode.details:
        return AppGlyphs.columnsThree;
      case LibraryViewMode.coverGrid:
        return AppGlyphs.dashboard;
      case LibraryViewMode.mosaicGrid:
        return AppGlyphs.photos;
    }
  }
}
