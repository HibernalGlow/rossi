/// 真页上「按气泡轮廓采平色底」到底采得出多少 —— 这条是**量数**的，不是断言行为的。
///
/// 为什么要单独量：叠层那一档省时间的全部依据是「漫画白气泡里的字本来就在一片纯色里，
/// 用气泡自己的底色沿 quad 盖掉即可」，于是可以整段跳过 LaMa（实测 4.2–4.7 s/页）。
/// 但 `completed_page_overlay_e2e_test.dart` 在真页上量到的是 **0/15 框能采出平色**，
/// 也就是那一档在真数据上根本没生效过 —— 每一页都还是付了擦字那 4.7 s。
/// **量出来的结论（8 页真页、121 框）**：可填 0 框，即 **0/121 = 0.0%**。
/// 同一把尺重算的诊断数是：`flatRatio` 每页中位 0.33–0.66，
/// 「离中位色的最大偏离」每页中位 **243–251**（满量程 255）。
///
/// 这两个数合起来说的是同一件事，**不是阈值太严**：偏离 250 意味着那圈采样带里
/// 同时有近黑（笔画）与近白（气泡底），也就是**检测框是贴着字形切的**——
/// 真页上的 quad 是「一行字」而不是「一个气泡」，框边内侧 3–7 px 还在字里，
/// 根本没有「气泡自己的底」可采。合成夹具（白底 + 四周留白）恰好不是这个形状，
/// 所以 bubble_fill 那 10 条判据全绿，而生产那一档在真页上一次都没成立过。
///
/// 因此本仓当前的事实是：**叠层档每一页都要付擦字那 ~4.7 s**
/// （`completed_page_overlay_e2e_test.dart` 实测 4698 ms），
/// 「采到平色就跳过 LaMa」这条捷径在真数据上是死的。
/// 要救它得改**采样方向**（往框外扩一圈去找气泡底，而不是往框内缩），
/// 那不是调阈值能解决的 —— 调松只会把「用墨水的中位色去填框」放行，画面上是一团灰。
///
/// 改判据 + 改方向**还不够**（第三条尺）：按框外环带逐框量，候选阈值下框级通过 26/121、53/121、59/121，
/// 看着有救 —— 但生产规则是「**有一框不过就整页不填**」，于是按页只有 **0/8 页**全框通过（三种候选阈值都是 0）。
/// ⇒ 这一档在真页上不是差一个阈值，而是差一条页级规则：要么允许同页「能填的填、填不了的擦」
/// （代价就是 §决定 4 那条「两种底」的顾虑），要么维持现状（叠层每页付擦字那 ~4.7 s，但仍与超分共存）。
/// 这条取舍是设计决定，不由调参解决 —— 所以本文件按页与按框两个口径都打出来。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/bubble_fill.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

