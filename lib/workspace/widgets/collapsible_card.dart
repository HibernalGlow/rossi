import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';

/// 通用可折叠卡片组件外壳（支持泳道与边栏中 100% 复用）
///
/// 轨道上关于「位置」的三个动作 —— 上移 / 下移 / 收起 —— 都由宿主
/// （面板 / 抽屉）通过 [onMoveUp] / [onMoveDown] / [onHide] 传进来。
/// 卡片自己不需要知道自己在第几位，也不需要知道有没有下家。
class CollapsibleCard extends StatelessWidget {
  final String cardId;
  final String title;
  final Glyph icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget child;
  final bool expressive;

  /// 由内容自己适配有界槽位（分段、紧凑图表），不再套滚动视图。
  final bool scrollContent;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? contentPadding;

  /// 在所属面板里上移 / 下移。`null` = 已经在头/尾（菜单项置灰）。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// 把这张卡从当前面板收起来（可从面板标题行的「已收起」入口恢复）。
  final VoidCallback? onHide;

  /// 非 null = 这张卡在**当前这台机器上用不了**：内容整体灰掉、不吃点击，
  /// 标题行挂一颗说明 tag（例如「仅桌面」）。
  ///
  /// 为什么不是干脆不画：面板会把「一张卡都没有」的整个页签藏掉，
  /// 于是「这个功能不存在」和「这台机器暂时做不到」在界面上长得一模一样。
  final String? disabledHint;

