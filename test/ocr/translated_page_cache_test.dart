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
import 'package:zephyr/service/ocr/translated_page_layer.dart';
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

  test('老版本降级目录里那张没翻译的，不算进「已生成 N 张」', () async {
    final png = await _realPng();
    await put(png);
    expect(await TranslatedPageCache.pageCount(), 1);
    // 这条档已经没有了（翻译失败现在整页失败），但用户盘上老版本留下的那张还在：
    // 「已生成 N 张」把没翻译的页报成产物，就是虚报。
    final legacy = Directory(
      p.join((await OcrService.outputRoot()).path, 'manga_translated_degraded'),
    );
    await legacy.create(recursive: true);
    await File(p.join(legacy.path, 'p3.png')).writeAsBytes(png, flush: true);
    expect(await TranslatedPageCache.pageCount(), 1);
    // 「在受管根目录下」的实际含义：那颗「清空成品页」的按钮管得到它。
    await TranslatedPageCache.clearAll();
    expect(await legacy.exists(), isFalse);
  });

  group('overlayDisplayable：叠层能不能直接显示', () {
    TranslatedPageLayer buildLayer({required bool filled}) =>
        TranslatedPageLayer(
          pageWidth: 200,
          pageHeight: 120,
          boxes: [
            // 填色是一框一份：全页有没有可用底，就看这些框是不是都有色。
            TranslatedBox(
              quad: const [20.0, 20.0, 160.0, 20.0, 160.0, 100.0, 20.0, 100.0],
              source: 'トカゲじゃ',
              text: '是蜥蜴啊',
              fill: filled ? const ui.Color.fromARGB(255, 255, 255, 255) : null,
            ),
          ],
        );

    Future<void> putLayer(TranslatedPageLayer layer) =>
        TranslatedPageCache.writeLayer(
          label: label,
          pageIndex: 0,
          json: layer.encode(),
        );

    test('每框都有填色：不需要擦字底图也算可用', () async {
      // 这一格钉的是「跳过擦字」那条路的命中判据：那一趟既不写 PNG 也不写底图，
      // 按「必须有 base 文件」判就永远 miss，每次上屏重跑那十几秒。
      await putLayer(buildLayer(filled: true));
      expect(
        await (await TranslatedPageCache.baseFile(
          label: label,
          pageIndex: 0,
        )).exists(),
        isFalse,
        reason: '前提没搭对：这一格要的就是「没有底图文件」',
      );
      expect(
        await TranslatedPageCache.overlayDisplayable(label: label, pageIndex: 0),
        isTrue,
      );
    });

    test('有框没填色、底图又不在：判不可用，而不是端出一张字压字的页', () async {
      await putLayer(buildLayer(filled: false));
      expect(
        await TranslatedPageCache.overlayDisplayable(label: label, pageIndex: 0),
        isFalse,
      );
    });

    test('补擦过底图之后：同一份图层就可用了', () async {
      await putLayer(buildLayer(filled: false));
      await (await TranslatedPageCache.baseFile(
        label: label,
        pageIndex: 0,
      )).create(recursive: true);
      expect(
        await TranslatedPageCache.overlayDisplayable(label: label, pageIndex: 0),
        isTrue,
      );
    });

    test('图层解坏了：判不可用而不是抛，也不拿半份数据画', () async {
      await (await TranslatedPageCache.layerFile(
        label: label,
        pageIndex: 0,
      )).create(recursive: true);
      await (await TranslatedPageCache.layerFile(
        label: label,
        pageIndex: 0,
      )).writeAsString('{"boxes": [ 坏掉的', flush: true);
      expect(
        await TranslatedPageCache.overlayDisplayable(label: label, pageIndex: 0),
        isFalse,
      );
    });
  });
}
