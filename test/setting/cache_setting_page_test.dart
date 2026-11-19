import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/cache/cache_setting_page.dart';

import '../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
  });

  tearDownAll(() async {
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(GlobalSettingCubit, WidgetTester)> pumpPage(
    WidgetTester tester, {
    CacheSettingState? initialCacheSetting,
  }) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cubit = GlobalSettingCubit();
    if (initialCacheSetting != null) {
      cubit.updateCacheSetting((_) => initialCacheSetting);
    }

    await tester.pumpWidget(
      TranslationProvider(
        child: BlocProvider<GlobalSettingCubit>.value(
          value: cubit,
          child: const MaterialApp(home: CacheSettingPage()),
        ),
      ),
    );
    // 泵固定数帧等待页面构建
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    return (cubit, tester);
  }

  testWidgets('完整渲染所有缓存与自动清理分组卡片', (tester) async {
    await pumpPage(tester);

    // 1. 当前缓存卡
    expect(find.text(t.cache.currentCache), findsOneWidget);
    expect(find.text(t.cache.totalCache), findsOneWidget);
    expect(find.text(t.cache.clearAll), findsOneWidget);

    // 2. 缓存分类明细卡
    expect(find.text(t.cache.categoryBreakdown), findsOneWidget);
    expect(find.text(t.cache.readerImageProcessing), findsWidgets);
    expect(find.text(t.cache.comicPages), findsOneWidget);
    expect(find.text(t.cache.thumbnailsAndCatalogs), findsOneWidget);
    expect(find.text(t.cache.videoPosters), findsOneWidget);

    // 3. 图片处理缓存专用自动清理设置卡
    expect(find.text(t.cache.readerImageProcessingAutoClean), findsWidgets);

    // 4. 全局自动清理与其它分类自动清理卡
    expect(find.text(t.cache.autoCleanSettings), findsOneWidget);
    expect(find.text(t.cache.autoClean), findsOneWidget);
    expect(find.text(t.cache.sizeLimit), findsOneWidget);
    expect(find.text(t.cache.autoCleanOnStartup), findsOneWidget);
    expect(find.text(t.cache.comicPagesAutoClean), findsOneWidget);
    expect(find.text(t.cache.thumbnailsAutoClean), findsOneWidget);
    expect(find.text(t.cache.videoPostersAutoClean), findsOneWidget);
  });

  testWidgets('切换图片处理缓存自动清理开关能正确更新状态', (tester) async {
    final (cubit, _) = await pumpPage(
      tester,
      initialCacheSetting: const CacheSettingState(
        autoCleanReaderImageProcessing: true,
      ),
    );

    expect(cubit.state.cacheSetting.autoCleanReaderImageProcessing, isTrue);

    // 找到图片处理自动清理开关并点击切换
    final switchFinder = find.widgetWithText(
      ListTile,
      t.cache.readerImageProcessingAutoClean,
    );
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(cubit.state.cacheSetting.autoCleanReaderImageProcessing, isFalse);
  });

  testWidgets('切换启动时自动清理开关能正确更新状态', (tester) async {
    final (cubit, _) = await pumpPage(
      tester,
      initialCacheSetting: const CacheSettingState(autoCleanOnStartup: true),
    );

    expect(cubit.state.cacheSetting.autoCleanOnStartup, isTrue);

    final switchFinder = find.widgetWithText(
      ListTile,
      t.cache.autoCleanOnStartup,
    );
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(cubit.state.cacheSetting.autoCleanOnStartup, isFalse);
  });

  testWidgets('切换漫画页面缓存与缩略图缓存自动清理开关能正确更新状态', (tester) async {
    final (cubit, _) = await pumpPage(
      tester,
      initialCacheSetting: const CacheSettingState(
        autoCleanComicPages: true,
        autoCleanThumbnails: false,
      ),
    );

    // 切换漫画页面自动清理
    final comicPagesSwitch = find.widgetWithText(
      ListTile,
      t.cache.comicPagesAutoClean,
    );
    await tester.tap(comicPagesSwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cubit.state.cacheSetting.autoCleanComicPages, isFalse);

    // 切换缩略图自动清理
    final thumbnailsSwitch = find.widgetWithText(
      ListTile,
      t.cache.thumbnailsAutoClean,
    );
    await tester.tap(thumbnailsSwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cubit.state.cacheSetting.autoCleanThumbnails, isTrue);
  });
}
