import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 只在阅读设置面板启用渐进说明，共用控件在工作台里仍可直接展示说明。
class SettingsPresentationScope extends InheritedWidget {
  const SettingsPresentationScope({
    super.key,
    required this.showDescriptions,
    required this.animate,
    required super.child,
  });

  final bool showDescriptions;
  final bool animate;

  static SettingsPresentationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsPresentationScope>();

  @override
  bool updateShouldNotify(SettingsPresentationScope oldWidget) =>
      showDescriptions != oldWidget.showDescriptions ||
      animate != oldWidget.animate;
}

/// 设置动作与帮助有独立点击目标，展开说明不会改变设置值。
class SettingsDetailTile extends StatefulWidget {
  const SettingsDetailTile({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.stackControlOnNarrow = false,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool stackControlOnNarrow;
  final bool enabled;

  @override
  State<SettingsDetailTile> createState() => _SettingsDetailTileState();
}

class _SettingsDetailTileState extends State<SettingsDetailTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = SettingsPresentationScope.maybeOf(context);
    final hasDescription = widget.description?.isNotEmpty ?? false;
    final expanded =
        hasDescription && (_expanded || (scope?.showDescriptions ?? false));
    final animate =
        (scope?.animate ?? true) && !MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackControl =
                    widget.stackControlOnNarrow &&
                    (constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: widget.enabled
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          if (hasDescription)
                            Semantics(
                              expanded: expanded,
                              child: IconButton(
                                tooltip: '${t.common.help}: ${widget.title}',
                                isSelected: expanded,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  foregroundColor: scheme.onSurfaceVariant,
                                ),
                                icon: const GlyphIcon(AppGlyphs.info, size: 18),
                                selectedIcon: GlyphIcon(
                                  AppGlyphs.info,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _expanded = !_expanded);
                                },
                              ),
                            ),
                          if (!stackControl && widget.trailing != null)
                            widget.trailing!,
                        ],
                      ),
                    ),
                    if (stackControl && widget.trailing != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: widget.trailing!,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: animate ? ExpressiveMotion.spatialDuration : Duration.zero,
          curve: ExpressiveMotion.spatialCurve,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 20, 16),
                  child: Text(
                    widget.description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 次要调节按任务收纳，折叠时仍显示当前状态。
class SettingsFoldout extends StatelessWidget {
  const SettingsFoldout({
    super.key,
    required this.title,
    required this.child,
    this.summary,
    this.icon,
  });

  final String title;
  final String? summary;
  final Glyph? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animate =
        (SettingsPresentationScope.maybeOf(context)?.animate ?? true) &&
        !MediaQuery.disableAnimationsOf(context);
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        leading: icon == null ? null : GlyphIcon(icon!, color: scheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: summary == null
            ? null
            : Text(summary!, style: Theme.of(context).textTheme.bodySmall),
        expansionAnimationStyle: animate
            ? AnimationStyle(
                duration: ExpressiveMotion.spatialDuration,
                curve: ExpressiveMotion.spatialCurve,
              )
            : AnimationStyle.noAnimation,
        children: [child],
      ),
    );
  }
}

/// 同一任务里的多个独立开关以图标卡片组合，整块是一个选择区。
class SettingsToggleOption {
  const SettingsToggleOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final String description;
  final Glyph icon;
  final bool selected;
  final ValueChanged<bool> onChanged;
}

class SettingsToggleGroup extends StatelessWidget {
  const SettingsToggleGroup({super.key, required this.options});
  final List<SettingsToggleOption> options;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionBubbleRegion(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final minWidth = MediaQuery.textScalerOf(context).scale(170);
                final columns = (constraints.maxWidth / minWidth).floor().clamp(
                  1,
                  options.length,
                );
                final width =
                    (constraints.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      SizedBox(
                        width: width,
                        child: ActionBubbleTarget(
                          child: ElasticButton(
                            enabled: !MediaQuery.disableAnimationsOf(context),
                            child: Semantics(
                              toggled: option.selected,
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 86),
                                  padding: const EdgeInsets.all(12),
                                  backgroundColor: option.selected
                                      ? scheme.secondaryContainer
                                      : scheme.surfaceContainerHigh,
                                  foregroundColor: option.selected
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      option.selected ? 24 : 16,
                                    ),
                                  ),
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  option.onChanged(!option.selected);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        GlyphIcon(option.icon),
                                        GlyphIcon(
                                          option.selected
                                              ? AppGlyphs.checkCircle
                                              : AppGlyphs.addCircle,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(option.title),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (SettingsPresentationScope.maybeOf(context)?.showDescriptions ??
                false)
              _descriptions(context)
            else
              SettingsFoldout(
                title: t.common.help,
                icon: AppGlyphs.info,
                child: _descriptions(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _descriptions(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options) ...[
          Text(option.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            option.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
