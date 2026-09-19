import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';

/// 单个泳道容器：栏头（折叠 / 独占 / 宽度）+ 内容。
///
/// **栏头归泳道自己**（neoview 契约）：edge 模式那套「钉边 / 拖动 / 改尺寸」的控件
/// 在这里一律不出现；[headerActions] 是泳道往自己栏头里塞控件的口子 ——
/// 阅读器泳道就用它把模式切换放进自己的 chrome，于是 Reader 的动作永远跟着 Reader 走。
class SwimlaneColumn extends StatelessWidget {
  final String laneId;
  final LaneConfig config;

  /// 本泳道当前的实际宽度（阅读器泳道由视口比例算出，不等于 [LaneConfig.width]）。
  final double resolvedWidth;

  final bool isSolo;

  /// 是不是当前**激活**的那条泳道。
  ///
  /// 它只用来给用户一个「交互现在交给谁」的视觉线索。激活本身（以及
  /// 「非激活泳道的第一下点击被吃掉」）由 `SwimlaneWorkspace` 负责 ——
  /// 那条判断不能放在这里：栏头自己的按钮在非激活态也要能按。
  final bool isActive;

  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final VoidCallback? onResetWidth;

  /// 覆盖栏头标题（例如阅读器泳道显示当前书名）。
  final String? titleOverride;

  /// 栏头右侧的附加控件。**必须窄**（图标按钮级别），否则窄栏会挤压标题。
  final List<Widget> headerActions;

  /// 这条泳道承载哪一侧的面板；`null` = 没有面板（阅读器泳道）。
  ///
  /// 传的是**哪一侧**而不是一个现成的 widget：面板操作栏要按自己的记账
  /// （钉在哪儿 / 悬浮在哪儿）摆在泳道内部，而那需要**泳道自己的尺寸**，
  /// 只有这一层知道。调用方在别处把它构造出来的话，尺寸就只能猜。
  final WorkspacePanelSide? panelSide;

  final Widget? child;
  final List<Widget>? cards;

