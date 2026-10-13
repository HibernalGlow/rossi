part of '../fluent_dropdown.dart';

class _HoverableMenuItem extends StatelessWidget {
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
  Widget build(BuildContext context) => ActionBubbleTarget(
    enabled: enabled && !eInkInstantRoutes,
    corner: 10,
    child: ElasticPress(
      enabled:
          enabled &&
          !eInkInstantRoutes &&
          !MediaQuery.disableAnimationsOf(context),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: isSelected,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .5)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
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
          child: ActionBubbleRegion(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.isDivider) {
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Divider(height: 1, thickness: 1),
                    ),
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
                              ? GlyphIcon(
                                  AppGlyphs.check,
                                  key: const ValueKey('check'),
                                  size: 18,
                                  color: colorScheme.primary,
                                )
                              : const SizedBox(
                                  width: 18,
                                  key: ValueKey('empty'),
                                ),
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
                              GlyphIcon(
                                AppGlyphs.check,
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

/// 下拉菜单仍浮在根导航层，出场由统一 CommonPopupRoute 管理。
CommonPopupRoute<T> _insertMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required double menuWidth,
  required List<_MenuEntry<T>> entries,
  required ValueChanged<T> onSelected,
  required VoidCallback onClosed,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final box = navigator.context.findRenderObject() as RenderBox;
  final localAnchor = box.globalToLocal(anchor.topLeft) & anchor.size;
  final route = CommonPopupRoute<T>(
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    modal: false,
    anchorOf: () => localAnchor,
    placement: PopupPlacement.belowPoint,
    anchorShift: const Offset(0, _kMenuGap),
    builder: (routeContext) {
      final bounds = _overlayBounds(routeContext);
      final placement = _placeMenu(
        anchor: localAnchor,
        menuSize: _menuNaturalSize(menuWidth, entries),
        bounds: bounds,
      );
      return InheritedTheme.captureAll(
        context,
        _MenuPanel<T>(
          menuWidth: menuWidth,
          maxHeight: math.max(
            0,
            bounds.bottom - _kMenuEdgeMargin - placement.offset.dy,
          ),
          entries: entries,
          onSelected: (value) => navigator.pop(value),
        ),
      );
    },
  );
  navigator.push(route);
  route.completed.then((value) {
    if (value != null) onSelected(value);
    onClosed();
  });
  return route;
}
