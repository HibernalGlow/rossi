import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 书签 / 历史面板的工具栏：视图模式 + 排序 + 搜索 + 导入导出 + 计数。
///
/// 对应 neoview 的 `ReaderLibraryViewToolbar`。文件管理器不用它 —— 那一侧的
/// 工具栏还背着页签、穿透、目录列、隐藏文件这些文件系统专属的东西，而且排序
/// 状态住在 Rust 会话里；两张工具栏长得像，但语义不是一回事。
///
/// **语义分开，度量与配色只有一份**：图标钮几何、分组间距、选中态一律走
/// [FileManagerToolbarMetrics] 与它的按钮（图标钮 40 见方、图标 20、组内 4、
/// 组间 12、选中 `secondaryContainer`、禁用 `onSurfaceVariant` 38%）。
/// 那一份住在 `cards/` 下而不是这里，是因为它先为文件管理器而生；两处各写一份
/// 常数的好下场就是同一条工具栏里长出两种高度。
///
/// 分组**只靠间距分级，不画分隔线、也不套下沉槽**：文件管理器那边同样只有
/// 「导航」那一组用了 `FileManagerToolbarGroup`，主工具组是散着的。
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
    this.onExport,
    this.onImport,
    this.portLabel = '导入 / 导出',
    this.timelineOn = false,
    this.onTimeline,
    this.busy = false,
    this.searchHint = '搜索标题 / 作者 / 来源',
  });

  final LibraryViewMode viewMode;
  final ValueChanged<LibraryViewMode> onViewMode;
  final ShelfSort sort;
  final ValueChanged<ShelfSort> onSort;
  final TextEditingController searchController;
  final ValueChanged<String> onKeywordChanged;

  /// 当前列表的条目数。
  final int count;

  /// 导出与导入。两者都不给时整组不出现 —— 「有这一颗但点了没反应」
  /// 比没有更糟，因为用户会以为是自己的数据不对。
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  /// 时间线是否开着。开了之后**视图档与排序这两颗键会灰掉**（不是藏掉）：
  /// 时间线用自己的行式与自己的时间序，那两颗键此刻确实没有可改的东西。
  ///
  /// 为什么是开关而不是第七档视图：见 `model/shelf_timeline.dart` 的库注释 ——
  /// `LibraryViewMode` 与 Rust 侧的枚举一一对应，为书架专属的东西去动三家
  /// 共用的行契约不划算。
  final bool timelineOn;

  /// 时间线的切换动作。不给 ⇒ 这一侧没有时间线（文件管理器就不给）。
  final VoidCallback? onTimeline;

  /// 这一组的名字，出现在触发键的 tooltip 上（「书签数据」/「历史数据」）。
  ///
  /// 导入导出原先是两颗长得几乎一样的下载/上传箭头，20dp 下根本分不出谁是谁；
  /// 收进一颗带文字的菜单之后，方向写在项上，不再靠猜图标。
  final String portLabel;

  /// 有请求在飞（正在读写文件）：整组禁用，避免叠动作。
  final bool busy;
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

  bool get _hasPort => widget.onExport != null || widget.onImport != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = widget.viewMode;
    final searchOn = _searchExpanded || widget.searchController.text.isNotEmpty;
    const within = SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup);
    const between = SizedBox(width: FileManagerToolbarMetrics.gapBetweenGroups);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // —— 「怎么看」这一组：视图 / 排序 / 时间线 / 搜索，组内 4 ——
                ShelfMenuButton(
                  tooltip: widget.timelineOn
                      ? '视图模式（时间线下不适用）'
                      : '视图模式：${mode.label}',
                  icon: mode.icon,
                  // 时间线开着时灰着而不是藏起来：MD3 的禁用态就是
                  // `onPressed: null`，用户看得见「有这件事，只是现在做不了」。
                  enabled: !widget.timelineOn,
                  menuChildren: [
                    for (final option in LibraryViewMode.values)
                      ShelfMenuItem(
                        label: option.label,
                        icon: option.icon,
                        selected: option == mode,
                        onPressed: () => widget.onViewMode(option),
                      ),
                  ],
                ),
                within,
                ShelfMenuButton(
                  tooltip: widget.timelineOn
                      ? '排序（时间线固定按时间排）'
                      : '排序：${widget.sort.field.label} · '
                            '${widget.sort.ascending ? '升序' : '降序'}',
                  icon: Icons.sort_rounded,
                  enabled: !widget.timelineOn,
                  menuChildren: [
                    for (final field in ShelfSortField.values)
                      ShelfMenuItem(
                        label: field.label,
                        selected: field == widget.sort.field,
                        onPressed: () =>
                            widget.onSort(widget.sort.toggled(field)),
                      ),
                    const ShelfMenuDivider(),
                    ShelfMenuItem(
                      label: widget.sort.ascending ? '切换为降序' : '切换为升序',
                      icon: widget.sort.ascending
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      onPressed: () => widget.onSort(
                        ShelfSort(
                          field: widget.sort.field,
                          ascending: !widget.sort.ascending,
                        ),
                      ),
                    ),
                  ],
                ),
                within,
                // 时间线：这一侧没有这个能力时（`onTimeline` 不给）整颗不出现，
                // 与导入导出那一组同一个口径。
                if (widget.onTimeline != null)
                  FileManagerToolbarToggleButton(
                    icon: Icons.timeline_rounded,
                    tooltip: widget.timelineOn ? '退出时间线' : '按天看时间线',
                    on: widget.timelineOn,
                    onPressed: widget.onTimeline,
                  ),
                within,
                // 搜索键不参与 busy 门控：展开/收起只是 UI 状态切换，不碰数据。
                FileManagerToolbarToggleButton(
                  icon: Icons.search_rounded,
                  tooltip: _searchExpanded ? '收起搜索' : '搜索',
                  on: searchOn,
                  onPressed: () =>
                      setState(() => _searchExpanded = !_searchExpanded),
                ),

                // —— 「数据」这一组：组间 12 ——
                if (_hasPort) ...[
                  between,
                  ShelfMenuButton(
                    tooltip: widget.portLabel,
                    icon: Icons.import_export_rounded,
                    enabled: !widget.busy,
                    menuChildren: [
                      ShelfMenuItem(
                        label: '导出为 JSON',
                        icon: Icons.file_download_outlined,
                        onPressed: widget.busy
                            ? null
                            : widget.onExport,
                      ),
                      ShelfMenuItem(
                        label: '从 JSON 导入',
                        icon: Icons.file_upload_outlined,
                        onPressed: widget.busy ? null : widget.onImport,
                      ),
                    ],
                  ),
                ],
                between,
                // 计数坐在与图标钮同一条 40 的高度带的垂直中心，而不是贴着
                // 行的基线 —— 之前它跟着 18dp 的图标走，整行看着矮一截。
                //
                // 字号写死：这套 `material_ui` 的 textTheme token 不带
                // fontSize（见 `widgets/plat/rossi_plat_theme.dart` 的说明），
                // 只给 `labelSmall` 等于什么都没设。
                SizedBox(
                  height: FileManagerToolbarMetrics.buttonSize,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.count} 项',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_searchExpanded) ...[
          const SizedBox(height: 8),
          _buildSearchField(context),
        ],
      ],
    );
  }

  /// MD3 的**描边式**文本框 —— 描边档与填充档都是 MD3 认的形态，这里跟
  /// 文件管理器展开搜索保持同一种（那一份也是 `OutlineInputBorder`）。
  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: widget.searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.searchHint,
        // MD3 文本框的前后置图标是 24dp，不是压到 18。
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: '清除搜索并收起',
          icon: const Icon(Icons.close_rounded),
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