  const CollapsibleCard({
    super.key,
    required this.cardId,
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    this.trailing,
    required this.child,
    this.expressive = false,
    this.scrollContent = true,
    this.margin,
    this.contentPadding,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = CardLayoutScope.maybeOf(context);
    // MD3 的 filled 卡片靠**容器色**分层，不描边、不投影；圆角跟主题的形状档走。
    final radius = themeRadius(context, fallback: 12);
    final showLayoutControls = layout?.editing == true;
    final content = Padding(
      padding: contentPadding ?? const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: applyCardGate(child, disabledHint: disabledHint),
    );

    // 卡片可直接挂在泳道/抽屉里，由自身提供与应用同库的 Material。
    // 用 Material 绘制背景并裁剪，保证标题栏和内容的墨水反馈也在圆角内。
    return CardHeaderActionsHost(
      builder: (context, headerActions) => Padding(
        padding:
            margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: expressive
                ? const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(28),
                  )
                : BorderRadius.circular(radius),
            side: layout?.resizing == true || layout?.dragging == true
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : layout?.editing == true
                ? BorderSide(color: theme.colorScheme.outlineVariant)
                : BorderSide.none,
          ),
          animationDuration: ExpressiveMotion.duration(
            context,
            ExpressiveMotion.effectDuration,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              LayoutBuilder(
                builder: (context, bounds) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 300;
                          final titleRegion = Semantics(
                            button: true,
                            expanded: isExpanded,
                            hint: isExpanded ? '点击折叠' : '点击展开',
                            child: InkWell(
                              onTap: onToggle,
                              splashFactory: expressive
                                  ? NoSplash.splashFactory
                                  : null,
                              overlayColor: expressive
                                  ? const WidgetStatePropertyAll(
                                      Colors.transparent,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: expressive ? 48 : 36,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, titleConstraints) => Row(
                                    children: [
                                      if (titleConstraints.maxWidth >= 64) ...[
                                        if (expressive)
                                          SizedBox(
                                            width: 36,
                                            height: 36,
                                            child: M3EShapeContainer(
                                              kind: M3EShapeKind.cookie4Sided,
                                              color: theme
                                                  .colorScheme
                                                  .primaryContainer,
                                              child: Center(
                                                child: GlyphIcon(
                                                  icon,
                                                  size: 20,
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          GlyphIcon(
                                            icon,
                                            size: 17,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: expressive
                                              ? theme.textTheme.titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    )
                                              : theme.textTheme.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                          final header = expressive
                              ? ActionBubbleRegion(
                                  child: ActionBubbleTarget(
                                    enabled: !eInkInstantRoutes,
                                    child: ElasticPress(
                                      enabled:
                                          !eInkInstantRoutes &&
                                          !MediaQuery.disableAnimationsOf(
                                            context,
                                          ),
                                      child: titleRegion,
                                    ),
                                  ),
                                )
                              : titleRegion;
                          final titleRow = Row(
                            children: [
                              Expanded(
                                child: layout?.wrapHeader(header) ?? header,
                              ),
                              if (isExpanded && headerActions != null)
                                Flexible(child: headerActions),
                              if (!narrow && trailing != null) ...[
                                Flexible(child: trailing!),
                                const SizedBox(width: 6),
                              ],
                              if (!narrow && disabledHint != null) ...[
                                Flexible(
                                  child: _DisabledTag(text: disabledHint!),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (showLayoutControls &&
                                  (layout?.onResize != null ||
                                      layout?.onHide != null ||
                                      onMoveUp != null ||
                                      onMoveDown != null ||
                                      onHide != null))
                                _buildTrackMenu(context, layout),
                              if (showLayoutControls)
                                ExpressiveIconButton(
                                  tooltip: isExpanded ? '折叠$title' : '展开$title',
                                  glyph: AppGlyphs.chevronDown,
                                  active: isExpanded,
                                  activeTurns: .5,
                                  size: 32,
                                  onPressed: onToggle,
                                ),
                            ],
                          );
                          if (!narrow ||
                              (trailing == null && disabledHint == null)) {
                            return titleRow;
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              titleRow,
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (trailing != null)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: constraints.maxWidth,
                                      ),
                                      child: trailing!,
                                    ),
                                  if (disabledHint case final hint?)
                                    _DisabledTag(text: hint),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // 网格槽位由跨度决定；正文滚动或自行适配，标题与手柄留在原位。
                    if (bounds.hasBoundedHeight)
                      Expanded(
                        child: RetainedPanelSwitcher(
                          selectedId: isExpanded ? 'content' : 'collapsed',
                          children: {
                            'content': scrollContent
                                ? SingleChildScrollView(
                                    primary: false,
                                    child: content,
                                  )
                                : content,
                            'collapsed': const SizedBox.expand(),
                          },
                        ),
                      )
                    else
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: content,
                        crossFadeState: isExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: eInkInstantRoutes
                            ? Duration.zero
                            : ExpressiveMotion.duration(
                                context,
                                ExpressiveMotion.spatialDuration,
                              ),
                        firstCurve: Curves.easeOut,
                        secondCurve: Curves.easeOut,
                        sizeCurve: ExpressiveMotion.spatialCurve,
                      ),
                    if (isExpanded && layout?.resizeHandle != null)
                      SizedBox(
                        height: bounds.hasBoundedHeight
                            ? (bounds.maxHeight * .2).clamp(0, 36)
                            : 36,
                      ),
                  ],
                ),
              ),
              if (isExpanded && layout?.resizeHandle != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        if (layout?.resizing == true)
                          Expanded(
                            child: Text(
                              '${layout!.previewSize?.width.round()} × ${layout.previewSize?.height.round()} · 松开保存',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Spacer(),
                        layout!.resizeHandle!,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 卡片尺寸预设与收起入口；网格内排序由标题拖动完成。
  ///
  /// 放在卡片的**标题栏里**而不是卡内：这几个动作改的是「卡片在面板里的位置」，
  /// 与卡片内容无关；收进一个菜单也让标题栏在窄泳道里不至于被按钮挤爆。
  ///
  /// 与内容工具栏共享 Expressive 操作入口、分组表面和菜单动画。
  Widget _buildTrackMenu(BuildContext context, CardLayoutScope? layout) {
    final hide = layout?.onHide ?? onHide;
    return ShelfMenuButton(
      tooltip: layout == null ? '卡片位置' : '卡片布局',
      glyph: layout?.editing == true ? AppGlyphs.gridPlus : AppGlyphs.more,
      size: 32,
      shape: ExpressiveButtonShape.roundedSquare,
      menuChildren: [
        if (layout?.onResize != null) ...[
          for (final preset in [
            (1, 1, '1×1'),
            (2, 1, '2×1'),
            (2, 2, '2×2'),
            (4, 2, '全宽'),
          ])
            ShelfMenuItem(
              label: preset.$3,
              selected:
                  layout!.widthSpan == preset.$1 &&
                  layout.heightSpan == preset.$2,
              onPressed: () => layout.onResize!(preset.$1, preset.$2),
            ),
        ],
        // 没有网格宿主的独立卡片仍可使用旧的排序回调。
        if (layout == null) ...[
          ShelfMenuItem(
            label: '上移',
            glyph: AppGlyphs.arrowUp,
            onPressed: onMoveUp,
          ),
          ShelfMenuItem(
            label: '下移',
            glyph: AppGlyphs.arrowDown,
            onPressed: onMoveDown,
          ),
        ],
        if (hide != null) ...[
          const ShelfMenuDivider(),
          ShelfMenuItem(
            label: '从该面板收起',
            glyph: AppGlyphs.eyeOff,
            onPressed: hide,
            destructive: true,
          ),
        ],
      ],
    );
  }
}

/// 标题行上那颗「这台机器做不到」的小标签。
class _DisabledTag extends StatelessWidget {
  final String text;

  const _DisabledTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 平台判不动这张卡时，把内容**灰掉且不吃点击**，但照样画出来。
///
/// 单独抽出来是因为它有两个落点：折叠外壳的内容区，以及独占面板
/// （`WorkspaceCardChrome.standalone` —— 那条路上根本没有 [CollapsibleCard]）。
/// 只在壳里做的话，卡片一旦独占整个面板，灰显就静默失效了。
///
/// 灰掉但留着：看得见「有这颗开关、这台机器暂时拨不动」，
/// 比整张卡凭空消失少一次「那功能去哪了」。
Widget applyCardGate(Widget child, {String? disabledHint}) {
  if (disabledHint == null) return child;
  return Opacity(
    opacity: 0.55,
    child: IgnorePointer(ignoring: true, child: child),
  );
}
