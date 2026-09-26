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
import 'package:zephyr/src/rust/frb_generated.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  /// 原生库要在 **FakeAsync 区之外**初始化一次：`testWidgets` 体里 await 一个真异步
  /// （`RustLib.init` 要 dlopen + 起线程）永远不会推进，只会等到 10 min 超时。
  /// 这条测试要问 Rust 侧要「本机各段落点」，而设置页拿不到时会安静地不画那一行
  /// （宁可不说，也不替构建撒谎），所以必须先确认原生库真的在 ——
  /// 否则那条「找不到文案」的断言会误报成页面错。
  var nativeReady = false;
  var nativeError = '';

  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
  });

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

  /// 泵到页面真的加载完（权重那一段进树）为止。
  ///
  /// 不写死次数：`_load` 那几条是**真**文件 IO，全仓一起跑、机器被 e2e 占满时
  /// 固定 6 次泵会不够，于是偶尔看到的还是加载转圈。
  /// 第三条（API Key 掩码）尤其吃这个：它断言的是「不该出现」，
  /// 页面还在转圈时它一样会绿 —— 那是假绿，不是通过。
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
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find.text(t.ocr.modelSection).evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('设置页 10 s 内没加载完');
        }
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
    // 先要「那一行画出来了」，再判「没有明文」—— 只看后半句的话，
    // 页面卡在加载转圈上也会绿，那是假绿。
    expect(find.textContaining('••••••'), findsOneWidget);
    expect(find.textContaining('sk-super-secret'), findsNothing);
  });

  testWidgets('推理后端那行下面，如实说本机各段会落到哪条 EP', (tester) async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了（$nativeError）');
      return;
    }
    await pump(tester);
    // 值来自 Rust 侧同一把尺子（`ocr_core::stage_ep_plan`）：Windows 上 auto 落成
    // 检测 cpu / 识别 directml / 擦字 directml，其余平台三段都是 cpu。
    final expected = Platform.isWindows
        ? t.ocr.epPlan(
            detect: 'cpu',
            recognize: 'directml',
            inpaint: 'directml',
          )
        : t.ocr.epPlan(detect: 'cpu', recognize: 'cpu', inpaint: 'cpu');
    expect(
      find.text(expected),
      findsOneWidget,
      reason: '选了 auto 就得说清本机各段实际会落到哪条 —— 这正是「不静默退回 CPU」的一半',
    );
  });
}
