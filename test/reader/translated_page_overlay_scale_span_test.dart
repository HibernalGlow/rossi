/// 「字号必须跟着底图倍率走」这条判据的**独立**版本。
///
/// 渲染台（`test/ocr/translated_page_layer_overlay_bench_test.dart`）也量这一维，但那条要
/// 真权重、真页与擦字底图，跑一次十几秒，而且它量的是「整页并集」的跨度 —— 最靠边那一框
/// 有没有墨就会把比值带走（2026-10-04 那条 1.55 就是这么来的：尺子喂了两遍放大）。
/// 这一份用合成数据把同一个性质钉死：同一批框、同一个图层，画在 1× 与 2× 的盒子上，
/// 墨的竖直跨度就该差两倍、墨量按面积走。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/translated_page_overlay.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';

const _page = 200;

/// 一框一句，故意放三框：单框会因换行数被 4 舍 5 入，多框的跨度才是稳的量。
const _texts = ['危机契约', '还给我！', '那个田舍'];

TranslatedPageLayer _layer() => TranslatedPageLayer(
  pageWidth: _page,
  pageHeight: _page,
  boxes: [
    for (var i = 0; i < _texts.length; i++)
      TranslatedBox(
        quad: [
          20.0,
          20.0 + i * 60.0,
          180.0,
          20.0 + i * 60.0,
          180.0,
          70.0 + i * 60.0,
          20.0,
          70.0 + i * 60.0,
        ],
        source: 'トカゲじゃ',
        text: _texts[i],
      ),
  ],
);

/// 把图层画进一张 `size` 的白底，回 RGBA。
Future<({Uint8List rgba, int width, int height})> _paint(double side) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, side, side),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  paintTranslatedPageLayer(
    canvas,
    layer: _layer(),
    size: ui.Size(side, side),
  );
  final image = await recorder.endRecording().toImage(side.round(), side.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: side.round(),
    height: side.round(),
  );
}

/// 墨的竖直跨度：第一个有墨的行到最后一个有墨的行。
///
/// 先看 alpha：白底上没画到的地方是 255，但这一张是**不透明**白，
/// 判据仍按「三通道都暗」数墨，与渲染台同一定义。
int _inkSpan(
  ({Uint8List rgba, int width, int height}) r,
  List<double> rows,
) {
  var first = -1, last = -1;
  for (final y0 in rows) {
    final y = y0.round();
    for (var x = 0; x < r.width; x++) {
      final i = (y * r.width + x) * 4;
      if (r.rgba[i] < 64 && r.rgba[i + 1] < 64 && r.rgba[i + 2] < 64) {
        if (first < 0) first = y;
        last = y;
        break;
      }
    }
  }
  return first < 0 ? 0 : last - first;
}

int _inkCount(({Uint8List rgba, int width, int height}) r) {
  var n = 0;
  for (var i = 0; i + 2 < r.rgba.length; i += 4) {
    if (r.rgba[i] < 64 && r.rgba[i + 1] < 64 && r.rgba[i + 2] < 64) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一份图层：盒子大一倍，墨的竖直跨度也大一倍', () async {
    final one = await _paint(_page.toDouble());
    final two = await _paint(_page * 2.0);
    // 三框各自的行范围（1× 上是 20..70 / 80..130 / 140..190；2× 上全部翻倍）。
    final rows1 = [for (final y in List.generate(51, (i) => 20.0 + i)) y];
    final rows2 = [for (final y in List.generate(102, (i) => 40.0 + i)) y];
    final span1 = _inkSpan(one, rows1);
    final span2 = _inkSpan(two, rows2);
    // 这一框在 1× 上高 50 px，一行字占掉二十几 px —— 跨度只要真实存在就够了，
    // 判据看的是**两倍的比值**，不是绝对高度。
    expect(span1, greaterThan(10), reason: '1× 连跨度都没有 = 尺子无效');
    final ratio = span2 / span1;
    expect(
      ratio,
      inInclusiveRange(1.9, 2.1),
      reason: '2× 的字高只有 1× 的 ${ratio.toStringAsFixed(2)} 倍 —— '
          '倍率只放大了画布、没放大排版决策（大气泡配小字）',
    );
  });

  test('同一份图层：墨量按面积走（不是只把画布拉大）', () async {
    final one = await _paint(_page.toDouble());
    final two = await _paint(_page * 2.0);
    final ink1 = _inkCount(one);
    final ink2 = _inkCount(two);
    expect(ink1, greaterThan(300), reason: '1× 就没画出多少墨 = 尺子无效');
    // 抗锯齿栅格不可能精确 ×4，给 2–8 倍区间（与渲染台同一档宽容度）。
    expect(
      ink2,
      inInclusiveRange(ink1 * 2, ink1 * 8),
      reason: '2× 墨量没按面积走：$ink1 → $ink2',
    );
  });

  test('证伪位：把倍率写死成 1，跨度比就该掉到 1 附近', () async {
    final one = await _paint(_page.toDouble());
    // 同一张 2× 的画布，但只按 1× 画 —— 这正是「忘了把 scale 交给 paintLayer」那种错。
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, _page * 2, _page * 2),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    TranslatedPageRenderer.paintLayer(canvas, _layer());
    final image = await recorder.endRecording().toImage(_page * 2, _page * 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final rgba = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final rows = [for (final y in List.generate(51, (i) => 20.0 + i)) y];
    final stuck = _inkSpan((rgba: rgba, width: _page * 2, height: _page * 2), rows);
    final ratio = stuck / _inkSpan(one, rows);
    expect(
      ratio,
      lessThan(1.2),
      reason: '这把尺看不见「倍率没进排版」= 上面那条判据是假的',
    );
  });
}
