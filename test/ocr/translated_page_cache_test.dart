/// 成品页缓存「能不能用」的判据。
///
/// ADR-0018 §决定 3 要求产物缺失或损坏时**静默回落到原图**，
/// 而 `exists()` 把「存在」当成「可用」—— 半张 PNG 会被当成可用交下去，
/// 最后表现为呈现器拒绝注入并给用户弹一条他无法行动的错。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

OcrBlock _block() => OcrBlock(
  quad: Float32List.fromList([20, 20, 160, 20, 160, 100, 20, 100]),
  text: 'トカゲじゃ',
  boxes: 1,
  truncated: false,
);

Future<Uint8List> _realPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 200, 120),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(200, 120);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String label;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_ocr_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    SharedPreferences.setMockInitialValues({});
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(baseUrl: 'https://x/v1', model: 'm'),
    );
    label = (await TranslatedPageCache.describe(
      config: const OcrTranslationConfig(baseUrl: 'https://x/v1', model: 'm'),
      modelTag: 'fixed',
    )).label;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  Future<void> put(Uint8List bytes) async {
    await TranslatedPageCache.write(
      label: label,
      pageIndex: 0,
      pngBytes: bytes,
    );
  }

  Future<File> target() =>
      TranslatedPageCache.pageFile(label: label, pageIndex: 0);

  test('正常渲染出来的成品：判为可用', () async {
    final png = await TranslatedPageRenderer.render(
      erasedPng: await _realPng(),
      blocks: [_block()],
      translations: const ['是蜥蜴啊'],
    );
    await put(png);
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 0),
      isTrue,
    );
  });

  test('尾巴被截掉：判为不可用（IEND 不在了）', () async {
    final png = await _realPng();
    await put(Uint8List.fromList(png.sublist(0, png.length - 8)));
    expect(
      await File((await target()).path).exists(),
      isTrue,
      reason: '文件确实在，只是坏了',
    );
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 0),
      isFalse,
    );
  });

  test('开头是 PNG 签名但内容是垃圾：判为不可用', () async {
    final f = await target();
    await f.parent.create(recursive: true);
    final junk = Uint8List(4096);
    junk.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    await f.writeAsBytes(junk, flush: true);
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 0),
      isFalse,
    );
  });

  test('小到不像一张图：判为不可用', () async {
    final f = await target();
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Uint8List(16), flush: true);
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 0),
      isFalse,
    );
  });

  test('没有文件：判为不可用而不是抛', () async {
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 7),
      isFalse,
    );
  });

  test('降级产物写在持久根目录下，但不进指纹目录', () async {
    final f = await TranslatedPageCache.writeDegraded(
      pageIndex: 7,
      pngBytes: await _realPng(),
    );
    // 落点必须在 outputRoot 里：系统临时目录会被 dirhelper 每天扫一次，
    // 而呈现器是按归属表里这个路径重注入的 —— 被扫走就等于正在显示的页静默变回原图。
    expect(p.isWithin((await OcrService.outputRoot()).path, f.path), isTrue);
    expect(await f.exists(), isTrue);
    // 同一个页号在缓存那一侧仍然「没有可用产物」：降级档不进指纹缓存，
    // 否则端点恢复之后永远端出这张没翻译的页。
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 7),
      isFalse,
    );
    // 「在受管根目录下」的实际含义：设置页那颗「清空成品页」的按钮管得到它。
    // 写在系统临时目录里的那一版是管不到的 —— 它会自己在一个没人知道的时间消失。
    await TranslatedPageCache.clearAll();
    expect(await f.exists(), isFalse);
  });

  test('已生成张数不把降级产物算进去', () async {
    final png = await _realPng();
    await put(png);
    expect(await TranslatedPageCache.pageCount(), 1);
    await TranslatedPageCache.writeDegraded(pageIndex: 3, pngBytes: png);
    expect(
      await TranslatedPageCache.pageCount(),
      1,
      reason: '「已生成 N 张」把没翻译的那张报成产物，就是虚报',
    );
  });
}
