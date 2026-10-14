import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/widgets/plugin_function_chips.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/plugin_icon.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

class PluginCard extends StatelessWidget {
  const PluginCard({
    super.key,
    required this.pluginUuid,
    required this.pluginState,
    required this.infoState,
    required this.isToggling,
    required this.onSearch,
    required this.onSettings,
    required this.onToggleEnabled,
    required this.onRetry,
    required this.onAction,
  });

  final String pluginUuid;
  final PluginRuntimeState pluginState;
  final DiscoverPluginInfoState infoState;
  final bool isToggling;
  final VoidCallback onSearch;
  final void Function(String title) onSettings;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onRetry;
  final Future<void> Function(Map<String, dynamic> action) onAction;

  @override
  Widget build(BuildContext context) {
    if (infoState.loading) {
      return _buildLoading(context);
    }
    if (infoState.error != null || infoState.data == null) {
      return _buildError(context, infoState.error);
    }
    return _buildLoaded(context, infoState.data!);
  }

  Widget _buildLoading(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          M3EShapeContainer(
            kind: M3EShapeKind.cookie6Sided,
            width: 48,
            height: 48,
            color: scheme.secondaryContainer,
            child: Center(
              child: GlyphIcon(
                AppGlyphs.hourglass,
                size: 22,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ExpressiveStatusPill(
                text: t.common.loading,
                tone: ExpressiveTone.secondary,
                icon: AppGlyphs.hourglass,
                dot: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String? error) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          M3EShapeContainer(
            kind: M3EShapeKind.cookie4Sided,
            width: 48,
            height: 48,
            color: scheme.errorContainer,
            child: Center(
              child: GlyphIcon(
                AppGlyphs.error,
                size: 22,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              t.discover.pluginInfoLoadFailed(error: error ?? ''),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElasticButton(
            enabled: animate,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: () {
                HapticFeedback.lightImpact();
                onRetry();
              },
              child: Text(t.common.retry),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, Map<String, dynamic> info) {
    final isEnabled = pluginState.isEnabled;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);

    final rawFunctions = asJsonList(
      info['functions'] ?? info['function'] ?? const <dynamic>[],
    ).map((item) => asJsonMap(item)).toList();
    final pluginName = info['name']?.toString().trim() ?? '';
    final title = pluginName.isNotEmpty
        ? pluginName
        : t.discover.pluginCapability;

    // 生成图标上的那截字只认真名字：拿不到名字时宁可是一个「?」，
    // 也不要「插件能力」缩写成的「插件」——那枚图标会在每张卡上长得一样。
    final displayName = pluginName;
    final iconUrl = info['iconUrl']?.toString().trim() ?? '';
    final iconWidget = ClipRSuperellipse(
      borderRadius: BorderRadius.circular(15),
      child: PluginIcon(
        url: iconUrl,
        // 没有 iconUrl（或还没取到）时按插件名生成一枚：不少图源压根没有图标，
        // 一排拼图占位图等于没有信息，而这里要靠图标区分插件。
        placeholder: GeneratedPluginIcon(seed: pluginUuid, name: displayName),
      ),
    );

    return AnimatedOpacity(
      duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
      opacity: isEnabled ? 1.0 : 0.68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              children: [
                SizedBox(width: 48, height: 48, child: iconWidget),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(height: 4),
                        ExpressiveStatusPill(
                          text: t.discover.disabled,
                          tone: ExpressiveTone.neutral,
                          compact: true,
                          dot: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildTonalIconButton(
                  context,
                  tooltip: t.common.search,
                  glyph: AppGlyphs.search,
                  enabled: isEnabled,
                  animate: animate,
                  onPressed: isEnabled
                      ? () {
                          HapticFeedback.lightImpact();
                          onSearch();
                        }
                      : null,
                ),
                const SizedBox(width: 6),
                _buildTonalIconButton(
                  context,
                  tooltip: t.discover.settings,
                  glyph: AppGlyphs.settings,
                  enabled: true,
                  animate: animate,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onSettings(title);
                  },
                ),
                const SizedBox(width: 8),
                isToggling
                    ? SizedBox(
                        width: 52,
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    : M3ESwitch(
                        selectedIcon: const Icon(Icons.check, size: 16),
                        value: isEnabled,
                        onChanged: (value) {
                          HapticFeedback.lightImpact();
                          onToggleEnabled(value);
                        },
                      ),
              ],
            ),
          ),
          if (rawFunctions.isNotEmpty && isEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PluginFunctionChips(
                functions: rawFunctions,
                onAction: onAction,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTonalIconButton(
    BuildContext context, {
    required String tooltip,
    required Glyph glyph,
    required bool enabled,
    required bool animate,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ElasticButton(
      enabled: animate && enabled,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(38),
          minimumSize: const Size.square(38),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: enabled
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          foregroundColor: enabled
              ? scheme.onSurfaceVariant
              : scheme.onSurfaceVariant.withValues(alpha: 0.38),
          shape: const StadiumBorder(),
        ),
        icon: GlyphIcon(glyph, size: 18),
      ),
    );
  }
}
