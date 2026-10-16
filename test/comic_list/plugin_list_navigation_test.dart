import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_cubit.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_navigation_controller.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_position_store.dart';
import 'package:zephyr/page/comic_list/view/plugin_list_navigation_host.dart';
import 'package:zephyr/widgets/library_viewport_anchor.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

import 'plugin_list_fixture.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('真实展墙用同一滚动控制器恢复远处卡片，重新布局后对齐偏移', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = PluginListPositionStore();
    await positions.save(
      'wall-resume',
      const PluginListPosition(page: 7, entryKey: 'plugin:7-40', offset: -10),
    );
    final list = cubit((page) async => response(page, count: 90));
    await list.loadInitial();
    final nav = PluginListNavigationController();
    final scroll = ScrollController();
    final registry = LibraryViewportRegistry();
    final canvas = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: list,
          child: Scaffold(
            body: PluginListNavigationHost(
              navigation: nav,
              positionStore: positions,
              scope: 'wall-resume',
              viewport: registry,
              scroll: scroll,
              canvasKey: canvas,
              child:
                  BlocBuilder<
                    PluginPagedComicListCubit,
                    PluginPagedComicListState
                  >(
                    builder: (_, state) => LibraryEditorialCanvas(
                      key: canvas,
                      scrollController: scroll,
                      scope: 'wall-resume-layout',
                      standalone: true,
                      initialPresentation: const LibraryPresentation(
                        hero: false,
                        asymmetric: false,
                        gapFill: LibraryGapFill.off,
                      ),
                      entries: [
                        for (final item in state.list)
                          LibraryEntry(
                            key: '${item.source}:${item.id}',
                            title: item.title,
                          ),
                      ],
                      wrapCard: (_, row, child) => LibraryViewportAnchor(
                        registry: registry,
                        entryKey: row.key,
                        child: child,
                      ),
                      cardBuilder: (_, row, tap) => Text(row.title),
                      legacyBuilder: (_) => const SizedBox(),
                      onTap: (_) {},
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
    final restore = nav.restore();
    await frames(tester);
    await restore;
    expect(nav.currentPage, 7);
    expect(registry.firstVisible()!.key, 'plugin:7-40');
    expect(registry.firstVisible()!.offset, closeTo(-10, .5));
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    scroll.dispose();
    nav.dispose();
    await list.close();
    await positions.read('wall-resume');
    expect(tester.takeException(), isNull);
  });

  testWidgets('直接恢复保存页与条目偏移，继续翻页显示实际可见页且重进不覆盖记录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = PluginListPositionStore();
    const scope = 'navigation-test';
    await positions.save(
      scope,
      const PluginListPosition(page: 35, entryKey: 'plugin:35-15', offset: -20),
    );
    final requests = <int>[];
    final list = cubit((page) async {
      requests.add(page);
      return response(page, count: 30);
    });
    final nav = PluginListNavigationController();
    final scroll = ScrollController();
    final registry = LibraryViewportRegistry();
    await list.loadInitial();

    Widget view() => MaterialApp(
      home: BlocProvider.value(
        value: list,
        child: Scaffold(
          body: PluginListNavigationHost(
            navigation: nav,
            positionStore: positions,
            scope: scope,
            viewport: registry,
            scroll: scroll,
            canvasKey: null,
            child:
                BlocBuilder<
                  PluginPagedComicListCubit,
                  PluginPagedComicListState
                >(
                  builder: (_, state) => ListView.builder(
                    controller: scroll,
                    itemExtent: 100,
                    itemCount: state.list.length,
                    itemBuilder: (_, index) {
                      final item = state.list[index];
                      return LibraryViewportAnchor(
                        registry: registry,
                        entryKey: '${item.source}:${item.id}',
                        child: Text(item.title),
                      );
                    },
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view());
    await frames(tester);
    expect(nav.currentPage, 1);
    expect(nav.savedPage, 35);
    expect((await positions.read(scope))!.page, 35);
    final restore = nav.restore();
    await frames(tester);
    await restore;
    expect(requests, [1, 35]);
    expect(nav.currentPage, 35);
    expect(scroll.offset, closeTo(1520, .5));
    expect(registry.firstVisible()!.key, 'plugin:35-15');
    expect(registry.firstVisible()!.offset, closeTo(-20, .5));

    await list.loadMore();
    await frames(tester);
    expect(nav.currentPage, 35, reason: '后台加载下一页不能提前改变当前可见页');
    scroll.jumpTo(3520);
    await frames(tester);
    expect(nav.currentPage, 36);
    final saved = (await positions.read(scope))!;
    expect(saved.page, 36);
    expect(saved.entryKey, 'plugin:36-5');
    expect(saved.offset, closeTo(-20, .5));

    await tester.pumpWidget(const SizedBox());
    await list.loadInitial();
    await tester.pumpWidget(view());
    await frames(tester);
    expect(nav.savedPage, 36);
    expect(nav.currentPage, 1);
    expect((await positions.read(scope))!.page, 36);
    final jump = nav.jumpToPage(72);
    await frames(tester);
    await jump;
    expect(requests, [1, 35, 36, 1, 72]);
    expect(nav.currentPage, 72);
    expect(scroll.offset, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await list.close();
    scroll.dispose();
    nav.dispose();
    expect(tester.takeException(), isNull);
  });
}
