import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/bookshelf/bookshelf.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_field.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_header.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_panels.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bookshelfSetting = context
        .read<GlobalSettingCubit>()
        .state
        .bookshelfSetting;
    return MultiBlocProvider(
      providers: [
        BlocProvider<BookshelfSearchCubit>(
          create: (context) => BookshelfSearchCubit(
            favorite: SearchStatusState(
              sort: bookshelfSetting.rememberFavoriteSort
                  ? bookshelfSetting.favoriteSort
                  : 'dd',
            ),
            history: SearchStatusState(
              sort: bookshelfSetting.rememberHistorySort
                  ? bookshelfSetting.historySort
                  : 'dd',
            ),
            download: SearchStatusState(
              sort: bookshelfSetting.rememberDownloadSort
                  ? bookshelfSetting.downloadSort
                  : 'dd',
            ),
          ),
        ),
      ],
      child: _BookshelfPageContent(
        initialIndex: bookshelfSetting.homePageIndex,
      ),
    );
  }
}

class _BookshelfPageContent extends StatefulWidget {
  const _BookshelfPageContent({required this.initialIndex});

  final int initialIndex;

  @override
  State<_BookshelfPageContent> createState() => _BookshelfPageContentState();
}

class _BookshelfPageContentState extends State<_BookshelfPageContent> {
  late final List<String> _labels = [
    t.bookshelf.favorite,
    t.bookshelf.history,
    t.bookshelf.download,
  ];

