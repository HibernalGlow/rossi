import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/source_visibility.dart';
import 'package:zephyr/plugin/source_visibility_policy.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/page/search/widget/source_select_dialog.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_mapper.dart';
import 'package:zephyr/widgets/section_header.dart';

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search_aggregate/cubit/search_aggregate_cubit.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/search/model/plugin_search_history_store.dart';

@RoutePage()
class SearchAggregateResultPage extends StatelessWidget
    implements AutoRouteWrapper {
  const SearchAggregateResultPage({
    super.key,
    required this.searchEvent,
    this.searchCubit,
    this.selectedSources = const <String, bool>{},
  });

  final SearchEvent searchEvent;
  final SearchCubit? searchCubit;
  final Map<String, bool> selectedSources;

  @override
  Widget wrappedRoute(BuildContext context) {
    final registry = context.read<PluginRegistryCubit>().state;
    final showRestricted = context
        .read<GlobalSettingCubit>()
        .state
        .showRestrictedSources;
    final visiblePlugins = PluginRegistryService.I.sortPlugins(
      filterRestrictedPlugins(
        registry.plugins.values.where((state) => !state.isDeleted),
        showRestricted: showRestricted,
      ),
    );
    final initial = selectedSources.isNotEmpty
        ? {
            for (final entry in selectedSources.entries)
              if (showRestricted ||
                  !SourceVisibilityPolicy.isRestricted(uuid: entry.key))
                entry.key: entry.value,
          }
        : {for (final plugin in visiblePlugins) plugin.uuid: plugin.isEnabled};
    return MultiBlocProvider(
      providers: [
        searchCubit != null
            ? BlocProvider.value(value: searchCubit!)
            : BlocProvider(
                create: (_) => SearchCubit(searchEvent.searchStates),
              ),
        BlocProvider(
          create: (_) =>
              AggregateSearchCubit(searchEvent, initialSelectedSources: initial)
                ..search(),
        ),
      ],
      child: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SearchAggregateResultPage(searchEvent: searchEvent);
  }
}

class _SearchAggregateResultPage extends StatefulWidget {
  const _SearchAggregateResultPage({required this.searchEvent});

  final SearchEvent searchEvent;

  @override
  State<_SearchAggregateResultPage> createState() =>
      _SearchAggregateResultPageState();
}

class _SearchAggregateResultPageState
    extends State<_SearchAggregateResultPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final keyword = widget.searchEvent.searchStates.searchKeyword.trim();
      if (keyword.isEmpty || !mounted) {
        return;
      }
      final historyItem = _buildHistoryItem(widget.searchEvent);
      final settingCubit = context.read<GlobalSettingCubit>();
      await PluginSearchHistoryStore(
        settingCubit,
        historyItem.source,
      ).record(historyItem.keyword);
    });
  }

  SearchHistoryEntry _buildHistoryItem(SearchEvent event) {
    // 聚合搜索跨全部插件，不隶属某一个插件，所以固定记成聚合哨兵。
    // 这里**不能**读 `searchStates.from`：发现页开聚合搜索时它被塞成了
    // 「当前聚焦的那个插件」（`discover_page.dart:107`），照抄会把一次跨全站的
    // 搜索挂到单个图源名下。
    return SearchHistoryEntry(
      keyword: event.searchStates.searchKeyword.trim(),
      source: kAggregateSearchSource,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchBarTrigger(searchEvent: widget.searchEvent),
      ),
      body: Column(
        children: [
          const _FilterChipsRow(),
          Expanded(
            child: BlocConsumer<AggregateSearchCubit, AggregateSearchState>(
              listener: (context, state) {
                if (state.results.isNotEmpty) {
                  for (final items in state.results.values) {
                    if (items.isNotEmpty) {
                      final list = mapToUnifiedComicSimplifyEntryInfoList(
                        items,
                      );
                      final first = list.firstOrNull;
                      if (first != null && first.fileServer.isNotEmpty) {
                        DiscoverTabScope.maybeOf(context)?.reportFirstCover(
                          url: first.fileServer,
                          path: first.path,
                          from: first.from,
                          cartoonId: first.id,
                        );
                        break;
                      }
                    }
                  }
                }
              },
              builder: (context, state) {
                final hasAnyResponse =
                    state.results.isNotEmpty || state.errors.isNotEmpty;
                if (state.status == AggregateSearchStatus.loading &&
                    !hasAnyResponse) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Stack(
                  children: [
                    _ResultList(searchEvent: widget.searchEvent, state: state),
                    if (state.status == AggregateSearchStatus.loading)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBarTrigger extends StatelessWidget {
  const _SearchBarTrigger({required this.searchEvent});

  final SearchEvent searchEvent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Expanded(
            child: SearchQueryField(
              query: searchEvent.searchStates.searchKeyword,
              history: PluginSearchHistoryStore(
                context.read<GlobalSettingCubit>(),
                kAggregateSearchSource,
              ),
              hintText: t.search.searchHint,
              semanticLabel: t.search.title,
              onTap: () => _openSearchPage(context),
            ),
          ),
          IconButton(
            tooltip: t.search.selectSourceTooltip,
            onPressed: () => _showSourceDialog(context),
            icon: const GlyphIcon(AppGlyphs.sliders),
          ),
        ],
      ),
    );
  }

  void _openSearchPage(BuildContext context) {
    // 在发现页的标签里：根栈上只有导航栏，「弹回去」与「换一页」两件事都不成立，
    // 所以开一条搜索标签。
    final tabs = DiscoverTabScope.maybeOf(context);
    if (tabs != null) {
      tabs.openSearchInput(
        context.read<SearchCubit>().state,
        aggregateMode: true,
      );
      return;
    }

    final stack = context.router.stack;
    if (stack.length > 1 && stack[stack.length - 2].name == SearchRoute.name) {
      context.maybePop();
      return;
    }

    context.replaceRoute(
      SearchRoute(
        key: ValueKey(const Uuid().v4()),
        searchState: context.read<SearchCubit>().state,
        aggregateMode: true,
      ),
    );
  }

  Future<void> _showSourceDialog(BuildContext context) async {
    final cubit = context.read<AggregateSearchCubit>();
    final options = _sourceOptions(context, cubit.state.selectedSources.keys);
    final selected = await showSourceSelectDialog(
      context,
      initial: cubit.state.selectedSources,
      sourceOptions: options,
    );
    if (selected != null) {
      await cubit.applySelectedSources(selected);
    }
  }

  List<({String pluginId, String title})> _sourceOptions(
    BuildContext context,
    Iterable<String> selectedKeys,
  ) {
    final registry = context.read<PluginRegistryCubit>().state;
    final ordered = PluginRegistryService.I.sortPlugins(
      filterRestrictedPlugins(
        registry.plugins.values.where((state) => !state.isDeleted),
        showRestricted: context
            .read<GlobalSettingCubit>()
            .state
            .showRestrictedSources,
      ),
    );
    final selectedSet = selectedKeys.toSet();
    final result = <({String pluginId, String title})>[];
    for (final plugin in ordered) {
      if (!selectedSet.contains(plugin.uuid)) {
        continue;
      }
      result.add((
        pluginId: plugin.uuid,
        title: registry.pluginName(plugin.uuid),
      ));
    }
    return result;
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AggregateSearchCubit, AggregateSearchState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  showCheckmark: false,
                  label: Text(t.search.hasResults),
                  selected: state.showHasResults,
                  onSelected: (value) => context
                      .read<AggregateSearchCubit>()
                      .toggleHasResults(value),
                ),
                FilterChip(
                  showCheckmark: false,
                  label: Text(t.search.showErrors),
                  selected: state.showErrors,
                  onSelected: (value) => context
                      .read<AggregateSearchCubit>()
                      .toggleShowErrors(value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.searchEvent, required this.state});

  final SearchEvent searchEvent;
  final AggregateSearchState state;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final registry = context.watch<PluginRegistryCubit>().state;
    final selectedIds = state.selectedSources.keys.toSet();
    final pluginIds = PluginRegistryService.I
        .sortPlugins(
          filterRestrictedPlugins(
            registry.plugins.values.where(
              (plugin) => selectedIds.contains(plugin.uuid),
            ),
            showRestricted: context
                .watch<GlobalSettingCubit>()
                .state
                .showRestrictedSources,
          ),
        )
        .map((plugin) => plugin.uuid)
        .toList();
    for (final pluginId in pluginIds) {
      final selected = state.selectedSources[pluginId] ?? false;
      if (!selected) {
        continue;
      }

      final items = state.results[pluginId] ?? const <dynamic>[];
      final error = state.errors[pluginId] ?? '';
      final refreshing = state.refreshingSources.contains(pluginId);

      final shouldShowResultSection = items.isNotEmpty || !state.showHasResults;
      if (shouldShowResultSection) {
        final List<ComicSimplifyEntryInfo> entries = items.isNotEmpty
            ? mapToUnifiedComicSimplifyEntryInfoList(items)
            : const <ComicSimplifyEntryInfo>[];
        children.add(
          Padding(
            key: ValueKey('aggregate-source-$pluginId'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: _sourceTitle(context, pluginId),
                  subtitle: t.search.resultCount(count: items.length),
                  onTap: () => _openSourceSearch(context, pluginId),
                ),
                if (entries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: ComicFixedSizeHorizontalList(
                      key: ValueKey('aggregate-list-$pluginId'),
                      entries: entries,
                      spacing: 10,
                      itemWidth: 112,
                    ),
                  ),
                if (entries.isEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 2, 14, 8),
                    child: Text(t.search.noResults),
                  ),
              ],
            ),
          ),
        );
      }

      if (state.showErrors && error.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Card(
              child: ListTile(
                leading: const GlyphIcon(AppGlyphs.error),
                title: Text(
                  t.search.loadFailedForSource(
                    source: _sourceTitle(context, pluginId),
                  ),
                ),
                subtitle: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: t.common.refresh,
                        icon: const GlyphIcon(AppGlyphs.refresh),
                        onPressed: () => context
                            .read<AggregateSearchCubit>()
                            .refreshSource(pluginId),
                      ),
              ),
            ),
          ),
        );
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView(children: children);
  }

  String _sourceTitle(BuildContext context, String pluginId) {
    return context.select<PluginRegistryCubit, String>(
      (cubit) => cubit.state.pluginName(pluginId),
    );
  }

  void _openSourceSearch(BuildContext context, String pluginId) {
    final currentStates = searchEvent.searchStates;
    context.pushRoute(
      SearchResultRoute(
        key: ValueKey(const Uuid().v4()),
        searchEvent: searchEvent.copyWith(
          searchStates: currentStates.copyWith(from: pluginId),
          page: 1,
        ),
        searchCubit: context.read<SearchCubit>(),
      ),
    );
  }
}
