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

import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
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
    await OcrLog.flush();
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
          stageEps: const OcrStageEps(
            detect: 'cpu',
            recognize: 'cpu',
            inpaint: 'cpu',
          ),
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

  test('翻译那一跳失败：整页失败，不产出「擦字又画回原文」那种假成品', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
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
          stageEps: const OcrStageEps(
            detect: 'cpu',
            recognize: 'cpu',
            inpaint: 'cpu',
          ),
        );
      },
      translate: (texts, cfg) async => const ['只有一条'],
    );

    // 端点档本身就是所选那一档，没有第二档可问 → 必须抛，而不是端出一张没翻译的页。
    await expectLater(
      page.build(imagePath: 'unused.jpg', pageIndex: 0, config: cfg2),
      throwsA(isA<OcrTranslationException>()),
    );

    // 抛了就不许留下任何产物：那张「降级页」曾经会进持久目录，
    // 芯片一句「原文回填」滑过去，用户读到的是被擦过又重新画上日文的页。
    // （失败的那一页连目录都不该建起来，所以这里要先问在不在。）
    final root = await OcrService.outputRoot();
    final leftovers = await root.exists()
        ? await root
              .list(recursive: true, followLinks: false)
              .where((e) => e is File && e.path.endsWith('.png'))
              .toList()
        : const <FileSystemEntity>[];
    expect(
      leftovers,
      isEmpty,
      reason: '失败的一页在 ${root.path} 里留下了产物：$leftovers',
    );
    expect(
      OcrLog.log.entries.value.join('\n'),
      contains('按失败处理'),
      reason: '失败原因必须留痕：界面上那句提示几秒就被下一次点击顶掉了',
    );
  });

  test('端侧档挂了且端点已配：回落端点，产物记在**端点档**的指纹下', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    const sourceA = 'トカゲじゃ';
    // 回落档是从 prefs 的原样快照里读的，所以这里要把端点字段**存进去**，
    // 而不是只改传进来的 config —— 只改 config 等于测了一条生产走不到的路。
    SharedPreferences.setMockInitialValues({
      'ocr_base_url': 'http://127.0.0.1:${server.port}/v1',
      'ocr_model': 'stub',
    });
    final appleConfig = OcrTranslationConfig(
      baseUrl: '',
      model: '',
      engine: OcrTranslateEngine.appleOnDevice,
    );
    final asked = <OcrTranslateEngine>[];
    final page = TranslatedPageBuilder(
      analyze: (imagePath, erasedPath, ep) async {
        await File(
          erasedPath,
        ).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
        return OcrPageResult(
          blocks: [_block(_boxA, sourceA)],
          pageWidth: _pageW,
          pageHeight: _pageH,
          detectMs: BigInt.one,
          recognizeMs: BigInt.one,
          inpaintMs: BigInt.one,
          erasedPath: erasedPath,
          stageEps: const OcrStageEps(
            detect: 'cpu',
            recognize: 'cpu',
            inpaint: 'cpu',
          ),
        );
      },
      translate: (texts, cfg) async {
        asked.add(cfg.engine);
        if (cfg.engine == OcrTranslateEngine.appleOnDevice) {
          // 真机上那一跳的成因是语言包没装（TranslationError.notInstalled）。
          throw OcrTranslationException('Apple 系统翻译不可用：notInstalled');
        }
        return const ['〔中1〕这是一句回填用的中文译文'];
      },
    );

    final out = await page.build(
      imagePath: 'unused.jpg',
      pageIndex: 2,
      config: appleConfig,
    );

    expect(asked, [OcrTranslateEngine.appleOnDevice, OcrTranslateEngine.endpoint]);
    // 关键的一条：产物**不能**记在 Apple 档名下。否则用户把语言包装上之后，
    // 这一页会永远命中这张端点翻出来的图，而指纹声称它是 Apple 的产物。
    final appleLabel = (await TranslatedPageCache.describe(config: appleConfig))
        .label;
    expect(out.path, isNot(contains(appleLabel)));
    expect(
      out.path,
      contains('zh-Hans_stub_'),
      reason: '译文出自端点档，就该落在端点档的目录里',
    );
    expect(
      OcrLog.log.entries.value.join('\n'),
      contains('回落 endpoint'),
    );
  });
}
