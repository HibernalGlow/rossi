// 来源：FlClash（https://github.com/chen08209/FlClash），GPL-3.0。
// 原文：`lib/widgets/sidebar.dart`（上游提交 841d6035「add a sidebar, floating dock,
// snap sheets and drag to go back」+ Gilberta 分支 b7e1318c / 23337390 的 Arc 化改造）。
// 许可口径见 `docs/adr/0021-flclash-navigation-port-and-gpl-relicense.md`。
//
// # 相对原文改了哪几处（其余逐字未动）
//
// 1. import 路径（`fl_clash/*` → `zephyr/*`）；
// 2. `context.colorScheme` / `context.textTheme` 走 `navigation_context.dart`
//    里的扩展，调用写法与原文一字不差；
// 3. `HiddenBarScrollBehavior()` → `NavigationHiddenBarScrollBehavior()`
//    （那个类拖着本仓没有的 CommonScrollBar 依赖，取语义重写）；
// 4. 顶部/底部的两条文案：上游走 `appLocalizations.showLess/showMore`，
//    这里走 slang 的 `t.navigation.sidebarCollapse/sidebarExpand`；
// 5. **底部那颗「自定义导航」从写死改成参数**（`onCustomize` + `customizeLabel`）：
//    原文直接调 `CustomNavigationDialog.show(context)`，那会把侧栏与弹窗绑死。
//    现在侧栏不认识弹窗，谁用谁传；
// 6. **新增 `actions`**：底部动作区（Glyph + 文案 + 回调的列表）。本仓导航栏上
//    原本挂在 `NavigationRail.trailing` 的那几颗动作按钮（打开本地漫画 / GPU 上屏 /
//    工作台 / 搜索）需要有个新家，而它们与 destination 的区别只是「点了不换页」。
//    **画法与上游不同**：原文复用 `_SidebarButton` + `_DestinationRow`（展开时
//    带文案），本仓改画成**一只竖排的分组槽**（`ActionGroup(axis: Axis.vertical)`）
//    里的图标键，文字走 tooltip —— 同一份清单在侧栏竖排、在底部 Dock 横排，
//    两档只换 axis（见 `page/navigation_bar.dart` 的 `_buildDockLayout`）。
//
// `windowControls` 原样保留：本仓桌面端用的是**自制标题栏**
// （`lib/widgets/desktop/desktop_shell_frame.dart`），侧栏不会与 macOS 红绿灯
// 重叠，所以调用方传 `Size.zero`；留这个参数是为了不离上游太远。

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/navigation/navigation_context.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';

const _compactWidth = 48.0;
const _expandedWidth = 220.0;
const _itemSize = 40.0;
const _itemGap = 4.0;
const _toggleGap = 8.0;
const _verticalInset = 4.0;
const _maxSideInset = 12.0;
const _iconSize = 24.0;
const _labelGap = 12.0;
const _indicatorWidth = 3.0;
const _indicatorHeight = 16.0;
const _expandDuration = Duration(milliseconds: 250);
const _indicatorDuration = Duration(milliseconds: 320);
final _itemShape = AppShape.all(10);

class SidebarDestination {
  const SidebarDestination({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;
}

/// 底部动作区的一条。与 [SidebarDestination] 长得一样、画法也一样，
/// 差别只在「点了不换页」—— 所以它没有 `selected`。
class SidebarAction {
  const SidebarAction({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;
}

/// Where the sidebar cannot widen in place, [onToggle] is null and the toggle
/// opens the expanded pane over the content instead.
///
/// [windowControls] is the area native window buttons cover at the top start
/// corner; the pane keeps it clear and never gets narrower than it.
class NavigationSidebar extends StatefulWidget {
  const NavigationSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    this.onToggle,
    this.windowControls = Size.zero,
    this.actions = const [],
    this.onCustomize,
    this.customizeLabel,
  });

  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback? onToggle;
  final Size windowControls;

  /// 底部的动作区（打开本地漫画 / GPU 上屏 / 工作台 / 搜索…）。
  final List<SidebarAction> actions;

  /// 传了才画那颗「自定义导航」入口；不传就整条不出现。
  final VoidCallback? onCustomize;

  /// 那颗入口的文案。为空时退回通用词条。
  final String? customizeLabel;

  @override
  State<NavigationSidebar> createState() => _NavigationSidebarState();
}

class _NavigationSidebarState extends State<NavigationSidebar>
    with SingleTickerProviderStateMixin {
  final _overlayController = OverlayPortalController();
  late final AnimationController _overlayExpansion = AnimationController(
    vsync: this,
    duration: _expandDuration,
  );
  late final CurvedAnimation _overlayProgress = CurvedAnimation(
    parent: _overlayExpansion,
    curve: Easing.standard,
  );

  @override
  void didUpdateWidget(covariant NavigationSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle != null && _overlayController.isShowing) {
      _overlayExpansion.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideIfDismissed());
    }
  }

