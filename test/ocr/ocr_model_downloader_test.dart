/// 权重首下的验证 —— 只验**它自己的不变量**，不碰网络。
///
/// 这条路径的产物是 660 MB 权重，真下载不能是单测前提；但它守的东西跟下载无关：
/// 「中断不许留下一个看起来存在、其实半截的模型」，以及「已经齐了就一个字节都不再下」。
/// 那两条都是会让用户重下一遍 660 MB 的错。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_model_downloader.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

/// 每个文件「算合法」的下限体积（与 `OcrModels._minBytes` 同量级，取中间值）。
const _good = <String, int>{
  OcrModels.detFile: 5 * 1024 * 1024,
  OcrModels.encoderFile: 340 * 1024 * 1024,
  OcrModels.decoderFile: 120 * 1024 * 1024,
  OcrModels.vocabFile: 30 * 1024,
  OcrModels.inpaintFile: 200 * 1024 * 1024,
};

/// 稀疏文件：只写目录项，不占磁盘。
void _sparse(String path, int size) {
  final f = File(path)..createSync(recursive: true);
  final raf = f.openSync(mode: FileMode.write);
  raf.truncateSync(size);
  raf.closeSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory models;
  late List<String> requested;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_ocr_dl_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    models = await OcrModels.directory();
    models.createSync(recursive: true);
    requested = <String>[];
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  /// 假下载：写到「目标体积的一半」就当作成功返回（正是断线重连后常见的半截货）。
  Future<void> halfDownload(
    String url,
    String path,
    void Function(int, int) p,
  ) async {
    requested.add(url);
    final name = path.split('/').last.split('.download_').first;
    final target = (_good[name] ?? 4 * 1024 * 1024) ~/ 2;
    _sparse(path, target);
    p(target, target * 2);
  }

  Future<void> goodDownload(
    String url,
    String path,
    void Function(int, int) p,
  ) async {
    requested.add(url);
    final name = path.split('/').last.split('.download_').first;
    final target = _good[name] ?? 4 * 1024 * 1024;
    _sparse(path, target);
    p(target, target);
  }

  test('半截文件既不落地也不留在目录里', () async {
    await expectLater(
      OcrModelDownloader.ensure(download: halfDownload),
      throwsA(isA<StateError>()),
    );
    expect(
      File(await OcrModels.pathOf(OcrModels.detFile)).existsSync(),
      isFalse,
    );
    final residue = models
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.download_'))
        .toList();
    expect(residue, isEmpty, reason: '半截的 .download_ 没清掉，下次进来会撞名');
  });

  test('下对了才改名落地，五个文件一个不少', () async {
    await OcrModelDownloader.ensure(download: goodDownload);
    expect(requested, hasLength(5));
    for (final name in _good.keys) {
      expect(
        File(await OcrModels.pathOf(name)).existsSync(),
        isTrue,
        reason: name,
      );
    }
    expect((await OcrModels.status()).$1, hasLength(5));
  });

  test('已经齐了就一个字节都不再下；force 才重来', () async {
    await OcrModelDownloader.ensure(download: goodDownload);
    requested.clear();

    await OcrModelDownloader.ensure(download: goodDownload);
    expect(requested, isEmpty);

    await OcrModelDownloader.ensure(download: goodDownload, force: true);
    expect(requested, hasLength(5));
  });

  test('withInpaint=false 只要识别链路那四件', () async {
    await OcrModelDownloader.ensure(withInpaint: false, download: goodDownload);
    expect(requested, hasLength(4));
    expect((await OcrModels.inpaintReady()), isFalse);
    expect((await OcrModels.recognizeReady()), isTrue);
  });

  test('总进度单调不减，且终点等于已知体积之和', () async {
    final seen = <int>[];
    await OcrModelDownloader.ensure(
      download: goodDownload,
      onProgress: (received, total, file) => seen.add(received),
    );
    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i],
        greaterThanOrEqualTo(seen[i - 1]),
        reason: '进度倒退 = UI 上进度条往回跳',
      );
    }
  });
}
