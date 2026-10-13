import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

part 'path_breadcrumb_surface.dart';

class PathCrumb {
  const PathCrumb({
    required this.id,
    required this.label,
    this.isRoot = false,
    this.isCurrent = false,
  });
  final String id;
  final String label;
  final bool isRoot;
  final bool isCurrent;
}

/// 两种外观共用布局与交互；折叠菜单只转发路径，不维护导航状态。
class PathBreadcrumb extends StatelessWidget {
  const PathBreadcrumb({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.overflowLabel,
    this.style = BreadcrumbStyle.restrained,
    this.enabled = true,
    this.animate = true,
    this.trailing,
    this.itemKey,
    this.viewportKey,
  });

  final List<PathCrumb> entries;
  final ValueChanged<PathCrumb> onSelected;
  final String overflowLabel;
  final BreadcrumbStyle style;
  final bool enabled;
  final bool animate;
  final Widget? trailing;
  final Key Function(PathCrumb)? itemKey;
  final Key? viewportKey;

  bool get _expressive => style == BreadcrumbStyle.expressive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w500,
    );
    final motion = animate && !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      child: ActionBubbleRegion(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerHigh,
            shape: _expressive
                ? const _BreadcrumbWaveBorder()
                : const StadiumBorder(),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: _expressive ? 2 : 0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final available = constraints.maxWidth;
                      final widths = entries.map((entry) {
                        if (entry.isRoot) return 48.0;
                        final painter = TextPainter(
                          text: TextSpan(text: entry.label, style: textStyle),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          maxLines: 1,
                        )..layout();
                        final width = (painter.width + (_expressive ? 44 : 28))
                            .clamp(48.0, 200.0);
                        painter.dispose();
                        return width;
                      }).toList();
                      // 从最深层向前保留，根目录始终可见。省略的祖先在统一弹层中可达。
                      var firstTail = 1;
                      double extent() =>
                          widths.fold(0.0, (a, b) => a + b) +
                          math.max(0, entries.length - 1) * 16;
                      if (entries.length > 2 && extent() > available) {
                        firstTail = entries.length - 1;
                        var used = widths.first + 48 + 32 + widths.last;
                        while (firstTail > 2 &&
                            used + widths[firstTail - 1] + 16 <= available) {
                          firstTail--;
                          used += widths[firstTail] + 16;
                        }
                      }
                      final hidden = entries.length > 2 && firstTail > 1
                          ? entries.sublist(1, firstTail)
                          : const <PathCrumb>[];
                      final visible = [
                        if (entries.isNotEmpty) entries.first,
                        ...entries.skip(firstTail),
                      ];
                      final fixed = visible
                          .take(math.max(0, visible.length - 1))
                          .fold(
                            0.0,
                            (sum, entry) =>
                                sum + widths[entries.indexOf(entry)],
                          );
                      final separators =
                          math.max(0, visible.length - 1) * 16 +
                          (hidden.isNotEmpty ? 64 : 0);
                      final lastWidth = math.max(
                        48.0,
                        available - fixed - separators,
                      );
                      return SingleChildScrollView(
                        key: viewportKey,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < visible.length;
                              index++
                            ) ...[
                              if (index > 0) _separator(scheme),
                              if (index == 1 && hidden.isNotEmpty) ...[
                                CommonPopupBox(
                                  targetBuilder: (open) => _crumbButton(
                                    context,
                                    motion: motion,
                                    width: 48,
                                    tooltip: overflowLabel,
                                    onPressed: enabled ? open : null,
                                    child: const Text(
                                      '…',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                  ),
                                  popupBuilder: (_) => CommonPopupMenu(
                                    items: [
                                      for (final entry in hidden)
                                        CommonPopupMenuItem(
                                          label: entry.label,
                                          onPressed: enabled
                                              ? () => onSelected(entry)
                                              : null,
                                        ),
                                    ],
                                  ),
                                ),
                                _separator(scheme),
                              ],
                              _crumbButton(
                                context,
                                key: itemKey?.call(visible[index]),
                                motion: motion,
                                width: index == visible.length - 1
                                    ? math.min(
                                        widths[entries.indexOf(visible[index])],
                                        lastWidth,
                                      )
                                    : widths[entries.indexOf(visible[index])],
                                tooltip: visible[index].id,
                                current: visible[index].isCurrent,
                                root: visible[index].isRoot,
                                onPressed: enabled
                                    ? () {
                                        HapticFeedback.selectionClick();
                                        onSelected(visible[index]);
                                      }
                                    : null,
                                child: visible[index].isRoot
                                    ? const GlyphIcon(AppGlyphs.home, size: 22)
                                    : Text(
                                        visible[index].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle.copyWith(
                                          color: !enabled
                                              ? scheme.onSurface.withValues(
                                                  alpha: .38,
                                                )
                                              : visible[index].isCurrent
                                              ? (_expressive
                                                    ? scheme.onPrimaryContainer
                                                    : scheme.primary)
                                              : scheme.onSurfaceVariant,
                                          fontWeight: visible[index].isCurrent
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (trailing != null)
                  ActionBubbleTarget(
                    corner: 24,
                    enabled: animate && enabled,
                    child: ElasticPress(
                      enabled: motion && enabled,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_expressive)
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: M3EShapeContainer(
                                  kind: M3EShapeKind.cookie4Sided,
                                  color: scheme.secondaryContainer,
                                ),
                              ),
                            trailing!,
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

  Widget _separator(ColorScheme scheme) => SizedBox(
    width: 16,
    child: ExcludeSemantics(
      child: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 14,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _crumbButton(
    BuildContext context, {
    Key? key,
    required bool motion,
    required double width,
    required String tooltip,
    required Widget child,
    VoidCallback? onPressed,
    bool current = false,
    bool root = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _expressive && (current || root);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        selected: current,
        child: ActionBubbleTarget(
          corner: 24,
          enabled: animate && onPressed != null,
          child: ElasticPress(
            enabled: motion && onPressed != null,
            child: SizedBox(
              key: key,
              width: width,
              height: 48,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (accent)
                    Padding(
                      padding: root
                          ? const EdgeInsets.all(6)
                          : const EdgeInsets.symmetric(vertical: 4),
                      child: M3EShapeContainer(
                        kind: current
                            ? M3EShapeKind.pill
                            : M3EShapeKind.cookie4Sided,
                        color: current
                            ? scheme.primaryContainer
                            : scheme.secondaryContainer,
                      ),
                    ),
                  TextButton(
                    style:
                        TextButton.styleFrom(
                              foregroundColor: accent
                                  ? (current
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSecondaryContainer)
                                  : (current
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant),
                              padding: EdgeInsets.symmetric(
                                horizontal: root ? 10 : (_expressive ? 18 : 12),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: const StadiumBorder(),
                            )
                            .merge(ElasticPress.buttonStyle)
                            .copyWith(
                              overlayColor: const WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
                            ),
                    onPressed: onPressed,
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