  late int _currentIndex;
  final List<int> _refreshSignals = [0, 0, 0];
  final FocusNode _searchFocusNode = FocusNode();
  // 关键词防抖：短时间内连续输入只保留最后一次，停顿后才真正写入过滤；
  // 回车提交走 onSubmitted 立即生效，不经过这里。
  final _keywordDebouncer = Debouncer(milliseconds: 500);
  List<String> _lastAvailableSources = const <String>[];
  bool _isSearchExpanded = false;
  bool _isFilterOpen = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _labels.length - 1);
    _syncSourcesFromRegistry(context.read<PluginRegistryCubit>().state);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _keywordDebouncer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

    return BlocListener<PluginRegistryCubit, Map<String, PluginRuntimeState>>(
      listenWhen: (previous, current) =>
          _pluginAvailabilityRevision(previous) !=
          _pluginAvailabilityRevision(current),
      listener: (context, pluginStates) {
        _syncSourcesFromRegistry(pluginStates);
        _triggerRefreshAll();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: isDesktop ? 16 : 8,
          title: isDesktop ? _buildDesktopHeader() : _buildMobileHeader(),
        ),
        body: Column(
          children: [
            if (!isDesktop)
              ShelfSearchRegion(
                expanded: _isSearchExpanded,
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: _buildShelfSearchField(autoExpand: true),
              ),
            Expanded(
              child: BookshelfPanels(
                selectedIndex: _currentIndex,
                onSelected: _onTabChanged,
                children: [
                  FolderShelfPage(
                    mode: ShelfPageMode.favorite,
                    refreshSignal: _refreshSignals[0],
                    isActive: _currentIndex == 0,
                  ),
                  FolderShelfPage(
                    mode: ShelfPageMode.history,
                    refreshSignal: _refreshSignals[1],
                    isActive: _currentIndex == 1,
                  ),
                  FolderShelfPage(
                    mode: ShelfPageMode.download,
                    refreshSignal: _refreshSignals[2],
                    isActive: _currentIndex == 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 扇形按钮直接呈现自己的轮廓，不再套一层圆角底槽。
  Widget _buildFilterAction() => _buildFilterButton();

  /// 那颗滑块钮本体 —— 弹层从**这颗按钮**的位置飞出来。
  ///
  /// 包在 [CommonPopupBox] 里而不是用 `showPopupPanel`：这一条要的是完整观感
  /// （按钮先被拍成快照、随托盘一起飞），而按钮就在我们手上，锚点现成。
  /// 种子（当前模式 / 排序 / 图源选择 / 全部可选图源）在 build 里算好 ——
  /// 面板住在根路由里，够不着 `BookshelfSearchCubit`，也没有「哪些图源可用」
  /// 这份知识。`_openFilter` 落账时用的是**同一份**种子，两处不各算一次。
  Widget _buildFilterButton({bool fromSearch = false}) {
    final seed = _filterSeed();
    return CommonPopupBox<BookshelfFilterResult>(
      targetBuilder: (open) => ExpressiveIconButton(
        shape: ExpressiveButtonShape.fan,
        active: _isFilterOpen,
        activeTurns: 0,
        glyph: AppGlyphs.sliders,
        tooltip: t.bookshelf.filter,
        onPressed: () => _openFilter(open, seed: seed, fromSearch: fromSearch),
      ),
      popupBuilder: (_) => BookshelfFilterPanel(
        mode: seed.mode,
        initialSort: seed.sort,
        initialSources: seed.sources,
        sourceOptions: seed.options,
      ),
    );
  }

  /// 打开筛选弹层时的那份「种子」。
  ///
  /// 排序菜单是按模式分开记的（收藏 / 历史 / 下载各一套），图源选择也是，
  /// 所以种子必须先问清楚「现在在哪个模式」——这一份与面板拿到的是同一个
  /// 对象，落账时不再重算，避免两次 rebuild 之间漂移。
  _FilterSeed _filterSeed() {
    final mode = _currentMode();
    final current = context.read<BookshelfSearchCubit>().state.stateOf(mode);
    final options = _buildFilterSourceOptions();
    final available = options.map((option) => option.pluginId).toList();
    // 一个都没勾（新装的图源、清过设置）时按「全选」起：空着打开筛选、
    // 一按应用把书架清空，那不是用户按下这颗按钮时想要的。
    var selected = current.sources.where(available.contains).toSet();
    if (selected.isEmpty) {
      selected = available.toSet();
    }
    return (
      mode: mode,
      sort: switch (mode) {
        (ShelfPageMode.favorite || ShelfPageMode.download)
            when current.sort == 'vd' || current.sort == 'va' =>
          current.sort,
        _ when current.sort == 'da' => 'da',
        _ => 'dd',
      },
      sources: selected,
      options: options,
    );
  }

  Widget _buildDesktopHeader() {
    return ActionBubbleRegion(
      child: Row(
        children: [
          _buildPanelTabs(),
          const SizedBox(width: 24),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _buildShelfSearchField(autoExpand: false),
                  ),
                ),
                const SizedBox(width: 8),
                _buildFilterAction(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 展开内联输入区域，输入框挂载后直接聚焦。
  void _expandSearch() {
    if (_isSearchExpanded) {
      return;
    }
    setState(() => _isSearchExpanded = true);
  }

  /// 退出搜索：先收起键盘；若有关键词则清空并刷新列表，再收起搜索栏。
  /// 与浮层输入框内的 ×（清空但保持展开，方便继续输入）语义区分开。
  void _exitSearch() {
    _keywordDebouncer.cancel();
    _searchFocusNode.unfocus();
    if (_currentSearchState().keyword.isNotEmpty) {
      _setKeyword('');
      _triggerRefresh(goTop: true);
    }
    if (_isSearchExpanded) {
      setState(() => _isSearchExpanded = false);
    }
  }

  Widget _buildMobileHeader() {
    return ShelfSearchHeader(
      expanded: _isSearchExpanded,
      tabs: ActionBubbleRegion(child: _buildPanelTabs()),
      filter: _buildFilterButton(fromSearch: _isSearchExpanded),
      onExpand: _expandSearch,
      onClose: _exitSearch,
    );
  }

  Widget _buildPanelTabs() => PanelSwitcherTabs(
    items: [for (final label in _labels) PanelSwitcherItem(label: label)],
    selectedIndex: _currentIndex,
    onSelected: _onTabChanged,
  );

  /// 关键词防抖写入。mode 在调用时快照，避免防抖期间切 tab 把词写到别的 tab。
  void _setKeywordDebounced(ShelfPageMode mode, String keyword) {
    _keywordDebouncer.run(() {
      if (!mounted) {
        return;
      }
      final cubit = context.read<BookshelfSearchCubit>();
      if (cubit.state.stateOf(mode).keyword == keyword) {
        return;
      }
      cubit.setKeyword(mode, keyword);
    });
  }

  /// 书架搜索框：移动端内联展开，桌面端复用 SearchQueryField。
  /// 非空输入经 500ms 防抖写入 cubit（列表按 keyword 做 BlocBuilder 实时过滤）；
  /// 清空（删到空/点 ×）是明确的单次操作，立即生效；
  /// 回车提交立即生效、保留输入焦点并回到顶部。移动端展开时直接挂载输入框。
  Widget _buildShelfSearchField({required bool autoExpand}) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      buildWhen: (prev, curr) =>
          prev.stateOf(_currentMode()).keyword !=
          curr.stateOf(_currentMode()).keyword,
      builder: (context, state) {
        void onChanged(String keyword) {
          if (autoExpand && !_isSearchExpanded) return;
          if (keyword.isEmpty) {
            _keywordDebouncer.cancel();
            if (_currentSearchState().keyword.isNotEmpty) {
              _setKeyword('');
              _triggerRefresh(goTop: true);
            }
            return;
          }
          _setKeywordDebounced(_currentMode(), keyword);
        }

        void onSubmitted(String keyword) {
          if (autoExpand && !_isSearchExpanded) return;
          _keywordDebouncer.cancel();
          _setKeyword(keyword.trim());
          _triggerRefresh(goTop: true);
        }

        final key = ValueKey('shelf_search_$_currentIndex');
        final query = state.stateOf(_currentMode()).keyword;
        if (autoExpand) {
          return ShelfSearchField(
            key: key,
            query: query,
            focusNode: _searchFocusNode,
            hintText: t.bookshelf.searchList,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          );
        }
        return SearchQueryField(
          key: key,
          query: query,
          focusNode: _searchFocusNode,
          closeOnSubmit: false,
          hintText: t.bookshelf.searchList,
          semanticLabel: t.bookshelf.searchList,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        );
      },
    );
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  ShelfPageMode _currentMode() {
    return switch (_currentIndex) {
      0 => ShelfPageMode.favorite,
      1 => ShelfPageMode.history,
      2 => ShelfPageMode.download,
      _ => ShelfPageMode.favorite,
    };
  }

  void _maybePersistSort(ShelfPageMode mode, String sort) {
    final cubit = context.read<GlobalSettingCubit>();
    final setting = cubit.state.bookshelfSetting;
    final shouldPersist = switch (mode) {
      ShelfPageMode.favorite => setting.rememberFavoriteSort,
      ShelfPageMode.history => setting.rememberHistorySort,
      ShelfPageMode.download => setting.rememberDownloadSort,
    };
    if (!shouldPersist) return;
    cubit.updateBookshelfSetting(
      (current) => switch (mode) {
        ShelfPageMode.favorite => current.copyWith(favoriteSort: sort),
        ShelfPageMode.history => current.copyWith(historySort: sort),
        ShelfPageMode.download => current.copyWith(downloadSort: sort),
      },
    );
  }

  SearchStatusState _currentSearchState() {
    final cubit = context.read<BookshelfSearchCubit>();
    return cubit.state.stateOf(_currentMode());
  }

  void _setKeyword(String keyword) {
    context.read<BookshelfSearchCubit>().setKeyword(_currentMode(), keyword);
  }

  void _triggerRefresh({bool goTop = false}) {
    setState(() {
      _refreshSignals[_currentIndex] = _refreshSignals[_currentIndex] + 1;
    });
  }

  void _triggerRefreshAll() {
    if (!mounted) {
      return;
    }
    setState(() {
      for (var i = 0; i < _refreshSignals.length; i++) {
        _refreshSignals[i] = _refreshSignals[i] + 1;
      }
    });
  }

  /// 弹出筛选并把结果落账。
  ///
  /// [seed] 是 build 那一刻算好的种子（面板拿到的就是它），所以这里**不再重算**
  /// 一遍当前选择 —— 重算会多读一次 cubit，两次之间但凡有个 rebuild，
  /// 面板里的勾选与落账的基准就会错开一格。
  ///
  /// [fromSearch] 走的是「搜索展开态打开筛选」那条路：弹层会抢走焦点，
  /// 关掉之后若还在搜索态就把焦点还回去，键盘接着输。
  Future<void> _openFilter(
    PopupOpen<BookshelfFilterResult> open, {
    required _FilterSeed seed,
    bool fromSearch = false,
  }) async {
    if (seed.options.isEmpty && seed.mode != ShelfPageMode.favorite) {
      showInfoToast(t.bookshelf.noFilterSource, context: context);
      return;
    }

    // cubit 在 await 之前就抓在手里：`await open()` 之后 `context` 已经跨了
    // 一次异步间隙，那时再读会踩 `use_build_context_synchronously`。
    final searchCubit = context.read<BookshelfSearchCubit>();

    if (_isFilterOpen) return;
    setState(() => _isFilterOpen = true);
    BookshelfFilterResult? result;
    try {
      result = await open();
    } finally {
      if (mounted) setState(() => _isFilterOpen = false);
    }

    if (mounted && fromSearch && _isSearchExpanded) {
      _searchFocusNode.requestFocus();
    }
    if (result == null) return;

    searchCubit.setSort(seed.mode, result.sort);
    _maybePersistSort(seed.mode, result.sort);
    searchCubit.setSources(seed.mode, result.sources.toList());
    _triggerRefresh(goTop: true);
  }

  List<FilterSourceOption> _buildFilterSourceOptions() {
    final pluginStates = context.read<PluginRegistryCubit>().state;
    final sourceOptions = PluginRegistryService.I.sortPlugins(
      pluginStates.values.where(
        (plugin) => plugin.isEnabled && !plugin.isDeleted,
      ),
    );
    final list = sourceOptions
        .map(
          (plugin) => FilterSourceOption(
            pluginId: plugin.uuid,
            title: _sourceTitle(plugin.uuid),
          ),
        )
        .toList();
    list.add(
      FilterSourceOption(pluginId: 'local', title: _sourceTitle('local')),
    );
    return list;
  }

  String _sourceTitle(String pluginId) {
    if (pluginId == 'local') {
      return '本地漫画';
    }
    final info = PluginRegistryService.I.getCachedPluginInfo(pluginId);
    final name = info?['name']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : pluginId;
  }

  void _syncSourcesFromRegistry(Map<String, PluginRuntimeState> pluginStates) {
    final available = pluginStates.values
        .where((plugin) => plugin.isEnabled && !plugin.isDeleted)
        .map((plugin) => plugin.uuid)
        .toList();
    if (!available.contains('local')) {
      available.add('local');
    }
    available.sort();

    if (listEquals(_lastAvailableSources, available)) {
      return;
    }
    final addedSources = available
        .where((item) => !_lastAvailableSources.contains(item))
        .toList();
    _lastAvailableSources = List<String>.from(available);

    context.read<BookshelfSearchCubit>().syncSources(
      available,
      autoSelect: addedSources,
    );
  }

  String _pluginAvailabilityRevision(
    Map<String, PluginRuntimeState> pluginStates,
  ) {
    final entries =
        pluginStates.entries
            .map(
              (entry) =>
                  '${entry.key}:${entry.value.isEnabled ? 1 : 0}:${entry.value.isDeleted ? 1 : 0}',
            )
            .toList()
          ..sort();
    return entries.join('|');
  }
}

/// 打开筛选时算好的那一份「种子」。
///
/// 排序与图源选择都是**按模式分开记**的（收藏 / 历史 / 下载各一套），
/// 所以面板必须连「现在在哪个模式」一起拿到，不能只给它两个值。
/// 用记录类型而不是再定义一个类：它是三个字段的一次性打包，
/// 生命周期只到这一次弹出结束。
typedef _FilterSeed = ({
  ShelfPageMode mode,
  String sort,
  Set<String> sources,
  List<FilterSourceOption> options,
});
