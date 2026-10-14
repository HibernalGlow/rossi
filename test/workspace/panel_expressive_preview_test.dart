import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';

import '../test_helper.dart';

/// 把三块面板出成图，用来**用眼睛比**参照面板（阅读洞察）。
///
/// 出图方式沿用 `library_design_preview_test.dart` 那套
/// （`ROSSI_UI_PREVIEW_DIR=<目录> flutter test …`，一图一 test）。
/// 配色取暗色 + 仓里那支墨红 `0xff8b4148` 当种子，贴近截图那台机器的观感。
///
/// 这些用例断言的是「渲染没抛异常」，真正的判据是**产出的 PNG**：
/// 静态分析看不出圆角对不对、字重压不压迫、色档在暗底上够不够分。
const _seed = Color(0xff8b4148);

/// `flutter test` 不加载 FontManifest，中文全是豆腐块 —— 出图就没法判断字重与行高。
/// 霞鹜文楷在本仓是**运行时**用 FontLoader 注册的（不进 pubspec 的 `fonts:` 段），
/// 这里显式 loadFontFromList 一次，并把主题的字族指过去。
const _cjkFamily = 'PreviewCJK';

Future<void> _loadCjk() async {
  final bytes = File('asset/fonts/LXGWWenKaiLite-Regular.ttf').readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: _cjkFamily);
}

Future<void> _write(WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['ROSSI_UI_PREVIEW_DIR'];
  if (output == null) return;
  final context = boundary.currentContext;
  if (context == null) return;
  await tester.runAsync(() async {
    final image = await (context.findRenderObject()! as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required String panelId,
  required Size size,
  required GlobalKey boundary,
}) async {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  cubit.setActivePanel('right', panelId);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        // 右上角那条斜的「DEBUG」缎带会被拍进图里（测试里文字是方块，
        // 看上去像一处溢出）。
        debugShowCheckedModeBanner: false,
        // 少了 delegate，PopupMenuButton 会先抛 No MaterialLocalizations，
        // 它的 ErrorWidget 再把布局带偏。
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          fontFamily: _cjkFamily,
        ),
        home: Scaffold(
          backgroundColor: scheme.surface,
          // 桥接层必须在 MaterialApp **里面**：它要读 Localizations 祖先
          // （放外面直接抛 'a Localizations ancestor was not found'）。
          // 少了它，plat / 上游页面里的 legacy Material 会回退到 Flutter 的
          // 浅色主题 —— 出图就成了一张不真实的图。
          // ignore: deprecated_member_use
          body: MaterialUiCompatibilityBridge(
            child: ThemeShapeScope(
              radius: kDefaultPanelRadius,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: cubit),
                  BlocProvider(create: (_) => GlobalSettingCubit()),
                  BlocProvider(create: (_) => PluginRegistryCubit()),
                ],
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: const LanePanelHost(side: WorkspacePanelSide.right),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // 不用 pumpAndSettle：控制面板里那排共享节挂着不定进度转圈时永远等不到
  // （实测 pumpAndSettle timed out）。出图要的是「弹簧落位后的一帧」。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadCjk();
    TestObjectBoxHelper.setUpTestObjectBox();
  });
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  final boundary = GlobalKey();

  testWidgets('出图：信息面板（未开书，对齐截图右侧那个状态）', (tester) async {
    await _pumpPanel(
      tester,
      panelId: WorkspacePanelId.info,
      size: const Size(660, 1180),
      boundary: boundary,
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'info-empty');
  });

  testWidgets('出图：信息面板（开书后填上值）', (tester) async {
    final reader = ReaderSessionCoordinator.instance;
    reader.attachSession(
      comicId: 'preview-book',
      from: 'bika',
      title: '月光旅行者 第 12 话',
      epInfo: NormalComicEpInfo(epName: '夜航'),
      currentSlot: 7,
      totalSlots: 24,
      jumpToSlot: (_) async {},
    );
    addTearDown(() => reader.detachSession('preview-book'));
    await _pumpPanel(
      tester,
      panelId: WorkspacePanelId.info,
      size: const Size(660, 1180),
      boundary: boundary,
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'info-filled');
  });

  testWidgets('出图：控制面板', (tester) async {
    await _pumpPanel(
      tester,
      panelId: WorkspacePanelId.control,
      size: const Size(660, 1180),
      boundary: boundary,
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'control');
  });

  testWidgets('出图：发现面板（整页卡 + 两张插件小组件）', (tester) async {
    await _pumpPanel(
      tester,
      panelId: WorkspacePanelId.discover,
      size: const Size(660, 1180),
      boundary: boundary,
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'discover');
  });

  testWidgets('出图：信息面板窄泳道（320）', (tester) async {
    await _pumpPanel(
      tester,
      panelId: WorkspacePanelId.info,
      size: const Size(320, 1180),
      boundary: boundary,
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'info-narrow');
  });
}
