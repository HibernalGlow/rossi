import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_tab_cubit.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

/// 发现页的**标签条**。
///
/// 摆位：顶栏那一行的**标题位**（用户 2026-09-20 的口径 —— 单独占一行会和
/// 「发现」标题栏割裂）。所以首页那一条标签就是原来那个「发现」标题，
/// 不再另起一行字。
///
/// 只在真的有多条标签时画（只剩首页那一条时它没有可切的东西，
/// 那时标题位让回「发现」两个字）。
class DiscoverTabStrip extends StatelessWidget {
  const DiscoverTabStrip({super.key, required this.state});

  final DiscoverTabState state;

  static const double _iconSize = 16;

  /// 一条标签最多占多宽。超出的字走省略号，全名在 tooltip 里。
  static const double _tabMaxWidth = 180;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DiscoverTabCubit>();

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in state.tabs)
                  _TabItem(
                    key: ValueKey(tab.id),
                    tab: tab,
                    active: tab.id == state.activeId,
                    onTap: () => cubit.activate(tab.id),
                    onClose: tab.closable ? () => cubit.closeTab(tab.id) : null,
                  ),
              ],
            ),
          ),
        ),
        const _DisplayOptionsButton(),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final DiscoverTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _revealLater();
  }

  @override
  void didUpdateWidget(_TabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _revealLater();
  }

  /// 切到哪条就把哪条滚进视野。
  ///
  /// 排到帧尾：`ensureVisible` 要读 `RenderObject`，而这一帧的子节点还没布局完。
  void _revealLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final setting = context.watch<GlobalSettingCubit>().state.discoverSetting;
    final tab = widget.tab;

    final short = setting.tabPluginShortEnabled
        ? pluginShortName(tab.pluginName)
        : '';
    final label = joinTabLabel(shortName: short, label: tab.label);
    // tooltip 用**全名**：标签上截的是缩写，窄泳道里那截字到底属于哪个插件，
    // 得有个地方能看全。
    final fullLabel = joinTabLabel(shortName: tab.pluginName, label: tab.label);
    final foreground = widget.active
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Tooltip(
        message: fullLabel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DiscoverTabStrip._tabMaxWidth,
          ),
          child: Material(
            color: widget.active
                ? scheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (setting.tabIconEnabled) ...[
                      _leading(scheme),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.onClose != null) ...[
                      const SizedBox(width: 4),
                      _closeButton(scheme),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(ColorScheme scheme) {
    final tab = widget.tab;
    if (tab.source.isEmpty) {
      // 没有插件来源的那几条（首页、聚合搜索）用各自指定的一颗。
      return Icon(
        tab.icon ?? Icons.explore,
        size: DiscoverTabStrip._iconSize,
        color: scheme.primary,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: DiscoverTabStrip._iconSize,
        height: DiscoverTabStrip._iconSize,
        child: PluginIcon(
          url: tab.iconUrl,
          placeholder: GeneratedPluginIcon(
            seed: tab.source,
            name: tab.pluginName,
          ),
        ),
      ),
    );
  }

  Widget _closeButton(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: widget.onClose,
      child: Tooltip(
        message: t.discover.closeTab,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close, size: 13, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 「标签上显示什么」的两颗开关。
///
/// 为什么不搬去设置页：这两颗改的是**眼前这一条**标签条的长相，就地调、就地看到，
/// 和「自定义插件顺序」摆在发现页顶栏是同一个道理。值本身仍写进全局设置，
/// 所以它跨重启留着（见 `DiscoverSettingState`）。
class _DisplayOptionsButton extends StatelessWidget {
  const _DisplayOptionsButton();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GlobalSettingCubit>();
    final setting = context.watch<GlobalSettingCubit>().state.discoverSetting;

    return PopupMenuButton<_TabDisplayOption>(
      tooltip: t.discover.tabDisplay,
      icon: const Icon(Icons.tune_rounded, size: 16),
      onSelected: (option) => cubit.updateDiscoverSetting(
        (current) => switch (option) {
          _TabDisplayOption.icon => current.copyWith(
            tabIconEnabled: !current.tabIconEnabled,
          ),
          _TabDisplayOption.pluginShort => current.copyWith(
            tabPluginShortEnabled: !current.tabPluginShortEnabled,
          ),
        },
      ),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _TabDisplayOption.icon,
          checked: setting.tabIconEnabled,
          child: Text(t.discover.tabShowIcon),
        ),
        CheckedPopupMenuItem(
          value: _TabDisplayOption.pluginShort,
          checked: setting.tabPluginShortEnabled,
          child: Text(t.discover.tabShowPluginShort),
        ),
      ],
    );
  }
}

enum _TabDisplayOption { icon, pluginShort }
