/// 设置页的**冒烟**验证：只验「能建起来、并且如实反映存储里的状态」。
///
/// 为什么要这条：页面的 `_load` 用 `Future.wait` 收五种不同类型的返回值再逐个 `as` 转型，
/// `dart analyze` 对这种转型一律照绿，只有真跑一次才知道拿错下标会不会当场炸。
library;

import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/ocr/ocr_setting_page.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_ocr_page_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    // 视口拉高：`ListView(children:)` 只建可见的那几行，默认 600 高的窗口里
    // 「模型权重」那段根本进不了树，`find` 会报「0 个」而不是「在屏幕外」。
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 必须走 runAsync：页面的 `_load` 做的是**真**文件 IO（临时目录列表），
    // 而 pump/pumpAndSettle 跑在 FakeAsync 里不会推进真实事件循环 ——
    // 直接 pumpAndSettle 的结果是永远卡在加载转圈上（实测超时）。
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: const OcrSettingPage()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    });
  }

  testWidgets('什么都没配：如实说还缺端点，并把 5 个权重全列为缺失', (tester) async {
    await pump(tester);
    expect(find.text(t.ocr.notConfigured), findsOneWidget);
    expect(find.textContaining(OcrModels.detFile), findsOneWidget);
    expect(find.textContaining(OcrModels.inpaintFile), findsOneWidget);
  });

  testWidgets('配好了：提示消失，存的值原样回填', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ocr_base_url': 'http://127.0.0.1:11434/v1',
      'ocr_model': 'qwen2.5:14b',
      'ocr_target_lang': 'en',
      'ocr_glossary': 'トカゲ=石龙子\n先生=老师',
    });
    await pump(tester);

    expect(find.text(t.ocr.notConfigured), findsNothing);
    expect(find.text('http://127.0.0.1:11434/v1'), findsOneWidget);
    expect(find.text('qwen2.5:14b'), findsOneWidget);
    expect(find.text('en'), findsOneWidget);
    // 术语表只铺第一条，多了省略：整段贴上去会把那行撑爆。
    expect(find.textContaining('トカゲ=石龙子'), findsOneWidget);
    expect(find.textContaining('先生=老师'), findsNothing);
  });

  testWidgets('API Key 在列表里是掩码，不裸奔', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ocr_base_url': 'https://x.example/v1',
      'ocr_model': 'm',
      'ocr_api_key': 'sk-super-secret',
    });
    await pump(tester);
    expect(find.textContaining('sk-super-secret'), findsNothing);
  });
}
