/// 成品页**端到端**验证：真权重、真过桥、真排版，只有翻译那一跳是假的。
///
/// 与 `ocr_analyze_page_probe_test.dart` 的分工：那条只证明「桥那头接得上」，
/// 这条证明「整条链路按生产的代码路径能出一张可看的成品页」——
/// 用的是不带任何注入的 `TranslatedPageBuilder()`（除了翻译），
/// 权重通过**符号链接**放进 `getFilePath()/manga_ocr/`，
/// 所以 `OcrService` 的就绪检查、路径解析、缓存指纹全都是生产那一套。
///
/// 翻译那一跳必须假：端点要网络 / 要 key，且「条数对不对」已由
/// `parseTranslatedLines` 的单测钉住。这里要验的是**画出来的东西**。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var ready = false;
  var reason = '';
  var page = '';
  late Directory appRoot;
  late TranslatedPageCacheProbe probe;

  setUpAll(() async {
    // 通道桩必须在**任何** OcrModels 调用之前装好：setUpAll 里就要往
    // getFilePath()/manga_ocr/ 里放符号链接。
    appRoot = await Directory.systemTemp.createTemp('rossi_ocr_e2e_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    final missing = await linkRealWeights();
    try {
      await RustLib.init();
    } catch (e) {
      missing.add('原生库：$e');
    }
    // 这条下面的尺寸断言（827×1170）是照这一页写的，所以按名字钉住，
    // 不能「拿目录里第一个」—— 那会随夹具顺序变成另一张图然后报一个假的尺寸错。
    const pinnedPage = 'mokuro_001a.jpg';
    final found = realPages();
    final wanted = found.where((p) => p.split('/').last == pinnedPage);
    page =
        Platform.environment['ROSSI_OCR_TEST_PAGE'] ??
        (wanted.isEmpty ? '' : wanted.first);
    if (page.isEmpty) missing.add('没有 $pinnedPage（尺寸断言照它写）');
    ready = missing.isEmpty;
    reason = ready ? '' : '缺权重或页图（${missing.join('、')}）';
    probe = TranslatedPageCacheProbe(page);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'fake-for-e2e',
      ),
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await appRoot.delete(recursive: true);
  });

  test('一页真漫画：检测 → 识别 → 擦字 → 回填，每块都有字、尺寸不变', () async {
    if (!ready) {
      markTestSkipped(reason);
      return;
    }
    final config = (await OcrSettings.loadConfig())!;
    final sw = Stopwatch()..start();
    final builder = TranslatedPageBuilder(
      translate: (texts, _) async => texts
          .map((t) => '〔译〕$t') // 真汉字 + 变长，逼排版重新求字号
          .toList(growable: false),
    );

    final out = await builder.build(
      imagePath: page,
      pageIndex: 0,
      config: config,
      force: true,
    );
    sw.stop();
    // ignore: avoid_print
    print(
      '成品页：${out.blockCount} 块，耗时 ${sw.elapsedMilliseconds} ms → ${out.path}',
    );

    expect(out.hasText, isTrue);
    expect(out.blockCount, greaterThan(0));

    final bytes = await File(out.path).readAsBytes();
    final decoded = await _decode(bytes);
    expect(decoded.width, 827, reason: '成品页尺寸必须与原页一致');
    expect(decoded.height, 1170);

    // 每一块都得有字：漏一块在成品页上就是一个空气泡，而这正是最难发现的一类错。
    final blocks = await probe.blocks();
    final empty = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final r = _rectOf(blocks[i]);
      if (_darkPixels(decoded.rgba, decoded.width, r) <= 0) empty.add(i);
    }
    expect(empty, isEmpty, reason: '这些块里一个墨点都没有（译文没画上去 / 字号崩了）');

    // 产物落进缓存目录，且第二次直接命中。
    expect(File(out.path).existsSync(), isTrue);
    final again = await builder.build(
      imagePath: page,
      pageIndex: 0,
      config: config,
    );
    expect(again.fromCache, isTrue);

    // 交给人眼复核：断言只能证明「每块有墨」，像不像成品页得看画。
    final dump = File('/tmp/ocr-lab/e2e_done.png');
    await dump.parent.create(recursive: true);
    await dump.writeAsBytes(bytes, flush: true);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// 缓存里那份成品页对应的块列表 —— 从同一份输入再跑一次「只到聚块」的分析拿框。
///
/// 为什么不把框从 builder 里带出来：那等于为了让测试能断言而给生产接口加一个
/// 平时没人用的返回值。重跑一次分析（几十秒）换接口干净，值。
class TranslatedPageCacheProbe {
  TranslatedPageCacheProbe(this.page);

  final String page;
  List<OcrBlock>? _cached;

  Future<List<OcrBlock>> blocks() async {
    return _cached ??= (await ocrAnalyzePage(
      imagePath: page,
      models: OcrModelPaths(
        det: await OcrModels.pathOf(OcrModels.detFile),
        encoder: await OcrModels.pathOf(OcrModels.encoderFile),
        decoder: await OcrModels.pathOf(OcrModels.decoderFile),
        vocab: await OcrModels.pathOf(OcrModels.vocabFile),
      ),
      ep: 'cpu',
    )).blocks;
  }
}

ui.Rect _rectOf(OcrBlock block) {
  final q = block.quad;
  final xs = [q[0], q[2], q[4], q[6]];
  final ys = [q[1], q[3], q[5], q[7]];
  return ui.Rect.fromLTRB(
    xs.reduce((a, b) => a < b ? a : b),
    ys.reduce((a, b) => a < b ? a : b),
    xs.reduce((a, b) => a > b ? a : b),
    ys.reduce((a, b) => a > b ? a : b),
  );
}

Future<({Uint8List rgba, int width, int height})> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width;
  final h = image.height;
  image.dispose();
  return (
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: w,
    height: h,
  );
}

int _darkPixels(Uint8List rgba, int stride, ui.Rect rect) {
  var count = 0;
  final x1 = rect.right.toInt().clamp(0, stride);
  final y1 = rect.bottom.toInt();
  for (var y = rect.top.toInt(); y < y1; y++) {
    for (var x = rect.left.toInt(); x < x1; x++) {
      final i = (y * stride + x) * 4;
      if (rgba[i] < 128 && rgba[i + 1] < 128 && rgba[i + 2] < 128) count++;
    }
  }
  return count;
}
