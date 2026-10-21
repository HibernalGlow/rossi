import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/source_visibility.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 插件运行状态卡 —— 发现面板的「这批图源现在到底能不能用」。
///
/// 数据只读 [PluginRegistryCubit] 那份运行时状态（与书架/发现页用的是同一份），
/// 不另开一条注册表读取路径。三档计数都是**在册**的数，不是「我以为加载好了」：
/// `lastLoadSuccess` 是宿主真的跑过一次初始化才写的，`lastLoadError` 是它自己报的。
class PluginStatusCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const PluginStatusCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  Widget build(BuildContext context) {
    final states =
        filterRestrictedPlugins(
          context.watch<PluginRegistryCubit>().state.values.where(
            (p) => !p.isDeleted,
          ),
          showRestricted: context
              .watch<GlobalSettingCubit>()
              .state
              .showRestrictedSources,
        ).toList()..sort((a, b) {
          final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
          if (order != 0) return order;
          return _nameOf(a).compareTo(_nameOf(b));
        });

    final enabled = states.where((p) => p.isEnabled).toList();
    final ready = enabled.where((p) => p.lastLoadSuccess).toList();
    final failed = enabled.where((p) => !p.lastLoadSuccess).toList();

    return CollapsibleCard(
      cardId: 'plugin_status',
      title: t.workspace.pluginRunState,
      icon: AppGlyphs.puzzle,
      expressive: true,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: InfoCardCounter(
        t.workspace.readyOfTotal(ready: ready.length, total: enabled.length),
      ),
      child: states.isEmpty
          ? ExpressiveEmptyState(
              icon: AppGlyphs.puzzle,
              text: t.workspace.noPluginsInstalled,
              hint: t.workspace.installOrImportPlugin,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExpressiveTileGrid(
                  minTileWidth: 120,
                  children: [
                    ExpressiveStatTile(
                      value: '${enabled.length}',
                      label: '已启用',
                      icon: AppGlyphs.power,
                      highlight: enabled.isNotEmpty,
                      caption: t.workspace.registeredCount(n: states.length),
                    ),
                    ExpressiveStatTile(
                      value: '${ready.length}',
                      label: t.workspace.gpuReadyState,
                      icon: AppGlyphs.checkCircle,
                      gauge: enabled.isEmpty
                          ? null
                          : ready.length / enabled.length,
                    ),
                    ExpressiveStatTile(
                      value: '${failed.length}',
                      label: '加载失败',
                      icon: AppGlyphs.warning,
                      highlight: failed.isNotEmpty,
                      caption: failed.isEmpty
                          ? t.workspace.allHealthy
                          : t.workspace.seeDetailsBelow,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ExpressiveTileGrid(
                  minTileWidth: 240,
                  children: [
                    for (final plugin in states)
                      // 只读披露：点了没意义（启停要去「图源与扩展」那张卡），
                      // 所以不给 onTap —— 否则一颗看着能按的格子其实只会折叠整张卡。
                      ExpressiveFactTile(
                        label: _nameOf(plugin),
                        valueWidget: _statusPill(plugin),
                        icon: pluginIcon(plugin.uuid),
                        trailing: _versionTag(plugin),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  static String _nameOf(PluginRuntimeState plugin) {
    final info = PluginRegistryService.I.getCachedPluginInfo(plugin.uuid);
    return info?['name']?.toString().trim() ?? plugin.uuid;
  }

  /// 三态：就绪 / 加载中 / 失败（失败时把宿主报的那句原样带出来）。
  Widget _statusPill(PluginRuntimeState plugin) {
    if (!plugin.isEnabled) {
      return ExpressiveStatusPill(
        text: t.workspace.notEnabled,
        tone: ExpressiveTone.neutral,
        compact: true,
      );
    }
    if (plugin.lastLoadSuccess) {
      return ExpressiveStatusPill(
        text: t.workspace.readyState,
        tone: ExpressiveTone.primary,
        compact: true,
      );
    }
    final error = plugin.lastLoadError;
    return ExpressiveStatusPill(
      text: error == null || error.isEmpty
          ? t.workspace.loadingState
          : t.workspace.failedWith(error: error),
      tone: ExpressiveTone.warning,
      compact: true,
    );
  }

  Widget? _versionTag(PluginRuntimeState plugin) {
    if (plugin.version.isEmpty && !plugin.debug) return null;
    return ExpressiveStatusPill(
      text: plugin.debug ? '调试' : 'v${plugin.version}',
      dot: false,
      compact: true,
      tone: plugin.debug ? ExpressiveTone.tertiary : ExpressiveTone.neutral,
    );
  }
}

/// 按 uuid 猜一颗图标（与「图源与扩展」那张卡同一套启发式，抽出来共用）。
Glyph pluginIcon(String uuid) {
  final lower = uuid.toLowerCase();
  if (lower.contains('bika')) return AppGlyphs.sparkle;
  if (lower.contains('jm')) return AppGlyphs.openBook;
  if (lower.contains('local')) return AppGlyphs.folder;
  return AppGlyphs.puzzle;
}
