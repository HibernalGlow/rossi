/// 成品页**编排层**的验证。
///
/// 三个阶段各自都有单测了，但他们**串起来**的行为是另一类错的地方，逐条守住：
/// 缓存命中不许再跑分析（分析一页 ~14 s）、换目标语言必须失效（否则用户会看到旧译）、
/// 无文字的页直接返回原图（不占缓存）、取消之后不许留下半成品、
/// 擦字中间产物不许漏进缓存目录（用户分不清哪个是成品）。
///
/// 分析端与翻译端都注入假的：真权重 660 MB、真端点要网络，都不该是单测的前提。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

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

OcrBlock _block(ui.Rect r, {String text = 'トカゲじゃ', bool truncated = false}) => OcrBlock(
  quad: Float32List.fromList([
    r.left, r.top, r.right, r.top, r.right, r.bottom, r.left, r.bottom,
  ]),
  text: text,
  boxes: 1,
  truncated: truncated,
);

const _pageW = 400, _pageH = 300;
final _boxA = const ui.Rect.fromLTWH(40, 30, 140, 90);

/// 假的分析端：把「擦干净的底图」写到 Rust 侧应该在的位置，并记下调用次数与
/// 那一刻该文件是否真的落盘（编排层把路径交出去、又指望它存在，这条必须验）。
class _FakeAnalyze {
  _FakeAnalyze(this.blocks);

  final List<OcrBlock> blocks;
  int calls = 0;
  bool erasedSeenAtCallTime = false;
  String? lastErasedPath;
  String? lastEp;

  Future<OcrPageResult> call(String imagePath, String erasedPath, String ep) async {
    calls++;
    lastEp = ep;
    lastErasedPath = erasedPath;
    // 正常链路里这张图是 Rust 写的；这里替它写一张纯白底。
    await File(erasedPath).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
    erasedSeenAtCallTime = await File(erasedPath).exists();
    return OcrPageResult(
      blocks: blocks,
      pageWidth: _pageW,
      pageHeight: _pageH,
      detectMs: BigInt.from(190),
      recognizeMs: BigInt.from(3700),
      inpaintMs: BigInt.from(1700),
      erasedPath: erasedPath,
    );
  }
}

class _FakeTranslate {
  _FakeTranslate(this.reply);

  final List<String> Function(List<String> texts) reply;
  int calls = 0;
  List<String>? lastTexts;

  Future<List<String>> call(List<String> texts, OcrTranslationConfig config) async {
    calls++;
    lastTexts = texts;
    return reply(texts);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late OcrTranslationConfig config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('rossi_ocr_build_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    config = const OcrTranslationConfig(
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'hello-world',
      targetLanguage: 'zh-Hans',
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  TranslatedPageBuilder builderWith(_FakeAnalyze a, _FakeTranslate t) =>
      TranslatedPageBuilder(analyze: a.call, translate: t.call);

  test('首建走完整链路，成品落进缓存且真有墨', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final translate = _FakeTranslate((texts) => ['是蜥蜴啊']);

    final out = await builderWith(analyze, translate).build(
      imagePath: '/nonexistent/page.jpg',
      pageIndex: 0,
      config: config,
    );

    expect(analyze.calls, 1);
    expect(analyze.lastEp, 'cpu', reason: '没设置过就该走实测最快的默认档');
    expect(translate.lastTexts, ['トカゲじゃ'], reason: '送翻译的必须是识别出来的原文');
    expect(analyze.erasedSeenAtCallTime, isTrue, reason: '底图没落盘就去画，成品会是空的');
    expect(out.fromCache, isFalse);
    expect(out.hasText, isTrue);
    expect(out.blockCount, 1);

    final file = File(out.path);
    expect(await file.exists(), isTrue);
    final rgba = await _rgba(await file.readAsBytes());
    expect(_darkPixels(rgba, _pageW, _boxA), greaterThan(200), reason: '译文没画上去');

    // 缓存目录里只该有成品与清单：擦字中间产物漏进来，用户就分不清哪张是成品页。
    final dir = file.parent;
    expect(
      (await dir.list().map((e) => e.uri.pathSegments.last).toList())..sort(),
      ['manifest.json', 'p0.png'],
    );
    final manifest = await File('${dir.path}/manifest.json').readAsString();
    expect(manifest, contains('zh-Hans'));
    expect(analyze.lastErasedPath, startsWith(Directory.systemTemp.path));
  });

  test('再建命中缓存，一次分析都不许重跑', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));

