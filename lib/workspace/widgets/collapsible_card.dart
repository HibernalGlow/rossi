import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_control_kit.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 通用可折叠卡片组件外壳（支持泳道与边栏中 100% 复用）
///
/// 轨道上关于「位置」的三个动作 —— 上移 / 下移 / 收起 —— 都由宿主
/// （面板 / 抽屉）通过 [onMoveUp] / [onMoveDown] / [onHide] 传进来。
/// 卡片自己不需要知道自己在第几位，也不需要知道有没有下家。
///
/// 当 [headerless] 为 `true` 时，采用「无常驻标题栏 MD3 小组件 + 悬浮/右键控制层」：
/// - **日常展开态**：隐藏常驻标题栏，空间 100% 让给内容；右键或长按组件任意位置弹出上下文菜单（折叠、自定义布局、尺寸预设、全宽并撑满高度、收起/恢复）；
/// - **日常折叠态**：保留紧凑的可恢复胶囊条（图标 + 标题/摘要 + 点击展开），防止组件折叠后难以找回；
/// - **编辑布局态**：浮现顶部独立拖拽手柄、临时组件名称标签、布局菜单、折叠按钮与右下角尺寸调整手柄，内容区域本身不响应拖拽以免与滚动/滑块冲突。
class CollapsibleCard extends StatelessWidget {
  final String cardId;
  final String title;
  final Glyph icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget child;
  final bool expressive;

  /// 无常驻标题栏模式：日常态不画标题行，通过右键/长按菜单触发折叠与进入编辑模式。
  final bool headerless;

