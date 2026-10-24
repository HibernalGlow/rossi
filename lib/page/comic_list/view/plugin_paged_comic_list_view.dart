import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_navigation_controller.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_position_store.dart';
import 'package:zephyr/page/comic_list/view/plugin_list_navigation_host.dart';
import 'package:zephyr/widgets/library_viewport_anchor.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_list/view/discover_library_entries.dart';
import 'package:zephyr/page/comic_list/view/discover_library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_cubit.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';
import 'package:zephyr/page/comic_list/view/plugin_comic_grid_sliver.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_mapper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/widgets/error_view.dart';

export 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_cubit.dart';
export 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';

class PluginPagedComicListView extends StatelessWidget {
  const PluginPagedComicListView({
    super.key,
    required this.pluginId,
    required this.fnPath,
    required this.coreBuilder,
    required this.externBuilder,
    this.shrinkWrap = false,
    this.editorialKey,
    this.navigationController,
    this.physics,
    this.collectionTargetId,
    this.collectionTargetName,
    this.suppressNeedLoginEvent = false,
    this.detailed = false,
  });

  final PluginListNavigationController? navigationController;
  final GlobalKey<LibraryEditorialCanvasState>? editorialKey;
  final String pluginId;
  final String fnPath;
  final PluginPageCoreBuilder coreBuilder;
  final PluginPageExternBuilder externBuilder;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final String? collectionTargetId;
  final String? collectionTargetName;
  final bool suppressNeedLoginEvent;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PluginPagedComicListCubit(
        pluginId: pluginId,
        fnPath: fnPath,
        coreBuilder: coreBuilder,
        externBuilder: externBuilder,
        suppressNeedLoginEvent: suppressNeedLoginEvent,
      )..loadInitial(),
      child: _PluginPagedComicListBody(
        editorialKey: editorialKey,
        navigationController: navigationController,
        positionScope: pluginListPositionScope(
          pluginId,
          fnPath,
          coreBuilder(1),
          externBuilder(1),
        ),
        presentationScope: 'discover:$pluginId:$fnPath',
        shrinkWrap: shrinkWrap,
        physics: physics,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
        detailed: detailed,
      ),
    );
  }
}

class _PluginPagedComicListBody extends StatefulWidget {
  const _PluginPagedComicListBody({
    required this.shrinkWrap,
    required this.presentationScope,
    required this.positionScope,
    this.navigationController,
    this.editorialKey,
    required this.physics,
    this.collectionTargetId,
    this.collectionTargetName,
    this.detailed = false,
  });

  final String positionScope;
  final PluginListNavigationController? navigationController;
  final GlobalKey<LibraryEditorialCanvasState>? editorialKey;
  final String presentationScope;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final String? collectionTargetId;
  final String? collectionTargetName;
  final bool detailed;

  @override
  State<_PluginPagedComicListBody> createState() =>
      _PluginPagedComicListBodyState();
}

