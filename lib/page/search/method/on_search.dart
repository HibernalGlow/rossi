import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search_aggregate/view/search_aggregate_result_page.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/page/search_result/view/search_result_page.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';

void onSearch(
  BuildContext context,
  String keyword, {
  Map<String, dynamic>? pluginExtern,
  bool aggregateMode = true,
  Map<String, bool>? aggregateSources,
}) async {
  final searchCubit = context.read<SearchCubit>();
  final nextExtern = pluginExtern == null
      ? Map<String, dynamic>.from(searchCubit.state.pluginExtern)
      : Map<String, dynamic>.from(pluginExtern);
  final nextAggregateSources = aggregateSources == null
      ? Map<String, bool>.from(searchCubit.state.aggregateSources)
      : Map<String, bool>.from(aggregateSources);
  searchCubit.update(
    searchCubit.state.copyWith(
      searchKeyword: keyword,
      pluginExtern: nextExtern,
      aggregateSources: nextAggregateSources,
    ),
  );

  final event = SearchEvent().copyWith(searchStates: searchCubit.state);
  // 在发现页的标签体系里：结果页开成**一条新标签**，标题就是关键词 ——
  // 「同时开几个搜索各查一个词」是这里的日常用法，推一整页会把标签条盖掉。
  final tabs = DiscoverTabScope.maybeOf(context);
  final tabLabel = keyword.trim().isEmpty ? t.discover.search : keyword.trim();

  if (aggregateMode) {
    final pluginStates = context.read<PluginRegistryCubit>().state;
    final availableSources = PluginRegistryService.I
        .sortPlugins(
          pluginStates.values.where(
            (plugin) => plugin.isEnabled && !plugin.isDeleted,
          ),
        )
        .map((plugin) => plugin.uuid)
        .toList();
    final selected = nextAggregateSources.isNotEmpty
        ? nextAggregateSources
        : {for (final source in availableSources) source: true};
    if (tabs != null) {
      final page = SearchAggregateResultPage(
        searchEvent: event,
        searchCubit: searchCubit,
        selectedSources: selected,
      );
      tabs.openPage(
        label: tabLabel,
        // 聚合结果跨全部插件，不隶属某一个插件，所以标签不带插件来源。
        source: '',
        icon: Icons.search,
        content: (context) => page.wrappedRoute(context),
      );
      return;
    }
    context.pushRoute(
      SearchAggregateResultRoute(
        searchEvent: event,
        searchCubit: searchCubit,
        selectedSources: selected,
      ),
    );
    return;
  }

  if (tabs != null) {
    final page = SearchResultPage(searchEvent: event, searchCubit: searchCubit);
    tabs.openPage(
      label: tabLabel,
      source: searchCubit.state.from,
      content: (context) => page.wrappedRoute(context),
    );
    return;
  }

  context.pushRoute(
    SearchResultRoute(searchEvent: event, searchCubit: searchCubit),
  );
}
