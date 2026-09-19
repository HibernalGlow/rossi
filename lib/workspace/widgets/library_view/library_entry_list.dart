import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_surface.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_layout.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

/// 六档视图的宿主。对应 neoview 的 `ReaderLibraryList`：
/// 只负责「按当前视图模式把行排出来 + 边框 + 忙遮罩 + 空态」，
/// 行内容一概交给 [LibraryEntrySurface]。
class LibraryEntryList extends StatelessWidget {
  const LibraryEntryList({
    super.key,
    required this.mode,
    required this.entries,
    required this.onTap,
    this.emptyText = '没有条目',
    this.columns = const [],
    this.titleColumn,
    this.sortKey,
    this.sortAscending = false,
    this.onSort,
    this.canDoubleTap,
    this.onDoubleTap,
    this.wrapRow,
    this.enabled = true,
    this.busy = false,
    this.standalone = false,
  });

  final LibraryViewMode mode;
  final List<LibraryEntry> entries;
  final ValueChanged<LibraryEntry> onTap;

  /// 空列表文案。搜索/筛选有没有生效由调用方判断，这里只负责照实显示。
  final String emptyText;

  /// 详细信息视图的数据列（不含标题列）。
  final List<LibraryColumn> columns;

  /// 标题列。给了才会在详细信息表头画一个可排序的标题格。
  final LibraryColumn? titleColumn;

  final String? sortKey;
  final bool sortAscending;
  final ValueChanged<String>? onSort;

  final bool Function(LibraryEntry entry)? canDoubleTap;
  final ValueChanged<LibraryEntry>? onDoubleTap;

  /// 给整行套一层壳子（书签与历史用它挂右键菜单宿主）。
  final Widget Function(BuildContext context, LibraryEntry entry, Widget row)
  ? wrapRow;

  /// 为假时行不接手势，也不显示水波纹（沿用文件管理器在 `_busy` 下的表现）。
  final bool enabled;
  final bool busy;

  /// 独占整个面板时不再套 120~440 的高度限制。
  final bool standalone;

  static const double _borderRadius = 8;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return _buildEmpty(context);

    final view = _buildView(context);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.35,
          ),
        ),
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
        child: view,
      ),
    );

    final list = standalone
        ? content
        : ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 120,
              maxHeight: 440,
            ),
            child: content,
          );

    return Stack(
      fit: standalone ? StackFit.expand : StackFit.loose,
      children: [
        list,
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final empty = Center(
      child: Text(emptyText, style: Theme.of(context).textTheme.bodySmall),
    );
    return standalone ? empty : SizedBox(height: 170, child: empty);
  }

  Widget _buildView(BuildContext context) {
    if (mode == LibraryViewMode.details) return _buildDetails(context);
    final geometry = LibraryViewLayout.list(mode);
    if (!geometry.isGrid) return _buildListView(context, geometry);
    return _buildGridView(context, geometry);
  }

  Widget _row(BuildContext context, int index) {
    final entry = entries[index];
    final row = LibraryEntrySurface(
      key: ValueKey('${mode.name}:${entry.key}'),
      mode: mode,
      entry: entry,
      onTap: enabled ? () => onTap(entry) : null,
      onDoubleTap: enabled && (canDoubleTap?.call(entry) ?? false)
          ? () => onDoubleTap?.call(entry)
          : null,
    );
    return wrapRow?.call(context, entry, row) ?? row;
  }

  Widget _buildListView(BuildContext context, LibraryListGeometry geometry) {
    return ListView.separated(
      primary: false,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: _row,
    );
  }

  Widget _buildGridView(BuildContext context, LibraryListGeometry geometry) {
    return GridView.builder(
      padding: geometry.padding,
      primary: false,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: geometry.maxCrossAxisExtent ?? 320,
        mainAxisExtent: geometry.mainAxisExtent,
        crossAxisSpacing: geometry.crossAxisSpacing,
        mainAxisSpacing: geometry.mainAxisSpacing,
      ),
      itemCount: entries.length,
      itemBuilder: _row,
    );
  }

  Widget _buildDetails(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < LibraryViewLayout.detailsMinWidth
            ? LibraryViewLayout.detailsMinWidth
            : constraints.maxWidth;
        return DetailsColumns(
          columns: columns,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDetailsHeader(context),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      primary: false,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: _row,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsHeader(BuildContext context) {
    final theme = Theme.of(context);
    final title = titleColumn;
    return Container(
      height: 32,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: LibraryViewLayout.detailsTitleFlex,
            child: title == null
                ? const SizedBox.shrink()
                : _sortableHeaderCell(
                    context,
                    column: title,
                    flex: LibraryViewLayout.detailsTitleFlex,
                  ),
          ),
          for (final column in columns) ...[
            const SizedBox(width: LibraryViewLayout.detailsColumnGap),
            SizedBox(
              width: column.width,
              child: _sortableHeaderCell(context, column: column),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sortableHeaderCell(
    BuildContext context, {
    required LibraryColumn column,
    int flex = 1,
  }) {
    final theme = Theme.of(context);
    final isActive = sortKey == column.key;
    final handleSort = onSort;
    final canTap = enabled && handleSort != null && column.sortable;

    return InkWell(
      onTap: canTap ? () => handleSort(column.key) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisAlignment: column.alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                column.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
