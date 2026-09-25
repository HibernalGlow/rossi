/// 冒烟页的构建期验证：不点下载、不跑链路，只看它把状态**说对了**没有。
///
/// 这页存在的意义就是「把六道关摊开给人看」，所以它自己报错了就等于整个工具失效。
/// 与设置页那条同理：`initState` 里是真文件 IO，必须 runAsync，否则永远停在查询中。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/debug/ocr_smoke_debug_page.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_ocr_smoke_page_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  /// 泵到页面真的把状态跑出来为止。
  ///
  /// 不能只泵固定的 6 次：`initState` 里那次 `OcrModels.status()` 是**真文件 IO**
  /// （查目录 + 逐个 stat 权重体积），全仓一起跑、机器被 e2e 那条占满时
  /// 300 ms 不够用，于是偶尔看到的一直是「权重状态查询中…」。
  Future<void> pumpUntil(WidgetTester tester, bool Function() settled) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: const OcrSmokeDebugPage()));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!settled()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('冒烟页 10 s 内没把状态跑出来');
        }
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    });
  }

  testWidgets('没下过权重：如实报缺 5 个，并把每个文件名列出来', (tester) async {
    await pumpUntil(
      tester,
      () => find.textContaining('缺 5 个').evaluate().isNotEmpty,
    );
    expect(find.text('权重状态查询中…'), findsNothing);
    expect(find.textContaining('缺 5 个'), findsOneWidget);
    expect(find.textContaining(OcrModels.detFile), findsOneWidget);
    expect(find.textContaining(OcrModels.inpaintFile), findsOneWidget);
  });

  testWidgets('没选页时开跑是灰的，后端那行说明 auto 的语义', (tester) async {
    await pumpUntil(
      tester,
      () => find.textContaining('推理后端').evaluate().isNotEmpty,
    );
    expect(find.text('还没选页'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开跑'),
    );
    expect(button.onPressed, isNull, reason: '没选页就能点 = 跑一次必然失败的链路');
    expect(
      find.textContaining('推理后端（请求值）：auto'),
      findsOneWidget,
      reason: '这行必须说清是请求值，不是实际生效的那条 EP',
    );
  });
}
