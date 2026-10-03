/// `paintLayer` 用 `canvas.scale(倍率)` 画放大的译文，字到底糊不糊 —— 这是量出来的，
/// 不是论证出来的。
///
/// 三张图同一页内容：
/// - **P（被测）**：800×600 画布，`canvas.scale(2)` 之后按 1× 的字号排版画字。
///   这就是叠层模式实际走的那条路。
/// - **C（清晰的参照）**：800×600 画布，直接把倍率乘进排版参数（`scale: 2`），
///   全程没有缩放变换。这条一定是清晰的。
/// - **B（一定糊的对照）**：先在 400×300 上画好，再把那张**位图**放大到 800×600。
///   这是「先烤一张小图再拉伸」的写法，也是 P 如果走错方向时会变成的样子。
///
/// 判据用锐度而不是像素相等：`ink / (ink + 中间灰)`。字糊掉时黑色像素会被抗锯齿
/// 摊成一片中间灰，这个比值明显掉下去。C 与 B 就是这把尺子的阳性与阴性对照 ——
/// 少了它们，「P 看着挺清楚」只是我自己的眼睛。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';

const _w = 400, _h = 300;

/// 一句话 + 一个窄高框：横排与竖排两条排版分支都要在放大下被看着。
final _layer = TranslatedPageLayer(
  pageWidth: _w,
  pageHeight: _h,
  boxes: [
    TranslatedBox(
      quad: const [40, 30, 200, 30, 200, 150, 40, 150].map((v) => v.toDouble()).toList(),
      source: '危機契約！？あなた、無事なの？',
      text: '危机契约！？你没事吧？有没有受伤？',
    ),
    TranslatedBox(
      quad: const [240, 40, 300, 40, 300, 250, 240, 250].map((v) => v.toDouble()).toList(),
      source: 'しばらく見てない間に作戦に行ってたの',
      text: '好几年没见的这段时间里你去执行作战了吧',
    ),
  ],
);

Future<ui.Image> _paint(void Function(ui.Canvas c) body, int outW, int outH) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  body(canvas);
  return recorder.endRecording().toImage(outW, outH);
}

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 锐度：近黑的墨 vs 被抗锯齿摊开的中间灰。比值越高越锐。
({double ratio, int ink, int mid}) _sharpness(Uint8List rgba, int stride) {
  var ink = 0, mid = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final v = rgba[i];
    if (v < 64) {
      ink++;
    } else if (v >= 64 && v <= 192) {
      mid++;
    }
  }
  expect(ink, greaterThan(2000), reason: '这张图上根本没画出多少字，尺子无效');
  return (ratio: ink / (ink + mid), ink: ink, mid: mid);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvas.scale 画放大译文：锐度必须与「把倍率乘进排版」同档，明显高于位图放大', () async {
    await TranslatedPageRenderer.ensureFontLoaded();

    // C：把倍率乘进参数，全程无变换 —— 清晰度上限。
    final directImg = await _paint(
      (c) => TranslatedPageRenderer.paintLayer(c, _layer, scale: 2),
      _w * 2,
      _h * 2,
    );
    final direct = await _rgba(directImg);
    directImg.dispose();
    // B：画一张 1× 的位图再拉伸 —— 糊的下限。
    final small = await _paint(
      (c) => TranslatedPageRenderer.paintLayer(c, _layer),
      _w,
      _h,
    );
    final upscaledImg = await _paint((c) {
      c.scale(2);
      c.drawImage(small, ui.Offset.zero, ui.Paint());
    }, _w * 2, _h * 2);
    final upscaled = await _rgba(upscaledImg);
    upscaledImg.dispose();
    small.dispose();
    // P：叠层模式实际那条路。
    final probedImg = await _paint((c) {
      c.scale(2);
      TranslatedPageRenderer.paintLayer(c, _layer);
    }, _w * 2, _h * 2);
    final probed = await _rgba(probedImg);
    probedImg.dispose();

    final c = _sharpness(direct, _w * 2);
    final b = _sharpness(upscaled, _w * 2);
    final p = _sharpness(probed, _w * 2);

    // 尺子先自证：清晰与糊这两端必须真的分得开，否则下面那句断言没有意义。
    expect(
      c.ratio,
      greaterThan(b.ratio * 1.2),
      reason: '对照没拉开：C=${c.ratio} B=${b.ratio} —— 这把尺子看不见模糊',
    );
    expect(
      p.ratio,
      greaterThan(b.ratio * 1.15),
      reason: 'canvas.scale 这条路和位图放大一样糊：P=${p.ratio} B=${b.ratio} '
          '—— 必须改成把倍率乘进排版参数',
    );
    // 允许一点点差：Skia 在 CTM 下取字形位图时的网格与直接放大字号不完全同。
    // 实测：P 与 C 的比值**逐位相同**（0.6904563784164373），位图放大那侧只有 0.4551。
    // 所以 Skia 在 CTM 下是按目标尺寸栅格化字形的，缩放路径不损失清晰度。
    expect(
      p.ratio,
      greaterThan(c.ratio * 0.85),
      reason: 'P=${p.ratio} 明显低于清晰的 C=${c.ratio}：缩放路径损失了清晰度',
    );
  });
}
