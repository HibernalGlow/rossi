import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/navigation/navigation_sidebar.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';

/// 「点空白收回」与五排标签布局的回归用例。
///
/// # 为什么形状要照着泳道搭
///
/// 阅读设置在真实 app 里挂在**阅读器泳道自己的局部 Navigator** 上
/// （`workspace_reader_host.dart:111`），并且那条泳道把 `MediaQuery.size`
/// 改写成泳道自己的尺寸（同文件 93-119 行）。用普通 `MaterialApp` 一层导航器去测，
/// 量到的是「整个窗口都是这条路由的 Overlay」那个理想情况 —— 恰好是坏掉那一格
/// 被测不到的原因。所以这里左栏一条、右边一条自己的 Navigator + 改写后的
/// MediaQuery，形状照抄。
final _laneSizeKey = UniqueKey();

class _SheetGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) {
    emit(state.copyWith(readSetting: updates(state.readSetting)));
  }
}

Future<void> _settle(WidgetTester tester) async {
  // 权重状态 / 成品页计数走真实文件系统，跨多个 await；在真实 IO 与测试帧之间推进。
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('面板没停下来');
}

Widget _harness({
  required double laneWidth,
  required double fullWidth,
  bool perComic = false,
  Brightness brightness = Brightness.light,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<GlobalSettingCubit>(
        create: (_) => _SheetGlobalSettingCubit(),
      ),
      BlocProvider(create: (_) => ComicReadPreferenceCubit()),
    ],
    child: TranslationProvider(
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8E526C),
            brightness: brightness,
          ),
          fontFamily:
              const String.fromEnvironment(
                'READER_SETTINGS_PREVIEW_DIR',
              ).isEmpty
              ? null
              : 'ReaderSettingsPreview',
        ),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('reader-settings-preview'),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: fullWidth - laneWidth,
                child: ColoredBox(
                  color: const Color(0xFF101010),
                  child: const Center(child: Text('other lane')),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  key: _laneSizeKey,
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: size),
                      child: Navigator(
                        onGenerateRoute: (settings) => MaterialPageRoute<void>(
                          settings: settings,
                          builder: (context) => Builder(
                            builder: (context) => TextButton(
                              onPressed: () => showReaderSettingsSheet(
                                context,
                                source: perComic ? 'test-source' : '',
                                comicId: perComic ? 'comic' : '',
                              ),
                              child: const Text('open'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    if (const String.fromEnvironment(
      'READER_SETTINGS_PREVIEW_DIR',
    ).isNotEmpty) {
      await (FontLoader(
            'ReaderSettingsPreview',
          )..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf')))
          .load();
    }
    // 「画面」那一排里的媒体格式表会走 `VideoSettingsStore` → FRB。
    // 写在 setUpAll 而不是某条 testWidgets 体里：后者会把这条测试挂到超时。
    await RustLib.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('rossi_settings_sheet_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => root.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(const ValueKey('reader-settings-panel')), findsOneWidget);
    expect(find.byTooltip(t.common.close), findsOneWidget);
  }

  testWidgets('泳道外的空白能收回面板，且只 pop 一次', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 800, fullWidth: 1200));
    await openSheet(tester);

    // 左栏在泳道之外：这条路由的遮罩盖不到那儿，所以要由全局指针路由接手。
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reader-settings-panel')),
      findsNothing,
      reason: '泳道外那一下必须把面板收回去',
    );
    // 只许 pop 一次：再多退一层，退掉的就是底下的阅读器页。
    expect(find.text('open'), findsOneWidget, reason: 'double-pop 会连阅读器页一起退掉');
    expect(find.text('other lane'), findsOneWidget);
  });

  testWidgets('泳道内的空白收回、卡片内不收回，两边不会抢同一下', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 800, fullWidth: 1200));

    // 框体上方：卡片只占泳道高 70%，上面那一截由框内那层点击层负责。
    await openSheet(tester);
    await tester.tapAt(const Offset(800, 30));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reader-settings-panel')),
      findsNothing,
      reason: '框体上方空白必须收回',
    );
    expect(find.text('open'), findsOneWidget, reason: '不能多 pop 一层');

    // 卡片之内：点标题不能把面板关掉。
    await openSheet(tester);
    await tester.tap(find.text('阅读模式').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reader-settings-panel')),
      findsOneWidget,
      reason: '卡片内不该被当成空白',
    );
    expect(find.text('open'), findsOneWidget);

    await tester.tapAt(const Offset(800, 30));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-settings-panel')), findsNothing);
  });

  testWidgets('宽栏复用项目侧栏，五项都有图标与文字', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1600));
    await openSheet(tester);

    expect(
      find.byKey(const ValueKey('reader-settings-panel')),
      findsOneWidget,
      reason: '全局入口使用五项标签栏',
    );
    for (final label in ['阅读', '手势', '界面', '画面', '翻译']) {
      expect(
        find.descendant(
          of: find.byType(NavigationSidebar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '$label 这一排要有文字，不能只剩图标',
      );
    }
    // 分组真落地了：手势那段跟着手势排走，而不是还堆在第一排。
    await tester.tap(find.text('手势'));
    await tester.pumpAndSettle();
    expect(find.text('翻页模式'), findsOneWidget);
    expect(find.text('阅读模式'), findsNothing);
    expect(tester.takeException(), isNull, reason: '卡片组的水波断言不能再抛');
  });

  testWidgets('漫画入口增加本漫标签，共用上游设置且保留独有全局选项', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(laneWidth: 1200, fullWidth: 1600, perComic: true),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    final bar = tester.widget<NavigationSidebar>(
      find.byType(NavigationSidebar),
    );
    expect(bar.destinations.length, 6);
    final perComicLabel = bar.destinations.last.label;
    await tester.tap(find.text(perComicLabel));
    await _settle(tester);
    expect(find.text('阅读模式'), findsOneWidget);
    expect(find.text('翻页模式'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('阅读'));
    await _settle(tester);
    expect(find.text(t.reader.readWhileDownloading), findsOneWidget);
    await tester.ensureVisible(find.text(t.reader.adaptive).first);
    await tester.tap(find.text(t.reader.adaptive).first);
    await _settle(tester);
    expect(find.text(t.reader.ambientDim), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄栏复用 Dock，分类入口保持可达且无溢出', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 300, fullWidth: 300));
    await openSheet(tester);
    final dock = tester.widget<NavigationDock>(find.byType(NavigationDock));
    expect(dock.destinations.length, 5);
    expect(find.byType(NavigationSidebar), findsNothing);
    for (final glyph in [
      AppGlyphs.openBook,
      AppGlyphs.touch,
      AppGlyphs.gridPlus,
      AppGlyphs.quality,
      AppGlyphs.translate,
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.byWidgetPredicate(
            (w) => w is GlyphIcon && w.glyph == glyph,
          ),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开前后只有一个关闭入口，窗口缩放保持当前分类', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1200));
    await openSheet(tester);
    await tester.tap(find.text('手势'));
    await _settle(tester);
    final initialHeight = tester
        .getSize(find.byKey(const ValueKey('reader-settings-panel')))
        .height;
    await tester.tap(find.byKey(const ValueKey('reader-settings-expand')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('reader-settings-panel')))
          .height,
      greaterThan(initialHeight),
    );
    expect(find.byTooltip(t.common.close), findsOneWidget);
    expect(find.text('翻页模式'), findsOneWidget);
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpWidget(_harness(laneWidth: 500, fullWidth: 500));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDock), findsOneWidget);
    expect(find.text('翻页模式'), findsOneWidget);
    expect(find.byTooltip(t.common.close), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-settings-panel')), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('阅读模式图标文字在横排与竖排中都居中，没有底部多余留白', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [1200.0, 390.0]) {
      tester.view.physicalSize = Size(width, 850);
      await tester.pumpWidget(_harness(laneWidth: width, fullWidth: width));
      await openSheet(tester);
      final choices = find.byWidgetPredicate(
        (widget) =>
            widget is SpringLensBar &&
            widget.tabs.any((tab) => tab.semanticLabel == t.reader.webtoon),
      );
      expect(choices, findsOneWidget);
      for (final label in [
        t.reader.webtoon,
        t.reader.singlePageLtr,
        t.reader.singlePageRtl,
      ]) {
        final slot = find.descendant(
          of: choices,
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          ),
        );
        final text = find.descendant(of: slot, matching: find.text(label));
        final icon = find.descendant(
          of: slot,
          matching: find.byType(GlyphIcon),
        );
        final rect = tester.getRect(slot);
        final textRect = tester.getRect(text);
        final iconRect = tester.getRect(icon);
        expect(textRect.center.dy, closeTo(rect.center.dy, 1));
        expect(iconRect.center.dy, closeTo(rect.center.dy, 1));
        expect(
          iconRect.expandToInclude(textRect).center.dx,
          closeTo(rect.center.dx, 1),
        );
        expect(rect.height, lessThanOrEqualTo(52));
      }
      await tester.tap(find.byKey(const ValueKey('reader-settings-close')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('正文上拖连续扩展到全屏后才滚内容，下拖可收回且仅一套关闭按钮', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1200));
    await openSheet(tester);
    final panel = find.byKey(const ValueKey('reader-settings-panel'));
    final scroll = find.byKey(const ValueKey('reader-settings-content-scroll'));
    final scrollable = find.descendant(
      of: scroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final initialHeight = tester.getSize(panel).height;
    final scrollRect = tester.getRect(scroll);
    final gesture = await tester.startGesture(
      Offset(scrollRect.left + 8, scrollRect.bottom - 40),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(panel).height, greaterThan(initialHeight));
    expect(tester.getSize(panel).height, lessThan(800));
    expect(position.pixels, 0, reason: '展开过程不会把正文一起滚走');
    await gesture.moveBy(const Offset(0, -300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), const Rect.fromLTWH(0, 0, 1200, 800));
    expect(find.byTooltip(t.common.close), findsOneWidget);
    await tester.dragFrom(
      Offset(tester.getRect(scroll).left + 8, 700),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: '全屏后继续拖动才滚动内容');
    await tester.dragFrom(
      tester.getCenter(find.text(t.reader.settings)),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, lessThan(800));
    expect(find.byTooltip(t.common.close), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标滚轮同样先展开面板再滚内容', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1000, fullWidth: 1000));
    await openSheet(tester);
    final panel = find.byKey(const ValueKey('reader-settings-panel'));
    final scroll = find.byKey(const ValueKey('reader-settings-content-scroll'));
    final initialHeight = tester.getSize(panel).height;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scroll),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, greaterThan(initialHeight));
    expect(find.byTooltip(t.common.close), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换侧栏与 Dock 保留当前分类正文的滚动位置', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1200));
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('reader-settings-expand')));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('reader-settings-content-scroll'));
    final scrollable = find.descendant(
      of: scroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(180);
    await tester.pump();
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpWidget(_harness(laneWidth: 500, fullWidth: 500));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDock), findsOneWidget);
    final newPosition = tester.state<ScrollableState>(scrollable).position;
    expect(newPosition, same(position));
    expect(newPosition.pixels, 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横向阅读的速度和高级延迟输入框在设置弹层内可编辑', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1200));
    final cubit = tester.element(find.text('open')).read<GlobalSettingCubit>();
    cubit.updateReadSetting((current) => current.copyWith(readMode: 1));
    await openSheet(tester);
    final speed = find.byType(TextField).first;
    await tester.ensureVisible(speed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(speed, '7.3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(cubit.state.readSetting.keyboardPageTurnPagesPerSecond, 7.3);
    final advanced = find.text(t.reader.keyboardPageTurnAdvanced);
    await tester.ensureVisible(advanced);
    await tester.pumpAndSettle();
    await tester.tap(advanced);
    await _settle(tester);
    final delay = find.byType(TextField).last;
    await tester.ensureVisible(delay);
    await tester.pumpAndSettle();
    await tester.enterText(delay, '600');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(cubit.state.readSetting.keyboardPageTurnHoldDelayMs, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('界面与画面两排各拿到该走的那几段', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1600));
    await openSheet(tester);

    await tester.tap(find.text('界面'));
    await tester.pumpAndSettle();
    expect(find.text('上下栏与边距'), findsOneWidget);
    expect(find.text('底部缩略图条'), findsOneWidget);

    await tester.tap(find.text('画面'));
    await _settle(tester);
    expect(find.text('画面处理'), findsOneWidget);
    expect(find.text('AI 超分辨率'), findsOneWidget);
  });

  for (final laneWidth in [1200.0, 430.0]) {
    testWidgets('缩略图比例在界面设置中修改，关闭胶卷不丢偏好：宽度=$laneWidth', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(laneWidth: laneWidth, fullWidth: 1600));
      await openSheet(tester);
      await tester.tap(find.text('界面'));
      await _settle(tester);
      final thumbnails = find.text(t.reader.thumbnailStrip);
      final cubit = tester.element(thumbnails).read<GlobalSettingCubit>();
      expect(
        cubit.state.readSetting.thumbnailStripOriginalAspectRatio,
        isFalse,
      );
      await tester.ensureVisible(thumbnails);
      await tester.pumpAndSettle();
      await tester.tap(thumbnails);
      await _settle(tester);
      final originalRatio = find.text(
        t.reader.thumbnailStripOriginalAspectRatio,
      );
      await tester.ensureVisible(originalRatio);
      await tester.pumpAndSettle();
      await tester.tap(originalRatio);
      await _settle(tester);
      expect(cubit.state.readSetting.thumbnailStripOriginalAspectRatio, isTrue);
      expect(
        find.byKey(const ValueKey('reader-thumbnail-aspect-toggle')),
        findsNothing,
      );
      await tester.ensureVisible(thumbnails);
      await tester.pumpAndSettle();
      await tester.tap(thumbnails);
      await _settle(tester);
      expect(cubit.state.readSetting.showThumbnailStrip, isFalse);
      expect(cubit.state.readSetting.thumbnailStripOriginalAspectRatio, isTrue);
      await tester.tap(thumbnails);
      await _settle(tester);
      expect(cubit.state.readSetting.showThumbnailStrip, isTrue);
      expect(cubit.state.readSetting.thumbnailStripOriginalAspectRatio, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('翻译排里有自动译开关、引擎与日志入口', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1600));
    await openSheet(tester);

    await tester.tap(find.text('翻译'));
    await _settle(tester);
    expect(find.text('翻到新的一页自动译'), findsOneWidget);
    expect(find.text('译文引擎'), findsOneWidget);
    expect(find.text('翻译日志'), findsWidgets);

    // 开关要真的落到那份存储里，而不是只画一颗常亮的灯。
    await tester.tap(find.text('翻到新的一页自动译'));
    await _settle(tester);
    expect(await OcrSettings.loadAutoTranslatePage(), isTrue);
    // 只改这一颗，不能顺手把端点配置清空。
    expect(await OcrSettings.loadDraft(), isNotNull);
  });

  if (const String.fromEnvironment('READER_SETTINGS_PREVIEW_DIR').isNotEmpty) {
    for (final width in [520.0, 1200.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('阅读设置视觉预览 $width ${brightness.name}', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _harness(
              laneWidth: width,
              fullWidth: width,
              brightness: brightness,
            ),
          );
          await openSheet(tester);
          await captureSettings(
            tester,
            '${width.toInt()}-${brightness.name}-partial',
          );
          final scroll = tester.getRect(
            find.byKey(const ValueKey('reader-settings-content-scroll')),
          );
          await tester.dragFrom(
            Offset(scroll.left + 8, scroll.bottom - 40),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          await captureSettings(
            tester,
            '${width.toInt()}-${brightness.name}-full',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Future<void> captureSettings(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('READER_SETTINGS_PREVIEW_DIR');
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('reader-settings-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
