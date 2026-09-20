import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/swimlane/lane_more_menu.dart';

/// 单个泳道容器：栏头（折叠 / 独占 / 宽度 / 更多）+ 内容。
///
/// **栏头与紧凑轨都可以右键**，打开的就是那颗「更多」按钮的同一份菜单 ——
/// 栏头窄的时候那几颗按钮是**故意让位**的（面板图标优先，见 [_fitHeader]），
/// 而「改回宽度 / 换停靠边 / 退出独占」不能跟着一起没有入口。见 [_laneMenu]。
///
/// **栏头归泳道自己**（neoview 契约）：edge 模式那套「钉边 / 拖动 / 改尺寸」的控件
/// 在这里一律不出现；[headerActions] 是泳道往自己栏头里塞控件的口子 ——
/// 阅读器泳道就用它把模式切换放进自己的 chrome，于是 Reader 的动作永远跟着 Reader 走。
class SwimlaneColumn extends StatelessWidget {
  final String laneId;
  final LaneConfig config;

  /// 本泳道当前的实际宽度（阅读器泳道由视口比例算出，不等于 [LaneConfig.width]）。
  final double resolvedWidth;

  /// 工作台视口宽：宽度输入框要把「用户输入的像素」换算回阅读器泳道的比例，
  /// 而这个数只有条带那一层知道（`SwimlaneWorkspace` 的 LayoutBuilder）。
  final double viewportWidth;

  final bool isSolo;
  final bool isFullscreen;

  /// 这一档**按紧凑轨来画**（44px 那条只留图标与标题的窄栏）。
  ///
  /// 它比 `config.collapsed` 更宽：除了用户自己折叠的泳道，还包括「Reader 独占时
  /// 显示泳道切换栏」把其余泳道挤成轨的情形 —— 宽度是条带算出来的，
  /// 这里必须照同一个结果画，否则 44px 的盒子里塞进整块面板内容，
  /// 界面上就是一条黄黑斜纹而不是切换栏。
  final bool isRail;

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