Future<({Uint8List rgba, int width, int height})> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(
    await File(path).readAsBytes(),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width;
  final h = image.height;
  image.dispose();
  expect(data, isNotNull);
  return (
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: w,
    height: h,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var ready = false;
  var reason = '';
  late Directory appRoot;
  late List<String> pages;

  setUpAll(() async {
    appRoot = await Directory.systemTemp.createTemp('rossi_fill_probe_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    final missing = await linkRealWeights();
    try {
      await RustLib.init();
    } catch (e) {
      missing.add('原生库：$e');
    }
    pages = realPages();
    if (pages.isEmpty) missing.add('没有真页夹具');
    ready = missing.isEmpty;
    reason = ready ? '' : '缺权重或页图（${missing.join('、')}）';
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await appRoot.delete(recursive: true);
  });

  test('逐页量：多少框能采出平色底（决定叠层要不要跑 LaMa）', () async {
    if (!ready) {
      markTestSkipped(reason);
      return;
    }
    var boxes = 0;
    var fillable = 0;
    // 「整页全框都过」才是能跳过擦字的那一格（生产判据是全有或全无），
    // 所以按页计数，而不是按框 —— 上一轮量到框级 26/121 能过，但那一格是逐框的。
    var pageAllA = 0, pageAllB = 0, pageAllC = 0;
    for (final page in pages) {
      final result = await ocrAnalyzePage(
        imagePath: page,
        models: OcrModelPaths(
          det: await OcrModels.pathOf(OcrModels.detFile),
          encoder: await OcrModels.pathOf(OcrModels.encoderFile),
          decoder: await OcrModels.pathOf(OcrModels.decoderFile),
          vocab: await OcrModels.pathOf(OcrModels.vocabFile),
        ),
        ep: 'cpu',
        // 采色的输入一律取**原图**的字节（下面 `_decode(page)`），所以桥那边擦不擦
        // 都不影响这个数；这里不传任何跳过擦字的参数 —— 那个开关不在 `ocrAnalyzePage` 上。
      );
      final img = await _decode(page);
      var ok = 0;
      final ratios = <double>[];
      final spreads = <double>[];
      final outRatios = <double>[];
      final outSpreads = <double>[];
      var outwardOk = 0;
      var candA = 0, candB = 0, candC = 0;
      final widths = <int>[];
      final heights = <int>[];
      for (final b in result.blocks) {
        final q = b.quad.map((v) => v.toDouble()).toList();
        final w = (q[2] - q[0]).abs().round();
        final h = (q[5] - q[1]).abs().round();
        widths.add(w);
        heights.add(h);
        final diag = _sampleForDiagnosis(img.rgba, img.width, img.height, q);
        final out = _outwardBand(img.rgba, img.width, img.height, q);
        if (out != null) {
          outRatios.add(out.$1);
          outSpreads.add(out.$2);
          // 候选判据（这次要量的就是哪一条在真页上放得开、又不至于把网点底放进来）：
          // 占比按现阈值 0.92 / 放宽到 0.85，偏离的上限从「最大值」换成 p90 ≤ 12 / 24 / 40。
          if (out.$1 >= 0.92 && out.$2 <= 40.0) outwardOk++;
          if (out.$1 >= 0.92 && out.$2 <= 12.0) candA++;
          if (out.$1 >= 0.85 && out.$2 <= 24.0) candB++;
          if (out.$1 >= 0.80 && out.$2 <= 40.0) candC++;
        }
        if (diag != null) {
          ratios.add(diag.$1);
          spreads.add(diag.$2);
        }
        if (sampleBoxFill(
              rgba: img.rgba,
              width: img.width,
              height: img.height,
              quad: q,
            )
            ?.color !=
            null) {
          ok++;
        }
      }
      final n = result.blocks.length;
      var a = 0, b = 0, c = 0;
      for (final blk in result.blocks) {
        final d = _outwardBand(
          img.rgba,
          img.width,
          img.height,
          blk.quad.map((v) => v.toDouble()).toList(),
        );
        if (d == null) continue;
        if (d.$1 >= 0.92 && d.$2 <= 12.0) a++;
        if (d.$1 >= 0.85 && d.$2 <= 24.0) b++;
        if (d.$1 >= 0.80 && d.$2 <= 40.0) c++;
      }
      if (n > 0 && a == n) pageAllA++;
      if (n > 0 && b == n) pageAllB++;
      if (n > 0 && c == n) pageAllC++;
      boxes += result.blocks.length;
      fillable += ok;
      // ignore: avoid_print
      outRatios.sort();
      outSpreads.sort();
      double mid(List<double> l) =>
          l.isEmpty ? 0 : l[(l.length ~/ 2).clamp(0, l.length - 1)];
      // ignore: avoid_print
      print(
        '   往**框外**扩一圈（AABB 外 1–8 px 的环带，量同一把尺）：'
        'flatRatio ${outRatios.isEmpty ? '—' : '${outRatios.first.toStringAsFixed(2)} / 中位 ${mid(outRatios).toStringAsFixed(2)} / 最高 ${outRatios.last.toStringAsFixed(2)}'}'
        '，偏离 ${outSpreads.isEmpty ? '—' : '${outSpreads.first.toStringAsFixed(1)} / 中位 ${mid(outSpreads).toStringAsFixed(1)}'}'
        '，候选判据可放行：p90≤40 且占比≥0.92 → $outwardOk 框；'
        'p90≤12 且≥0.92 → $candA 框；p90≤24 且≥0.85 → $candB 框；p90≤40 且≥0.80 → $candC 框'
        '（共 ${result.blocks.length} 框）',
      );
      ratios.sort();
      spreads.sort();
      // ignore: avoid_print
      print(
        '   采色带（同一把尺自己重算一遍）：flatRatio '
        '${ratios.isEmpty ? '—' : '${ratios.first.toStringAsFixed(2)} / 中位 ${ratios[(ratios.length ~/ 2).clamp(0, ratios.length - 1)].toStringAsFixed(2)} / 最高 ${ratios.last.toStringAsFixed(2)}'}'
        '，离中位最大偏离 '
        '${spreads.isEmpty ? '—' : '${spreads.first.toStringAsFixed(1)} / 中位 ${spreads[(spreads.length ~/ 2).clamp(0, spreads.length - 1)].toStringAsFixed(1)} / 最小达标线 12.0'}',
      );
      print(
        '${page.split('/').last}：${ok}/${result.blocks.length} 框采得出平色，'
        '框宽 ${widths.isEmpty ? 0 : widths.reduce((a, b) => a < b ? a : b)}–'
        '${widths.isEmpty ? 0 : widths.reduce((a, b) => a > b ? a : b)} px，'
        '框高 ${heights.isEmpty ? 0 : heights.reduce((a, b) => a < b ? a : b)}–'
        '${heights.isEmpty ? 0 : heights.reduce((a, b) => a > b ? a : b)} px',
      );
    }
    // ignore: avoid_print
    // ignore: avoid_print
    print(
      '合计：$fillable/$boxes 框采得出平色底'
      '（${boxes == 0 ? 'n/a' : (100 * fillable / boxes).toStringAsFixed(1)}%）'
      '；框外环带在三种候选阈值下的**整页全框通过率**：'
      'p90≤12/占比≥0.92 → $pageAllA/${pages.length} 页，'
      'p90≤24/≥0.85 → $pageAllB/${pages.length} 页，'
      'p90≤40/≥0.80 → $pageAllC/${pages.length} 页'
      '（生产是「有一框不过就整页不填」⇒ 只有整页通过率才算省时间）',
    );
    // 这条判据只钉「量到了东西」，不钉比例：比例是这一轮要看的数，写成阈值就是把结论焊死。
    expect(boxes, greaterThan(0), reason: '一页都没量到，数字不算数');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// 诊断用：把 `sampleBoxFill` 的那两条数**原样重算一遍**打印出来。
/// 生产判据仍然是 `sampleBoxFill` 本身 —— 这里不第二个真源，只是它拒绝时不报数，
/// 而「0/121」这个结论必须能看出是被哪一条挡住的（阈值太严？还是采到了框外？）。
(double, double)? _sampleForDiagnosis(
  Uint8List rgba,
  int width,
  int height,
  List<double> quad,
) {
  const inset = 3, ringPx = 4, tolerance = 12;
  final xs = [quad[0], quad[2], quad[4], quad[6]];
  final ys = [quad[1], quad[3], quad[5], quad[7]];
  var x0 = xs.reduce(math.min).round() + inset;
  var y0 = ys.reduce(math.min).round() + inset;
  var x1 = xs.reduce(math.max).round() - inset;
  var y1 = ys.reduce(math.max).round() - inset;
  x0 = x0.clamp(0, width - 1);
  y0 = y0.clamp(0, height - 1);
  x1 = x1.clamp(0, width - 1);
  y1 = y1.clamp(0, height - 1);
  if (x1 <= x0 || y1 <= y0) return null;
  final ring = <int>[];
  for (var y = y0; y <= y1; y++) {
    final edgeRow = y < y0 + ringPx || y > y1 - ringPx;
    for (var x = x0; x <= x1; x++) {
      if (!edgeRow && !(x < x0 + ringPx || x > x1 - ringPx)) continue;
      ring.add((y * width + x) * 4);
    }
  }
  if (ring.length < 16) return null;
  int median(Iterable<int> v) {
    final s = v.toList()..sort();
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) ~/ 2;
  }
  final rs = median(ring.map((i) => rgba[i]));
  final gs = median(ring.map((i) => rgba[i + 1]));
  final bs = median(ring.map((i) => rgba[i + 2]));
  var inside = 0;
  var hi = 0;
  for (final i in ring) {
    final delta = math.max(
      (rgba[i] - rs).abs(),
      math.max((rgba[i + 1] - gs).abs(), (rgba[i + 2] - bs).abs()),
    );
    if (delta <= tolerance) inside++;
    if (delta > hi) hi = delta;
  }
  return (inside / ring.length, hi.toDouble());
}

/// 诊断用第二条尺：**框外**的环带（AABB 往外 1–8 px），其余算法与生产同一套
/// （中位色 + 离中位色的最大偏离）。之所以用 AABB：真页的 quad 大多接近正框，
/// 而这一条只是量「往外交一圈能不能落在气泡自己的底上」，不是生产判据。
(double, double)? _outwardBand(
  Uint8List rgba,
  int width,
  int height,
  List<double> quad, {
  int gap = 1,
  int depth = 8,
  int tolerance = 12,
}) {
  final xs = [quad[0], quad[2], quad[4], quad[6]];
  final ys = [quad[1], quad[3], quad[5], quad[7]];
  final bx0 = xs.reduce(math.min).round();
  final bx1 = xs.reduce(math.max).round();
  final by0 = ys.reduce(math.min).round();
  final by1 = ys.reduce(math.max).round();
  final x0 = (bx0 - gap - depth).clamp(0, width - 1);
  final x1 = (bx1 + gap + depth).clamp(0, width - 1);
  final y0 = (by0 - gap - depth).clamp(0, height - 1);
  final y1 = (by1 + gap + depth).clamp(0, height - 1);
  final band = <int>[];
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final insideBox = x >= bx0 + gap && x <= bx1 - gap && y >= by0 + gap && y <= by1 - gap;
      if (insideBox) continue;
      band.add((y * width + x) * 4);
    }
  }
  if (band.length < 16) return null;
  int median(Iterable<int> v) {
    final s = v.toList()..sort();
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) ~/ 2;
  }
  final rs = median(band.map((i) => rgba[i]));
  final gs = median(band.map((i) => rgba[i + 1]));
  final bs = median(band.map((i) => rgba[i + 2]));
  var inside = 0;
  var hi = 0;
  for (final i in band) {
    final delta = math.max(
      (rgba[i] - rs).abs(),
      math.max((rgba[i + 1] - gs).abs(), (rgba[i + 2] - bs).abs()),
    );
    if (delta <= tolerance) inside++;
    if (delta > hi) hi = delta;
  }
  final sorted = <int>[];
  for (final i in band) {
    sorted.add(math.max(
      (rgba[i] - rs).abs(),
      math.max((rgba[i + 1] - gs).abs(), (rgba[i + 2] - bs).abs()),
    ));
  }
  sorted.sort();
  final p90 = sorted[((sorted.length * 0.90).floor()).clamp(0, sorted.length - 1)];
  return (inside / band.length, p90.toDouble());
}