  /// [headerless] 折叠态下的自定义摘要组件（为 null 时显示 [title] 与 [trailing]）。
  final Widget? collapsedChild;

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
    this.headerless = false,
    this.collapsedChild,
    this.scrollContent = true,
    this.margin,
    this.contentPadding,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.disabledHint,
  });

  static ExpressiveButtonShape _headerShapeForCard(String cardId, int seed) {
    return switch (cardId) {
      'switch_toast' => ExpressiveButtonShape.softBurst,
      'image_tuning' => ExpressiveButtonShape.clover4Leaf,
      'super_resolution' => ExpressiveButtonShape.verySunny,
      'translate' => ExpressiveButtonShape.puffyDiamond,
      'book_information' => ExpressiveButtonShape.cookie4Sided,
      'image_information' => ExpressiveButtonShape.flower,
      'storage_information' => ExpressiveButtonShape.cookie7Sided,
      'time_information' => ExpressiveButtonShape.sunny,
      'preload_status' => ExpressiveButtonShape.gem,
      _ => expressiveShapeForSeed(seed),
    };
  }

  static ExpressiveTone _headerToneForCard(String cardId, int seed) {
    return switch (cardId) {
      'switch_toast' => ExpressiveTone.primary,
      'image_tuning' => ExpressiveTone.tertiary,
      'super_resolution' => ExpressiveTone.secondary,
      'translate' => ExpressiveTone.primary,
      _ => expressiveAccentToneForSeed(seed),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = CardLayoutScope.maybeOf(context);
    // MD3 的 filled 卡片靠**容器色**分层，不描边、不投影；圆角跟主题的形状档走。
    final radius = themeRadius(context, fallback: 12);
    final showLayoutControls = layout?.editing == true;
    final cardSeed = expressiveBlobSeed(cardId);
    final headerShape = _headerShapeForCard(cardId, cardSeed);
    final headerTone = _headerToneForCard(cardId, cardSeed);
    final defaultPadding = headerless
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.fromLTRB(12, 0, 12, 12);
    final content = Padding(
      padding: contentPadding ?? defaultPadding,
      child: applyCardGate(child, disabledHint: disabledHint),
    );

    if (headerless) {
      return _buildHeaderlessCard(
        context: context,
        theme: theme,
        layout: layout,
        radius: radius,
        showLayoutControls: showLayoutControls,
        content: content,
      );
    }

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
              if (expressive)
                Positioned(
                  top: 0,
                  right: 0,
                  width: 196,
                  height: 82,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CardHeaderPatchPainter(
                        seed: cardSeed,
                        shape: headerShape,
                        scheme: theme.colorScheme,
                        isExpanded: isExpanded,
                      ),
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, bounds) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 300;
                          final titleRegion = Semantics(
                            button: true,
                            expanded: isExpanded,
                            hint: isExpanded
                                ? t.workspace.clickToCollapse
                                : t.workspace.clickToExpand,
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
                                          ExpressiveShapeBadge(
                                            icon: icon,
                                            shape: headerShape,
                                            seed: cardSeed,
                                            size: 38,
                                            glyphSize: 20,
                                            tone: headerTone,
                                            active: !isExpanded,
                                          )
                                        else
                                          GlyphIcon(
                                            icon,
                                            size: 17,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: expressive
                                              ? theme.textTheme.titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: .15,
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
                                  tooltip: isExpanded
                                      ? t.workspace.collapseNamed(title: title)
                                      : '展开$title',
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
                              t.workspace.resizePreview(
                                w: layout!.previewSize?.width.round() ?? 0,
                                h: layout.previewSize?.height.round() ?? 0,
                              ),
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

  /// 构建无常驻标题栏的 MD3 Expressive 小组件外壳。
  Widget _buildHeaderlessCard({
    required BuildContext context,
    required ThemeData theme,
    required CardLayoutScope? layout,
    required double radius,
    required bool showLayoutControls,
    required Widget content,
  }) {
    final borderRadius = expressive
        ? const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(22),
          )
        : BorderRadius.circular(radius);

    return CardHeaderActionsHost(
      builder: (context, headerActions) => _HeaderlessContextMenuRegion(
        enableLongPress: !showLayoutControls,
        onOpenMenu: (globalPosition) =>
            _openContextMenu(context, globalPosition, layout),
        child: Padding(
          padding: margin ?? EdgeInsets.zero,
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: layout?.resizing == true || layout?.dragging == true
                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                  : showLayoutControls
                  ? BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.55),
                      width: 1.2,
                    )
                  : BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.22,
                      ),
                      width: 0.5,
                    ),
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
                  builder: (context, bounds) {
                    // 1. 日常折叠态：不显示编辑栏，展示紧凑可恢复的胶囊条
                    if (!showLayoutControls && !isExpanded) {
                      return _buildHeaderlessCollapsedStrip(context, theme);
                    }

                    // 2. 日常展开态或编辑态
                    return Column(
                      mainAxisSize: bounds.hasBoundedHeight
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showLayoutControls)
                          _buildHeaderlessEditBar(
                            context: context,
                            theme: theme,
                            layout: layout,
                            headerActions: headerActions,
                          ),
                        if (isExpanded)
                          if (bounds.hasBoundedHeight)
                            Expanded(
                              child: scrollContent
                                  ? SingleChildScrollView(
                                      primary: false,
                                      child: content,
                                    )
                                  : content,
                            )
                          else
                            content,
                      ],
                    );
                  },
                ),
                if (isExpanded &&
                    showLayoutControls &&
                    layout?.resizeHandle != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          children: [
                            if (layout?.resizing == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  t.workspace.resizePreview(
                                    w: layout!.previewSize?.width.round() ?? 0,
                                    h: layout.previewSize?.height.round() ?? 0,
                                  ),
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
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 无标题栏组件在日常折叠后的紧凑可恢复胶囊条。
  Widget _buildHeaderlessCollapsedStrip(BuildContext context, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      expanded: false,
      label: '展开$title',
      child: InkWell(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: M3EShapeContainer(
                    kind: M3EShapeKind.cookie6Sided,
                    color: scheme.primaryContainer,
                    child: Center(
                      child: GlyphIcon(
                        icon,
                        size: 14,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      collapsedChild ??
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  Flexible(child: trailing!),
                ],
                const SizedBox(width: 6),
                Tooltip(
                  message: '展开$title',
                  child: GlyphIcon(
                    AppGlyphs.chevronDown,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 无标题栏组件在编辑模式下的顶部控制条：独立拖拽手柄 + 临时组件标签 + 菜单与折叠。
  Widget _buildHeaderlessEditBar({
    required BuildContext context,
    required ThemeData theme,
    required CardLayoutScope? layout,
    required Widget? headerActions,
  }) {
    final scheme = theme.colorScheme;
    final dragHandleRegion = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(
            AppGlyphs.dragHandle,
            size: 15,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 6),
          GlyphIcon(icon, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: layout?.wrapHeader(dragHandleRegion) ?? dragHandleRegion,
          ),
          if (isExpanded && headerActions != null)
            Flexible(child: headerActions),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Flexible(child: trailing!),
          ],
          const SizedBox(width: 4),
          _buildTrackMenu(context, layout),
          ExpressiveIconButton(
            tooltip: isExpanded
                ? t.workspace.collapseNamed(title: title)
                : '展开$title',
            glyph: AppGlyphs.chevronDown,
            active: isExpanded,
            activeTurns: .5,
            size: 28,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }

  /// 右键或长按无标题栏组件时弹出的上下文菜单。
  void _openContextMenu(
    BuildContext context,
    Offset globalPosition,
    CardLayoutScope? layout,
  ) {
    final hide = layout?.onHide ?? onHide;
    final items = <CommonPopupMenuItem>[
      CommonPopupMenuItem(
        label: isExpanded
            ? t.workspace.collapseNamed(title: title)
            : '展开$title',
        glyph: isExpanded ? AppGlyphs.fold : AppGlyphs.unfold,
        onPressed: onToggle,
      ),
      if (layout?.onToggleEditing != null)
        CommonPopupMenuItem(
          label: layout!.editing ? '完成布局' : '自定义布局',
          glyph: layout.editing ? AppGlyphs.checkCircle : AppGlyphs.gridPlus,
          onPressed: layout.onToggleEditing,
        ),
    ];

    if (layout?.onResize != null || layout?.onFillRemainingHeight != null) {
      items.add(const CommonPopupMenuItem.divider());
      if (layout?.onFillRemainingHeight != null) {
        items.add(
          CommonPopupMenuItem(
            label: t.workspace.fullWidthFullHeight,
            glyph: AppGlyphs.openInFull,
            checked: layout!.fillRemainingHeight && layout.widthSpan == 4,
            onPressed: layout.onFillRemainingHeight,
          ),
        );
      }
      if (layout?.onResize != null) {
        for (final preset in [
          (1, 1, '1×1'),
          (2, 1, '2×1'),
          (2, 2, '2×2'),
          (4, 2, t.workspace.fullWidth),
        ]) {
          items.add(
            CommonPopupMenuItem(
              label: preset.$3,
              checked:
                  !layout!.fillRemainingHeight &&
                  layout.widthSpan == preset.$1 &&
                  layout.heightSpan == preset.$2,
              onPressed: () => layout.onResize!(preset.$1, preset.$2),
            ),
          );
        }
      }
    }

    if (layout != null &&
        layout.hiddenCards.isNotEmpty &&
        layout.onRestoreCard != null) {
      items.add(const CommonPopupMenuItem.divider());
      for (final hidden in layout.hiddenCards) {
        items.add(
          CommonPopupMenuItem(
            label: t.workspace.restoreNamed(title: hidden.title),
            glyph: hidden.icon,
            onPressed: () => layout.onRestoreCard!(hidden.id),
          ),
        );
      }
    }

    if (hide != null) {
      items.add(const CommonPopupMenuItem.divider());
      items.add(
        CommonPopupMenuItem(
          label: t.workspace.collapseFromPanel,
          glyph: AppGlyphs.eyeOff,
          danger: true,
          onPressed: hide,
        ),
      );
    }

    unawaited(
      showCommonPopupMenu(
        context: context,
        position: globalPosition,
        items: items,
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
      tooltip: layout == null
          ? t.workspace.cardPosition
          : t.workspace.cardLayout,
      glyph: layout?.editing == true ? AppGlyphs.gridPlus : AppGlyphs.more,
      size: headerless ? 28 : 32,
      shape: ExpressiveButtonShape.roundedSquare,
      menuChildren: [
        if (headerless) ...[
          ShelfMenuItem(
            label: isExpanded
                ? t.workspace.collapseNamed(title: title)
                : '展开$title',
            glyph: isExpanded ? AppGlyphs.fold : AppGlyphs.unfold,
            onPressed: onToggle,
          ),
          if (layout?.onToggleEditing != null)
            ShelfMenuItem(
              label: layout!.editing ? '完成布局' : '自定义布局',
              glyph: layout.editing
                  ? AppGlyphs.checkCircle
                  : AppGlyphs.gridPlus,
              onPressed: layout.onToggleEditing,
            ),
          const ShelfMenuDivider(),
        ],
        if (layout?.onFillRemainingHeight != null)
          ShelfMenuItem(
            label: t.workspace.fullWidthFullHeight,
            glyph: AppGlyphs.openInFull,
            selected: layout!.fillRemainingHeight && layout.widthSpan == 4,
            onPressed: layout.onFillRemainingHeight,
          ),
        if (layout?.onResize != null) ...[
          for (final preset in [
            (1, 1, '1×1'),
            (2, 1, '2×1'),
            (2, 2, '2×2'),
            (4, 2, t.workspace.fullWidth),
          ])
            ShelfMenuItem(
              label: preset.$3,
              selected:
                  !(layout!.fillRemainingHeight) &&
                  layout.widthSpan == preset.$1 &&
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
        if (layout != null &&
            layout.hiddenCards.isNotEmpty &&
            layout.onRestoreCard != null) ...[
          const ShelfMenuDivider(),
          for (final hidden in layout.hiddenCards)
            ShelfMenuItem(
              label: t.workspace.restoreNamed(title: hidden.title),
              glyph: hidden.icon,
              onPressed: () => layout.onRestoreCard!(hidden.id),
            ),
        ],
        if (hide != null) ...[
          const ShelfMenuDivider(),
          ShelfMenuItem(
            label: t.workspace.collapseFromPanel,
            glyph: AppGlyphs.eyeOff,
            onPressed: hide,
            destructive: true,
          ),
        ],
      ],
    );
  }
}

/// 保证无标题栏组件在任何内部子控件（缩略图、输入框、滑块、展墙）上右键或长按都能可靠弹出菜单。
///
/// 原因：内部 `TextField`、`InkWell` 或滚动视图在手势竞技场中可能赢走次键点击，
/// 导致外层 `GestureDetector.onSecondaryTapUp` 不触发。这里用 `Listener` 直接观测
/// 鼠标右键按下与抬起（位移除小于触控阈值即判定为右键点击），并配合长按手势与去重保护。
class _HeaderlessContextMenuRegion extends StatefulWidget {
  final Widget child;
  final bool enableLongPress;
  final ValueChanged<Offset> onOpenMenu;

  const _HeaderlessContextMenuRegion({
    required this.child,
    required this.enableLongPress,
    required this.onOpenMenu,
  });

  @override
  State<_HeaderlessContextMenuRegion> createState() =>
      _HeaderlessContextMenuRegionState();
}

class _HeaderlessContextMenuRegionState
    extends State<_HeaderlessContextMenuRegion> {
  Offset? _secondaryDownPosition;
  DateTime? _lastOpenedAt;

  void _trigger(Offset globalPosition) {
    final now = DateTime.now();
    if (_lastOpenedAt != null &&
        now.difference(_lastOpenedAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastOpenedAt = now;
    widget.onOpenMenu(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          _secondaryDownPosition = event.position;
        } else {
          _secondaryDownPosition = null;
        }
      },
      onPointerUp: (event) {
        final down = _secondaryDownPosition;
        _secondaryDownPosition = null;
        if (down != null && (event.position - down).distance <= kTouchSlop) {
          _trigger(event.position);
        }
      },
      onPointerCancel: (_) => _secondaryDownPosition = null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _trigger(details.globalPosition),
        onLongPressStart: widget.enableLongPress
            ? (details) => _trigger(details.globalPosition)
            : null,
        child: widget.child,
      ),
    );
  }
}

/// 卡片标题栏右上角的 **M3E 撞色几何贴片群**。
class _CardHeaderPatchPainter extends CustomPainter {
  const _CardHeaderPatchPainter({
    required this.seed,
    required this.shape,
    required this.scheme,
    required this.isExpanded,
  });

  final int seed;
  final ExpressiveButtonShape shape;
  final ColorScheme scheme;
  final bool isExpanded;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = seed.abs();
    final isDark = scheme.brightness == Brightness.dark;
    final colors = [
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
    ];
    final firstColor = colors[s % colors.length].withValues(
      alpha: isDark ? 0.36 : 0.55,
    );
    final secondColor = colors[(s + 1) % colors.length].withValues(
      alpha: isDark ? 0.28 : 0.45,
    );

    // 1. 右上主几何贴片
    _drawPolygon(
      canvas,
      polygon: shape.polygon,
      center: Offset(size.width - 20, 14),
      diameter: 66,
      angle: ((s % 9) - 4) * 0.14 + (isExpanded ? 0.15 : 0.0),
      paint: Paint()..color = firstColor,
    );

    // 2. 左侧错位次级撞色多边形贴片
    final secondShape = expressiveShapeForSeed(s >> 5);
    _drawPolygon(
      canvas,
      polygon: secondShape.polygon,
      center: Offset(size.width - 76, 8),
      diameter: 40,
      angle: -((s % 7) * 0.18),
      paint: Paint()..color = secondColor,
    );

    // 3. 种子驱动的不规则 Blob 描边环
    final blobPath = ExpressiveBlob.ofSeed(s ^ 0x27d4eb2d).path(
      rect: Rect.fromCenter(
        center: Offset(size.width - 48, 28),
        width: 48,
        height: 32,
      ),
      progress: isExpanded ? 0.2 : 0.8,
      safeInset: 4,
    );
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = scheme.primary.withValues(alpha: isDark ? 0.32 : 0.42),
    );
  }

  void _drawPolygon(
    Canvas canvas, {
    required RoundedPolygon polygon,
    required Offset center,
    required double diameter,
    required double angle,
    required Paint paint,
  }) {
    var path = polygon.toPath();
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(diameter, diameter, 1, 1)
      ..translateByDouble(-.5, -.5, 0, 1);
    path = path.transform(matrix.storage);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CardHeaderPatchPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.shape != shape ||
      oldDelegate.scheme != scheme ||
      oldDelegate.isExpanded != isExpanded;
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
