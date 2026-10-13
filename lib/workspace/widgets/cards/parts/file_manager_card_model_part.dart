part of '../file_manager_card.dart';

// 视图模式映射与错误态
extension FileManagerLayoutModeX on FileManagerLayoutMode {
  String get label => switch (this) {
    FileManagerLayoutMode.content => '内容视图',
    FileManagerLayoutMode.tree => '树形视图',
    FileManagerLayoutMode.columns => '分栏视图',
  };
  Glyph get icon => switch (this) {
    FileManagerLayoutMode.content => AppGlyphs.layoutList,
    FileManagerLayoutMode.tree => AppGlyphs.tree,
    FileManagerLayoutMode.columns => AppGlyphs.columnsTwo,
  };
}

extension FileManagerViewModeX on FileManagerViewMode {
  /// 文案与图标只有一份，住在 `LibraryViewModeX`：文件管理器与书签/历史面板
  /// 共用同一套视图模式，工具栏 tooltip 与视图菜单不会长出两种叫法。
  String get label => fileManagerLibraryMode(this).label;

  Glyph get icon => fileManagerLibraryMode(this).icon;
}

LibraryViewMode fileManagerLibraryMode(FileManagerViewMode mode) {
  return switch (mode) {
    FileManagerViewMode.compact => LibraryViewMode.compact,
    FileManagerViewMode.coverList => LibraryViewMode.coverList,
    FileManagerViewMode.mosaicList => LibraryViewMode.mosaicList,
    FileManagerViewMode.details => LibraryViewMode.details,
    FileManagerViewMode.coverGrid => LibraryViewMode.coverGrid,
    FileManagerViewMode.mosaicGrid => LibraryViewMode.mosaicGrid,
  };
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(AppGlyphs.error, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 6),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const GlyphIcon(AppGlyphs.refresh, size: 16),
          label: const Text('重试'),
        ),
      ],
    );
  }
}

/// 主页键长按 / 右键菜单的三个动作，现在以「菜单项各自的 onPressed 闭包」
/// 直接分派（`_openHomeMenu`），不再需要一个中间枚举。
