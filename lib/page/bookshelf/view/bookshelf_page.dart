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
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
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

class _BookshelfPageContentState extends State<_BookshelfPageContent>
    with SingleTickerProviderStateMixin {
  late final List<String> _labels = [
    t.bookshelf.favorite,
    t.bookshelf.history,
    t.bookshelf.download,
  ];

  late int _currentIndex;
  late final TabController _tabController;
  final List<int> _refreshSignals = [0, 0, 0];
  final FocusNode _searchFocusNode = FocusNode();
  // 关键词防抖：短时间内连续输入只保留最后一次，停顿后才真正写入过滤；
  // 回车提交走 onSubmitted 立即生效，不经过这里。
  final _keywordDebouncer = Debouncer(milliseconds: 500);
  List<String> _lastAvailableSources = const <String>[];
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _labels.length - 1);
    _tabController = TabController(
      initialIndex: _currentIndex,
      length: _labels.length,
      vsync: this,
    )..addListener(_handleTabControllerChanged);
    _syncSourcesFromRegistry(context.read<PluginRegistryCubit>().state);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabControllerChanged)
      ..dispose();
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
        body: TabBarView(
          controller: _tabController,
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
    );
  }

  /// 右上角那一组图标钮的底色。
  ///
  /// 与左边那条胶囊 tab（[_buildSleekTabs] 的容器）**同一个色** —— 同一条栏上
  /// 两个容器读作同一种「可点区」，而不是两种灰。数值也是照抄那边的，改动要一起改。
  Color get _actionWellFill =>
      context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

  /// 筛选键：全应用同一颗 [ActionIconButton]，装在与搜索同一档的分组槽里。
  ///
  /// 桌面端搜索是一个**输入框**（`SearchQueryField`），与这颗不同质，所以不并进
  /// 同一只槽；窄屏那一支两颗都是图标，才合成一条（见 [_buildMobileHeader]）。
  Widget _buildFilterAction() {
    return ActionGroup(
      fill: _actionWellFill,
      children: [
        ActionIconButton(
          glyph: AppGlyphs.sliders,
          tooltip: t.bookshelf.filter,
          onPressed: _openFilter,
        ),
      ],
    );
  }

  Widget _buildDesktopHeader() {
    return Row(
      children: [
        _buildSleekTabs(),
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
    );
  }

  /// 展开移动端搜索栏。挂载的 SearchQueryField 自带 autoExpand，
  /// 首帧后自动展开浮层并聚焦，键盘随之弹出。
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

  /// 展开态打开筛选：弹窗会抢走焦点，关闭后若还在搜索态则恢复聚焦，键盘回来接着输。
  Future<void> _openFilterFromSearch() async {
    await _openFilter();
    if (mounted && _isSearchExpanded) {
      _searchFocusNode.requestFocus();
    }
  }

  Widget _buildMobileHeader() {
    if (_isSearchExpanded) {
      return Row(
        children: [
          IconButton(
            tooltip: t.common.back,
            icon: const GlyphIcon(AppGlyphs.arrowBack),
            onPressed: _exitSearch,
          ),
          Expanded(child: _buildShelfSearchField(autoExpand: true)),
          ActionGroup(
            fill: _actionWellFill,
            children: [
              ActionIconButton(
                glyph: AppGlyphs.sliders,
                tooltip: t.bookshelf.filter,
                onPressed: _openFilterFromSearch,
              ),
            ],
          ),
        ],
      );
    }

    // 右上角那两颗（放大镜 / 滑块）装进**同一只分组槽** —— 这正是 FlClash 顶栏
    // 右上角的形态：一个胶囊里几颗图标，旁边不再散着一颗。左边的胶囊 tab 不动。
    return Row(
      children: [
        _buildSleekTabs(),
        const Spacer(),
        ActionGroup(
          fill: _actionWellFill,
          children: [
            ActionIconButton(
              glyph: AppGlyphs.search,
              tooltip: t.common.search,
              onPressed: _expandSearch,
            ),
            ActionIconButton(
              glyph: AppGlyphs.sliders,
              tooltip: t.bookshelf.filter,
              onPressed: _openFilter,
            ),
          ],
        ),
      ],
    );
  }

  /// 书架顶栏那排胶囊 tab（收藏 / 历史 / 下载）。
///
/// # 为什么用 [SpringLensBar] 而不是自己排一个 Row
///
/// 选中态改由 Dock 那一套弹簧 lens 接管（见 `widgets/spring_lens/`）：点一下
/// 时它是**弹**过去的，不是 `AnimatedContainer` 那样 180ms 线性淡入；按下会鼓、
/// 跟着手指走、跨格有触感回馈。切换的**内容**（`TabBarView` 与三个
/// `FolderShelfPage`）完全没动，仍由 [_tabController] 驱动 —— 这里换的只是
/// 「选中态画成什么样」。
///
/// # 为什么要自己量宽度（[tabSizes]）
///
/// 这一排是**按文字取宽**的（「收藏」两字比「下载」两字宽，中英文差得更多），
/// 而 Dock 那边 lens 建立在等宽假设上。所以这里按渲染出来的那一份样式量出每格
/// 宽度喂给组件，lens 的落点与宽度才与实际排出来的那几格对得上。
///
/// 量宽度要量**真正渲染的那一份**（理由同 `reader_settings_tab_bar_part.dart`
/// 那一段：本仓主题的字体档位可能只改字族、把 fontSize 留成 null）。
Widget _buildSleekTabs() {
  // 量宽度用的那份样式必须与 `_SleekTabLabel` **渲染的那一份**同源 ——
  // 拿 token 直接量、在 fontSize 为 null 的档位上量到的是回落值，
  // 于是「每格多宽」与实际排出来的宽度对不上，lens 的落点会偏。
  final labelStyle = DefaultTextStyle.of(context).style.merge(
    context.theme.textTheme.titleSmall,
  );

  // 量每格宽度：文字实测宽 + 左右内边距。与 `_Slot` 里那个
  // `SizedBox(width: extent)` 用的是同一个数。
  final sizes = <double>[];
  for (final label in _labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    sizes.add(painter.width + _SleekTabLabel.hPadding * 2);
    painter.dispose();
  }

  return Container(
    // 底板与右边那颗筛选钮的 `_actionWellFill` **同一个色** —— 判据见上面
    // `_actionWellFill` 的注释（两条栏上两个容器读作同一种「可点区」）。
    decoration: BoxDecoration(
      color: context.theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.all(4),
    child: SpringLensBar(
      tabs: [
        for (var i = 0; i < _labels.length; i++)
          SpringLensTab(
            // 文字色/字重仍按选中态分档（lens 只接管**底色**那块方块）。
            // 两件事分开：`lensColor` 给 secondaryContainer 那一档，
            // 于是选中块是「灰胶囊里的一块浅色」，与右边筛选钮那一档同族。
            child: _SleekTabLabel(
              text: _labels[i],
              selected: i == _currentIndex,
              baseStyle: labelStyle,
            ),
            semanticLabel: _labels[i],
          ),
      ],
      tabSizes: sizes,
      selectedIndex: _currentIndex,
      onSelected: _onTabChanged,
      // lens 圆角跟原来那个选中块的 16 一致，不是全圆 —— 顶栏这排是「胶囊里
      // 几块」，全圆会让两端贴到容器边上。
      lensCorner: 16,
    ),
  );
}

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

  /// 书架搜索框：复用搜索页的 SearchQueryField（浮层展开、多行展示、回车即搜）。
  /// 非空输入经 500ms 防抖写入 cubit（列表按 keyword 做 BlocBuilder 实时过滤）；
  /// 清空（删到空/点 ×）是明确的单次操作，立即生效；
  /// 回车提交立即生效、保持浮层展开并回到顶部，方便继续改词。桌面端常驻显示（autoExpand 关），
  /// 移动端在展开时挂载（autoExpand 开，首帧自动聚焦弹键盘）。
  Widget _buildShelfSearchField({required bool autoExpand}) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      buildWhen: (prev, curr) =>
          prev.stateOf(_currentMode()).keyword !=
          curr.stateOf(_currentMode()).keyword,
      builder: (context, state) {
        return SearchQueryField(
          // 按 tab 区分 element：切 tab 时重建，保证各 tab 关键词独立，
          // 且展开中的浮层不会串词。
          key: ValueKey('shelf_search_$_currentIndex'),
          query: state.stateOf(_currentMode()).keyword,
          autoExpand: autoExpand,
          focusNode: _searchFocusNode,
          closeOnSubmit: false,
          hintText: t.bookshelf.searchList,
          semanticLabel: t.bookshelf.searchList,
          onChanged: (keyword) {
            if (keyword.isEmpty) {
              // 清空是明确的单次操作，立即生效，不走防抖。
              _keywordDebouncer.cancel();
              if (_currentSearchState().keyword.isNotEmpty) {
                _setKeyword('');
                _triggerRefresh(goTop: true);
              }
              return;
            }
            _setKeywordDebounced(_currentMode(), keyword);
          },
          onSubmitted: (keyword) {
            _keywordDebouncer.cancel();
            _setKeyword(keyword.trim());
            _triggerRefresh(goTop: true);
          },
        );
      },
    );
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) return;
    _tabController.animateTo(index);
  }

  void _handleTabControllerChanged() {
    if (!mounted || _currentIndex == _tabController.index) {
      return;
    }
    setState(() {
      _currentIndex = _tabController.index;
    });
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

  Future<void> _openFilter() async {
    final searchCubit = context.read<BookshelfSearchCubit>();
    final currentMode = _currentMode();
    final current = searchCubit.state.stateOf(currentMode);
    final sourceOptions = _buildFilterSourceOptions();
    final availableSources = sourceOptions
        .map((source) => source.pluginId)
        .toList();

    if (availableSources.isEmpty && currentMode != ShelfPageMode.favorite) {
      showInfoToast(t.bookshelf.noFilterSource, context: context);
      return;
    }

    var selectedSources = current.sources
        .where(availableSources.contains)
        .toSet();
    if (selectedSources.isEmpty) {
      selectedSources = availableSources.toSet();
    }

    final result = await showDialog<_BookshelfFilterResult>(
      context: context,
      builder: (_) => _BookshelfFilterDialog(
        mode: currentMode,
        initialSort: switch (currentMode) {
          (ShelfPageMode.favorite || ShelfPageMode.download)
              when current.sort == 'vd' || current.sort == 'va' =>
            current.sort,
          _ when current.sort == 'da' => 'da',
          _ => 'dd',
        },
        initialSources: selectedSources,
        availableSources: availableSources,
        sourceOptions: sourceOptions,
      ),
    );

    if (result == null) return;

    searchCubit.setSort(currentMode, result.sort);
    _maybePersistSort(currentMode, result.sort);

    final nextSources = result.sources.toList();
    searchCubit.setSources(currentMode, nextSources);
    _triggerRefresh(goTop: true);
  }

  List<_FilterSourceOption> _buildFilterSourceOptions() {
    final pluginStates = context.read<PluginRegistryCubit>().state;
    final sourceOptions = PluginRegistryService.I.sortPlugins(
      pluginStates.values.where(
        (plugin) => plugin.isEnabled && !plugin.isDeleted,
      ),
    );
    final list = sourceOptions
        .map(
          (plugin) => _FilterSourceOption(
            pluginId: plugin.uuid,
            title: _sourceTitle(plugin.uuid),
          ),
        )
        .toList();
    list.add(
      _FilterSourceOption(pluginId: 'local', title: _sourceTitle('local')),
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

/// 顶栏那一排 tab 的文字。选中与否只影响字重与颜色，**内边距两档相同** ——
/// 内边距参与「每格多宽」的计算（见 [_BookshelfPageContentState._buildSleekTabs]），
/// 两档若不同，切档时 lens 的落点就会偏一点。
class _SleekTabLabel extends StatelessWidget {
  const _SleekTabLabel({
    required this.text,
    required this.selected,
    required this.baseStyle,
  });

  /// 文字左右各留的内边距。
  ///
  /// **量与画必须读同一份**：`_buildSleekTabs` 量每格宽度时用它算总宽，
  /// 这里用它排版。两处各写一个数的话，lens 的落点会与实际排出来的位置差
  /// 那一点点 —— 按内容取宽的档位最怕这个。
  static const double hPadding = 16;

  /// 文字上下的内边距（不参与宽度计算）。
  static const double vPadding = 6;

  final String text;
  final bool selected;

  /// 由 [_buildSleekTabs] 量宽度时用的**那一份**样式传进来 —— 量与画必须同源。
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: hPadding,
        vertical: vPadding,
      ),
      child: Text(
        text,
        style: baseStyle.copyWith(
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          color: selected
              ? context.textColor
              : context.textColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _BookshelfFilterDialog extends StatefulWidget {
  const _BookshelfFilterDialog({
    required this.mode,
    required this.initialSort,
    required this.initialSources,
    required this.availableSources,
    required this.sourceOptions,
  });

  final ShelfPageMode mode;
  final String initialSort;
  final Set<String> initialSources;
  final List<String> availableSources;
  final List<_FilterSourceOption> sourceOptions;

  @override
  State<_BookshelfFilterDialog> createState() => _BookshelfFilterDialogState();
}

class _BookshelfFilterDialogState extends State<_BookshelfFilterDialog> {
  late String _selectedSort;
  late Set<String> _selectedSources;

  bool get _isFavoriteMode => widget.mode == ShelfPageMode.favorite;
  bool get _isDownloadMode => widget.mode == ShelfPageMode.download;

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.initialSort;
    _selectedSources = Set<String>.from(widget.initialSources);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.bookshelf.filter),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSortSection(context),
              const SizedBox(height: 16),
              _buildSourceSection(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _BookshelfFilterResult(
              sort: _selectedSort,
              sources: _selectedSources,
            ),
          ),
          child: Text(t.common.apply),
        ),
      ],
    );
  }

  Widget _buildSortSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.bookshelf.sort, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              showCheckmark: false,
              label: Text(t.bookshelf.sortDesc),
              selected: _selectedSort == 'dd',
              onSelected: (_) => setState(() => _selectedSort = 'dd'),
            ),
            ChoiceChip(
              showCheckmark: false,
              label: Text(t.bookshelf.sortAsc),
              selected: _selectedSort == 'da',
              onSelected: (_) => setState(() => _selectedSort = 'da'),
            ),
            if (_isFavoriteMode || _isDownloadMode) ...[
              ChoiceChip(
                showCheckmark: false,
                label: Text(t.bookshelf.viewSortDesc),
                selected: _selectedSort == 'vd',
                onSelected: (_) => setState(() => _selectedSort = 'vd'),
              ),
              ChoiceChip(
                showCheckmark: false,
                label: Text(t.bookshelf.viewSortAsc),
                selected: _selectedSort == 'va',
                onSelected: (_) => setState(() => _selectedSort = 'va'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSourceSection(BuildContext context) {
    final isAllSelected =
        _selectedSources.length == widget.availableSources.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              t.bookshelf.source,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                if (isAllSelected) {
                  _selectedSources.clear();
                } else {
                  _selectedSources = widget.availableSources.toSet();
                }
              }),
              child: Text(
                isAllSelected ? t.bookshelf.deselectAll : t.common.selectAll,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in widget.sourceOptions)
              FilterChip(
                showCheckmark: false,
                label: Text(source.title),
                selected: _selectedSources.contains(source.pluginId),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _selectedSources.add(source.pluginId);
                  } else {
                    _selectedSources.remove(source.pluginId);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class _BookshelfFilterResult {
  _BookshelfFilterResult({required this.sort, required Set<String> sources})
    : sources = Set<String>.from(sources);

  final String sort;
  final Set<String> sources;
}

class _FilterSourceOption {
  const _FilterSourceOption({required this.pluginId, required this.title});

  final String pluginId;
  final String title;
}
