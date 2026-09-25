/// 多页质量扫描：把手边**所有**真页都过一遍完整链路，钉住两条单页测试钉不住的事。
///
/// `completed_page_e2e_test.dart` 只跑一页，而且只断言「每块有墨」。
/// 「有墨」离「像一张成品页」还差两步，而这两步恰好都是会静默发生的：
///
/// 1. **越框** —— 回填的字画到框外，压到隔壁气泡或画面区。ADR-0018 §3.4 明令禁止，
///    但在合成页上测不出来：合成框是方的、彼此分离，真页上的框会贴边、会嵌套。
///    这里用「擦干净的底图」做逐像素对照，判据是**越框像素离框有多远**而不是有几个：
///    八页实测每页 0–83 个像素、全部在框边 4 px 内（笔画压线 / 取整），
///    而「字跑到隔壁泡里」长的是几十像素外 —— 同一次运行里用一个刻意放大 30 px 的
///    对照渲染证明这条度量看得见那种。
/// 2. **一页过 / 页页过** —— 单页能过可能只是那张图脾气好。竖排窄格、极长句、
///    贴边小框这些形态要凑够样本才撞得出来，所以这里遍历整个目录而不是挑一张。
///
/// 翻译那一跳仍然是假的（要网络与 key），但**长度是真的**：伪译文按原文的可视宽度
/// 生成同字数的汉字，逼字号重新求解 —— 用固定短串会让越框变得不可能发生。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _dumpDir = '/tmp/ocr-lab/sweep';

/// 浮点框取整带来的边界宽度：检测件的框是小数坐标，画字按整数栅格落墨，
/// 边界上一两列像素属于取整，不算越框。
const _boxRoundTolerancePx = 1;

