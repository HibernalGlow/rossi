/// 生成 README 用的项目截图 —— 用 Flutter 自己把真页面画出来，不借助外部截图软件。
///
/// 跑法（**要 --update-goldens**，否则是在比对而不是生成）：
///
/// ```bash
/// flutter test --update-goldens tool/readme_shots/readme_shots_test.dart
/// ```
///
/// 产物直接落在 `assets/readme/shots/`：`<名字>.png` 是中文界面，`<名字>.en.png` 是英文界面。
///
/// # 为什么要这么绕
/// README 里的图得是**真组件**，不能是画出来的假 UI；可真跑 app 要么需要设备、要么需要
/// 一整套 ObjectBox + Rust 初始化。widget 测试这条路两头都躲开了：页面是真的、皮肤是真的
/// （`ColorScheme.fromSeed` 与 main.dart 同一个种子色），只是数据没接。
///
/// # 两个必须手动做的事
/// 1. **字体**：`flutter test` 默认字体是 Ahem，中文会全渲染成方块。这里显式用
///    `FontLoader` 把随包的霞鹜文楷挂成 `Roboto`（主题的默认族），再把 MaterialIcons
///    从 SDK 缓存里挂上，否则图标也是方块。
/// 2. **尺寸**：`tester.view.physicalSize` 按 2 倍像素比给，出图才是视网膜清晰度；
///    每个用例退出时还原，否则后面的用例会继承这个尺寸。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/setting/global/appearance_setting_page.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_example.dart';
import 'package:zephyr/main.dart';

import '../../test/test_helper.dart';

/// 与 `main.dart` 同一个种子色：默认主题那档「面具红」。
const _seed = Color(0xFF9C4B5E);

ThemeData _theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
);

Widget _app(Widget page, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(brightness),
      home: page,
    );

/// 把随包中文字体与 SDK 里的图标字体塞进测试引擎。
Future<void> _loadFonts() async {
  final cjk = FontLoader('Roboto')
    ..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf'));
  await cjk.load();

  final mono = FontLoader('JetBrainsMonoNL-Regular')
    ..addFont(rootBundle.load('asset/fonts/JetBrainsMonoNL-Regular.ttf'));
  await mono.load();

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      // 测试进程的可执行文件在 <flutter>/bin/cache/dart-sdk/bin/dart，
      // 往上数五层就是 SDK 根。
      Directory(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

/// 以 2× 像素比把画布固定成 [size]（逻辑像素）。
Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// 固定泵几帧：真页面上常驻动画（滚动指示、状态点）会让 `pumpAndSettle` 等到超时。
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 16)),
    );
    await tester.pump(const Duration(milliseconds: 32));
  }
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget page, {
  required Size size,
  Brightness brightness = Brightness.light,
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(_app(page, brightness: brightness));
  await _settle(tester);
  await afterPump?.call(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../assets/readme/shots/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    await TestObjectBoxHelper.setUpTestObjectBox();
  });
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
  });

  for (final locale in [AppLocale.zhCn, AppLocale.enUs]) {
    final suffix = locale == AppLocale.zhCn ? '' : '.en';
    final tag = suffix.isEmpty ? 'zh' : 'en';

    testWidgets('外观设置页 $tag', (tester) async {
      await tester.runAsync(() => LocaleSettings.setLocale(locale));
      final cubit = GlobalSettingCubit();
      addTearDown(cubit.close);
      await _shot(
        tester,
        'settings-appearance$suffix',
        BlocProvider.value(
          value: cubit,
          child: const AppearanceSettingPage(),
        ),
        size: const Size(1080, 752),
      );
    });

    testWidgets('图像处理对照 $tag', (tester) async {
      await tester.runAsync(() => LocaleSettings.setLocale(locale));
      await _shot(
        tester,
        'processing-trim$suffix',
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ProcessingExample(kind: ProcessingExampleKind.autoTrim),
          ),
        ),
        // 默认收起（收起时不加载图片），先点开再等解码
        size: const Size(720, 620),
        afterPump: (tester) async {
          await tester.tapAt(
            tester.getTopLeft(find.byType(ProcessingExample)) +
                const Offset(80, 30),
          );
          await _settle(tester, frames: 30);
        },
      );
    });
  }
}
