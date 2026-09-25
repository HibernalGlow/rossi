/// **整摞东西接在一起**的验证：编排层 + 真翻译客户端 + 真回填 + 真缓存。
///
/// 各层单独都有测试了，但「谁把谁的输出喂给了谁」是另一类错的地方：
/// 翻译客户端解析出来的顺序错位、编排层把原文当译文画、缓存写到了另一个指纹目录里 ——
/// 这些在各自的单测里全都看不出来。所以这里只留一个假件：**分析那一跳**（要 660 MB 权重），
/// 其余全用生产实现：`OcrTranslator` 走真 HTTP（本地桩端点）、`TranslatedPageRenderer` 真画字、
/// `TranslatedPageCache` 真落盘。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

const _pageW = 400, _pageH = 300;
final _boxA = const ui.Rect.fromLTWH(40, 30, 140, 90);
final _boxB = const ui.Rect.fromLTWH(220, 160, 140, 90);

Future<Uint8List> _whitePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> _rgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

int _darkPixels(Uint8List rgba, int stride, ui.Rect rect) {
  var count = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * stride + x) * 4;
      if (rgba[i] < 128 && rgba[i + 1] < 128 && rgba[i + 2] < 128) count++;
    }
  }
  return count;
}

OcrBlock _block(ui.Rect r, String text) => OcrBlock(
  quad: Float32List.fromList([
    r.left,
    r.top,
    r.right,
    r.top,
    r.right,
    r.bottom,
    r.left,
    r.bottom,
  ]),
  text: text,
  boxes: 1,
  truncated: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nativeReady = false;
  String nativeError = '';
  late Directory root;
  late HttpServer server;
  final received = <String>[];

  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      received.add(body);
      // 桩按提示词里的编号回话：条数与顺序都必须对得上，否则编排层该抛。
      // 注意要**先解 JSON** 再数：提示词在请求体里是一整行转义过的字符串，
      // 直接按多行正则数会得到 0 条。
      final prompt =
          (((jsonDecode(body) as Map)['messages'] as List).last
                  as Map)['content']
              as String;
      final n = RegExp(r'^\d+\t', multiLine: true).allMatches(prompt).length;
      final content = List.generate(
        n,
        (i) => '${i + 1}\t〔中${i + 1}〕这是一句回填用的中文译文',
      ).join('\n');
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
        );
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() async {
    received.clear();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('rossi_ocr_stack_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  test('原文进请求、译文进画面、产物落进指纹目录', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了（HTTP 那一跳走不通）：$nativeError');
      return;
    }
    const sourceA = 'トカゲじゃ';
    const sourceB = 'あの田舎とかにいる!?';
    final page = TranslatedPageBuilder(
      analyze: (imagePath, erasedPath, ep) async {
        expect(ep, 'auto', reason: '分析那一跳该拿到设置里的默认策略');
        await File(
          erasedPath,
        ).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
        return OcrPageResult(
          blocks: [_block(_boxA, sourceA), _block(_boxB, sourceB)],
          pageWidth: _pageW,
          pageHeight: _pageH,
          detectMs: BigInt.one,
          recognizeMs: BigInt.one,
          inpaintMs: BigInt.one,
          erasedPath: erasedPath,
        );
      },
    );
    final config = OcrTranslationConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'stub',
    );

    final out = await page.build(
      imagePath: 'unused.jpg',
      pageIndex: 6,
      config: config,
    );

    // 1) 原文确实发出去了（两块的顺序与编号都在）
    expect(received, hasLength(1));
    expect(received.single, contains(sourceA));
    expect(received.single, contains(sourceB));

    // 2) 画上去的是**译文**，不是原文：拿「用原文渲染」的那张当对照，必须不一样。
    final drawn = await File(out.path).readAsBytes();
    final asSource = await TranslatedPageRenderer.render(
      erasedPng: await _whitePng(_pageW, _pageH),
      blocks: [_block(_boxA, sourceA), _block(_boxB, sourceB)],
      translations: [sourceA, sourceB],
    );
    expect(drawn, isNot(equals(asSource)), reason: '成品页与「原文直接回填」逐字节相同 = 画的是原文');

    // 3) 两块都有墨，且尺寸没变
    final rgba = await _rgba(drawn);
    expect(_darkPixels(rgba, _pageW, _boxA), greaterThan(200));
    expect(_darkPixels(rgba, _pageW, _boxB), greaterThan(200));

    // 4) 产物落在**指纹目录**里，目录名带着目标语言与模型名
    final label = (await TranslatedPageCache.describe(config: config)).label;
    expect(label, startsWith('zh-Hans_stub_'));
    expect(out.path, contains(label));
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 6),
      isTrue,
    );
    expect(
      File(
        '${root.path}/files/manga_translated/$label/manifest.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('端点回少了条数：降级成原文回填，且不进指纹缓存', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    // 桩按请求里的编号条数回复，这里只给一块 → 条数对不上，应当整页抛。
    final cfg2 = OcrTranslationConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'stub',
    );
    final page = TranslatedPageBuilder(
      analyze: (imagePath, erasedPath, ep) async {
        await File(
          erasedPath,
        ).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
        return OcrPageResult(
          blocks: [_block(_boxA, 'トカゲじゃ'), _block(_boxB, 'あの田舎とかにいる!?')],
          pageWidth: _pageW,
          pageHeight: _pageH,
          detectMs: BigInt.one,
          recognizeMs: BigInt.one,
          inpaintMs: BigInt.one,
          erasedPath: erasedPath,
        );
      },
      translate: (texts, cfg) async => const ['只有一条'],
    );
    final out = await page.build(
      imagePath: 'unused.jpg',
      pageIndex: 0,
      config: cfg2,
    );
    // ADR-0018 §决定 7 的降级档：端点不可用 / 模型漏译时出「擦字 + 原文回填」，
    // 而不是整页失败。
    expect(out.degraded, isTrue);
    expect(out.hasText, isTrue);
    expect(await File(out.path).exists(), isTrue, reason: '降级页也得能显示出来');

    final label = (await TranslatedPageCache.describe(config: cfg2)).label;
    expect(
      await TranslatedPageCache.isUsable(label: label, pageIndex: 0),
      isFalse,
      reason: '降级产物写进指纹缓存 = 端点恢复后永远端出这张未翻译的页',
    );

    // 画上去的确实是原文：与「拿原文直接回填」的对照逐字节相同。
    final asSource = await TranslatedPageRenderer.render(
      erasedPng: await _whitePng(_pageW, _pageH),
      blocks: [_block(_boxA, 'トカゲじゃ'), _block(_boxB, 'あの田舎とかにいる!?')],
      translations: const ['トカゲじゃ', 'あの田舎とかにいる!?'],
    );
    expect(await File(out.path).readAsBytes(), equals(asSource));
  });
}