class _PluginPagedComicListBodyState extends State<_PluginPagedComicListBody>
    with AutomaticKeepAliveClientMixin {
  final ScrollController scrollController = ScrollController();
  final _viewport = LibraryViewportRegistry();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = RefreshIndicator(
      onRefresh: () => context.read<PluginPagedComicListCubit>().loadInitial(),
      child: BlocConsumer<PluginPagedComicListCubit, PluginPagedComicListState>(
        listener: (context, state) {
          if (state.list.isNotEmpty) {
            final firstComic = mapToUnifiedComicSimplifyEntryInfoList(
              state.list,
            ).where((info) => info.title != '无数据').firstOrNull;
            if (firstComic != null && firstComic.fileServer.isNotEmpty) {
              DiscoverTabScope.maybeOf(context)?.reportFirstCover(
                url: firstComic.fileServer,
                path: firstComic.path,
                from: firstComic.from,
                cartoonId: firstComic.id,
              );
            }
          }
        },
        builder: (context, state) {
          // 「详情布局」开启 = 关闭展墙，直接走 web 风详情行（_legacyContent
          // → _buildContent 会把 detailed 传进网格 sliver）；关 = 展墙照旧。
          if (widget.editorialKey != null &&
              !widget.shrinkWrap &&
              !widget.detailed) {
            final settings = context.watch<GlobalSettingCubit>().state;
            final comics = mapToUnifiedComicSimplifyEntryInfoList(
              state.list,
            ).where((info) => info.title != '无数据').toList();
            return DiscoverLibraryView(
              canvasKey: widget.editorialKey!,
              viewportRegistry: _viewport,
              scrollController: scrollController,
              scope: widget.presentationScope,
              entries: [
                for (final info in comics) discoverLibraryEntry(info, settings),
              ],
              collectionTargetId: widget.collectionTargetId,
              collectionTargetName: widget.collectionTargetName,
              onReachEnd: () {
                if (state.status == PluginPagedComicListStatus.success &&
                    widget.navigationController?.busy != true) {
                  context.read<PluginPagedComicListCubit>().loadMore();
                }
              },
              footerBuilder: (_) => _wallFooter(context, state),
              legacyBuilder: (_) => _legacyContent(context, state),
            );
          }
          return _legacyContent(context, state);
        },
      ),
    );
    final navigation = widget.navigationController;
    if (navigation == null) return content;
    return PluginListNavigationHost(
      navigation: navigation,
      scope: widget.positionScope,
      viewport: _viewport,
      scroll: scrollController,
      canvasKey: widget.editorialKey,
      child: content,
    );
  }

  Widget _legacyContent(BuildContext context, PluginPagedComicListState state) {
    switch (state.status) {
      case PluginPagedComicListStatus.initial:
        return const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      case PluginPagedComicListStatus.failure:
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(
                errorMessage: '${state.result}\n${t.comicList.loadFailedRetry}',
                // 登录失效时给「去登录」入口（上游插件首页口径）。
                loginPluginId: state.loginPluginId,
                onRetry: () => context
                    .read<PluginPagedComicListCubit>()
                    .jumpToPage(state.page),
              ),
            ),
          ],
        );
      case PluginPagedComicListStatus.loadingMore:
      case PluginPagedComicListStatus.loadingMoreFailure:
      case PluginPagedComicListStatus.success:
        return _buildContent(context, state);
    }
  }

  Widget _wallFooter(BuildContext context, PluginPagedComicListState state) {
    if (state.status == PluginPagedComicListStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.status == PluginPagedComicListStatus.loadingMoreFailure) {
      return Center(
        child: FilledButton.tonal(
          onPressed: () =>
              context.read<PluginPagedComicListCubit>().retryLoadMore(),
          child: Text(t.oldHome.loadMoreFailed),
        ),
      );
    }
    if (state.hasReachedMax) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(t.oldHome.noMore)),
      );
    }
    return Center(
      child: TextButton(
        onPressed: () => context.read<PluginPagedComicListCubit>().loadMore(),
        child: Text(t.oldHome.loadMore),
      ),
    );
  }

  Widget _buildContent(BuildContext context, PluginPagedComicListState state) {
    if (state.list.isEmpty &&
        state.status == PluginPagedComicListStatus.success) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                t.comicList.nothingHere,
                style: const TextStyle(fontSize: 20.0),
              ),
            ),
          ),
        ],
      );
    }

    final list = mapToUnifiedComicSimplifyEntryInfoList(state.list);

    return PluginComicGridSliver(
      controller: scrollController,
      entries: list,
      hasReachedMax: state.hasReachedMax,
      isLoadingMore: state.status == PluginPagedComicListStatus.loadingMore,
      loadMoreFailed:
          state.status == PluginPagedComicListStatus.loadingMoreFailure,
      onRetryLoadMore: () =>
          context.read<PluginPagedComicListCubit>().retryLoadMore(),
      onLoadMore: () => context.read<PluginPagedComicListCubit>().loadMore(),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics ?? const AlwaysScrollableScrollPhysics(),
      collectionTargetId: widget.collectionTargetId,
      collectionTargetName: widget.collectionTargetName,
      detailed: widget.detailed,
    );
  }

  void _onScroll() {
    if (_isBottom && widget.navigationController?.busy != true) {
      context.read<PluginPagedComicListCubit>().loadMore();
    }
  }

  bool get _isBottom {
    if (!scrollController.hasClients) return false;
    final maxScroll = scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return false;
    final currentScroll = scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }
}
