import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/cubit/discover_tab_cubit.dart';
import 'package:zephyr/page/discover/service/discover_router.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/discover/view/plugin_order_dialog.dart';
import 'package:zephyr/page/discover/widgets/discover_tab_strip.dart';
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
      child: const _DiscoverTabs(),
    );
  }
}

/// 发现页的标签体系：首页那一条是插件列表，其余每条装一个上游原版页面。
class _DiscoverTabs extends StatelessWidget {
  const _DiscoverTabs();

  static const String _homeId = 'discover-home';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DiscoverTabCubit(
        homeTab: DiscoverTab(
          id: _homeId,
          label: t.discover.title,
          source: '',
          pluginName: '',
          iconUrl: '',
          closable: false,
          icon: Icons.explore,
          content: (context) => const _PluginHome(),
        ),
      ),
      child: const _DiscoverScaffold(),
    );
  }
}

class _DiscoverScaffold extends StatelessWidget {
  const _DiscoverScaffold();

  @override
  Widget build(BuildContext context) {
    final tabs = context.read<DiscoverTabCubit>();
    final state = context.watch<DiscoverTabCubit>().state;
    final onHome = state.activeId == state.tabs.first.id;

    return Scaffold(
      appBar: _topBar(context, tabs, state),
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: state.activeIndex,
        children: [
          for (final tab in state.tabs)
            KeyedSubtree(
              key: ValueKey(tab.id),
              child: DiscoverTabScope(
                actions: _TabActions(tabs: tabs, tabId: tab.id),
                child: tab.content(context),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: onHome
          ? FloatingActionButton(
              tooltip: t.discover.search,
              onPressed: () => _search(context, tabs),
              child: const Icon(Icons.search),
            )
          : null,
    );
  }

  /// 顶栏那一行**就是**标签条：首页那条标签顶掉了原来的「发现」标题，
  /// 不再另起一行（两行会割裂，用户 2026-09-20 的口径）。
  ///
  /// 只有一条标签时标题位让回「发现」两个字 —— 那时没有可切的东西。
  /// 非首页时这一行仍然在：它是切回去与关标签的唯一出口；
  /// 标签内容自己的 AppBar 落在它下面一行（浏览器：标签栏 + 页面工具栏）。
  AppBar _topBar(
    BuildContext context,
    DiscoverTabCubit tabs,
    DiscoverTabState state,
  ) {
    final onHome = state.activeId == state.tabs.first.id;
    return AppBar(
      // 标签条自己带左右留白，只留一窄条，比 AppBar 默认的 16 紧一点。
      titleSpacing: state.showsStrip ? 8 : null,
      title: state.showsStrip
          ? DiscoverTabStrip(state: state)
          : Text(t.discover.title),
      actions: [
        // 「自定义插件顺序」改的是首页那张列表，只在首页摆出来。
        if (onHome)
          IconButton(
            tooltip: t.discover.customOrder,
            icon: const Icon(Icons.reorder),
            onPressed: () => showPluginOrderDialog(context),
          ),
        IconButton(
          tooltip: t.discover.search,
          icon: const Icon(Icons.search),
          onPressed: () => _search(context, tabs),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// 顶栏与悬浮按钮上那颗「搜索」：跨全部插件的聚合搜索，不隶属某一个插件，
  /// 所以标签不带插件来源（图标走 [DiscoverTab.icon]）。
  void _search(BuildContext context, DiscoverTabCubit tabs) {
    final source = context.read<DiscoverCubit>().currentFrom;
    if (source.isEmpty) {
      showErrorToast(t.discover.noPluginForSearch);
      return;
    }
    final searchState = SearchStates.initial().copyWith(from: source);
    tabs.open(
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
/// 标签的 `content` 构建器由 [_DiscoverScaffold] 的 context 调用，
/// 把那个 context 存进 widget 字段里是另一种味道，不如让子节点用自己的。
class _PluginHome extends StatelessWidget {
  const _PluginHome();

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
    final tabs = context.read<DiscoverTabCubit>();
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

  void _openPluginSearch(
    BuildContext context,
    DiscoverTabCubit tabs,
    String from,
  ) {
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

  void _openPluginSettings(DiscoverTabCubit tabs, String uuid, String title) {
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

/// 递给标签内容的那份把手（见 [DiscoverTabScope]）。
class _TabActions implements DiscoverTabActions {
  const _TabActions({required this.tabs, required this.tabId});

  final DiscoverTabCubit tabs;
  final String tabId;

  @override
  void openComicInfo({
    required String comicId,
    required String from,
    required String title,
    String? collectionTargetId,
    String? collectionTargetName,
  }) {
    DiscoverRouter.openComicInfoTab(
      tabs,
      comicId: comicId,
      from: from,
      title: title,
      collectionTargetId: collectionTargetId,
      collectionTargetName: collectionTargetName,
    );
  }

  @override
  void openPage({
    required String label,
    required String source,
    required WidgetBuilder content,
    IconData? icon,
  }) {
    tabs.open(label: label, source: source, content: content, icon: icon);
  }

  @override
  void closeCurrentTab() => tabs.closeTab(tabId);

  @override
  void goHome() => tabs.activateHome();
}
