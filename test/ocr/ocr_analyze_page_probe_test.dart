/// OCR 链路**过桥**验证：Dart → FRB → Rust(`ocr_core`) → 回来。
///
/// 为什么单开一个文件：`rust/ocr_core` 的四个阶段各有自己的单测，`dart analyze` 也绿，
/// 但这些都证明不了「桥那头接的是不是这个函数、参数顺序对不对、返回的结构 Dart 侧能不能解出来」——
/// 这一层之前只有 codegen 通过，从没被真实调用过。
///
/// 模型与页图**不在仓库里**（ADR-0018 §决定 5：权重不随包、字体才是随包的），
/// 所以查找口径统一走 `real_page_fixtures.dart`（env → `.local/ocr-test-data/` → `/tmp/*-lab`），
/// 找不到就 skip 并说明理由，不留永远红的测试。
/// ⚠️ 这份以前自己抄了一份只认 `/tmp` 的，`/tmp` 被清之后就静默 skip 了几天 ——
/// 抽出口的正是这个文件要防的事，别再把路径抄回本地。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

/// 尺寸与块文本那几条断言就是照这一页写的。
const _pinnedPage = 'mokuro_001a.jpg';

void main() {
  var nativeReady = false;
  String? nativeError;
  var fixturesReady = false;
  var fixturesReason = '';

  var det = '';
  var encoder = '';
  var decoder = '';
  var vocab = '';
  var lama = '';
  var page = '';

  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }

    // 查找口径**必须**走 `real_page_fixtures.dart`。这里曾经自己抄了一份只认
    // `/tmp/{inpaint,detect}-lab` 的，于是 /tmp 被 dirhelper 扫走之后，这条测试
    // 静默 skip 了几天，而文档里还写着它跑过 —— 正是那个文件头警告的那件事。
    String? find(String upstream) {
      for (final d in realModelDirs()) {
        final f = File('${d.path}/$upstream');
        if (f.existsSync()) return f.path;
      }
      return null;
    }

    det = find(realModelFiles[OcrModels.detFile]!) ?? '';
    encoder = find(realModelFiles[OcrModels.encoderFile]!) ?? '';
    decoder = find(realModelFiles[OcrModels.decoderFile]!) ?? '';
    vocab = find(realModelFiles[OcrModels.vocabFile]!) ?? '';
    lama = find(realModelFiles[OcrModels.inpaintFile]!) ?? '';
    // 尺寸与块文本那几条断言是照 `mokuro_001a` 写的（827×1170、15 块），
    // 所以先找它；`ROSSI_OCR_TEST_PAGE` 留给临时换页时用。
    final envPage = Platform.environment['ROSSI_OCR_TEST_PAGE'];
    page = envPage != null && envPage.isNotEmpty && File(envPage).existsSync()
        ? envPage
        : realPages()
              .where((p) => p.endsWith(_pinnedPage))
              .fold('', (acc, p) => acc.isEmpty ? p : acc);

    final missing = [
      if (det.isEmpty) 'ppocr det',
      if (encoder.isEmpty) 'manga-ocr encoder',
      if (decoder.isEmpty) 'manga-ocr decoder',
      if (vocab.isEmpty) 'manga-ocr vocab',
      if (page.isEmpty) '测试页',
    ];
    fixturesReady = missing.isEmpty;
    fixturesReason = missing.isEmpty
        ? ''
        : '缺少 ${missing.join(' / ')}；放进取 `real_page_fixtures.dart` 里那三个目录之一'
              '（通常是 `.local/ocr-test-data/models`），或设 ROSSI_OCR_MODELS_DIR';
  });

  OcrModelPaths paths() =>
      OcrModelPaths(det: det, encoder: encoder, decoder: decoder, vocab: vocab);

  test('过桥：检测 → 识别 → 聚块，块文本与四角点都拿得到', () async {
    if (!nativeReady) return markTestSkipped('原生库加载不了（$nativeError）');
    if (!fixturesReady) return markTestSkipped(fixturesReason);

    final result = await ocrAnalyzePage(
      imagePath: page,
      models: paths(),
      ep: 'cpu',
      inpaintModel: null,
      erasedOutput: null,
      maxNewTokens: null,
    );

    expect(result.pageWidth, 827);
    expect(result.pageHeight, 1170);
    expect(result.blocks.length, greaterThan(5), reason: '这一页实测出 15 块');
    // u64 过 FRB 是 Dart 的 BigInt，不是 int —— 这里踩过一次，别再写成 greaterThan(0)。
    expect(result.detectMs, greaterThan(BigInt.zero));
    expect(result.recognizeMs, greaterThan(BigInt.zero));
    expect(result.erasedPath, isNull, reason: '没给擦字模型就不该有产物');
    // 三段各自**实际生效**的 EP 要真的过桥回来（以前只有请求值，识别段根本没报）。
    expect(
      (result.stageEps.detect, result.stageEps.recognize),
      ('cpu', 'cpu'),
      reason: '显式传了 cpu，前两段必须如实回报 cpu',
    );
    expect(
      result.stageEps.inpaint,
      isNull,
      reason: '没跑擦字就该是 null，而不是回一条「跑过但用了 cpu」',
    );

    final texts = result.blocks.map((b) => b.text).toList();
    // 回归锚点，取自 2026-09-25 的实测（`REFERENCE_RESEARCH.md` §8.6.7）：
    // 「トカゲじゃ」/「ない!?」两列必须合成一块，否则竖排被切断的 bug 回来了。
    expect(
      texts.any((t) => t.contains('トカゲじゃ') && t.contains('ない')),
      isTrue,
      reason: '竖排两列应聚成一块：$texts',
    );
    expect(
      texts.any((t) => t.contains('どっから捕まえてきたんだよお前')),
      isTrue,
      reason: '相邻两气泡不该串成一簇：$texts',
    );
    expect(
      result.blocks.every((b) => !b.truncated),
      isTrue,
      reason: '不该有被 max_new_tokens 截断的块',
    );

    // 四角点：8 个数、落在页内、顺序是左上→右上→右下→左下（x 单调不减再减）。
    for (final b in result.blocks) {
      expect(b.quad.length, 8, reason: '块 ${b.text} 的四角点不是 8 个数');
      for (var i = 0; i < 8; i += 2) {
        expect(b.quad[i], inInclusiveRange(0, 827));
        expect(b.quad[i + 1], inInclusiveRange(0, 1170));
      }
      expect(b.quad[0], lessThanOrEqualTo(b.quad[2]));
      expect(b.quad[1], lessThanOrEqualTo(b.quad[5]));
    }
    printOnFailure('块文本：$texts');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('过桥：擦字写出底图，尺寸不变', () async {
    if (!nativeReady) return markTestSkipped('原生库加载不了（$nativeError）');
    if (!fixturesReady || lama.isEmpty) {
      return markTestSkipped(
        lama.isEmpty ? '缺少 LaMa 权重（lama-manga-dynamic.onnx）' : fixturesReason,
      );
    }

    final out =
        '${Directory.systemTemp.createTempSync('rossi-ocr').path}/erased.png';
    final result = await ocrAnalyzePage(
      imagePath: page,
      models: paths(),
      ep: 'cpu',
      inpaintModel: lama,
      erasedOutput: out,
      maxNewTokens: null,
    );

    expect(result.erasedPath, out);
    final erased = File(out);
    expect(erased.existsSync(), isTrue, reason: '擦干净的底图必须落盘');
    expect(erased.lengthSync(), greaterThan(1000));
    expect(result.inpaintMs, greaterThan(BigInt.zero));
    expect(result.stageEps.inpaint, 'cpu', reason: '跑了擦字就必须报出它实际用的那条 EP，而不是留空');
    // PNG 头里的宽高要与原页一致（降采样只发生在推理内部，产物是原尺寸）。
    final header = erased.readAsBytesSync().sublist(16, 24);
    final w = header[0] << 24 | header[1] << 16 | header[2] << 8 | header[3];
    final h = header[4] << 24 | header[5] << 16 | header[6] << 8 | header[7];
    expect([w, h], [827, 1170], reason: '产物尺寸该等于原页');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
