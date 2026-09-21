import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/service/discover_router.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/view/plugin_order_dialog.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/page/discover/widgets/plugin_card.dart';
import 'package:zephyr/page/plugin_settings/view/plugin_settings_page.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/view/search_page.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DiscoverCubit()..load(),
      child: const _DiscoverTabsHost(),
    );
  }
}

/// 持有那一组标签的生命周期。
///
/// `PlatController` 是个 `ChangeNotifier`，但它**不是** InheritedWidget 那一类
/// 可以随树重建而重算的东西：标签开在哪、哪条是当前，是活的会话状态，
/// 所以这里用 StatefulWidget 建一次、拆一次。
class _DiscoverTabsHost extends StatefulWidget {
  const _DiscoverTabsHost();

  @override
  State<_DiscoverTabsHost> createState() => _DiscoverTabsHostState();
}

class _DiscoverTabsHostState extends State<_DiscoverTabsHost> {
  late final DiscoverTabs _tabs = DiscoverTabs(
    side: context.read<GlobalSettingCubit>().state.discoverSetting.tabSide,
    home: DiscoverLeafSpec(
      label: t.discover.title,
      source: '',
      pluginName: '',
      iconUrl: '',
      icon: Icons.explore,
      content: (context) => _PluginHome(tabs: _tabs),
    ),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.discoverSetting;

    return ListenableBuilder(
      listenable: _tabs.controller,
      builder: (context, _) => Scaffold(
        // 顶栏那一行交给标签条了（用户口径：另起一行会割裂），所以这里
        // 没有 AppBar；状态栏的内边距由 SafeArea 收在标签条上面。
        // 竖向档在窄页面上会被 DiscoverPlatView 自己钳回横向 —— 那层才知道
        // 轨厚吃掉的是谁的宽度。
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: DiscoverPlatView(
            tabs: _tabs,
            setting: setting,
            onSearch: () => _openAggregateSearch(context),
            onCustomizeOrder: () => showPluginOrderDialog(context),
          ),
        ),
        floatingActionButtonLocation:
            context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
            ? FloatingActionButtonLocation.startFloat
            : FloatingActionButtonLocation.endFloat,
        floatingActionButton: _tabs.onHome
            ? FloatingActionButton(
                tooltip: t.discover.search,
                onPressed: () => _openAggregateSearch(context),
                child: const Icon(Icons.search),
              )
            : null,
      ),
    );
  }

  /// 跨全部插件的聚合搜索。它不隶属某一个插件，所以标签不带插件来源，
  /// 图标走 [DiscoverLeafSpec.icon]。
  void _openAggregateSearch(BuildContext context) {
    final source = context.read<DiscoverCubit>().currentFrom;
    if (source.isEmpty) {
      showErrorToast(t.discover.noPluginForSearch);
      return;
    }
    final searchState = SearchStates.initial().copyWith(from: source);
    _tabs.open(
      label: t.discover.search,
      source: '',
      icon: Icons.search,
      content: (context) =>
          SearchPage(searchState: searchState, aggregateMode: true),
    );
  }
}

/// 首页标签的内容：插件商店入口 + 每张插件卡。
///
/// 单独一个 widget 是为了拿到一个挂在两个 cubit 之下的 element context ——
/// 标签的 `content` 构建器由标签宿主调用，把那个 context 存进 widget 字段里
/// 是另一种味道，不如让子节点用自己的。
class _PluginHome extends StatelessWidget {
  const _PluginHome({required this.tabs});

  final DiscoverTabs tabs;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<DiscoverCubit>().reload(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: _buildPluginHome(context),
        ),
      ),
    );
  }

  Widget _buildPluginHome(BuildContext context) {
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      builder: (context, state) {
        final plugins = state.plugins.values.toList();

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            const SizedBox(height: 16),
            _buildPluginStoreButton(context),
            const SizedBox(height: 8),
            _buildSectionHeader(context, t.discover.pluginManagement),
            if (plugins.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    t.discover.noPlugins,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              for (final plugin in plugins) ...[
                _buildPluginCard(context, plugin, state),
              ],
          ],
        );
      },
    );
  }

  Widget _buildPluginCard(
    BuildContext context,
    PluginRuntimeState plugin,
    DiscoverState state,
  ) {
    final cubit = context.read<DiscoverCubit>();
    final tabs = this.tabs;
    final infoState =
        state.infoStates[plugin.uuid] ??
        const DiscoverPluginInfoState(loading: true);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: PluginCard(
        pluginUuid: plugin.uuid,
        pluginState: plugin,
        infoState: infoState,
        isToggling: state.togglingUuids.contains(plugin.uuid),
        onSearch: () => _openPluginSearch(context, tabs, plugin.uuid),
        onSettings: (title) => _openPluginSettings(tabs, plugin.uuid, title),
        onToggleEnabled: (enabled) => cubit.toggleEnabled(plugin.uuid, enabled),
        onRetry: () => cubit.retryLoadInfo(plugin.uuid),
        onAction: (action) => DiscoverRouter.route(
          context,
          action: DiscoverRouter.attachSource(action, plugin.uuid),
          currentFrom: cubit.currentFrom,
          tabs: tabs,
        ),
      ),
    );
  }

  void _openPluginSearch(BuildContext context, DiscoverTabs tabs, String from) {
    final source = from.trim();
    if (source.isEmpty) {
      showErrorToast(t.error.missingPluginSource(action: t.discover.search));
      return;
    }
    final searchState = SearchStates.initial().copyWith(from: source);
    tabs.open(
      label: t.discover.search,
      source: source,
      content: (context) =>
          SearchPage(searchState: searchState, aggregateMode: false),
    );
  }

  void _openPluginSettings(DiscoverTabs tabs, String uuid, String title) {
    tabs.open(
      label: t.discover.settings,
      source: uuid,
      content: (context) => PluginSettingsPage(
        from: uuid,
        pluginUuid: uuid,
        pluginRuntimeName: uuid,
        pluginDisplayName: title,
      ),
    );
  }

  Widget _buildPluginStoreButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.pushRoute(const PluginStoreRoute()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 22,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.discover.pluginStore,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              t.discover.browseInstall,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
