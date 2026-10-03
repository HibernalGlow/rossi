/// 气泡底色采样的验证。
///
/// 这个采样的产物不是「好不好看」，而是一个**闸门**：只有采到平色的框才允许用
/// 填色替代擦字。所以这里的重点不是「能算出一个颜色」，而是**平色判据既不放过
/// 脏底、也不冤枉干净的气泡** —— 两头都要有对照，缺一头这条判据就是摆设。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/bubble_fill.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';

const _w = 120, _h = 120;

/// 一个左上到右下渐变之外的简单画布：整幅纯色，之后按图案往上改。
Uint8List _canvas(int r, int g, int b) {
  final out = Uint8List(_w * _h * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  return out;
}

void _dot(Uint8List rgba, int x, int y, int r, int g, int b) {
  if (x < 0 || y < 0 || x >= _w || y >= _h) return;
  final i = (y * _w + x) * 4;
  rgba[i] = r;
  rgba[i + 1] = g;
  rgba[i + 2] = b;
}

void _box(Uint8List rgba, int x0, int y0, int x1, int y1, int r, int g, int b) {
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      _dot(rgba, x, y, r, g, b);
    }
  }
}

/// 一个 20..90 的框，字（黑）画在框中央，边圈留白。
const _quad = [
  20.0, 20.0, //
  90.0, 20.0, //
  90.0, 90.0, //
  20.0, 90.0, //
];

BoxFill? _sample(Uint8List rgba, {List<double>? quad}) => sampleBoxFill(
  rgba: rgba,
  width: _w,
  height: _h,
  quad: quad ?? _quad,
);

void main() {
  test('白气泡里的黑字：判可填，且颜色是白不是黑', () {
    final rgba = _canvas(255, 255, 255);
    // 墨水只占框的中部，边圈仍是纯白 —— 采整框会被墨污染，采边圈不会。
    _box(rgba, 30, 30, 80, 80, 10, 10, 10);
    final fill = _sample(rgba);
    expect(fill, isNotNull, reason: '干净白气泡必须放行，否则填色档等于永远不生效');
    expect(fill!.color, ui.Color.fromARGB(255, 255, 255, 255));
    expect(fill.flatRatio, greaterThan(0.99));
  });

  test('平色淡黄气泡：采到的是它自己的黄，不是硬编码白', () {
    final rgba = _canvas(250, 244, 214);
    _box(rgba, 35, 35, 75, 75, 20, 20, 20);
    final fill = _sample(rgba);
    expect(fill, isNotNull);
    expect(fill!.color, ui.Color.fromARGB(255, 250, 244, 214));
  });

  test('网点底（交替黑白）：必须判不可填', () {
    // 阳性对照的反面：这种底上填一块纯色就是糊一脸，判据必须拦下。
    final rgba = _canvas(255, 255, 255);
    for (var y = 0; y < _h; y += 2) {
      for (var x = 0; x < _w; x += 2) {
        _dot(rgba, x, y, 0, 0, 0);
      }
    }
    expect(_sample(rgba), isNull);
  });

  test('一条深色边穿过框边：也要判不可填', () {
    final rgba = _canvas(255, 255, 255);
    _box(rgba, 30, 30, 80, 80, 10, 10, 10);
    _box(rgba, 0, 22, _w - 1, 24, 12, 12, 12); // 压在框的上边圈上
    expect(_sample(rgba), isNull);
  });

  test('框太小采不满一圈：判不可填而不是猜一个颜色', () {
    final rgba = _canvas(255, 255, 255);
    final tiny = <double>[50, 50, 54, 50, 54, 54, 50, 54];
    expect(sampleBoxFill(rgba: rgba, width: _w, height: _h, quad: tiny), isNull);
  });

  test('四角点不是 8 个数：抛，不静默返回 null', () {
    // 静默 null 会被读成「这块底不干净」，而真实原因是接线错了 —— 两件事不能混。
    expect(
      () => sampleBoxFill(
        rgba: _canvas(255, 255, 255),
        width: _w,
        height: _h,
        quad: const [1, 2, 3],
      ),
      throwsArgumentError,
    );
  });

  test('阈值这把尺子看得见「接近平色」的边界', () {
    // 采样带是「内缩 3 px 之后的最外 4 px」，也就是 y/x 的 23..26 与 84..87。
    // 脏像素必须画在**这一带里** —— 画在内缩之外的话，这条对照会假绿：
    // 它测的不是判据，而是"我瞄对位置了没有"。
    final ok = _canvas(252, 252, 252);
    _box(ok, 30, 30, 80, 80, 10, 10, 10);
    expect(_sample(ok), isNotNull, reason: '干净平色必须放行');

    final dirty = _canvas(252, 252, 252);
    _box(dirty, 23, 23, 87, 25, 8, 8, 8); // 上采样带整条压黑
    _box(dirty, 23, 84, 87, 87, 8, 8, 8); // 下采样带整条压黑
    _box(dirty, 30, 30, 80, 80, 10, 10, 10);
    expect(_sample(dirty), isNull, reason: '采样带三分之一以上是脏的还放行，填色会盖出花边');
  });

  group('填色真的盖得住原字', () {
    /// 底图是**黑**的（相当于原字/网点完全遮住底），填色后框内必须变成填的那个颜色。
    /// 用黑而不是白做底，是为了让「没填上」与「填了白」在像素上不可能混。
    Future<Uint8List> paint({required ui.Color? fill, double scale = 1}) async {
      final layer = TranslatedPageLayer(
        pageWidth: _w,
        pageHeight: _h,
        boxes: [
          TranslatedBox(
            quad: List<double>.from(_quad),
            source: '危機契約',
            text: '危机契约',
            fill: fill,
          ),
        ],
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, _w.toDouble() * scale, _h.toDouble() * scale),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      TranslatedPageRenderer.paintLayer(canvas, layer, scale: scale);
      final image = await recorder.endRecording().toImage(
        (_w * scale).round(),
        (_h * scale).round(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    int at(Uint8List rgba, int width, int x, int y) => rgba[(y * width + x) * 4];

    test('给了 fill：框内变成填的色，不再是黑底', () async {
      final png = await paint(fill: const ui.Color.fromARGB(255, 250, 244, 214));
      // 框内一角（离边 6 px，避开文字与外扩边）。
      expect(at(png, _w, 26, 26), greaterThan(200), reason: '填色没盖住这一角');
      // 框外仍是黑的：填色不许多盖到气泡外面。
      expect(at(png, _w, 5, 5), lessThan(30), reason: '填色溢出到框外了');
    });

    test('没给 fill：什么都不盖（黑底原样留着）', () async {
      final png = await paint(fill: null);
      expect(at(png, _w, 26, 26), lessThan(30));
    });

    test('叠到 2× 底图上时，填色跟着放大而不是只盖住 1× 的那块', () async {
      final scale = 2.0;
      final png = await paint(
        fill: const ui.Color.fromARGB(255, 255, 255, 255),
        scale: scale,
      );
      final w2 = (_w * scale).round();
      // 原来 (26,26) 的位置在 2× 上是 (52,52)；1× 坐标处必须还是黑的，
      // 否则说明倍率只乘了字号没乘几何。
      expect(at(png, w2, 52, 52), greaterThan(200), reason: '2× 上填色没跟着放大');
      expect(at(png, w2, 10, 10), lessThan(30), reason: '1× 位置也被盖住了 = 倍率没进几何');
    });
  });
}