/// 允许笔画压到框边之外多少像素。
///
/// 这个数不是拍出来的：八页真页实测越框像素全部落在 1–4 px（详见 `_outsideScan` 的注释），
/// 而刻意把框放大 30 px 造出来的对照落在几十像素外 —— 中间有一整个数量级的空档，
/// 取 6 是把两边分开的最小整数。对照断言（`blindMetric`）保证这个阈值不是摆设。
const _maxSpillPxBeyondBox = 6;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var ready = false;
  var reason = '';
  var pages = <String>[];
  late Directory appRoot;

  setUpAll(() async {
    appRoot = await Directory.systemTemp.createTemp('rossi_ocr_sweep_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    final missing = await linkRealWeights();
    try {
      await RustLib.init();
    } catch (e) {
      missing.add('原生库：$e');
    }
    pages = realPages();
    if (pages.isEmpty) {
      missing.add('没有真页（找过 ${realPagesDirs().map((d) => d.path).join('、')}）');
    }
    ready = missing.isEmpty;
    reason = missing.isEmpty ? '' : '跑不了：${missing.join('、')}';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'fake-for-sweep',
      ),
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await appRoot.delete(recursive: true);
  });

  test('每一页：框内必须有墨，字不许画到框外几十像素', () async {
    if (!ready) {
      markTestSkipped(reason);
      return;
    }
    final config = (await OcrSettings.loadConfig())!;
    await Directory(_dumpDir).create(recursive: true);

    final report = <String>[];
    final spilled = <String>[];
    final blindMetric = <String>[];
    final emptyBlocks = <String>[];
    final sizeMismatch = <String>[];

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final pagePath = pages[pageIndex];
      final name = pagePath.split('/').last;

      List<OcrBlock> blocks = const [];
      Uint8List erasedPng = Uint8List(0);
      final builder = TranslatedPageBuilder(
        // 与生产的默认那一跳逐字相同，只是顺手把「擦干净的底图」和框留给自己用 ——
        // 越框这件事必须拿底图对照，事后重跑一次擦字等于把成本翻倍。
        analyze: (imagePath, erasedPath, ep) async {
          final r = await OcrService.instance.analyzePage(
            imagePath: imagePath,
            inpaint: true,
            erasedOutput: erasedPath,
            ep: ep,
          );
          blocks = r.blocks;
          // 没识别到文字的页，Rust 侧根本不会写擦字底图（builder 那时直接回原图），
          // 这里读一个不存在的路径会把整轮扫描打断。
          erasedPng = File(erasedPath).existsSync()
              ? await File(erasedPath).readAsBytes()
              : Uint8List(0);
          return r;
        },
        translate: (texts, _) async =>
            texts.map(_pseudoTranslate).toList(growable: false),
      );

      final out = await builder.build(
        imagePath: pagePath,
        pageIndex: pageIndex,
        config: config,
        force: true,
      );
      final productPng = await File(out.path).readAsBytes();
      if (blocks.isEmpty) {
        // 没有框就没有「越框」可言；这类页 builder 直接回原图，也是对的。
        // ignore: avoid_print
        print('$name：没识别到文字，成品页=原图（hasText=${out.hasText}）');
        expect(out.hasText, isFalse, reason: '$name 无块却声称出了译文页');
        continue;
      }
      final [source, erased, product] = [
        await _decode(await File(pagePath).readAsBytes()),
        await _decode(erasedPng),
        await _decode(productPng),
      ];

      if (product.width != source.width || product.height != source.height) {
        sizeMismatch.add(
          '$name：成品 ${product.width}×${product.height} != 原图 '
          '${source.width}×${source.height}',
        );
      }

      final quads = blocks.map(_rectOf).toList(growable: false);
      final minInk = quads.isEmpty
          ? -1
          : quads
                .map((r) => _darkPixels(product.rgba, product.width, r))
                .reduce((a, b) => a < b ? a : b);
      final scan = _outsideScan(erased: erased, product: product, quads: quads);
      // 对照：同一张底图、同样这些字，但把框**故意放大 30 px** 再交给渲染器 ——
      // 那一定画到真框之外。度量要是看不见这种越框，它对真缺陷也是瞎的，
      // 那条 `maxDist <=` 断言就成了摆设。这条对照是钉**度量本身**的。
      final controlBlocks = [
        for (final b in blocks)
          OcrBlock(
            quad: _quadOfRect(_rectOf(b).inflate(30)),
            text: b.text,
            boxes: b.boxes,
            truncated: b.truncated,
          ),
      ];
      final controlPng = await TranslatedPageRenderer.render(
        erasedPng: erasedPng,
        blocks: controlBlocks,
        translations: controlBlocks
            .map((b) => _pseudoTranslate(b.text))
            .toList(growable: false),
      );
      final control = _outsideScan(
        erased: erased,
        product: await _decode(controlPng),
        quads: quads,
      );
      report.add(
        '$name：${blocks.length} 块，最少墨点 $minInk，截断块 '
        '${blocks.where((b) => b.truncated).length}，'
        '框外最远 ${scan.maxDist} px / ${scan.changed} 个像素，'
        '对照（框放大 30 px）${control.maxDist} px / ${control.changed} 个',
      );
      if (scan.changed > 0) {
        report.add('    框外按离框距离分布：${scan.histLabel}');
      }
      if (quads.isNotEmpty && minInk <= 0) emptyBlocks.add(name);
      if (scan.maxDist > _maxSpillPxBeyondBox) {
        spilled.add(
          '$name：字画到框外 ${scan.maxDist} px（上限 $_maxSpillPxBeyondBox px）',
        );
      }
      if (control.changed == 0 || control.maxDist <= _maxSpillPxBeyondBox) {
        blindMetric.add(
          '$name：对照没炸（${control.changed} 个像素 / ${control.maxDist} px）'
          '—— 这条度量看不见刻意造出来的越框',
        );
      }

      await File(
        '$_dumpDir/${name.split('.').first}_done.png',
      ).writeAsBytes(productPng, flush: true);
    }

    // ignore: avoid_print
    print('—— 多页扫描（${pages.length} 页）\n${report.join('\n')}');
    expect(sizeMismatch, isEmpty, reason: '成品页尺寸必须与原页一致');
    expect(emptyBlocks, isEmpty, reason: '这些页里有某个块一个墨点都没有');
    // 先判度量有没有眼睛，再判它看到了什么 —— 反过来的话，一条瞎掉的度量会给出一个绿的「没有越框」。
    expect(blindMetric, isEmpty, reason: '越框度量看不见刻意造出来的越框，下面的断言就不算数');
    expect(spilled, isEmpty, reason: '字画到框外去了（见上面逐页的「框外最远」）');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// 按原文的可视宽度造一条**同字数**的中文伪译文。
///
/// 必须是汉字：回填的字号是按「能不能塞进框」反复求解的，喂回同一段假名只会证明
/// 度量单位没变；同字数则保证不会靠「译文刚好更短」蒙过越框这一关。
String _pseudoTranslate(String source) {
  const filler = '这是一句用来占位的中文译文而已啦';
  final n = source.runes.where((r) => r > 0x20).length.clamp(1, 120);
  return List<String>.generate(n, (i) => filler[i % filler.length]).join();
}

/// 框外被改动的像素有多少、最远到哪儿。
///
/// 为什么断「最远距离」而不是「个数」：真跑八页之后量到的是每页 0–83 个像素、
/// 全部落在框边 4 px 以内，通道差却是满幅（200+）—— 那是**笔画压到框边**，
/// 属于描边与字形 ink 外沿的正常溢出；「字跑到隔壁气泡里」长的是几十像素。
/// 个数当判据会把前者一并禁掉，等于逼渲染器去消灭抗锯齿。
({int changed, int maxDist, String histLabel}) _outsideScan({
  required ({Uint8List rgba, int width, int height}) erased,
  required ({Uint8List rgba, int width, int height}) product,
  required List<ui.Rect> quads,
}) {
  if (erased.width != product.width || erased.height != product.height) {
    // 底图与成品尺寸都不一样时逐像素比对没有意义，交给尺寸那条断言去报。
    return (changed: 0, maxDist: 0, histLabel: '尺寸不一致，跳过');
  }
  final w = product.width;
  final h = product.height;
  final inflated = quads
      .map((r) => r.inflate(_boxRoundTolerancePx.toDouble()))
      .toList(growable: false);
  var changed = 0;
  var maxDist = 0;
  final byDistance = <int, int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = ui.Offset(x.toDouble(), y.toDouble());
      if (inflated.any((r) => r.contains(p))) continue;
      final i = (y * w + x) * 4;
      final d = [
        (erased.rgba[i] - product.rgba[i]).abs(),
        (erased.rgba[i + 1] - product.rgba[i + 1]).abs(),
        (erased.rgba[i + 2] - product.rgba[i + 2]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      if (d == 0) continue;
      changed++;
      var dist = 1 << 30;
      for (final r in inflated) {
        final dx = r.left > p.dx
            ? (r.left - p.dx).ceil()
            : (p.dx >= r.right ? (p.dx - r.right).ceil() : 0);
        final dy = r.top > p.dy
            ? (r.top - p.dy).ceil()
            : (p.dy >= r.bottom ? (p.dy - r.bottom).ceil() : 0);
        final m = dx > dy ? dx : dy;
        if (m < dist) dist = m;
      }
      if (dist > maxDist) maxDist = dist;
      byDistance[dist] = (byDistance[dist] ?? 0) + 1;
    }
  }
  final keys = byDistance.keys.toList()..sort();
  return (
    changed: changed,
    maxDist: maxDist,
    histLabel: keys.isEmpty
        ? '无'
        : keys.map((k) => '${k}px:${byDistance[k]}').join(' '),
  );
}

/// 把矩形写回检测件那套四角点顺序：左上→右上→右下→左下。
Float32List _quadOfRect(ui.Rect r) => Float32List.fromList([
  r.left,
  r.top,
  r.right,
  r.top,
  r.right,
  r.bottom,
  r.left,
  r.bottom,
]);

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
