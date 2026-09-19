import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// 书签 / 历史面板的工具栏：视图模式 + 排序 + 搜索 + 计数。
///
/// 对应 neoview 的 `ReaderLibraryViewToolbar`。文件管理器不用它 —— 那一侧的
/// 工具栏还背着页签、穿透、目录列、隐藏文件这些文件系统专属的东西，而且排序
/// 状态住在 Rust 会话里；两张工具栏长得像，但语义不是一回事。
class ShelfListToolbar extends StatefulWidget {
  const ShelfListToolbar({
    super.key,
    required this.viewMode,
    required this.onViewMode,
    required this.sort,
    required this.onSort,
    required this.searchController,
    required this.onKeywordChanged,
    required this.count,
    this.trailing,
    this.searchHint = '搜索标题 / 作者 / 来源',
  });

  final LibraryViewMode viewMode;
  final ValueChanged<LibraryViewMode> onViewMode;
  final ShelfSort sort;
  final ValueChanged<ShelfSort> onSort;
  final TextEditingController searchController;
  final ValueChanged<String> onKeywordChanged;

  /// 当前列表的条目数，显示在右上角。
  final int count;

  /// 卡片自己的动作（新建列表、导入、导出）。
  final Widget? trailing;
  final String searchHint;

  @override
  State<ShelfListToolbar> createState() => _ShelfListToolbarState();
}

class _ShelfListToolbarState extends State<ShelfListToolbar> {
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchExpanded = widget.searchController.text.isNotEmpty;
    widget.searchController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // 外部清空搜索（比如切列表）时把搜索条一起收掉。
    if (widget.searchController.text.isEmpty && mounted) {
      setState(() => _searchExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = widget.viewMode;
    final searchActive =
        _searchExpanded || widget.searchController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FluentPopupMenuButton<LibraryViewMode>(
                  tooltip: '视图模式：${mode.label}',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(mode.icon, size: 18),
                  onSelected: widget.onViewMode,
                  itemBuilder: (_) => [
                    for (final option in LibraryViewMode.values)
                      FluentPopupMenuItem(
                        value: option,
                        leading: Icon(option.icon, size: 16),
                        selected: option == mode,
                        title: Text(option.label),
                      ),
                  ],
                ),
                FluentPopupMenuButton<String>(
                  tooltip: '排序：${widget.sort.field.label} · '
                      '${widget.sort.ascending ? '升序' : '降序'}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.sort_rounded, size: 18),
                  onSelected: (value) {
                    if (value == 'order') {
                      widget.onSort(
                        ShelfSort(
                          field: widget.sort.field,
                          ascending: !widget.sort.ascending,
                        ),
                      );
                      return;
                    }
                    widget.onSort(
                      widget.sort.toggled(
                        ShelfSortField.values.byName(value),
                      ),
                    );
                  },
                  itemBuilder: (_) => [
                    for (final field in ShelfSortField.values)
                      FluentPopupMenuItem(
                        value: field.name,
                        selected: field == widget.sort.field,
                        title: Text(field.label),
                      ),
                    const FluentPopupMenuItem.divider(),
                    FluentPopupMenuItem(
                      value: 'order',
                      title: Text(
                        widget.sort.ascending ? '切换为降序' : '切换为升序',
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: searchActive ? theme.colorScheme.primary : null,
                  ),
                  tooltip: _searchExpanded ? '收起搜索' : '搜索',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      setState(() => _searchExpanded = !_searchExpanded),
                ),
                ?widget.trailing,
                const SizedBox(width: 4),
                Text(
                  '${widget.count} 项',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        if (_searchExpanded) ...[
          const SizedBox(height: 6),
          _buildSearchField(context),
        ],
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: widget.searchController,
      autofocus: true,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.searchHint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: IconButton(
          tooltip: '清除搜索并收起',
          icon: const Icon(Icons.clear, size: 16),
          onPressed: () {
            widget.searchController.clear();
            widget.onKeywordChanged('');
            setState(() => _searchExpanded = false);
          },
        ),
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onKeywordChanged,
    );
  }
}
