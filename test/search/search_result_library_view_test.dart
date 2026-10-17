import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/view/comic_info.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/discover/service/discover_tab_toolbar.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/page/search_result/models/comic_number.dart';
import 'package:zephyr/page/search_result/view/search_result_library_view.dart';
import 'package:zephyr/page/search_result/view/search_result_page.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

import '../test_helper.dart';

class _Settings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

class _Search extends SearchBloc {
  _Search(SearchState initial) {
    emit(initial);
  }

  void publish(SearchState value) => emit(value);

  final requests = <SearchEvent>[];
  @override
  void add(SearchEvent event) => requests.add(event);
}

class _Tabs implements DiscoverTabActions {
  final opened = <String>[];
  @override
  void openComicInfo({
    required String comicId,
    required String from,
    required String title,
    String? coverUrl,
    String? coverPath,
    String? collectionTargetId,
    String? collectionTargetName,
  }) {
    opened.add('$from:$comicId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SearchState _state({
  SearchStatus status = SearchStatus.success,
  bool end = true,
  int count = 3,
}) => SearchState(
  status: status,
  hasReachedMax: end,
  searchEvent: const SearchEvent(
    page: 3,
    searchStates: SearchStates(
      from: 'test-plugin',
      searchKeyword: 'artist:One',
    ),
  ),
  comics: [
    for (var i = 0; i < count; i++)
      ComicNumber(
        buildNumber: i,
        comic: UnifiedComicListItem.fromJson({
          'source': 'test-plugin',
          'id': '$i',
          'title': '结果 $i',
          'cover': {'url': '', 'path': '', 'id': '$i'},
        }),
      ),
  ],
);

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
    objectbox.userSettingBox.put(UserSetting());
  });
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('搜索默认使用展墙新封面，信息键原位展开与收起，不打开新页签', (tester) async {
    final settings = _Settings();
    final canvas = GlobalKey<LibraryEditorialCanvasState>();
    final scroll = ScrollController();
    final tabs = _Tabs();
    addTearDown(settings.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: DiscoverTabScope(
              actions: tabs,
              child: SearchResultLibraryView(
                state: _state(),
                canvasKey: canvas,
                controller: scroll,
                source: 'test-plugin',
                onLoadMore: () {},
                onRetryLoadMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryEditorialTile), findsWidgets);
    expect(find.byType(ComicCoverSurface), findsWidgets);
    await tester.tap(find.byTooltip('展开信息').first);
    await tester.pumpAndSettle();
    final details = tester.widget<EmbeddedComicInfo>(
      find.byType(EmbeddedComicInfo),
    );
    expect(details.from, 'test-plugin');
    expect(details.comicId, '0');
    expect(canvas.currentState!.expandedEntries.single.key, 'test-plugin:0');
    expect(tabs.opened, isEmpty);
    await tester.ensureVisible(find.byTooltip('收起信息').first);
    await tester.tap(find.byTooltip('收起信息').first);
    await tester.pumpAndSettle();
    expect(canvas.currentState!.expandedEntries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实结果页保留页签展墙工具、分页失败重试和同一视口', (tester) async {
    final settings = _Settings();
    final initial = _state();
    final search = _Search(initial);
    final query = SearchCubit(initial.searchEvent.searchStates);
    final selection = StringSelectCubit();
    final toolbar = DiscoverTabToolbarController();
    addTearDown(settings.close);
    addTearDown(() async {
      if (search.isClosed) return;
      final closing = search.close();
      await tester.pump();
      await closing;
    });
    addTearDown(query.close);
    addTearDown(selection.close);
    addTearDown(toolbar.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: settings),
          BlocProvider<SearchBloc>.value(value: search),
          BlocProvider<SearchCubit>.value(value: query),
          BlocProvider<StringSelectCubit>.value(value: selection),
        ],
        child: MaterialApp(
          home: DiscoverTabToolbarScope(
            controller: toolbar,
            child: SearchResultPage(searchEvent: initial.searchEvent),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryEditorialTile), findsWidgets);
    expect(toolbar.presentation, isNotNull);
    final canvas = tester.state<LibraryEditorialCanvasState>(
      find.byType(LibraryEditorialCanvas),
    );
    search.publish(_state(status: SearchStatus.getMoreFailure, end: false));
    await tester.pumpAndSettle();
    expect(
      tester.state<LibraryEditorialCanvasState>(
        find.byType(LibraryEditorialCanvas),
      ),
      same(canvas),
    );
    final retry = find.text(t.oldHome.loadMoreFailed);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    expect(search.requests.single.page, 4);
    expect(search.requests.single.status, SearchStatus.loadingMore);
    expect(search.requests.single.searchStates.searchKeyword, 'artist:One');
    search.publish(_state(status: SearchStatus.loadingMore, end: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(search.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(toolbar.presentation, isNull);
    // Bloc 的事件流在 widget 测试的虚拟时钟中创建，关闭时也推进其微任务。
    final closing = search.close();
    await tester.pump();
    await closing;
  });

  testWidgets('长搜索结果只挂载视口附近封面，历史更新不重算条目', (tester) async {
    final settings = _Settings();
    final scroll = ScrollController();
    final canvas = GlobalKey<LibraryEditorialCanvasState>();
    addTearDown(settings.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SearchResultLibraryView(
              state: _state(count: 2000),
              canvasKey: canvas,
              controller: scroll,
              source: 'test-plugin',
              onLoadMore: () {},
              onRetryLoadMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final view = find.byType(LibraryEditorialCanvas);
    final entries = tester.widget<LibraryEditorialCanvas>(view).entries;
    expect(entries, hasLength(2000));
    expect(
      find.byType(ComicCoverSurface).evaluate().length,
      inExclusiveRange(0, 100),
    );
    settings.updateState(
      (state) => state.copyWith(
        searchHistory: const [
          SearchHistoryEntry(keyword: 'new query', source: 'test-plugin'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryEditorialCanvas>(view).entries, same(entries));
    scroll.jumpTo(scroll.position.maxScrollExtent * .8);
    await tester.pumpAndSettle();
    expect(
      find.byType(ComicCoverSurface).evaluate().length,
      inExclusiveRange(0, 100),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LibraryEditorialTile &&
            widget.entry.key == 'test-plugin:0',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('展墙偏好按图源恢复，普通视图仍可原位展开', (tester) async {
    await LibraryPresentationStore.instance.save(
      'search:test-plugin',
      const LibraryPresentation(editorial: false, hero: false),
    );
    final settings = _Settings();
    final scroll = ScrollController();
    final canvas = GlobalKey<LibraryEditorialCanvasState>();
    addTearDown(settings.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SearchResultLibraryView(
              state: _state(),
              canvasKey: canvas,
              controller: scroll,
              source: 'test-plugin',
              onLoadMore: () {},
              onRetryLoadMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryEditorialTile), findsNothing);
    expect(find.byTooltip('展开信息'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
