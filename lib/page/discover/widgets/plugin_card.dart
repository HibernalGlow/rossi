import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/widgets/plugin_function_chips.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/plugin_icon.dart';
import 'package:zephyr/icons/icons.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 16),
          Text(t.common.loading),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String? error) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: GlyphIcon(
                AppGlyphs.error,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              t.discover.pluginInfoLoadFailed(error: error ?? ''),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(t.common.retry)),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, Map<String, dynamic> info) {
    final isEnabled = pluginState.isEnabled;
    final colorScheme = Theme.of(context).colorScheme;

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
    final iconWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PluginIcon(
        url: iconUrl,
        // 没有 iconUrl（或还没取到）时按插件名生成一枚：不少图源压根没有图标，
        // 一排拼图占位图等于没有信息，而这里要靠图标区分插件。
        placeholder: GeneratedPluginIcon(seed: pluginUuid, name: displayName),
      ),
    );

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            isThreeLine: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 6,
            ),
            leading: SizedBox(width: 48, height: 48, child: iconWidget),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: isEnabled
                ? null
                : Text(
                    t.discover.disabled,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: t.common.search,
                  icon: const GlyphIcon(AppGlyphs.search, size: 20),
                  onPressed: isEnabled ? onSearch : null,
                ),
                IconButton(
                  tooltip: t.discover.settings,
                  icon: const GlyphIcon(AppGlyphs.settings, size: 20),
                  onPressed: () => onSettings(title),
                ),
                isToggling
                    ? const SizedBox(
                        width: 48,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Switch(
                        value: isEnabled,
                        thumbIcon: kSettingSwitchThumbIcon,
                        onChanged: onToggleEnabled,
                      ),
              ],
            ),
          ),
          if (rawFunctions.isNotEmpty && isEnabled)
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                top: 2,
                right: 20,
                bottom: 12,
              ),
              child: PluginFunctionChips(
                functions: rawFunctions,
                onAction: onAction,
              ),
            ),
        ],
      ),
    );
  }
}
