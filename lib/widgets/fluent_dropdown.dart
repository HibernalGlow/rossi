import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/context/context_extensions.dart';

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

  final GlobalKey<_MenuSurfaceState<T>> _surfaceKey =
      GlobalKey<_MenuSurfaceState<T>>();
  OverlayEntry? _overlayEntry;
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
      _surfaceKey.currentState?.close();
    } else {
      _openMenu();
    }
  }

  /// 在宿主 `dispose()` 里调用：菜单还开着就被摘掉时把 OverlayEntry 收干净。
  void detachMenu() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
  }

  void _openMenu() {
    final entries = buildMenuEntries();
    final renderBox = context.findRenderObject() as RenderBox;
    _overlayEntry = _insertMenu<T>(
      context: context,
      key: _surfaceKey,
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
      icon: widget.icon ?? const Icon(Icons.more_vert),
      tooltip: widget.tooltip,
      visualDensity: widget.visualDensity,
      style: widget.style,
      onPressed: widget.enabled ? toggleMenu : null,
    );
  }
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
  });

  /// Currently selected value.
  final T value;

  /// Text displayed in the trigger button.
  final String displayValue;

  /// Map of selectable values to their display labels.
  final Map<T, String> items;

  /// Called when the user selects a different value.
  final ValueChanged<T>? onChanged;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = context.textColor;

    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return GestureDetector(
      onTap: widget.onChanged == null ? null : toggleMenu,
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
              turns: menuIsOpen ? 0.5 : 0,
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

String? _extractText(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  return null;
}

class _HoverableMenuItem extends StatefulWidget {
  const _HoverableMenuItem({
    required this.isSelected,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_HoverableMenuItem> createState() => _HoverableMenuItemState();
}

class _HoverableMenuItemState extends State<_HoverableMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                : _isHovered
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _MenuPanel<T> extends StatelessWidget {
  const _MenuPanel({
    required this.menuWidth,
    required this.maxHeight,
    required this.entries,
    required this.onSelected,
  });

  final double menuWidth;

  /// 面板能长多高 —— 由 `_MenuSurface` 按「菜单顶部到可绘制区底边」算出来，
  /// 所以长菜单在够高的窗口里不必滚动，放不下才滚。
  final double maxHeight;
  final List<_MenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: menuWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              if (entry.isDivider) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1, thickness: 1),
                );
              }
              final showLeadingCheck =
                  entry.isSelected && entry.leading == null;
              final showTrailingCheck =
                  entry.isSelected && entry.leading != null;
              return _HoverableMenuItem(
                isSelected: entry.isSelected,
                enabled: entry.enabled,
                onTap: entry.enabled && entry.value != null
                    ? () => onSelected(entry.value as T)
                    : null,
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
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: child,
                          );
                        },
                        child: showLeadingCheck
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
                    if (entry.trailing != null || showTrailingCheck) ...[
                      const SizedBox(width: 12),
                      IconTheme(
                        data: IconTheme.of(context).copyWith(
                          color: entry.enabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        child:
                            entry.trailing ??
                            Icon(
                              Icons.check,
                              size: 18,
                              color: colorScheme.primary,
                            ),
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

/// 菜单与锚点之间的缝隙。
const double _kMenuGap = 6;

/// 菜单离可绘制区边缘至少留多少，避免贴死圆角/系统 inset。
const double _kMenuEdgeMargin = 8;

/// 单项高度：`_HoverableMenuItem` 的上下 padding 10+10 与 24 高的图标行。
const double _kMenuItemHeight = 44;

/// `_MenuPanel` 的上下内边距合计（面板里是 `EdgeInsets.all(8)`）。
const double _kMenuPanelPadding = 16;

/// 一条分隔线占的高度：`Divider(height: 1)` 加上下各 4。
const double _kMenuDividerHeight = 9;

/// 菜单的自然高度（内容全展开）。摆位按它算，不按某个固定上限估 ——
/// 15 项的菜单实际要 700 高，按 320 判断会以为「下面放得下」，于是画到屏幕外；
/// 反过来短菜单也不会被撑高。放不下时才由 `_MenuPanel` 的 `maxHeight` 夹住并滚动。
Size _menuNaturalSize(double width, List<_MenuEntry<Object?>> entries) => Size(
  width,
  _kMenuPanelPadding +
      entries.fold<double>(
        0,
        (height, entry) =>
            height + (entry.isDivider ? _kMenuDividerHeight : _kMenuItemHeight),
      ),
);

/// 菜单该被钳进的那个框（全局坐标）：**它实际插入的 Overlay 的绘制范围**，
/// 而不是窗口尺寸。泳道里的局部 Navigator 会把最近的 Overlay 裁在面板内
/// （见 `EmbeddedUpstreamPage`），拿窗口尺寸判断就会「算得下却画不出来」。
Rect _overlayBounds(BuildContext context) {
  final box = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final padding = MediaQuery.paddingOf(context);
  final rect = box == null
      ? Offset.zero & MediaQuery.sizeOf(context)
      : box.localToGlobal(Offset.zero) & box.size;
  return Rect.fromLTRB(
    rect.left + padding.left,
    rect.top + padding.top,
    rect.right - padding.right,
    rect.bottom - padding.bottom,
  );
}

/// 把菜单摆进 [bounds]：默认贴着锚点下沿、左对齐；放不下就朝上翻 / 朝左翻，
/// 最后再用夹取兜底（锚点本身就在边缘外时，翻转也救不了，只能夹回来）。
_MenuPlacement _placeMenu({
  required Rect anchor,
  required Size menuSize,
  required Rect bounds,
}) {
  final minDx = bounds.left + _kMenuEdgeMargin;
  final minDy = bounds.top + _kMenuEdgeMargin;
  final maxDx = math.max(
    minDx,
    bounds.right - _kMenuEdgeMargin - menuSize.width,
  );
  final maxDy = math.max(
    minDy,
    bounds.bottom - _kMenuEdgeMargin - menuSize.height,
  );

  final openUp =
      anchor.bottom + _kMenuGap + menuSize.height >
          bounds.bottom - _kMenuEdgeMargin &&
      anchor.top - _kMenuGap - menuSize.height >= minDy;
  final openLeft =
      anchor.left + menuSize.width > bounds.right - _kMenuEdgeMargin;

  final dy = openUp
      ? anchor.top - _kMenuGap - menuSize.height
      : anchor.bottom + _kMenuGap;
  final dx = openLeft ? anchor.right - menuSize.width : anchor.left;

  return _MenuPlacement(
    offset: Offset(dx.clamp(minDx, maxDx), dy.clamp(minDy, maxDy)),
    // 缩放动画从靠锚点的那个角长出来。
    scaleAlignment: Alignment(openLeft ? 1 : -1, openUp ? 1 : -1),
  );
}

class _MenuPlacement {
  const _MenuPlacement({required this.offset, required this.scaleAlignment});

  final Offset offset;
  final Alignment scaleAlignment;
}

/// 把菜单插进**根** Overlay。
///
/// 必须是根：菜单是一次性 flyout，该浮在整个窗口上；插进「最近的」Overlay 就会被
/// 泳道的裁剪切掉一截（推入的页面和 bottom sheet 收在面板里才是对的，
/// 那个由 `EmbeddedUpstreamPage` 的局部 Navigator 负责）。
OverlayEntry _insertMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required double menuWidth,
  required List<_MenuEntry<T>> entries,
  required ValueChanged<T> onSelected,
  required VoidCallback onClosed,
  GlobalKey<_MenuSurfaceState<T>>? key,
}) {
  final entry = OverlayEntry(
    builder: (_) => _MenuSurface<T>(
      key: key,
      anchor: anchor,
      menuWidth: menuWidth,
      entries: entries,
      onSelected: onSelected,
      onClosed: onClosed,
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

/// 菜单本体：自己持有开合动画，按锚点 + Overlay 范围摆位，点空白处关闭。
class _MenuSurface<T> extends StatefulWidget {
  const _MenuSurface({
    super.key,
    required this.anchor,
    required this.menuWidth,
    required this.entries,
    required this.onSelected,
    required this.onClosed,
  });

  /// 触发点（或右键位置）的全局矩形。
  final Rect anchor;
  final double menuWidth;
  final List<_MenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// 关闭动画播完（或被直接移除）后回调，宿主在这里移除 OverlayEntry。
  final VoidCallback onClosed;

  @override
  State<_MenuSurface<T>> createState() => _MenuSurfaceState<T>();
}

class _MenuSurfaceState<T> extends State<_MenuSurface<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  bool _closing = false;
  bool _closedReported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    // 被宿主直接移除时（例如右键另一个项目顶掉了旧菜单）没有关闭动画，
    // 但宿主的 await 仍然要落地，所以这里也要报一次。
    _reportClosed();
    super.dispose();
  }

  /// 宿主用来关掉菜单的入口（再次点触发按钮时走这里）。
  void close({VoidCallback? afterClosed}) {
    if (_closing) {
      afterClosed?.call();
      return;
    }
    _closing = true;
    _controller
        .reverse()
        .then((_) {
          if (!mounted) return;
          afterClosed?.call();
          _reportClosed();
        })
        .catchError((_) {
          // 动画被打断（控制器已 dispose）：仍然把状态报出去。
          if (!mounted) return;
          afterClosed?.call();
          _reportClosed();
        });
  }

  void _reportClosed() {
    if (_closedReported) return;
    _closedReported = true;
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _overlayBounds(context);
    final placement = _placeMenu(
      anchor: widget.anchor,
      menuSize: _menuNaturalSize(widget.menuWidth, widget.entries),
      bounds: bounds,
    );
    // 面板最多长到「自己的顶边到可绘制区底边」：摆位已经把顶边夹进可视区，
    // 所以这里天然不会画出屏幕，只是放不下时改为滚动。
    final maxHeight = math.max(
      0.0,
      bounds.bottom - _kMenuEdgeMargin - placement.offset.dy,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: close,
      onLongPress: close,
      onSecondaryTapDown: (_) => close(),
      child: Stack(
        children: [
          Positioned(
            left: placement.offset.dx,
            top: placement.offset.dy,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                alignment: placement.scaleAlignment,
                scale: _scaleAnimation,
                child: _MenuPanel(
                  menuWidth: widget.menuWidth,
                  maxHeight: maxHeight,
                  entries: widget.entries,
                  onSelected: (value) =>
                      close(afterClosed: () => widget.onSelected(value)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
      entry.remove();
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
