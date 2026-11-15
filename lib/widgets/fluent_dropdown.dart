import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/config/global/global_setting.dart';

part 'navigation/fluent_menu_surface.dart';

/// A single entry in a fluent popup menu.
class FluentPopupMenuItem<T> {
  const FluentPopupMenuItem({
    required this.value,
    this.leading,
    required this.title,
    this.trailing,
    this.enabled = true,
    this.selected = false,
  }) : isDivider = false;

  /// 一条分隔线：只把菜单切成几段，不可点、不返回值。
  const FluentPopupMenuItem.divider()
    : value = null,
      isDivider = true,
      leading = null,
      title = const SizedBox.shrink(),
      trailing = null,
      enabled = false,
      selected = false;

  /// The value returned when this item is selected.
  ///
  /// 分隔线没有值 —— 它不会被选中。
  final T? value;

  /// Whether this entry is just a divider.
  final bool isDivider;

  /// Optional widget displayed at the start of the item (typically an icon).
  final Widget? leading;

  /// The main label of the item.
  final Widget title;

  /// Optional widget displayed at the end of the item.
  final Widget? trailing;

  /// Whether the item can be selected.
  final bool enabled;

  /// 这一项是不是「当前生效的那个值」。
  ///
  /// 单选（视图模式、穿透深度）与开关（显示隐藏文件）都靠它打勾：没有 [leading]
  /// 时勾占住开头那一格，有图标就把勾挪到末尾 —— 与 [FluentDropdown] 同一套画法。
  final bool selected;
}

/// Internal representation of a menu entry, used by the shared overlay.
class _MenuEntry<T> {
  const _MenuEntry({
    required this.title,
    this.value,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.isSelected = false,
    this.isDivider = false,
  });

  final T? value;
  final Widget? leading;
  final Widget title;
  final Widget? trailing;
  final bool enabled;
  final bool isSelected;
  final bool isDivider;
}

/// A button that displays a fluent-styled popup menu when tapped.
///
/// This is intended as a drop-in replacement for [PopupMenuButton] with the
/// same visual style as [FluentDropdown]: 圆角面板、悬停高亮，选中项打勾
/// （[FluentPopupMenuItem.selected]），分组用 [FluentPopupMenuItem.divider]。
class FluentPopupMenuButton<T> extends StatefulWidget {
  const FluentPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.child,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.visualDensity,
    this.style,
  });

  /// Called to build the list of menu items when the menu is opened.
  final List<FluentPopupMenuItem<T>> Function(BuildContext context) itemBuilder;

  /// Called when the user selects an item.
  final ValueChanged<T>? onSelected;

  /// The widget used as the tappable trigger. Either [child] or [icon] must
  /// be provided.
  final Widget? child;

  /// Convenience property to use an icon as the trigger. Either [child] or
  /// [icon] must be provided.
  final Widget? icon;

  /// Tooltip shown on long press / hover.
  final String? tooltip;

  /// Whether the button can be pressed.
  final bool enabled;

  /// 触发键的密度。工具栏里别的键是 `VisualDensity.compact` 时传同一个值，
  /// 否则默认 48 的按钮会把整行顶高。
  final VisualDensity? visualDensity;

  /// 触发键的样式。它和同一行里的 `IconButton` 共用一份 MD3 度量时传进去
  /// （见 `workspace/widgets/cards/file_manager_toolbar.dart` 的
  /// `FileManagerToolbarIconButton.style`），否则这一颗会退回 48 的缺省档。
  final ButtonStyle? style;

  @override
  State<FluentPopupMenuButton<T>> createState() =>
      _FluentPopupMenuButtonState<T>();
}

