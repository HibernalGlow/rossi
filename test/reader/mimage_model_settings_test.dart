import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/mimage_model_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_engine_settings.dart';
import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

Future<void> _settleFileIO(WidgetTester tester) async {
  // 存在检查会跨多个文件系统 await；在真实 IO 和测试帧之间推进。
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('模型设置未结束加载');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('rossi_model_settings_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
  });
  tearDown(() async {
    await SuperResolutionLog.flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  testWidgets(
    'log viewer and clipboard contain the actual replacement result and output path',
    (tester) async {
      SuperResolutionLog.latestOutputPath = '/test/output.png';
      SuperResolutionLog.entries.value = ['第 1 页：文件已生成，但呈现器仍显示原图，替换失败。'];
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        SuperResolutionLog.entries.value = [];
        SuperResolutionLog.latestOutputPath = null;
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SuperResolutionLogControls())),
      );
      await tester.tap(find.text('复制日志'));
      await tester.pumpAndSettle();
      expect(copied, contains('替换失败'));
      expect(copied, contains('/test/output.png'));
      await tester.tap(find.text('查看超分日志'));
      await tester.pumpAndSettle();
      expect(find.text('超分日志'), findsOneWidget);
      expect(find.textContaining('替换失败'), findsOneWidget);
      expect(find.text('打开图片文件夹'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader settings exposes model controls without a ready GPU', (
    tester,
  ) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderSettingsSheet(context),
                child: const Text('打开阅读设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开阅读设置'));
    await tester.pump();
    await _settleFileIO(tester);
    expect(find.byType(MImageModelSettings), findsOneWidget);
    expect(find.text('自定义超分模型'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('mimage-model-selector')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isMacOS);

  testWidgets(
    'both engines remain selectable and retain separate model choices',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await RealSrSettings.saveMImageModel(MImageOnnxModel.anime6b);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SuperResolutionEngineSettings()),
          ),
        ),
      );
      await _settleFileIO(tester);
      await tester.tap(find.byKey(const ValueKey('apple-sr-engine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breeze 原生 CoreML').last);
      await _settleFileIO(tester);
      expect(find.text('倍率：原生 2×（由模型决定）'), findsOneWidget);
      expect(find.text('下载 Breeze 原生模型'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('breeze-coreml-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Real-CUGAN · 质量优先').last);
      await _settleFileIO(tester);
      expect((await RealSrSettings.loadCoreMLFamily()).id, 'realcugan');
      await tester.tap(find.byKey(const ValueKey('apple-sr-engine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mImage ONNX').last);
      await _settleFileIO(tester);
      expect(find.text(MImageOnnxModel.anime6b.fileName), findsOneWidget);
      expect(find.text('倍率：原生 4×（由模型决定）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apple-sr-engine')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breeze 原生 CoreML').last);
      await _settleFileIO(tester);
      expect(find.text('Real-CUGAN · 质量优先'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('breeze-coreml-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Real-ESRGAN x4plus · 照片/CG').last);
      await _settleFileIO(tester);
      expect(find.text('倍率：原生 4×（由模型决定）'), findsOneWidget);
      final esrganProfile = await RealSrSettings.loadProfile();
      expect(esrganProfile.engine, SuperResolutionEngine.breezeCoreML);
      expect(esrganProfile.coremlVariant.config['outputCrop'], 64);
      expect(
        esrganProfile.cacheKey,
        contains('RealESRGAN-x4plus.mlpackage_4x'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'native engine dispatch uses captured native model and true model scale',
    () async {
      final variant = CoreMLModelConfig.defaultVariant;
      final models = await CoreMLModelConfig.modelsDirectory;
      await models.create(recursive: true);
      await File('${models.path}/${variant.fileName}').writeAsBytes([1]);
      await RealSrSettings.saveEngine(
        SuperResolutionEngine.breezeCoreML,
      );
      expect(await RealSrSuperResolution.isAvailable, isTrue);
      final profile = await RealSrSettings.loadProfile();
      final nativeKey = profile.cacheKey;
      await RealSrSettings.saveEngine(
        SuperResolutionEngine.mimageOnnx,
      );
      expect(await RealSrSettings.loadCacheKey(), isNot(nativeKey));
      expect(await RealSrSuperResolution.isAvailable, isFalse);
      final input = File('${root.path}/input.png');
      await input.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
      final out = '${root.path}/output.png';
      Map<dynamic, dynamic>? arguments;
      const native = MethodChannel('coreml_upscale');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            arguments = call.arguments as Map<dynamic, dynamic>;
            await File(
              arguments!['outputPath'] as String,
            ).writeAsBytes([1, 2, 3]);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(native, null),
      );
      expect(
        await RealSrSuperResolution.upscale(
          inputPath: input.path,
          outputPath: out,
          engineProfile: profile,
        ),
        isTrue,
      );
      expect(arguments!['modelPath'], endsWith(variant.fileName));
      expect(arguments!['config']['scale'], 2);
      expect(arguments!['config']['blockSize'], 156);
      expect(
        await RealSrSettings.loadEngine(),
        SuperResolutionEngine.mimageOnnx,
      );
      await RealSrSettings.saveEngine(
        SuperResolutionEngine.breezeCoreML,
      );
      expect(await RealSrSettings.loadCacheKey(), nativeKey);
    },
    skip: !Platform.isMacOS,
  );

  testWidgets('model controls fit narrow reader and persist selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MImageModelSettings()),
        ),
      ),
    );
    // 文件存在检查使用真实临时目录，允许 IO 在真实异步区完成。
    await _settleFileIO(tester);
    expect(find.text('自定义超分模型'), findsOneWidget);
    expect(find.text('倍率：原生 4×（由模型决定）'), findsOneWidget);
    expect(find.text('导入本地 ONNX'), findsOneWidget);
    expect(find.text('下载当前模型'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mimage-model-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MImageOnnxModel.anime6b.label).last);
    await _settleFileIO(tester);
    expect(await RealSrSettings.loadMImageModel(), MImageOnnxModel.anime6b);
    expect(find.text(MImageOnnxModel.anime6b.fileName), findsOneWidget);
    expect(find.text('降噪：由模型固定，不支持单独调节强度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'import installs selected ONNX, revises cache, and preserves other models',
    () async {
      final previousKey = await RealSrSettings.loadCacheKey();
      final file = File('${root.path}/${MImageOnnxModel.realCugan4x.fileName}');
      await file.writeAsBytes(List.filled(2048, 1));
      await RealSrSuperResolution.importMImageModel(
        file.path,
        MImageOnnxModel.realCugan4x,
      );
      expect(await RealSrSettings.loadCacheKey(), isNot(previousKey));
      expect(
        await RealSrSuperResolution.isMImageModelAvailable(
          MImageOnnxModel.realCugan4x,
        ),
        isTrue,
      );
      await RealSrSettings.saveMImageModel(MImageOnnxModel.general);
      final general = File('${root.path}/${MImageOnnxModel.general.fileName}');
      await general.writeAsBytes(List.filled(2048, 2));
      await RealSrSuperResolution.importMImageModel(
        general.path,
        MImageOnnxModel.general,
      );
      expect(
        RealSrSuperResolution.manualDownloadUrl,
        endsWith(MImageOnnxModel.general.fileName),
      );
      await RealSrSuperResolution.deleteModel();
      expect(
        await RealSrSuperResolution.isMImageModelAvailable(
          MImageOnnxModel.general,
        ),
        isFalse,
      );
      expect(
        await RealSrSuperResolution.isMImageModelAvailable(
          MImageOnnxModel.realCugan4x,
        ),
        isTrue,
      );
    },
    skip: !Platform.isMacOS,
  );

  test('wrong model import does not replace the installed file', () async {
    final model = MImageOnnxModel.realCugan4x;
    final file = File('${root.path}/${model.fileName}');
    await file.writeAsBytes(List.filled(2048, 1));
    await RealSrSuperResolution.importMImageModel(file.path, model);
    await file.writeAsBytes([1]);
    await expectLater(
      RealSrSuperResolution.importMImageModel(file.path, model),
      throwsFormatException,
    );
    expect(await RealSrSuperResolution.isMImageModelAvailable(model), isTrue);
    await expectLater(
      RealSrSuperResolution.importMImageModel(
        file.path,
        MImageOnnxModel.general,
      ),
      throwsFormatException,
    );
  });
}
