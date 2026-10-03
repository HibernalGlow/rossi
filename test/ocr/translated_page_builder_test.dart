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

import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
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

OcrBlock _block(ui.Rect r, {String text = 'トカゲじゃ', bool truncated = false}) =>
    OcrBlock(
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

  /// 故意取一组**三段不同**的值（Windows 上 auto 的实际结果），
  /// 好让「编排层把实际生效的 EP 原样透传出来」这条测试能分辨真假。
  final OcrStageEps stageEps = const OcrStageEps(
    detect: 'cpu',
    recognize: 'directml',
    inpaint: 'directml',
  );

  Future<OcrPageResult> call(
    String imagePath,
    String? erasedPath,
    String ep,
  ) async {
    calls++;
    lastEp = ep;
    lastErasedPath = erasedPath;
    // null = 这一趟**不要**擦字（叠层档要先看框采色），与生产那边 `inpaint: false` 同形：
    // Rust 那时也不会写底图。假件替它写一张就是替这一档撒谎。
    if (erasedPath != null) {
      // 正常链路里这张图是 Rust 写的；这里替它写一张纯白底。
      await File(
        erasedPath,
      ).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
      erasedSeenAtCallTime = await File(erasedPath).exists();
    } else {
      erasedSeenAtCallTime = false;
    }
    return OcrPageResult(
      blocks: blocks,
      pageWidth: _pageW,
      pageHeight: _pageH,
      detectMs: BigInt.from(190),
      recognizeMs: BigInt.from(3700),
      inpaintMs: BigInt.from(1700),
      erasedPath: erasedPath,
      stageEps: stageEps,
    );
  }
}

class _FakeTranslate {
  _FakeTranslate(this.reply);

  final List<String> Function(List<String> texts) reply;
  int calls = 0;
  List<String>? lastTexts;

  Future<List<String>> call(
    List<String> texts,
    OcrTranslationConfig config,
  ) async {
    calls++;
    lastTexts = texts;
    return reply(texts);
  }
}

/// 一张「网点底」：每 2 px 一颗 1 px 黑点，铺满整页。
///
/// 采底色那一关在这张图上**必须**判不可填（平色占比约一半），于是这一页会走
/// 「补擦擦字底图」那条分支 —— 与纯白页那条「全填色、跳过擦字」正好配成一对。
Future<Uint8List> _halftonePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final dot = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      canvas.drawRect(ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), dot);
    }
  }
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 假「只擦字」那一跳（叠层档采不到平色时才被叫到）。
class _FakeErase {
  int calls = 0;
  List<Float32List>? lastQuads;
  String? lastOutput;

  /// true = 模拟 Rust 那边**掩膜为空**的回报：不写文件、`erasedPath` 是 null。
  bool writesNothing = false;