/// 触发按钮共用的一套「开一次菜单」：这里只负责插入/跟踪/移除，
/// 摆位与动画全部交给 [_MenuSurface]。
///
/// 用抽象成员而不是 `on State` 拿到 `context`/`setState`：`on State` 会被推成
/// `State<StatefulWidget>`，和 `State<FluentDropdown<T>>` 冲掉泛型实参。
///
/// 坑：`OverlayEntry.remove()` 会同步触发菜单的 `dispose()`，而它的 `dispose()`
/// 里也会回调 `onClosed` 走回这条路径，所以必须先摘掉引用再 remove，否则二次移除。
mixin _FluentMenuTrigger<T> {
  BuildContext get context;
  bool get mounted;
  void setState(VoidCallback fn);

  CommonPopupRoute<T>? _overlayEntry;
  bool _menuOpen = false;

  /// 菜单是否开着（`FluentDropdown` 用它转箭头）。
  bool get menuIsOpen => _menuOpen;

  /// 打开菜单时构造菜单项。
  List<_MenuEntry<T>> buildMenuEntries();

  /// 用户选了一项，在关闭动画播完之后回调。
  void onMenuSelected(T value);

  void toggleMenu() {
    if (!mounted) return;
    if (_menuOpen) {
      final route = _overlayEntry;
      if (route?.isCurrent ?? false) route!.navigator?.pop();
    } else {
      _openMenu();
    }
  }

  /// 在宿主 `dispose()` 里调用：菜单还开着就被摘掉时把 OverlayEntry 收干净。
  void detachMenu() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    // 触发控件可能随页面在 Navigator 锁定期间销毁，移除留到下一帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = entry.navigator;
      if (navigator != null && navigator.mounted) navigator.removeRoute(entry);
    });
  }

  void _openMenu() {
    final entries = buildMenuEntries();
    final renderBox = context.findRenderObject() as RenderBox;
    _overlayEntry = _insertMenu<T>(
      context: context,
      anchor: renderBox.localToGlobal(Offset.zero) & renderBox.size,
      entries: entries,
      menuWidth: _calculatePopupMenuWidth(
        context,
        renderBox.size.width,
        entries,
      ),
      onSelected: onMenuSelected,
      onClosed: _handleMenuClosed,
    );
    setState(() => _menuOpen = true);
  }

  void _handleMenuClosed() {
    detachMenu();
    if (mounted) setState(() => _menuOpen = false);
  }
}

class _FluentPopupMenuButtonState<T> extends State<FluentPopupMenuButton<T>>
    with _FluentMenuTrigger<T> {
  @override
  List<_MenuEntry<T>> buildMenuEntries() => widget
      .itemBuilder(context)
      .map(
        (item) => _MenuEntry<T>(
          value: item.value,
          leading: item.leading,
          title: item.title,
          trailing: item.trailing,
          enabled: item.enabled,
          isSelected: item.selected,
          isDivider: item.isDivider,
        ),
      )
      .toList();

  @override
  void onMenuSelected(T value) => widget.onSelected?.call(value);

  @override
  void dispose() {
    detachMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      return InkWell(
        onTap: widget.enabled ? toggleMenu : null,
        borderRadius: BorderRadius.circular(8),
        child: widget.child,
      );
    }
    return IconButton(
      icon: widget.icon ?? const GlyphIcon(AppGlyphs.more),
      tooltip: widget.tooltip,
      visualDensity: widget.visualDensity,
      style: widget.style,
      onPressed: widget.enabled ? toggleMenu : null,
    );
  }
}

/// How the selected item is highlighted inside a [FluentDropdown] menu.
enum FluentDropdownIndicator {
  /// Material-style checkmark on the left of the selected item.
  checkmark,

  /// Fluent UI-style vertical accent bar on the left of the selected item.
  bar,
}

