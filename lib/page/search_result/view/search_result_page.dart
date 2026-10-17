import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart' hide Thumb;
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/search_result/view/search_result_library_view.dart';
import 'package:zephyr/page/discover/service/discover_tab_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/page/search_result/search_result.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/search/model/plugin_search_history_store.dart';

@RoutePage()
class SearchResultPage extends StatelessWidget implements AutoRouteWrapper {
  final SearchEvent searchEvent;
  final SearchCubit? searchCubit;

  const SearchResultPage({
    super.key,
    required this.searchEvent,
    this.searchCubit,
  });

  @override
  Widget wrappedRoute(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        searchCubit != null
            ? BlocProvider.value(value: searchCubit!)
            : BlocProvider(
                create: (_) => SearchCubit(searchEvent.searchStates),
              ),
        BlocProvider(create: (_) => SearchBloc()..add(searchEvent)),
        BlocProvider(create: (_) => StringSelectCubit()),
      ],
      child: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SearchResultPage(searchEvent: searchEvent);
  }
}

class _SearchResultPage extends StatefulWidget {
  final SearchEvent searchEvent;

  const _SearchResultPage({required this.searchEvent});

  @override
  State<_SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<_SearchResultPage>
    with SingleTickerProviderStateMixin {
  late SearchEvent searchEvent;
  final _scrollController = ScrollController();
  final _canvasKey = GlobalKey<LibraryEditorialCanvasState>();
  DiscoverTabToolbarController? _tabToolbar;
  int pagesCount = 0;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // 动画持续时间
    );
    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, 0), // 初始位置
          end: const Offset(0, 2),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut, // 动画曲线
          ),
        );

    searchEvent = widget.searchEvent;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final keyword = widget.searchEvent.searchStates.searchKeyword.trim();
      if (keyword.isEmpty || !mounted) return;
      final historyItem = _buildHistoryItem(widget.searchEvent);
      final settingCubit = context.read<GlobalSettingCubit>();
      await PluginSearchHistoryStore(
        settingCubit,
        historyItem.source,
      ).record(historyItem.keyword);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final toolbar = DiscoverTabToolbarScope.maybeOf(context);
    if (identical(toolbar, _tabToolbar)) return;
    _tabToolbar?.unregister(this);
    _tabToolbar = toolbar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(toolbar, _tabToolbar)) {
        toolbar?.register(
          this,
          (anchor) async => _canvasKey.currentState?.openSettings(anchor),
        );
      }
    });
  }

  @override
  void dispose() {
    _tabToolbar?.unregister(this);
    _animationController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SearchResultBar(searchEvent: searchEvent),
      body: _bloc(),
      floatingActionButtonLocation:
          context.select(
            (GlobalSettingCubit cubit) => cubit.state.leftHandModeEnabled,
          )
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: SlideTransition(
        position: _slideAnimation,
        child: SpeedDial(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          buttonSize: const Size(56, 56),
          childrenButtonSize: const Size(56, 56),
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          activeChild: const GlyphIcon(AppGlyphs.close),
          useRotationAnimation: true,
          animationDuration: const Duration(milliseconds: 300),
          spacing: 12,
          spaceBetweenChildren: 8,
          children: [
            SpeedDialChild(
              child: const GlyphIcon(AppGlyphs.gradient),
              label: LibraryPresentationButton.tooltip,
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              onTap: () => _canvasKey.currentState?.openSettings(context),
            ),
            SpeedDialChild(
              child: const GlyphIcon(AppGlyphs.vAlignTop),
              label: t.searchResult.returnToTop,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              onTap: () {
                if (!_scrollController.hasClients) return;
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
              },
            ),
            SpeedDialChild(
              child: const GlyphIcon(AppGlyphs.openExternal),
              label: t.searchResult.jumpToPage,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              onTap: () async {
                final int? targetPage = await showNumberInputDialog(
                  context: context,
                  title: t.searchResult.jump,
                  initialValue: searchEvent.page,
                );

                if (targetPage != null && context.mounted) {
                  context.read<SearchBloc>().add(
                    searchEvent.copyWith(
                      page: targetPage,
                      status: SearchStatus.initial,
                    ),
                  );
                }
              },
            ),
          ],
          child: const GlyphIcon(AppGlyphs.menu),
        ),
      ),
    );
  }

  Widget _bloc() => BlocBuilder<SearchBloc, SearchState>(
    builder: (context, state) {
      switch (state.status) {
        case SearchStatus.initial:
          return Center(child: CircularProgressIndicator());
        case SearchStatus.failure:
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(state.result, style: TextStyle(fontSize: 20)),
                SizedBox(height: 10), // 添加间距
                ElevatedButton(
                  onPressed: () {
                    _refresh(SearchStatus.initial);
                  },
                  child: Text(t.searchResult.retry),
                ),
              ],
            ),
          );
        case SearchStatus.success:
        case SearchStatus.loadingMore:
        case SearchStatus.getMoreFailure:
          if (state.status == SearchStatus.success) {
            searchEvent = state.searchEvent;
            final searchCubit = context.read<SearchCubit>();
            if (searchCubit.state != state.searchEvent.searchStates) {
              searchCubit.update(state.searchEvent.searchStates);
            }
          }
          return _comicList(state);
      }
    },
  );

  SearchHistoryEntry _buildHistoryItem(SearchEvent event) {
    // `from` 就是这次搜索落在哪个插件上：发现页插件卡的搜索与聚合结果页的
    // 「下钻到某个源」都会带上；没带就算归属未知（空串 ⇒ 界面归进「未分类」）。
    return SearchHistoryEntry(
      keyword: event.searchStates.searchKeyword.trim(),
      source: event.searchStates.from.trim(),
    );
  }

  Widget _comicList(SearchState state) {
    return _genericList(state);
  }

  Widget _genericList(SearchState state) {
    if (state.status == SearchStatus.success) {
      if (state.comics.isEmpty && state.hasReachedMax) {
        return Center(
          child: Text(
            t.comicList.nothingHere,
            style: TextStyle(fontSize: 20.0),
          ),
        );
      }
    }

    return SearchResultLibraryView(
      state: state,
      canvasKey: _canvasKey,
      source: searchEvent.searchStates.from,
      controller: _scrollController,
      onRetryLoadMore: () => _fetchSearchResult(retry: true),
      onLoadMore: _fetchSearchResult,
    );
  }

  void _refresh(SearchStatus status) {
    // 使用原本输入参数进行重新搜索
    context.read<SearchBloc>().add(searchEvent.copyWith(status: status));
  }

  void _fetchSearchResult({bool retry = false}) {
    final state = context.read<SearchBloc>().state;
    if (state.hasReachedMax ||
        (state.status != SearchStatus.success &&
            !(retry && state.status == SearchStatus.getMoreFailure))) {
      return;
    }
    context.read<SearchBloc>().add(
      searchEvent.copyWith(
        page: searchEvent.page + 1,
        status: SearchStatus.loadingMore,
      ),
    );
  }

  void _onScroll() {
    // 控制 FAB 的上下移动
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      if (_animationController.isDismissed) {
        _animationController.forward(); // 向上滚动时隐藏 FAB
      }
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      if (_animationController.isCompleted) {
        _animationController.reverse(); // 向下滚动时显示 FAB
      }
    }

    if (_isBottom) {
      _fetchSearchResult();
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }
}