  Future<OcrEraseResult> call(
    String imagePath,
    List<Float32List> quads,
    String erasedOutput,
    String ep,
  ) async {
    calls++;
    lastQuads = quads;
    lastOutput = erasedOutput;
    if (writesNothing) {
      return OcrEraseResult(inpaintMs: BigInt.zero, ep: 'cpu');
    }
    await File(
      erasedOutput,
    ).writeAsBytes(await _whitePng(_pageW, _pageH), flush: true);
    return OcrEraseResult(
      erasedPath: erasedOutput,
      inpaintMs: BigInt.from(4200),
      ep: 'cpu',
    );
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
    await OcrLog.flush();
    await root.delete(recursive: true);
  });

  TranslatedPageBuilder builderWith(_FakeAnalyze a, _FakeTranslate t) =>
      TranslatedPageBuilder(analyze: a.call, translate: t.call);

  test('首建走完整链路，成品落进缓存且真有墨', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final translate = _FakeTranslate((texts) => ['是蜥蜴啊']);

    final out = await builderWith(
      analyze,
      translate,
    ).build(imagePath: '/nonexistent/page.jpg', pageIndex: 0, config: config);

    expect(analyze.calls, 1);
    expect(analyze.lastEp, 'auto', reason: '没设置过就该交给「按平台与模型选」，而不是写死 cpu');
    expect(translate.lastTexts, ['トカゲじゃ'], reason: '送翻译的必须是识别出来的原文');
    expect(analyze.erasedSeenAtCallTime, isTrue, reason: '底图没落盘就去画，成品会是空的');
    expect(out.fromCache, isFalse);
    expect(out.hasText, isTrue);
    expect(out.blockCount, 1);
    expect(
      out.stageEps,
      analyze.stageEps,
      reason: '三段实际生效的 EP 要原样透传出来 —— 界面据它核对「选了 GPU 就真用了 GPU」',
    );

    final file = File(out.path);
    expect(await file.exists(), isTrue);
    final rgba = await _rgba(await file.readAsBytes());
    expect(
      _darkPixels(rgba, _pageW, _boxA),
      greaterThan(200),
      reason: '译文没画上去',
    );

    // 缓存目录里只该有：成品 PNG、它的图层 JSON、清单。
    // 擦字中间产物漏进来，用户就分不清哪张是成品页；JSON 是**故意同目录同名**的 ——
    // 换超分档 / 换显示模式要靠它重新合成，分目录就会让「PNG 新、JSON 旧」这种错配发生。
    final dir = file.parent;
    expect(
      (await dir.list().map((e) => e.uri.pathSegments.last).toList())..sort(),
      ['manifest.json', 'p0.json', 'p0.png'],
    );
    final manifest = await File('${dir.path}/manifest.json').readAsString();
    expect(manifest, contains('zh-Hans'));
    expect(analyze.lastErasedPath, startsWith(Directory.systemTemp.path));

    // 六道关要有关关留痕 —— 用户那句「翻译没日志，我不知道情况如何」就是这个意思。
    final logged = OcrLog.log.entries.value.join('\n');
    expect(
      logged,
      contains('第 1 页 开始构建：引擎=endpoint 端点=127.0.0.1/hello-world'),
      reason:
          '端点只记 host：base URL 上可能夹着带 token 的路径，日志是要被复制走的；'
          '而「引擎」要排在最前面 —— 查「这页为什么没翻对」时第一个该排除的就是走错了档',
    );
    expect(
      logged,
      contains('实际生效 EP：检测=cpu 识别=directml 擦字=directml'),
      reason: '日志里的 EP 必须是 Rust 回报的实际值，不是设置里的请求值',
    );
    expect(logged, contains('第 1 页 翻译：1 条 → 1 条'));
    expect(logged, contains('第 1 页 回填排版'));
    expect(logged, contains('第 1 页 成品已写入'));
  });

  test('再建命中缓存，一次分析都不许重跑', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));

    final first = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 3,
      config: config,
    );
    final again = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 3,
      config: config,
    );

    expect(again.fromCache, isTrue);
    expect(again.path, first.path);
    expect(again.stageEps, isNull, reason: '命中缓存那一次什么都没跑，不该拿上一次的 EP 顶替（那是谎报）');
    final lastLogged = OcrLog.log.entries.value.last;
    expect(lastLogged, contains('命中缓存'));
    expect(lastLogged, isNot(contains('EP')), reason: '同上：日志里也不许出现一条没跑过的 EP');
    expect(analyze.calls, 1, reason: '一页分析 ~14 s，命中缓存还重跑等于没有缓存');
  });

  test('缓存里那张是坏的：当没有，重算一份，而不是把坏文件端出去', () async {
    // ADR-0018 §决定 3 的「缺失或损坏静默回落」在这里的前一步：
    // 编排层就不该把半张 PNG 当成产物返回。
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));
    final first = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 1,
      config: config,
    );
    final callsAfterFirst = analyze.calls;

    final file = File(first.path);
    final bytes = await file.readAsBytes();
    await file.writeAsBytes(
      bytes.sublist(0, bytes.length - 8),
      flush: true,
    ); // 砍掉 IEND

    final second = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 1,
      config: config,
    );
    expect(analyze.calls, callsAfterFirst + 1, reason: '坏产物命中了缓存 = 把损坏当存在');
    expect(second.fromCache, isFalse);
    expect(
      await File(second.path).length(),
      bytes.length,
      reason: '重算的那份要补回完整文件',
    );
  });

  test('force 重算，覆盖旧产物', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final b = builderWith(analyze, _FakeTranslate((_) => ['是蜥蜴啊']));
    await b.build(imagePath: 'p.jpg', pageIndex: 0, config: config);

    final forced = await b.build(
      imagePath: 'p.jpg',
      pageIndex: 0,
      config: config,
      force: true,
    );

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

    final out = await builderWith(
      analyze,
      translate,
    ).build(imagePath: original, pageIndex: 0, config: config);

    expect(out.hasText, isFalse);
    expect(out.path, original, reason: '擦不擦都一样的页，不该被换成一份缓存副本');
    expect(translate.calls, 0, reason: '没台词就别发翻译请求，白烧一次 token');
    expect(
      await TranslatedPageCache.isUsable(
        label: (await TranslatedPageCache.describe(config: config)).label,
        pageIndex: 0,
      ),
      isFalse,
    );
  });

  test('设置里选的后端真的传到分析那一跳（否则选择器是个骗人的控件）', () async {
    SharedPreferences.setMockInitialValues({'ocr_ep': 'coreml'});
    final analyze = _FakeAnalyze([_block(_boxA)]);
    await builderWith(
      analyze,
      _FakeTranslate((_) => ['是蜥蜴啊']),
    ).build(imagePath: 'p.jpg', pageIndex: 0, config: config);
    expect(analyze.lastEp, 'coreml');
  });

  test('中途取消：抛、且不留下半成品', () async {
    final analyze = _FakeAnalyze([_block(_boxA)]);
    var cancelled = false;
    final b = TranslatedPageBuilder(
      analyze: analyze.call,
      translate: (_, _) async {
        cancelled = true;
        return ['是蜥蜴啊'];
      },
    );

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
      await TranslatedPageCache.isUsable(
        label: (await TranslatedPageCache.describe(config: config)).label,
        pageIndex: 0,
      ),
      isFalse,
      reason: '半张 PNG 比没有更糟：Reader 会当它可用',
    );
  });

  test('阶段按顺序上报，UI 才有的显示', () async {
    final stages = <TranslatedPageStage>[];
    await builderWith(
      _FakeAnalyze([_block(_boxA)]),
      _FakeTranslate((_) => ['是蜥蜴啊']),
    ).build(
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
      _FakeAnalyze([
        _block(_boxA, truncated: true),
        _block(const ui.Rect.fromLTWH(220, 160, 140, 90)),
      ]),
      _FakeTranslate((texts) => List.filled(texts.length, '译文')),
    ).build(imagePath: 'p.jpg', pageIndex: 0, config: config);
    expect(out.blockCount, 2);
    expect(out.truncatedCount, 1);
  });

  // ─────────── 叠层档（ADR-0018 §决定 4 解冻那一轮）───────────

  test('叠层档：全页采到平色就一页不擦，也不烤 PNG', () async {
    final src = await Directory('${root.path}/src').create();
    final pageFile = File('${src.path}/flat.png');
    await pageFile.writeAsBytes(await _whitePng(_pageW, _pageH));
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final erase = _FakeErase();

    final out = await TranslatedPageBuilder(
      analyze: analyze.call,
      erase: erase.call,
      translate: _FakeTranslate((texts) => ['是蜥蜴啊']).call,
    ).build(
      imagePath: pageFile.path,
      pageIndex: 0,
      config: config,
      retainErasedBase: true,
    );

    expect(
      erase.calls,
      0,
      reason: '每框都能填色时，那 4.2 s 的擦字就该整个跳过 —— 这一档省的时间全在这里',
    );
    expect(
      out.path,
      pageFile.path,
      reason: '底图必须是原图：这一档不占增强图轨，超分产物照常往上面叠',
    );
    // 这一档的产物只有图层：没有烤好的 PNG，也没有擦字底图。
    expect(
      (await (await TranslatedPageCache.directory(out.label))
              .list()
              .map((e) => e.uri.pathSegments.last)
              .toList())
        ..sort(),
      ['manifest.json', 'p0.json'],
    );
    final layer = TranslatedPageLayer.tryDecode(
      await (await TranslatedPageCache.layerFile(
        label: out.label,
        pageIndex: 0,
      )).readAsString(),
    );
    expect(layer?.boxes.single.fill, isNotNull, reason: '图层没带上采到的底色');

    final logged = OcrLog.log.entries.value.join('\n');
    expect(logged, contains('全部填色（未跑擦字）'));
    // 命中判据也必须是叠层那把尺：按 PNG 判就永远 miss，每次上屏重跑十几秒。
    final again = await TranslatedPageBuilder(
      analyze: analyze.call,
      erase: erase.call,
      translate: _FakeTranslate((texts) => ['是蜥蜴啊']).call,
    ).build(
      imagePath: pageFile.path,
      pageIndex: 0,
      config: config,
      retainErasedBase: true,
    );
    expect(again.fromCache, isTrue);
    expect(analyze.calls, 1, reason: '命中缓存不许再跑分析');
    expect(again.path, pageFile.path);
  });

  test('叠层档：有一框采不出平色就补擦，底图原子进缓存', () async {
    final src = await Directory('${root.path}/src').create();
    final pageFile = File('${src.path}/halftone.png');
    await pageFile.writeAsBytes(await _halftonePng(_pageW, _pageH));
    final analyze = _FakeAnalyze([_block(_boxA)]);
    final erase = _FakeErase();

    final out = await TranslatedPageBuilder(
      analyze: analyze.call,
      erase: erase.call,
      translate: _FakeTranslate((texts) => ['是蜥蜴啊']).call,
    ).build(
      imagePath: pageFile.path,
      pageIndex: 0,
      config: config,
      retainErasedBase: true,
    );

    expect(erase.calls, 1);
    expect(
      erase.lastQuads?.length,
      1,
      reason: '掩膜要按同一批框生成 —— 传错就等于两边擦得不一样',
    );
    expect(
      out.path,
      (await TranslatedPageCache.baseFile(label: out.label, pageIndex: 0)).path,
    );
    expect(
      (await (await TranslatedPageCache.directory(out.label))
              .list()
              .map((e) => e.uri.pathSegments.last)
              .toList())
        ..sort(),
      ['manifest.json', 'p0.base.png', 'p0.json'],
      reason: '底图必须落在缓存档里（留在临时目录 = 每次上屏重擦一遍）',
    );
    // 全页不填色（半填半擦会露出两种底），但叠层照样可用：有底图就够了。
    final layer = TranslatedPageLayer.tryDecode(
      await (await TranslatedPageCache.layerFile(
        label: out.label,
        pageIndex: 0,
      )).readAsString(),
    );
    expect(layer?.boxes.single.fill, isNull);
    expect(
      await TranslatedPageCache.overlayDisplayable(
        label: out.label,
        pageIndex: 0,
      ),
      isTrue,
    );
    expect(OcrLog.log.entries.value.join('\n'), contains('已补擦底图'));
  });

  test('叠层档：擦字没写出底图就是失败，不许拿原图当底硬画', () async {
    final src = await Directory('${root.path}/src').create();
    final pageFile = File('${src.path}/halftone.png');
    await pageFile.writeAsBytes(await _halftonePng(_pageW, _pageH));
    final erase = _FakeErase()..writesNothing = true;

    await expectLater(
      TranslatedPageBuilder(
        analyze: _FakeAnalyze([_block(_boxA)]).call,
        erase: erase.call,
        translate: _FakeTranslate((texts) => ['是蜥蜴啊']).call,
      ).build(
        imagePath: pageFile.path,
        pageIndex: 0,
        config: config,
        retainErasedBase: true,
      ),
      throwsA(isA<OcrTranslationException>()),
      reason:
          '没有擦字底图时唯一的底就是原图，而叠在未擦字的原图上字压字率实测 0.085 —— '
          '与其画一张糊的冒充成品，不如让界面明说「译文失败」',
    );
    expect(erase.calls, 1);
    final cacheRoot = Directory('${root.path}/manga_translated');
    final leftovers = cacheRoot.existsSync()
        ? await cacheRoot
              .list(recursive: true)
              .where((e) => e is File)
              .map((e) => e.uri.pathSegments.last)
              .toList()
        : <String>[];
    expect(
      leftovers.where((n) => n == 'p0.json' || n == 'p0.base.png'),
      isEmpty,
      reason: '失败的那一页不许留下半成品图层或底图 —— 下次命中就会端出一张没底的叠层',
    );
  });
}