    final first = await b.build(imagePath: 'p.jpg', pageIndex: 3, config: config);
    final again = await b.build(imagePath: 'p.jpg', pageIndex: 3, config: config);

    expect(again.fromCache, isTrue);
    expect(again.path, first.path);
    expect(analyze.calls, 1, reason: '一页分析 ~14 s，命中缓存还重跑等于没有缓存');
  });

  test('force 重算，覆盖旧产物', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));
    await b.build(imagePath: 'p.jpg', pageIndex: 0, config: config);

    final forced = await b.build(imagePath: 'p.jpg', pageIndex: 0, config: config, force: true);

    expect(analyze.calls, 2);
    expect(forced.fromCache, isFalse);
  });

  test('换目标语言 / 换术语表都必须让缓存失效', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));
    await b.build(imagePath: 'p.jpg', pageIndex: 0, config: config);

    final en = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 0,
      config: config.copyWith(targetLanguage: 'en'),
    );
    expect(analyze.calls, 2, reason: '语言变了还端旧译，是最难自查的一类错');
    expect(en.fromCache, isFalse);

    final glossed = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 0,
      config: config.copyWith(glossary: 'トカゲ=石龙子'),
    );
    expect(analyze.calls, 3, reason: '术语表进指纹：改一个词就该重译');
    expect(glossed.fromCache, isFalse);
  });

  test('无文字的页返回原图，不写缓存', () async {
    final analyze = _FakeAnalyze(const []);
    final translate = _FakeTranslate((_) => const []);
    final original = '${root.path}/plain.jpg';
    await File(original).writeAsBytes(await _whitePng(_pageW, _pageH));

    final out = await builderWith(analyze, translate).build(
      imagePath: original,
      pageIndex: 0,
      config: config,
    );

    expect(out.hasText, isFalse);
    expect(out.path, original, reason: '擦不擦都一样的页，不该被换成一份缓存副本');
    expect(translate.calls, 0, reason: '没台词就别发翻译请求，白烧一次 token');
    expect(await TranslatedPageCache.has(label: (await TranslatedPageCache.describe(config: config)).label, pageIndex: 0), isFalse);
  });

  test('设置里选的后端真的传到分析那一跳（否则选择器是个骗人的控件）', () async {
    SharedPreferences.setMockInitialValues({'ocr_ep': 'coreml'});
    final analyze = _FakeAnalyze([_block(_boxA)]);
    await builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊'])).build(
      imagePath: 'p.jpg',
      pageIndex: 0,
      config: config,
    );
    expect(analyze.lastEp, 'coreml');
  });

  test('中途取消：抛、且不留下半成品', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    var cancelled = false;
    final b = TranslatedPageBuilder(analyze: analyze.call, translate: (_, _) async {
      cancelled = true;
      return ['是蜥蜴啊'];
    });

    await expectLater(
      b.build(
        imagePath: 'p.jpg',
        pageIndex: 0,
        config: config,
        shouldCancel: () => cancelled,
      ),
      throwsA(isA<TranslatedPageCancelled>()),
    );
    expect(
      await TranslatedPageCache.has(
        label: (await TranslatedPageCache.describe(config: config)).label,
        pageIndex: 0,
      ),
      isFalse,
      reason: '半张 PNG 比没有更糟：Reader 会当它可用',
    );
  });

  test('阶段按顺序上报，UI 才有的显示', () async {
    final stages = <TranslatedPageStage>[];
    await builderWith(_FakeAnalyze([_block(_boxA)]), _FakeTranslate((_) => ['是蜥蜴啊']))
        .build(
          imagePath: 'p.jpg',
          pageIndex: 7,
          config: config,
          onStage: stages.add,
        );
    expect(stages, [
      TranslatedPageStage.analyzing,
      TranslatedPageStage.translating,
      TranslatedPageStage.typesetting,
    ]);
  });

  test('截断的块数会被报上去，UI 好标「可疑」', () async {
    final out = await builderWith(
      _FakeAnalyze([_block(_boxA, truncated: true), _block(const ui.Rect.fromLTWH(220, 160, 140, 90))]),
      _FakeTranslate((texts) => List.filled(texts.length, '译文')),
    ).build(imagePath: 'p.jpg', pageIndex: 0, config: config);
    expect(out.blockCount, 2);
    expect(out.truncatedCount, 1);
  });
}