  void _handleToggle() {
    final onToggle = widget.onToggle;
    if (onToggle != null) {
      onToggle();
    } else if (_overlayExpansion.isForwardOrCompleted) {
      _closeOverlay();
    } else {
      _overlayController.show();
      _overlayExpansion.forward();
    }
  }

  void _closeOverlay() {
    _overlayExpansion.reverse().whenCompleteOrCancel(_hideIfDismissed);
  }

  void _hideIfDismissed() {
    if (mounted && _overlayExpansion.isDismissed) {
      _overlayController.hide();
    }
  }

  @override
  void dispose() {
    _overlayProgress.dispose();
    _overlayExpansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: (context, info) {
        return _SidebarOverlay(
          anchor: MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          ),
          overlayWidth: info.overlaySize.width,
          progress: _overlayProgress,
          onDismiss: _closeOverlay,
          builder: (progress) => Padding(
            padding: safePadding,
            child: _SidebarPane(
              progress: progress,
              windowControls: widget.windowControls,
              expanded: true,
              destinations: widget.destinations,
              selectedIndex: widget.selectedIndex,
              onSelected: (index) {
                widget.onSelected(index);
                _closeOverlay();
              },
              onToggle: _closeOverlay,
              actions: widget.actions,
              onCustomize: widget.onCustomize,
              customizeLabel: widget.customizeLabel,
            ),
          ),
        );
      },
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.expanded ? 1.0 : 0.0),
          duration: _expandDuration,
          curve: Easing.standard,
          builder: (context, progress, _) => _SidebarPane(
            progress: progress,
            windowControls: widget.windowControls,
            expanded: widget.expanded,
            destinations: widget.destinations,
            selectedIndex: widget.selectedIndex,
            onSelected: widget.onSelected,
            onToggle: _handleToggle,
            actions: widget.actions,
            onCustomize: widget.onCustomize,
            customizeLabel: widget.customizeLabel,
          ),
        ),
      ),
    );
  }
}

class _SidebarOverlay extends StatelessWidget {
  const _SidebarOverlay({
    required this.anchor,
    required this.overlayWidth,
    required this.progress,
    required this.onDismiss,
    required this.builder,
  });