  /// 栏头右侧的附加控件。**必须窄**（图标按钮级别）：[_fitHeader] 就是按
  /// 一颗 40 算它们要占多少，塞一条宽东西进去，让位判断会算错。
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
    required this.viewportWidth,
    required this.isSolo,
    this.isFullscreen = false,
    this.isRail = false,
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
    //
    // 这一档**没有**那颗「更多」按钮（44px 塞不下），所以右键这条轨就是改宽度 /
    // 独占 / 面板栏摆放的唯一入口 —— 折叠态下也要能把泳道改回来。
    if (_showsAsRail) {
      return _withLaneContextMenu(context, _buildCollapsedRail(context, theme));
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
            borderRadius: isFullscreen
                ? BorderRadius.zero
                : BorderRadius.circular(12),
            border: isFullscreen
                ? null
                : Border.all(
                    color: isActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.55)
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                    width: isActive ? 1.5 : 1,
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // 栏头整行都是「更多」菜单的右键目标：这一行被泳道裁剪，按钮
              // 一旦挤不出去就没有入口，而改宽度 / 换停靠边只有这里做得到。
              if (!isFullscreen)
                _withLaneContextMenu(
                  context,
                  _buildHeader(
                    context,
                    theme,
                    titleMounted,
                    constraints.maxWidth,
                  ),
                ),
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

  /// 这一档**是不是按紧凑轨画的**（`build()` 选轨用的就是它）。
  ///
  /// 单独抽出来是因为「更多」菜单里那一项的标签要照**画出来的样子**写，
  /// 而不是照 `config.collapsed` 那条记账 —— 见 `LaneMenu.showsAsRail`。
  bool get _showsAsRail => (config.collapsed || isRail) && !isSolo;

  /// 这条泳道的「更多」菜单内容。
  ///
  /// 栏头那颗按钮与**右键栏头**用的是同一份 —— 右键那条路是给「按钮被挤到看不见」
  /// 留的退路，两边项集不一致就失去了意义。
  LaneMenu _laneMenu() {
    return LaneMenu(
      laneId: laneId,
      viewportWidth: viewportWidth,
      panelSide: panelSide,
      showsAsRail: _showsAsRail,
      onToggleCollapse: onToggleCollapse,
      onToggleSolo: onToggleSolo,
      onResetWidth: onResetWidth,
    );
  }

  /// 把 [child] 包成「右键即打开本泳道更多菜单」的区域。
  ///
  /// 只挂右键：左键那几件事（双击标题重置宽度、按住把手重排、按钮本身）各有自己的
  /// 识别器，都在这个 `GestureDetector` 的内侧，谁离指针更近谁赢。页签条的页签
  /// 自己也吃右键，所以右键页签仍然是「那个面板」的菜单，不是这条泳道的。
  Widget _withLaneContextMenu(BuildContext context, Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) =>
          _laneMenu().show(context, details.globalPosition),
      child: child,
    );
  }

  /// 栏头。
  ///
  /// [laneWidth] 是这条泳道此刻的宽度：谁在、谁让位要从它算，见 [_fitHeader]。
  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool titleMounted,
    double laneWidth,
  ) {
    final fit = _fitHeader(context, titleMounted, laneWidth);

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
          //
          // 标题文本本身是 `Flexible`（省略号），所以栏头一挤它先缩水，不用判什么；
          // 徽标却是**硬**的 —— 留 0 宽它照样要 62.5，于是整行溢出（黄黑斜纹）。
          // 因此这一颗由 [_fitHeader] 决定画不画。
          Expanded(
            child: Tooltip(
              message: '双击重置该栏宽度　·　右键打开该泳道的菜单',
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
                    if (fit.showBadge) ...[
                      const SizedBox(width: 6),
                      // 宽度徽标是**定宽**的：栏头的让位判断要的是硬数，
                      // 而这一颗的宽跟着字号与字体走（`labelSmall` + 项目自带字体，
                      // 数字差不多一个字一个全角宽）。早先按「实测 62.5」记一笔，
                      // 字体口径一换就少算了 5px，表现为 440px 的泳道整行溢出。
                      // 定宽之后剩下的只是「四位数会不会省略号」，而那不再影响版式。
                      SizedBox(
                        width: _LaneChrome.badgeInner,
                        child: Container(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
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
          // 会**撑满**给它的约束。它在这里是**内联**在栏头 Row 里由 Row 摆放的
          // （`bounds == null` 正是 `PanelTabStrip` 为「不参与摆放」留的那一档），
          // 而且 `showHandle: false` 意味着它此刻根本没有拖动把手 ——
          // 传进去只会把版式撑坏。
          //
          // 「不参与摆放」不等于「按内容取宽」：视口在主轴上**总是铺满**给它的宽度，
          // 所以这里传的 `maxWidth` 就是它**实际能占**的那一段 ——
          // 由 [_fitHeader] 按「面板图标必须完整」算出来，而不是一个凭空的封顶值。
          if (titleMounted && panelSide != null) ...[
            const SizedBox(width: 4),
            PanelTabStrip(
              side: panelSide!,
              showHandle: false,
              maxWidth: fit.stripMaxWidth,
            ),
            const SizedBox(width: 4),
          ],

          // Solo 独占按钮
          if (fit.showSolo)
            IconButton(
              icon: Icon(
                isSolo
                    ? Icons.center_focus_strong_rounded
                    : Icons.center_focus_weak_rounded,
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
          if (fit.showCollapse)
            IconButton(
              icon: const Icon(Icons.vertical_align_center_rounded, size: 18),
              tooltip: '折叠为紧凑条 (Collapse)',
              onPressed: onToggleCollapse,
              visualDensity: VisualDensity.compact,
            ),
          // 这条泳道其余的动作（独占 / 宽度 / 面板栏摆放 / 折叠）。
          // 默认形态下面板栏就挂在这一行里、没有拖动把手，
          // 所以「把它挪走」只有这个菜单做得到 —— 见 `LaneMenu`。
          //
          // 它是三颗按钮里最后让位的那一颗（独占与折叠都在这份菜单里，
          // 而菜单本身还有右键栏头这一条退路，见 [_withLaneContextMenu]）。
          if (fit.showMore) LaneMoreMenu(menu: _laneMenu()),
        ],
      ),
    );
  }

  /// 栏头这一行此刻**谁在、谁让位**。
  ///
  /// 让位顺序（用户 2026-09-20 的口径）：**面板图标必须完整显示**，所以页签条先拿
  /// 走它实际要占的那一段；剩下的按「更多 → 折叠 → 独占 → 宽度徽标 → 标题文本」
  /// 分，越靠后的越先没有。标题文本是 `Flexible`，压力先到它身上（省略号），
  /// 这一档不需要判据；徽标是硬的，所以要单独判。三颗按钮让出去不等于失去功能 ——
  /// 那几件事全在右键栏头弹出的同一份菜单里（见 `LaneMenu`、[_withLaneContextMenu]）。
  ///
  /// 只有连「把手 + 页签条」都塞不下时，才让页签条自己滚（它本来就是滚动视口）——
  /// 那是最后一档，不是默认档。早先版本恰好相反：先给标题预留 75，剩下的封顶给
  /// 页签条，于是 389px 的泳道上只剩 158，而五个图标加「已收起」入口要 210 上下，
  /// 最后一个图标被齐根裁掉 —— 就是这次要修的东西。
  ///
  /// `stripMaxWidth` 取「页签条要的 + 此刻还没被拿走的余量」：`shrinkWrap` 的视口
  /// 只会占到自己要的那一段，多给的那点永远不会真被占掉；而它**小于**需求量时
  /// （最后一档）非弹性那几项的总和正好等于整行可用宽，`Expanded` 拿到 0 而不是
  /// 负数 —— 负数就是黄黑斜纹。
  _LaneHeaderFit _fitHeader(
    BuildContext context,
    bool titleMounted,
    double laneWidth,
  ) {
    final side = panelSide;
    final stripNeed = titleMounted && side != null
        ? PanelTabStrip.titleMountedWidth(
            side,
            context.select<WorkspaceCubit, WorkspaceBoardLayout>(
              (c) => c.state.board,
            ),
          )
        : 0.0;

    // 标题、徽标、页签条与右侧那几颗按钮能分的总量。
    // `headerActions` 按这个字段的契约（图标按钮级别）一颗算 40：今天只有阅读器
    // 泳道往里塞东西，而它没有页签条，所以这一项不影响面板泳道的那笔账。
    var rest =
        laneWidth -
        _LaneChrome.borderAndPadding(isActive) -
        _LaneChrome.handle -
        _LaneChrome.iconButton * headerActions.length;

    if (stripNeed > 0) rest -= _LaneChrome.stripGaps + stripNeed;

    // 越晚让位的越先要 —— 所以「更多」排在最前面领位置。
    final showMore = rest >= _LaneChrome.moreButton;
    if (showMore) rest -= _LaneChrome.moreButton;
    final showCollapse = rest >= _LaneChrome.collapseButton;
    if (showCollapse) rest -= _LaneChrome.collapseButton;
    final showSolo = rest >= _LaneChrome.soloButton;
    if (showSolo) rest -= _LaneChrome.soloButton;

    final showBadge = rest >= _LaneChrome.badge;
    if (showBadge) rest -= _LaneChrome.badge;

    return _LaneHeaderFit(
      stripMaxWidth: (stripNeed + (rest < 0 ? rest : 0)).clamp(
        0.0,
        double.infinity,
      ),
      showBadge: showBadge,
      showSolo: showSolo,
      showCollapse: showCollapse,
      showMore: showMore,
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

/// 栏头那一行各项的**实测**宽度（在 400px 泳道上量的，用于 [_fitHeader] 的让位判断）。
///
/// 只有 `borderAndPadding` 与 `handle` 是本文件画出来的（`Container` 的 10+10 内边距、
/// 泳道 1+1 边框、18 的图标与它后面那道 4）；`iconButton` 是
/// `IconButton(visualDensity: compact)` 的实际尺寸，`moreButton` 见 `LaneMoreMenu`，
/// `badge` 是宽度徽标连着它与标题之间的 6。改这几处版式都要回来核这几个数。
class _LaneChrome {
  const _LaneChrome._();

  /// 泳道边框 + 栏头左右内边距 10+10。
  ///
  /// 边框按**是不是激活那条**算：`Border.all(width: isActive ? 1.5 : 1)`，
  /// 于是激活那条的可用宽少 1px。少算这一格正好是「440px 的泳道溢出 1px」，
  /// 而溢出在判据里是异常、在界面上是斜纹。
  static double borderAndPadding(bool isActive) => 20 + (isActive ? 3 : 2);

  /// 泳道图标（= 重排把手）与它后面那道留白。
  static const double handle = 18 + 4;

  /// 页签条左右各 4 的留白。
  static const double stripGaps = 4 + 4;

  /// 一颗 `IconButton(visualDensity: compact)`。
  static const double iconButton = 40;

  static const double soloButton = iconButton;
  static const double collapseButton = iconButton;

  /// 「更多」：4+4 内边距 + 16 的图标（见 `LaneMoreMenu`）。
  static const double moreButton = 24;

  /// 宽度徽标：它是**定宽**的（`badgeInner`，见 `_buildHeader` 里那段说明），
  /// 所以这笔账是死的 —— 加上它与标题之间那道 6。
  static const double badgeInner = 72;
  static const double badge = badgeInner + 6;
}

/// [_fitHeader] 的结果：此刻栏头右侧哪几项还在。
class _LaneHeaderFit {
  const _LaneHeaderFit({
    required this.stripMaxWidth,
    required this.showBadge,
    required this.showSolo,
    required this.showCollapse,
    required this.showMore,
  });

  /// 挂进栏头那条页签条的上限宽（它按内容取宽，所以这是**上限**不是预留）。
  final double stripMaxWidth;

  final bool showBadge;
  final bool showSolo;
  final bool showCollapse;
  final bool showMore;
}
