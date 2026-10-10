import 'package:material_ui/material_ui.dart';

import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 书签 / 历史面板的工具栏：视图模式 + 排序 + 搜索 + 导入导出 + 计数。
///
/// 对应 neoview 的 `ReaderLibraryViewToolbar`。文件管理器不用它 —— 那一侧的
/// 工具栏还背着页签、穿透、目录列、隐藏文件这些文件系统专属的东西，而且排序
/// 状态住在 Rust 会话里；两张工具栏长得像，但语义不是一回事。
///
/// **语义分开，度量与配色只有一份**：图标钮几何、分组间距、选中态一律走
/// [ActionGroupMetrics]（图标钮 40 见方、图标 20、组内 4、组间 12、选中
/// `secondaryContainer`、禁用 `onSurfaceVariant` 38%）。这一份就是
/// `FileManagerToolbarMetrics` 转发的那一份，也是侧栏底部与书架页右上角那份 ——
/// 几处各写一份常数的好下场，就是同一条工具栏里长出两种高度。
///
/// **分组画成下沉槽**（[ActionGroup]）：一组可操作区一只槽，组与组之间只剩间距，
/// 不画分隔线。这与文件管理器的「导航」组、书架页右上角那两颗是同一个语言 ——
/// 统一的目的就在这里：同一屏上并排看，圆角、内边距、图标尺寸不再各处各漂一点。
/// 所以槽本身不另传 [ActionGroup.fill]，用默认那档（`surfaceContainer`，比卡片
/// 底低一档，读作「这一片是可操作区」而不是又加一层海拔）。
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
    const within = SizedBox(width: ActionGroupMetrics.gapWithinGroup);
    const between = SizedBox(width: ActionGroupMetrics.gapBetweenGroups);

    return ActionBubbleRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // —— 「怎么看」这一槽：视图 / 排序 / 时间线 / 搜索，槽内 4 ——
                  ActionGroup(
                    children: [
                      ShelfMenuButton(
                        tooltip: widget.timelineOn
                            ? '视图模式（时间线下不适用）'
                            : '视图模式：${mode.label}',
                        glyph: mode.icon,
                        shape: ExpressiveButtonShape.gem,
                        // 时间线开着时灰着而不是藏起来：MD3 的禁用态就是
                        // `onPressed: null`，用户看得见「有这件事，只是现在做不了」。
                        enabled: !widget.timelineOn,
                        menuChildren: [
                          for (final option in LibraryViewMode.values)
                            ShelfMenuItem(
                              label: option.label,
                              glyph: option.icon,
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
                        glyph: AppGlyphs.sort,
                        shape: ExpressiveButtonShape.fan,
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
                            glyph: widget.sort.ascending
                                ? AppGlyphs.arrowDown
                                : AppGlyphs.arrowUp,
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
                      //
                      // 分隔符跟着这一颗一起进 `if`：留在外面会让「没有时间线」那档
                      // 叠出两个 4 —— 排序与搜索之间变成 8，槽内间距就不止一个数了。
                      if (widget.onTimeline != null) ...[
                        ActionToggleButton(
                          glyph: AppGlyphs.clock,
                          tooltip: widget.timelineOn ? '退出时间线' : '按天看时间线',
                          on: widget.timelineOn,
                          onPressed: widget.onTimeline,
                        ),
                        within,
                      ],
                      // 搜索键不参与 busy 门控：展开/收起只是 UI 状态切换，不碰数据。
                      ActionToggleButton(
                        glyph: AppGlyphs.search,
                        tooltip: _searchExpanded ? '收起搜索' : '搜索',
                        on: searchOn,
                        onPressed: () =>
                            setState(() => _searchExpanded = !_searchExpanded),
                      ),
                    ],
                  ),

                  // —— 「数据」这一槽：导出 / 导入收在一颗菜单键里 ——
                  if (_hasPort) ...[
                    between,
                    ActionGroup(
                      children: [
                        ShelfMenuButton(
                          tooltip: widget.portLabel,
                          glyph: AppGlyphs.export,
                          enabled: !widget.busy,
                          menuChildren: [
                            ShelfMenuItem(
                              label: '导出为 JSON',
                              glyph: AppGlyphs.cloudDownload,
                              onPressed: widget.busy ? null : widget.onExport,
                            ),
                            ShelfMenuItem(
                              label: '从 JSON 导入',
                              glyph: AppGlyphs.upload,
                              onPressed: widget.busy ? null : widget.onImport,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  between,
                  // 计数**不进槽**：槽是「一组可按的东西」，一段数字坐进去会读成
                  // 一颗按不动的键。它跟整行共用同一条 40 的高度带，靠 Row 的
                  // 居中把它摆在这条带的中线上。
                  //
                  // 字号写死：这套 `material_ui` 的 textTheme token 不带
                  // fontSize（见 `widgets/plat/rossi_plat_theme.dart` 的说明），
                  // 只给 `labelSmall` 等于什么都没设。
                  Text(
                    '${widget.count} 项',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ExpressiveReveal(
            visible: _searchExpanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildSearchField(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索独立向下展开；填充圆角容器承接焦点，不画移动椭圆。
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
        prefixIcon: const GlyphIcon(AppGlyphs.search),
        suffixIcon: IconButton(
          tooltip: '清除搜索并收起',
          icon: const GlyphIcon(AppGlyphs.close),
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
