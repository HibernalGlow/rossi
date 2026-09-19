import 'package:material_ui/material_ui.dart';

/// 与 Rust 侧 `FileManagerViewMode` 一一对应的 Dart 视图模式。
///
/// 共享视图层不能直接吃 FRB 的枚举：书签和历史都住在 ObjectBox 里，没有
/// Rust 会话可言。所以这一层只认自己的枚举，文件管理器在适配器里映射一次。
enum LibraryViewMode { compact, coverList, mosaicList, details, coverGrid, mosaicGrid }

extension LibraryViewModeX on LibraryViewMode {
  /// 文案与 `FileManagerViewModeX.label` 保持逐字一致：文件卡工具栏的 tooltip
  /// 就是「视图模式：$label」，测试按这个字符串找按钮。
  String get label {
    switch (this) {
      case LibraryViewMode.compact:
        return '紧凑列表';
      case LibraryViewMode.coverList:
        return '封面列表';
      case LibraryViewMode.mosaicList:
        return '横幅';
      case LibraryViewMode.details:
        return '详细信息';
      case LibraryViewMode.coverGrid:
        return '封面网格';
      case LibraryViewMode.mosaicGrid:
        return '自由缩略图';
    }
  }

  IconData get icon {
    switch (this) {
      case LibraryViewMode.compact:
        return Icons.view_headline_rounded;
      case LibraryViewMode.coverList:
        return Icons.table_rows_rounded;
      case LibraryViewMode.mosaicList:
        return Icons.view_agenda_rounded;
      case LibraryViewMode.details:
        return Icons.table_chart_rounded;
      case LibraryViewMode.coverGrid:
        return Icons.grid_view_rounded;
      case LibraryViewMode.mosaicGrid:
        return Icons.grid_on_rounded;
    }
  }
}
