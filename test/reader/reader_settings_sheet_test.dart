import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
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
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<GlobalSettingCubit>(
        create: (_) => _SheetGlobalSettingCubit(),
      ),
      BlocProvider(create: (_) => ComicReadPreferenceCubit()),
    ],
    child: MaterialApp(
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
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
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
    expect(find.byType(SpringLensBar), findsOneWidget, reason: '面板应已打开');
    expect(
      tester.widget<SpringLensBar>(find.byType(SpringLensBar)).tabs.length,
      5,
    );
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
    expect(find.byType(SpringLensBar), findsNothing, reason: '泳道外那一下必须把面板收回去');
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
    expect(find.byType(SpringLensBar), findsNothing, reason: '框体上方空白必须收回');
    expect(find.text('open'), findsOneWidget, reason: '不能多 pop 一层');

    // 卡片之内：点标题不能把面板关掉。
    await openSheet(tester);
    await tester.tap(find.text('阅读模式').first);
    await tester.pumpAndSettle();
    expect(find.byType(SpringLensBar), findsOneWidget, reason: '卡片内不该被当成空白');
    expect(find.text('open'), findsOneWidget);

    await tester.tapAt(const Offset(800, 30));
    await tester.pumpAndSettle();
    expect(find.byType(SpringLensBar), findsNothing);
  });

  testWidgets('宽栏里五排标签都带图标与文字', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 1200, fullWidth: 1600));
    await openSheet(tester);

    expect(find.byType(SpringLensBar), findsOneWidget, reason: '全局入口使用五项标签栏');
    for (final label in ['阅读', '手势', '界面', '画面', '翻译']) {
      expect(
        find.descendant(
          of: find.byType(SpringLensBar),
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
    final bar = tester.widget<SpringLensBar>(find.byType(SpringLensBar));
    expect(bar.tabs.length, 6);
    final perComicLabel = bar.tabs.last.semanticLabel!;
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

  testWidgets('窄到放不下文字时只画图标，图标还是五排', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(laneWidth: 300, fullWidth: 300));
    await openSheet(tester);

    expect(find.byType(SpringLensBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SpringLensBar),
        matching: find.text('阅读'),
      ),
      findsNothing,
      reason: '放不下文字时必须收成仅图标，而不是溢出成没人知道能滑的横滚',
    );
    // 图标只能限定在 tab 里找：`openBook` 同时是「阅读模式」那段的段落图标，
    // 全树去数会得到 2 颗 —— 那是这把尺子量错了对象，不是排版重复。
    for (final glyph in [
      AppGlyphs.openBook,
      AppGlyphs.touch,
      AppGlyphs.gridPlus,
      AppGlyphs.quality,
      AppGlyphs.translate,
    ]) {
      expect(
        find.descendant(
          of: find.byType(SpringLensBar),
          matching: find.byWidgetPredicate(
            (w) => w is GlyphIcon && w.glyph == glyph,
          ),
        ),
        findsOneWidget,
        reason: '$glyph 这一排的图标必须还在 tab 里',
      );
    }
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
}