/// A Fluent UI-style dropdown button.
///
/// The trigger looks like a bordered input box. Tapping it opens an overlay
/// menu with rounded corners, a border, and a scale + fade open animation.
/// The menu is automatically aligned to stay within the screen bounds.
class FluentDropdown<T> extends StatefulWidget {
  const FluentDropdown({
    super.key,
    required this.value,
    required this.displayValue,
    required this.items,
    required this.onChanged,
    this.indicator = FluentDropdownIndicator.checkmark,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  /// Currently selected value.
  final T value;

  /// Text displayed in the trigger button.
  final String displayValue;

  /// Map of selectable values to their display labels.
  final Map<T, String> items;

  /// Called when the user selects a different value.
  final ValueChanged<T>? onChanged;

  /// Selected-item highlight style. Defaults to the settings-page checkmark.
  final FluentDropdownIndicator indicator;

  /// Menu panel background. Defaults to the theme surface color.
  final Color? panelColor;

  /// Selected item background. Defaults to a translucent primary container.
  final Color? selectedColor;

  /// Hovered item background. Defaults to a lighter translucent primary container.
  final Color? hoverColor;

  /// Menu panel corner radius.
  final double panelBorderRadius;

  /// Menu item corner radius.
  final double itemBorderRadius;

  @override
  State<FluentDropdown<T>> createState() => _FluentDropdownState<T>();
}

class _FluentDropdownState<T> extends State<FluentDropdown<T>>
    with _FluentMenuTrigger<T> {
  @override
  List<_MenuEntry<T>> buildMenuEntries() => widget.items.entries
      .map(
        (entry) => _MenuEntry<T>(
          value: entry.key,
          title: Text(entry.value),
          isSelected: entry.key == widget.value,
        ),
      )
      .toList();

  @override
  void onMenuSelected(T value) => widget.onChanged?.call(value);

  @override
  void dispose() {
    detachMenu();
    super.dispose();
  }

  void _toggle() {
    if (!mounted) return;
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final entries = widget.items.entries.map((entry) {
      return _MenuEntry<T>(
        value: entry.key,
        title: Text(entry.value),
        isSelected: entry.key == widget.value,
      );
    }).toList();

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);

    final fitsBelow =
        position.dy + size.height + 8 + 200 <
        screenSize.height - safePadding.bottom;
    final fitsRight = position.dx + 220 <= screenSize.width - safePadding.right;
    final menuWidth = _calculateMenuWidth(context, size.width);

    _overlayEntry = OverlayEntry(
      builder: (context) => _MenuOverlay<T>(
        layerLink: _layerLink,
        triggerSize: size,
        menuWidth: menuWidth,
        entries: entries,
        alignRight: !fitsRight,
        alignTop: !fitsBelow,
        onSelected: (value) {
          _close(onComplete: () => widget.onChanged?.call(value));
        },
        onDismiss: _close,
        scaleAnimation: _scaleAnimation,
        opacityAnimation: _opacityAnimation,
        indicator: widget.indicator,
        panelColor: widget.panelColor,
        selectedColor: widget.selectedColor,
        hoverColor: widget.hoverColor,
        panelBorderRadius: widget.panelBorderRadius,
        itemBorderRadius: widget.itemBorderRadius,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _controller.forward();
    setState(() => _isOpen = true);
  }

  void _close({VoidCallback? onComplete}) {
    if (!_isOpen || !mounted) return;
    // 立即把状态置为关闭，避免关闭过程中重复触发 _toggle/_close。
    _isOpen = false;
    _controller.reverse().then((_) {
      // 动画期间 widget 可能被 deactivate/dispose，所以这里必须判断 mounted。
      // onComplete（即 onChanged）仍要调用：用户已经做出了选择，
      // 即使本 widget 被移除，通知父级更新状态也是安全的（不访问 context）。
      if (!mounted) {
        onComplete?.call();
        return;
      }
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
      onComplete?.call();
    });
  }

  double _calculateMenuWidth(BuildContext context, double triggerWidth) {
    final textStyle =
        Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    var maxItemWidth = 0.0;
    for (final label in widget.items.values) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      if (painter.width > maxItemWidth) {
        maxItemWidth = painter.width;
      }
    }

    // indicator (18 checkmark / 3 bar) + 12 spacing + 24 item padding + 16 menu padding
    final indicatorWidth = widget.indicator == FluentDropdownIndicator.bar
        ? 3.0
        : 18.0;
    final contentWidth = maxItemWidth + indicatorWidth + 12 + 24 + 16;
    return contentWidth.clamp(triggerWidth, 340.0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = context.textColor;

    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _close();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: widget.onChanged == null ? null : _toggle,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle?.copyWith(
                      color: textColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _calculatePopupMenuWidth<T>(
  BuildContext context,
  double triggerWidth,
  List<_MenuEntry<T>> entries,
) {
  final textStyle =
      Theme.of(context).textTheme.bodyMedium ??
      DefaultTextStyle.of(context).style;
  final textScaler = MediaQuery.textScalerOf(context);
  var maxTextWidth = 0.0;
  for (final entry in entries) {
    final text = _extractText(entry.title);
    if (text == null || text.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    if (painter.width > maxTextWidth) {
      maxTextWidth = painter.width;
    }
  }

  // 兜底：如果没有任何可测量的文本，给一个默认宽度，避免菜单被压得过窄。
  if (maxTextWidth == 0.0 && entries.isNotEmpty) {
    maxTextWidth = 120.0;
  }

  // 24 (leading icon slot) / 18 (placeholder) + 12 (gap) +
  // 24 (item horizontal padding) + 16 (menu padding) + trailing slot。
  // 额外 +8 作为文本测量缓冲，防止因字体渲染差异导致折行。
  final hasLeading = entries.any((e) => e.leading != null);
  // 选中项有图标时勾画在末尾（见 `_MenuPanel`），所以那一栏也得留宽度。
  final needsTrailingSlot = entries.any(
    (e) => e.trailing != null || (e.isSelected && e.leading != null),
  );
  final trailingWidth = needsTrailingSlot ? 28.0 : 0.0;
  final contentWidth =
      maxTextWidth + (hasLeading ? 24 : 18) + 12 + 24 + 16 + trailingWidth + 8;
  return contentWidth.clamp(triggerWidth, 340.0);
}

/// 从 [widget] 里挖出**最长的那条文本**，用来估菜单该多宽。
///
/// 早就只认顶层的 `Text`／`RichText`。标题一旦是「一行标签 + 一行小字提示」
/// 这种 `Column`（见泳道栏头那份菜单 `LaneMenu`），就一条都量不到，
/// [_calculatePopupMenuWidth] 于是退回 120 的兜底值 —— 中文标签直接折行。
///
/// 这里往下走一层常见容器，取最长的一条：菜单宽度只要「最宽的那行放得下」，
/// 短的那行自然会跟着排。
String? _extractText(Widget widget) {
  final texts = <String>[];
  _collectTexts(widget, texts);
  if (texts.isEmpty) return null;
  return texts.reduce((a, b) => a.length >= b.length ? a : b);
}

/// [_extractText] 的递归体。只认「结构容器」，不认具体叶子控件 ——
/// 认多了会把角标、计数器之类的东西也算进来。
void _collectTexts(Widget widget, List<String> out) {
  if (widget is Text) {
    final data = widget.data ?? widget.textSpan?.toPlainText();
    if (data != null && data.isNotEmpty) out.add(data);
    return;
  }
  if (widget is RichText) {
    out.add(widget.text.toPlainText());
    return;
  }
  return null;
}

class _HoverableMenuItem extends StatefulWidget {
  const _HoverableMenuItem({
    required this.isSelected,
    required this.enabled,
    required this.onTap,
    required this.child,
    required this.selectedColor,
    required this.hoverColor,
    required this.borderRadius,
  });

  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget child;
  final Color selectedColor;
  final Color hoverColor;
  final double borderRadius;

  @override
  State<_HoverableMenuItem> createState() => _HoverableMenuItemState();
}

class _HoverableMenuItemState extends State<_HoverableMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.selectedColor
                : _isHovered
                ? widget.hoverColor
                : null,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _MenuPanel<T> extends StatefulWidget {
  const _MenuPanel({
    required this.menuWidth,
    required this.entries,
    required this.onSelected,
    this.indicator = FluentDropdownIndicator.checkmark,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  final double menuWidth;
  final List<_MenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final FluentDropdownIndicator indicator;
  final Color? panelColor;
  final Color? selectedColor;
  final Color? hoverColor;
  final double panelBorderRadius;
  final double itemBorderRadius;

  @override
  State<_MenuPanel<T>> createState() => _MenuPanelState<T>();
}

class _MenuPanelState<T> extends State<_MenuPanel<T>> {
  ScrollController? _scrollController;
  List<double>? _itemHeights;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scrollController != null) {
      return;
    }

    final textStyle =
        Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    final indicatorWidth = widget.indicator == FluentDropdownIndicator.bar
        ? 3.0
        : 18.0;
    // menu padding 16 + item padding 24 + indicator + gap 12 + 4px safety
    // (scrollbar/rounding can make the real text width a couple px narrower)
    final textWidth = (widget.menuWidth - 16 - 24 - indicatorWidth - 12 - 4)
        .clamp(1.0, double.infinity);

    final heights = <double>[];
    var selectedOffset = 0.0;
    var selectedIndex = -1;

    for (var i = 0; i < widget.entries.length; i++) {
      final entry = widget.entries[i];
      final label = _extractText(entry.title) ?? '';
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: textWidth);
      final contentHeight = painter.height > 20 ? painter.height : 20.0;
      if (entry.isSelected && selectedIndex < 0) {
        selectedIndex = i;
        selectedOffset = heights.fold(0.0, (sum, height) => sum + height);
      }
      heights.add(contentHeight + 20);
    }

    _itemHeights = heights;
    _scrollController = ScrollController(
      initialScrollOffset: selectedIndex > 0 ? selectedOffset : 0,
    );
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final panelColor = widget.panelColor ?? colorScheme.surface;
    final selectedColor =
        widget.selectedColor ??
        colorScheme.primaryContainer.withValues(alpha: 0.5);
    final hoverColor =
        widget.hoverColor ??
        colorScheme.primaryContainer.withValues(alpha: 0.35);

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(widget.panelBorderRadius),
      child: Container(
        width: widget.menuWidth,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(widget.panelBorderRadius),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.panelBorderRadius),
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            itemCount: widget.entries.length,
            itemExtentBuilder: (index, dimensions) => _itemHeights![index],
            itemBuilder: (context, index) {
              final entry = widget.entries[index];
              return _HoverableMenuItem(
                isSelected: entry.isSelected,
                enabled: entry.enabled,
                onTap: entry.enabled
                    ? () => widget.onSelected(entry.value)
                    : null,
                selectedColor: selectedColor,
                hoverColor: hoverColor,
                borderRadius: widget.itemBorderRadius,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.leading != null)
                      IconTheme(
                        data: IconTheme.of(context).copyWith(
                          color: entry.enabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        child: entry.leading!,
                      )
                    else if (widget.indicator == FluentDropdownIndicator.bar)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: entry.isSelected
                              ? colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: child,
                          );
                        },
                        child: entry.isSelected
                            ? Icon(
                                Icons.check,
                                key: const ValueKey('check'),
                                size: 18,
                                color: colorScheme.primary,
                              )
                            : const SizedBox(width: 18, key: ValueKey('empty')),
                      ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: entry.enabled
                              ? null
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        child: entry.title,
                      ),
                    ),
                    if (entry.trailing != null) ...[
                      const SizedBox(width: 12),
                      IconTheme(
                        data: IconTheme.of(context).copyWith(
                          color: entry.enabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        child: entry.trailing!,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MenuOverlay<T> extends StatelessWidget {
  const _MenuOverlay({
    required this.layerLink,
    required this.triggerSize,
    required this.menuWidth,
    required this.entries,
    required this.alignRight,
    required this.alignTop,
    required this.onSelected,
    required this.onDismiss,
    required this.scaleAnimation,
    required this.opacityAnimation,
    this.indicator = FluentDropdownIndicator.checkmark,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  final LayerLink layerLink;
  final Size triggerSize;
  final double menuWidth;
  final List<_MenuEntry<T>> entries;
  final bool alignRight;
  final bool alignTop;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;
  final Animation<double> scaleAnimation;
  final Animation<double> opacityAnimation;
  final FluentDropdownIndicator indicator;
  final Color? panelColor;
  final Color? selectedColor;
  final Color? hoverColor;
  final double panelBorderRadius;
  final double itemBorderRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onPanStart: (_) {},
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: alignTop
              ? const Offset(0, -6)
              : Offset(0, triggerSize.height + 6),
          targetAnchor: alignTop
              ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
              : (alignRight ? Alignment.topRight : Alignment.topLeft),
          followerAnchor: alignTop
              ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
              : (alignRight ? Alignment.topRight : Alignment.topLeft),
          child: FadeTransition(
            opacity: opacityAnimation,
            child: ScaleTransition(
              alignment: alignTop
                  ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
                  : (alignRight ? Alignment.topRight : Alignment.topLeft),
              scale: scaleAnimation,
              child: _MenuPanel(
                menuWidth: menuWidth,
                entries: entries,
                onSelected: onSelected,
                indicator: indicator,
                panelColor: panelColor,
                selectedColor: selectedColor,
                hoverColor: hoverColor,
                panelBorderRadius: panelBorderRadius,
                itemBorderRadius: itemBorderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }
  // 单孩子容器：`child` 在这套 widgets 里是可空的（`Flexible` 那支不空，
  // 但统一按可空处理，省得每加一类都要回去查签名）。
  final Widget? child = switch (widget) {
    // `Expanded` 是 `Flexible` 的子类，一条就够；`Center` 是 `Align` 的子类。
    Flexible(:final child) => child,
    Padding(:final child) => child,
    SizedBox(:final child) => child,
    Align(:final child) => child,
    DefaultTextStyle(:final child) => child,
    DecoratedBox(:final child) => child,
    _ => null,
  };
  if (child != null) _collectTexts(child, out);
}

/// Static helper for showing a fluent popup menu at an arbitrary screen
/// rectangle (e.g. the widget that was long-pressed).
class FluentPopupMenu {
  const FluentPopupMenu._();

  static VoidCallback? _disposeCurrent;

  /// Shows a fluent-styled popup menu anchored to [anchor].
  ///
  /// Returns the selected value, or `null` if the menu is dismissed without
  /// a selection.
  static Future<T?> show<T>({
    required BuildContext context,
    required List<FluentPopupMenuItem<T>> items,
    required Rect anchor,
    ValueChanged<T>? onSelected,
  }) async {
    // 先关闭上一个弹出的菜单，保证右键/长按另一个项目时只会显示最新菜单。
    _disposeCurrent?.call();
    _disposeCurrent = null;

    final entries = items
        .map(
          (item) => _MenuEntry<T>(
            value: item.value,
            leading: item.leading,
            title: item.title,
            trailing: item.trailing,
            enabled: item.enabled,
            isSelected: item.selected,
            isDivider: item.isDivider,
          ),
        )
        .toList();

    final completer = Completer<T?>();
    final closedCompleter = Completer<void>();

    final entry = _insertMenu<T>(
      context: context,
      anchor: anchor,
      menuWidth: _calculatePopupMenuWidth(context, anchor.width, entries),
      entries: entries,
      onSelected: (value) {
        if (!completer.isCompleted) completer.complete(value);
        onSelected?.call(value);
      },
      onClosed: () {
        // 只报一次关闭、没有选择 ⇒ 用户点空白把它关掉了。
        if (!completer.isCompleted) completer.complete(null);
        if (!closedCompleter.isCompleted) closedCompleter.complete();
      },
    );

    var removed = false;
    void removeEntry() {
      if (removed) return;
      removed = true;
      if (entry.navigator != null) entry.navigator!.removeRoute(entry);
    }

    late final VoidCallback disposeCurrent;
    disposeCurrent = () {
      if (!completer.isCompleted) completer.complete(null);
      if (!closedCompleter.isCompleted) closedCompleter.complete();
      removeEntry();
    };
    _disposeCurrent = disposeCurrent;

    final result = await completer.future;
    await closedCompleter.future;
    if (_disposeCurrent == disposeCurrent) {
      _disposeCurrent = null;
    }
    removeEntry();
    return result;
  }
}