  const SwimlaneColumn({
    super.key,
    required this.laneId,
    required this.config,
    required this.resolvedWidth,
    required this.isSolo,
    required this.isActive,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.titleOverride,
    this.headerActions = const <Widget>[],
    this.panelSide,
    this.child,
    this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 折叠状态（紧凑 44dp 轨）
    if (config.collapsed && !isSolo) {
      return _buildCollapsedRail(context, theme);
    }

    final barLayout = config.panelBar;
    final titleMounted = panelSide != null && barLayout.isTitleMounted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final laneBounds = PanelBarBounds(
          left: 0,
          top: 0,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );

        final body = Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isActive ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildHeader(context, theme, titleMounted),
              // 泳道内容 Body
              Expanded(
                child:
                    child ??
                    ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: cards ?? const [],
                    ),
              ),
            ],
          ),
        );

        final bar = _buildPanelBar(laneBounds, titleMounted);
        if (bar == null) return body;

        // 面板栏浮在内容之上（它自己去哪条边由记账决定）。
        return Stack(
          children: [
            Positioned.fill(child: body),
            bar,
          ],
        );
      },
    );
  }

  /// 面板操作栏：按 `panelBarMode / panelBarDock / panelBarPositionX/Y` 摆。
  ///
  /// 三种情形**不在这里画**：
  /// - 没有面板（阅读器泳道）；
  /// - 钉在顶部且没在拖动 —— 它被挂进栏头（[titleMounted]），由 `_buildHeader` 画；
  /// - 悬浮且**允许移出泳道** —— 它的容器是整个工作台视口，由 `SwimlaneWorkspace`
  ///   在更高一层画（泳道自己是裁剪的，越界的子节点连指针都收不到）。
  Widget? _buildPanelBar(PanelBarBounds laneBounds, bool titleMounted) {
    final side = panelSide;
    if (side == null || titleMounted) return null;
    final barLayout = config.panelBar;
    if (barLayout.mode == PanelBarMode.floating && !barLayout.constrained) {
      return null;
    }

    final vertical =
        barLayout.mode == PanelBarMode.pinned && !barLayout.dock.isHorizontal;

    return PanelBarPositioner(
      layout: barLayout,
      boundsOf: (_) => laneBounds,
      child: PanelTabStrip(
        side: side,
        bounds: laneBounds,
        laneBounds: laneBounds,
        vertical: vertical,
        floating: barLayout.mode == PanelBarMode.floating,
        showHandle: true,
      ),
    );
  }

  // ── 栏头 ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool titleMounted,
  ) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isSolo
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 栏头图标 = 泳道重排把手（按住拖到另一条泳道上即可换位）。
          // neoview：lane header owns collapse, reorder, focus, width ——
          // 所以「重排」这件事落在栏头，不另开一个拖拽区。
          _buildLaneHandle(context, theme),
          const SizedBox(width: 4),

          // 泳道标题（双击重置宽度）
          Expanded(
            child: Tooltip(
              message: '双击重置该栏宽度',
              child: InkWell(
                onDoubleTap: onResetWidth,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        titleOverride ?? config.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${resolvedWidth.toInt()}px',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          ...headerActions,

          // 挂进栏头的面板切换工具栏（`pinned + dock: top`，本项目默认形态）
          //
          // **刻意不传 `bounds` / `laneBounds`**：它们是「自己摆放自己」用的，
          // 而 `PanelBarPositioner` 是 LayoutBuilder + CustomSingleChildLayout，
          // 会**撑满**给它的约束 —— 页签条于是恒定占满 `maxWidth`（260），
          // 一个 380px 的泳道栏头会溢出 80 多像素（黄黑斜纹）。
          // 它在这里是**内联**在栏头 Row 里由 Row 摆放的（`bounds == null`
          // 正是 `PanelTabStrip` 为「不参与摆放」留的那一档），而且
          // `showHandle: false` 意味着它此刻根本没有拖动把手 ——
          // 传进去只会把版式撑坏。
          if (titleMounted && panelSide != null) ...[
            const SizedBox(width: 4),
            PanelTabStrip(side: panelSide!, showHandle: false),
            const SizedBox(width: 4),
          ],

          // Solo 独占按钮
          IconButton(
            icon: Icon(
              isSolo ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              size: 20,
              color: isSolo
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: isSolo ? '退出独占 (Exit Solo)' : '独占该栏 (Solo 聚焦)',
            onPressed: onToggleSolo,
            visualDensity: VisualDensity.compact,
          ),
          // 折叠泳道按钮
          IconButton(
            icon: const Icon(Icons.vertical_align_center_rounded, size: 18),
            tooltip: '折叠为紧凑条 (Collapse)',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// 栏头最左侧的泳道把手。
  ///
  /// 平时就是这条泳道的图标；**按住**才变成可拖动的把手 ——
  /// 于是「重排泳道」不需要额外占位，也不会误触（拖动与点击是两个手势）。
  Widget _buildLaneHandle(BuildContext context, ThemeData theme) {
    final icon = Icon(
      laneIcon(laneId),
      size: 18,
      color: theme.colorScheme.primary,
    );

    if (isSolo) {
      return Tooltip(message: config.title, child: icon);
    }

    return Tooltip(
      message: '${titleOverride ?? config.title}　（按住可拖动重排泳道）',
      waitDuration: const Duration(milliseconds: 500),
      child: LongPressDraggable<String>(
        data: laneId,
        delay: const Duration(milliseconds: 200),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  laneIcon(laneId),
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  titleOverride ?? config.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: icon),
      ),
    );
  }

  Widget _buildCollapsedRail(BuildContext context, ThemeData theme) {
    return Container(
      width: WorkspaceLayoutConfig.collapsedLaneWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          IconButton(
            icon: Icon(
              laneIcon(laneId),
              size: 18,
              color: theme.colorScheme.primary,
            ),
            tooltip: '${config.title} (点击展开泳道)',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              titleOverride ?? config.title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.unfold_more_rounded, size: 16),
            tooltip: '展开泳道',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static IconData laneIcon(String id) {
    switch (id) {
      case LaneId.left:
        return Icons.menu_book_rounded;
      case LaneId.reader:
        return Icons.auto_stories_rounded;
      case LaneId.right:
        return Icons.explore_rounded;
      default:
        return Icons.view_column_rounded;
    }
  }
}
