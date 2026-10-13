import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';

/// 选择的是原有 ThemeMode，预览只展示布局与明暗，不新建主题状态。
class AppearanceThemePicker extends StatelessWidget {
  const AppearanceThemePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.seedColor,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;
  final Color seedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = {
      ThemeMode.system: t.common.followSystem,
      ThemeMode.light: t.common.lightMode,
      ThemeMode.dark: t.common.darkMode,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.settings.theme, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            t.settings.themeSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final columns = constraints.maxWidth >= 420 * scale ? 3 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return ActionBubbleRegion(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final mode in labels.keys)
                      SizedBox(
                        width: width,
                        child: Semantics(
                          selected: value == mode,
                          inMutuallyExclusiveGroup: true,
                          child: ActionBubbleTarget(
                            corner: 20,
                            enabled: !eInkInstantRoutes,
                            child: ElasticPress(
                              enabled:
                                  !eInkInstantRoutes &&
                                  !MediaQuery.disableAnimationsOf(context),
                              child: M3ECard(
                                variant: M3ECardVariant.outlined,
                                trackHover: false,
                                color: value == mode
                                    ? theme.colorScheme.secondaryContainer
                                    : theme.colorScheme.surface,
                                border: BorderSide(
                                  color: value == mode
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                  width: value == mode ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                animationDuration: Duration.zero,
                                semanticLabel: labels[mode],
                                onPressed: () {
                                  if (mode == value) return;
                                  HapticFeedback.lightImpact();
                                  onChanged(mode);
                                },
                                child: columns == 1
                                    ? Row(
                                        children: [
                                          SizedBox(
                                            width: 72,
                                            height: 56,
                                            child: _preview(mode, theme),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              labels[mode]!,
                                              style: theme.textTheme.labelLarge,
                                            ),
                                          ),
                                          if (mode == value)
                                            const GlyphIcon(
                                              AppGlyphs.check,
                                              size: 20,
                                            ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          SizedBox(
                                            height: 76,
                                            child: _preview(mode, theme),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  labels[mode]!,
                                                  style: theme
                                                      .textTheme
                                                      .labelLarge,
                                                ),
                                              ),
                                              if (mode == value)
                                                const GlyphIcon(
                                                  AppGlyphs.check,
                                                  size: 18,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _preview(ThemeMode mode, ThemeData theme) {
    ColorScheme scheme(Brightness brightness) => theme.brightness == brightness
        ? theme.colorScheme
        : ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: mode == ThemeMode.system
            ? Row(
                children: [
                  Expanded(
                    child: _ThemeSketch(scheme: scheme(Brightness.light)),
                  ),
                  Expanded(
                    child: _ThemeSketch(scheme: scheme(Brightness.dark)),
                  ),
                ],
              )
            : _ThemeSketch(
                scheme: scheme(
                  mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
                ),
              ),
      ),
    );
  }
}

class _ThemeSketch extends StatelessWidget {
  const _ThemeSketch({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 8,
            width: 28,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
