import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
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
import 'package:zephyr/plugin/source_visibility.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

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
      icon: AppGlyphs.compass,
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
    final (setting, leftHand) = context.select(
      (GlobalSettingCubit cubit) =>
          (cubit.state.discoverSetting, cubit.state.leftHandModeEnabled),
    );

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
          child: Stack(
            children: [
              Positioned.fill(
                child: DiscoverPlatView(
                  tabs: _tabs,
                  setting: setting,
                  onSearch: () => _openAggregateSearch(context),
                  onCustomizeOrder: () => showPluginOrderDialog(context),
                ),
              ),
              if (_tabs.onHome)
                Positioned(
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  left: leftHand ? 16 : null,
                  right: leftHand ? null : 16,
                  child: ExpressiveIconButton(
                    key: const ValueKey('discover-aggregate-search-fab'),
                    glyph: AppGlyphs.search,
                    tooltip: t.discover.search,
                    size: 56,
                    shape: ExpressiveButtonShape.cookie4Sided,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _openAggregateSearch(context);
                    },
                  ),
                ),
            ],
          ),
        ),
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
      icon: AppGlyphs.search,
      content: (context) =>
          SearchPage(searchState: searchState, aggregateMode: true),
    );
  }
}

/// 首页标签的内容：MD3 Expressive 插件商店入口横幅 + 分段式插件管理列表。
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
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      builder: (context, state) {
        // 内置源与云端来源走同一套过滤：开关关闭时，受限来源不出现在来源列表里。
        final showRestricted = context.select(
          (GlobalSettingCubit cubit) => cubit.state.showRestrictedSources,
        );
        final plugins = filterRestrictedPlugins(
          state.plugins.values,
          showRestricted: showRestricted,
        ).toList();
        final enabledCount = plugins.where((p) => p.isEnabled).length;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _buildPluginStoreBanner(context),
            const SizedBox(height: 20),
            _buildSectionHeader(
              context,
              title: t.discover.pluginManagement,
              enabledCount: enabledCount,
              totalCount: plugins.length,
            ),
            if (plugins.isEmpty)
              ExpressiveTile(
                tone: ExpressiveTone.sunken,
                radius: expressiveCornerLg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ExpressiveEmptyState(
                  icon: AppGlyphs.puzzle,
                  text: t.discover.noPlugins,
                  hint: t.discover.browseInstall,
                ),
              )
            else
              M3EList(
                key: const ValueKey('discover-plugin-list'),
                itemCount: plugins.length,
                outerRadius: 24,
                innerRadius: 6,
                gap: 4,
                padding: EdgeInsets.zero,
                color: scheme.surfaceContainerLow,
                colorBuilder: (index) => plugins[index].isEnabled
                    ? scheme.surfaceContainerLow
                    : scheme.surfaceContainerLowest,
                itemBuilder: (context, index) =>
                    _buildPluginCard(context, plugins[index], state),
              ),
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

    return PluginCard(
      key: ValueKey('discover-plugin-card:${plugin.uuid}'),
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

  Widget _buildPluginStoreBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);

    return ActionBubbleRegion(
      child: ActionBubbleTarget(
        enabled: !eInkInstantRoutes,
        corner: 28,
        child: ElasticPress(
          enabled: animate,
          child: Material(
            key: const ValueKey('discover-plugin-store-banner'),
            color: scheme.primaryContainer,
            borderRadius: expressiveCornerLg,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: expressiveCornerLg,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              onTap: () {
                HapticFeedback.lightImpact();
                context.pushRoute(const PluginStoreRoute());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    M3EShapeContainer(
                      kind: M3EShapeKind.cookie4Sided,
                      width: 48,
                      height: 48,
                      color: scheme.primary,
                      child: Center(
                        child: GlyphIcon(
                          AppGlyphs.storefront,
                          size: 24,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.discover.pluginStore,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.discover.browseInstall,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer.withValues(
                                alpha: 0.84,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: ShapeDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        shape: const StadiumBorder(),
                      ),
                      child: Center(
                        child: GlyphIcon(
                          AppGlyphs.chevronForward,
                          size: 20,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int enabledCount,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          GlyphIcon(AppGlyphs.puzzle, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (totalCount > 0)
            ExpressiveStatusPill(
              text: '$enabledCount / $totalCount',
              tone: ExpressiveTone.secondary,
              compact: true,
              dot: true,
            ),
        ],
      ),
    );
  }
}
