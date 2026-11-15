import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/cubit/bookshelf_search_cubit.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_page.dart';
import 'package:zephyr/util/rust_loader.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

import '../test_helper.dart';

/// 书架刷新必须能读到主 isolate 刚写入的封面；查询走 `store.runAsync`。
void main() {
  setUpAll(() async {
    await initRustLib(silent: true);
    await TestObjectBoxHelper.setUpTestObjectBox();
  });
  tearDownAll(() async {
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });
  tearDown(TestObjectBoxHelper.cleanComicFolderBoxes);

  Future<void> waitForCoverPath(WidgetTester tester, String path) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      // 推进 RefreshIndicator 的 snap 动画，onRefresh 才会真正触发。
      await tester.pump(const Duration(milliseconds: 200));
      final covers = find.byType(CoverWidget).evaluate();
      if (covers.any((e) => (e.widget as CoverWidget).path == path)) return;
    }
    throw StateError('等待封面 $path 超时');
  }

  Future<void> pumpShelf(
    WidgetTester tester, {
    required int refreshSignal,
  }) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>(create: (_) => GlobalSettingCubit()),
          BlocProvider<BookshelfSearchCubit>(
            create: (_) => BookshelfSearchCubit(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FolderShelfPage(
              mode: ShelfPageMode.download,
              isActive: true,
              refreshSignal: refreshSignal,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('下拉刷新读到主 isolate 更新后的封面', (tester) async {
    const uniqueKey = 'test:comic1';
    final record = createTestDownload(uniqueKey)
      ..cover =
          '{"id":"c1","url":"","path":"old.jpg","extern":{"path":"old.jpg"}}';
    objectbox.unifiedDownloadBox.put(record);
    ComicLinkService.addComic(uniqueKey, null, ComicFolderType.download);

    await pumpShelf(tester, refreshSignal: 0);
    await waitForCoverPath(tester, 'old.jpg');

    record
      ..cover =
          '{"id":"c2","url":"","path":"new.jpg","extern":{"path":"new.jpg"}}'
      ..updatedAt = DateTime.now().toUtc();
    objectbox.unifiedDownloadBox.put(record);

    // 内容不足一屏也要能触发 RefreshIndicator；用慢拖而不是 fling，
    // 避免被当成惯性滚动。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GridView)),
    );
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    await waitForCoverPath(tester, 'new.jpg');

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('刷新按钮读到主 isolate 更新后的封面', (tester) async {
    const uniqueKey = 'test:comic1';
    final record = createTestDownload(uniqueKey)
      ..cover =
          '{"id":"c1","url":"","path":"old.jpg","extern":{"path":"old.jpg"}}';
    objectbox.unifiedDownloadBox.put(record);
    ComicLinkService.addComic(uniqueKey, null, ComicFolderType.download);

    await pumpShelf(tester, refreshSignal: 0);
    await waitForCoverPath(tester, 'old.jpg');

    // 主 isolate 更新封面（编辑页保存）。
    record
      ..cover =
          '{"id":"c2","url":"","path":"new.jpg","extern":{"path":"new.jpg"}}'
      ..updatedAt = DateTime.now().toUtc();
    objectbox.unifiedDownloadBox.put(record);

    // 模拟书架刷新按钮：refreshSignal 变化。
    await pumpShelf(tester, refreshSignal: 1);
    await waitForCoverPath(tester, 'new.jpg');

    await tester.pump(const Duration(seconds: 5));
  });
}
