/// CoreML 超分模型的**落点**测试。
///
/// 只守一条不变量：模型必须在持久目录里。曾经它解在 `$TMPDIR/coreml_models/`，
/// 而 macOS 的 dirhelper 每天清临时目录里 3 天没动过的文件 —— 就绪判据又只看这个
/// 目录里有没有文件，结果就是「明明下过，每次启动还要重下一整包」。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/util/coreml_model_loader.dart';
import 'package:zephyr/util/get_path.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_coreml_loc_test_');
    // 桩把两问都答成同一个 root：临时目录 = root，AppSupport = root。
    // 于是「新址在 root/files 下、旧址在 root 下」这种差别就是被测的东西。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  test('模型根目录在 files/super_resolution 下，不在临时目录里', () async {
    final dir = await CoreMLModelConfig.modelsDirectory;
    final files = await getFilePath();
    final legacy = await CoreMLModelConfig.legacyModelsDirectory;

    expect(
      dir.path,
      p.join(files, 'super_resolution', 'coreml_models', 'MacOS-iOS'),
    );
    expect(dir.path, isNot(legacy.path));
    expect(dir.path, isNot(root.path));
  });

  // 搬迁由启动期显式调（`main.dart`），所以这里也是显式调 —— 它不再依赖「进程内第一次
  // 访问」那种隐式时机。
  test('旧临时目录里那一份会被搬到新址，不需要重下', () async {
    final legacy = await CoreMLModelConfig.legacyModelsDirectory;
    legacy.createSync(recursive: true);
    final variant = CoreMLModelConfig.defaultVariant;
    File(p.join(legacy.path, variant.fileName)).writeAsStringSync('权重占位');

    await CoreMLModelLoader.migrateFromLegacyTemp();

    final moved = File(
      p.join((await CoreMLModelConfig.modelsDirectory).path, variant.fileName),
    );
    expect(await CoreMLModelLoader.isModelAvailable(variant.fileName), isTrue);
    expect(moved.existsSync(), isTrue, reason: '没搬到持久目录，下次清临时目录又要重下');
    expect(File(p.join(legacy.path, variant.fileName)).existsSync(), isFalse);
  });
}