  final Rect anchor;
  final double overlayWidth;
  final Animation<double> progress;
  final VoidCallback onDismiss;
  final Widget Function(double progress) builder;

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final colorScheme = context.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: isLtr ? anchor.left : null,
          right: isLtr ? null : overlayWidth - anchor.right,
          top: anchor.top,
          height: anchor.height,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onDismiss();
                    return null;
                  },
                ),
              },
              child: FocusScope(
                autofocus: true,
                child: Material(
                  color: colorScheme.surfaceContainer,
                  shape: BorderDirectional(
                    end: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: AnimatedBuilder(
                    animation: progress,
                    builder: (_, _) => builder(progress.value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarColors {
  _SidebarColors(ColorScheme scheme)
    : selectedFill = scheme.onSurface.withValues(alpha: 0.08),
      label = scheme.onSurface,
      icon = scheme.onSurfaceVariant,
      indicator = scheme.primary,
      overlay = WidgetStateProperty.fromMap({
        WidgetState.pressed: scheme.onSurface.withValues(alpha: 0.06),
        WidgetState.focused: scheme.onSurface.withValues(alpha: 0.1),
        WidgetState.hovered: scheme.onSurface.withValues(alpha: 0.04),
        WidgetState.any: Colors.transparent,
      });

  final Color selectedFill;
  final Color label;
  final Color icon;
  final Color indicator;
  final WidgetStateProperty<Color> overlay;
}

class _SidebarPane extends StatelessWidget {
  const _SidebarPane({
    required this.progress,
    required this.windowControls,
    required this.expanded,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onToggle,
    required this.actions,
    required this.onCustomize,
    required this.customizeLabel,
  });

  final double progress;
  final Size windowControls;
  final bool expanded;
  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggle;
  final List<SidebarAction> actions;
  final VoidCallback? onCustomize;
  final String? customizeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = _SidebarColors(context.colorScheme);
    final fontSize = context.textTheme.bodyMedium?.fontSize ?? 14;
    final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final compactWidth = math.max(_compactWidth, windowControls.width);
    final sideInset = math.min(_maxSideInset, (compactWidth - _itemSize) / 2);
    final itemWidth = compactWidth - sideInset * 2;
    final iconInset = (itemWidth - _iconSize) / 2;
    final itemHeight =
        _itemSize + MediaQuery.textScalerOf(context).scale(fontSize) - fontSize;
    final rowWidth = _expandedWidth - sideInset * 2;
    final labelStyle = context.textTheme.bodyMedium?.copyWith(
      color: colors.label,
    );
    final labelWidth = rowWidth - iconInset - _iconSize - _labelGap * 2;
    String rowTooltip(String label) =>
        expanded &&
            progress == 1 &&
            _fitsOneLine(context, label, labelStyle, labelWidth)
        ? ''
        : label;
    return SizedBox(
      width: lerpDouble(compactWidth, _expandedWidth, progress),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: windowControls.height + _verticalInset),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SidebarButton(
              colors: colors,
              height: itemHeight,
              sideInset: sideInset,
              tooltip: expanded
                  ? context.t.navigation.sidebarCollapse
                  : context.t.navigation.sidebarExpand,
              tooltipIsLabel: true,
              onTap: onToggle,
              child: SizedBox(
                width: itemWidth,
                child: Center(child: GlyphIcon(AppGlyphs.sidebar(progress))),
              ),
            ),
          ),
          const SizedBox(height: _toggleGap),
          Expanded(
            child: ScrollConfiguration(
              behavior: const NavigationHiddenBarScrollBehavior(),
              child: SingleChildScrollView(
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, destination) in destinations.indexed)
                          _SidebarButton(
                            key: ValueKey(destination.label),
                            colors: colors,
                            height: itemHeight,
                            sideInset: sideInset,
                            selected: index == selectedIndex,
                            tooltip: rowTooltip(destination.label),
                            onTap: () => onSelected(index),
                            child: _DestinationRow(
                              destination: destination,
                              selected: index == selectedIndex,
                              width: rowWidth,
                              iconInset: iconInset,
                              style: labelStyle,
                              labelOpacity: labelOpacity,
                            ),
                          ),
                      ],
                    ),
                    if (selectedIndex < destinations.length)
                      _SelectionIndicator(
                        color: colors.indicator,
                        index: selectedIndex,
                        start: sideInset,
                        stride: itemHeight + _itemGap,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: _toggleGap),
          // 底部动作区：**一只竖排的分组槽**，槽里只有图标键。
          //
          // 与上游的差别（登记在 ADR-0021 的边界表里）：原文把 `actions` 画成
          // 与 destination 一模一样的整行（图标 + 文案、展开时带标签）。本仓改成
          // 「一组图标键装在同一只槽里」—— 同一份动作在**侧栏里竖排、在底部
          // Dock 里横排**，两档只换 `ActionGroup.axis`，槽与间距口径同源
          // （`ActionGroupMetrics`），也和文件管理器、书架页右上角那两处一致。
          // 文字退到 tooltip：整组因此只有一列图标那么宽，侧栏展开时栏底也不会
          // 被拉出一排长条。
          if (actions.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: sideInset),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionGroup(
                  axis: Axis.vertical,
                  children: [
                    for (final (index, action) in actions.indexed) ...[
                      if (index > 0)
                        const SizedBox(
                          height: ActionGroupMetrics.gapWithinGroup,
                        ),
                      ActionIconButton(
                        key: ValueKey(action.label),
                        glyph: action.glyph,
                        tooltip: action.label,
                        onPressed: action.onTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (onCustomize != null)
            _SidebarButton(
              colors: colors,
              height: itemHeight,
              sideInset: sideInset,
              tooltip: customizeLabel ?? context.t.navigation.customize,
              tooltipIsLabel: true,
              onTap: onCustomize!,
              child: _DestinationRow(
                destination: SidebarDestination(
                  glyph: AppGlyphs.sliders,
                  label: customizeLabel ?? context.t.navigation.customize,
                ),
                selected: false,
                width: rowWidth,
                iconInset: iconInset,
                style: labelStyle,
                labelOpacity: labelOpacity,
              ),
            ),
          const SizedBox(height: _verticalInset),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    super.key,
    required this.colors,
    required this.height,
    required this.sideInset,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected,
    this.tooltipIsLabel = false,
  });

  final _SidebarColors colors;
  final double height;
  final double sideInset;
  final bool? selected;
  final String tooltip;
  final bool tooltipIsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sideInset,
        vertical: _itemGap / 2,
      ),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: Material(
          color: selected == true ? colors.selectedFill : Colors.transparent,
          shape: _itemShape,
          child: InkWell(
            onTap: onTap,
            customBorder: _itemShape,
            mouseCursor: SystemMouseCursors.basic,
            splashFactory: NoSplash.splashFactory,
            overlayColor: colors.overlay,
            child: Tooltip(
              message: tooltip,
              excludeFromSemantics: !tooltipIsLabel,
              child: IconTheme.merge(
                data: IconThemeData(size: _iconSize, color: colors.icon),
                child: SizedBox(height: height, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _fitsOneLine(
  BuildContext context,
  String text,
  TextStyle? style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: width);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

/// The row lays out at the expanded width whatever the pane's current width,
/// so the label is clipped rather than reflowed while the pane animates.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.width,
    required this.iconInset,
    required this.style,
    required this.labelOpacity,
  });

  final SidebarDestination destination;
  final bool selected;
  final double width;
  final double iconInset;
  final TextStyle? style;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: width,
        maxWidth: width,
        child: Row(
          children: [
            SizedBox(width: iconInset),
            AnimatedGlyph(glyph: destination.glyph, filled: selected),
            const SizedBox(width: _labelGap),
            Expanded(
              child: Opacity(
                opacity: labelOpacity,
                alwaysIncludeSemantics: true,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
            const SizedBox(width: _labelGap),
          ],
        ),
      ),
    );
  }
}

/// The indicator moves by stretching toward the new row before its trailing
/// edge catches up, rather than sliding at a fixed size.
class _SelectionIndicator extends StatefulWidget {
  const _SelectionIndicator({
    required this.color,
    required this.index,
    required this.start,
    required this.stride,
  });

  final Color color;
  final int index;
  final double start;
  final double stride;

  @override
  State<_SelectionIndicator> createState() => _SelectionIndicatorState();
}

class _SelectionIndicatorState extends State<_SelectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _indicatorDuration,
    value: 1,
  );
  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant _SelectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _from = oldWidget.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _topOf(int index) =>
      index * widget.stride + (widget.stride - _indicatorHeight) / 2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final from = _topOf(_from);
        final to = _topOf(widget.index);
        final lead = Curves.easeOutCubic.transform(math.min(1, t / 0.6));
        final trail = Curves.easeInOutCubic.transform(
          math.max(0, (t - 0.35) / 0.65),
        );
        final (top, bottom) = to >= from
            ? (lerpDouble(from, to, trail)!, lerpDouble(from, to, lead)!)
            : (lerpDouble(from, to, lead)!, lerpDouble(from, to, trail)!);
        return PositionedDirectional(
          start: widget.start,
          top: top,
          width: _indicatorWidth,
          height: bottom - top + _indicatorHeight,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: widget.color,
            shape: AppShape.full,
          ),
        ),
      ),
    );
  }
}
