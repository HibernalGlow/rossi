import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 从**原图**上采一个文本框自己的底色，供「按轮廓填色替代擦字」那一档用。
///
/// # 为什么这可能比擦字更好
///
/// 现在那条路是 LaMa：整页 768 边长推理 2.7 s 起步（实测同页掩膜 9% 时 36 ms 前处理 +
/// 6725 ms 推理 + 72 ms 合成），而漫画白气泡里的文字，本来就是被一片纯白包围的 ——
/// 用一个纯白多边形盖掉它，视觉上与修复结果没区别，却几乎不花时间。
///
/// # 但它只对「平色」成立
///
/// 拟声词压在网点、速度线、头发、彩底上的那一类，填一个色块就是糊一脸
/// （ADR-0018 §决定 2 里「拟声词区明确不处理」正是这个缺口，擦字在那儿也糊）。
/// 所以这里**不返回"最像的颜色"，而是返回「能不能填」**：
/// 采到的像素不够一致就交回 null，由调用方退回擦字那一条。
/// 判据是量出来的，不是感觉：`flatRatio` 与 `spread` 两条一起看（见 [sampleBoxFill]）。
class BoxFill {
  const BoxFill({required this.color, required this.flatRatio, required this.spread});

  /// 采样得到的底色。
  final ui.Color color;

  /// 有多少比例的采样像素落在中位色 ±容差内。1.0 = 完全平色。
  final double flatRatio;

  /// 通道方向上的最大离散（0–255）。平色接近 0。
  final double spread;

  @override
  String toString() =>
      '#BoxFill(${color.toARGB32().toRadixString(16)}, '
      'flat ${flatRatio.toStringAsFixed(3)}, spread ${spread.toStringAsFixed(1)})';
}

/// 沿框边**内侧**一圈采样的宽度（像素）。
///
/// 为什么不采整框：框里大半是文字笔画本身，采整框会把墨水的黑混进中位数；
/// 为什么不贴着边采：边界外是气泡外（可能是画面），边界内几像素才是气泡自己的底。
const _ringPx = 4;

/// 采样时往里再缩的距离（像素）。
///
/// 检测框是紧贴字形的，最外一圈常带笔画的抗锯齿与网点，所以要避开第一圈。
const _insetPx = 3;

/// 判「可以填」的两条阈值。都是**量出来的**，改它们要连同下面的对照测试一起改。
///
/// ⚠️ 2026-10-04 拿 8 页真页重量过这一档：**0/121 框能填**（`test/ocr/bubble_fill_real_page_probe_test.dart`）。
/// 框内侧那圈采到的是笔画与网点（真页的 OCR 框贴着字形、不是贴着气泡），偏离中位 243–251。
/// 把带子挪到框外能拿到平色（占比中位升到 0.75–0.99），但生产的规则是「一框不过就整页不填」，
/// 于是整页通过率仍然 **0/8 页** ⇒ 别指望调这两个数把「跳过擦字」救回来：那需要改**采样方向 + 页级规则**，
/// 并且回渲染台重新立证字压字率（现在的 0.085 / 0.000 是在「擦 / 不擦」两端量的）。
const _minFlatRatio = 0.92;
const _maxSpread = 12.0;

/// 采出这个框的底色，并判断它能不能被填。
///
/// [rgba] 是**行主序 RGBA8888**（`ui.ImageByteFormat.rawRgba` 的原样字节），
/// [width] 是每行像素数（= 图像宽，不是字节数）。
/// [quad] 是 8 个数（左上/右上/右下/左下），底图物理像素坐标 —— 与图层存的同一把尺子。
///
/// 返回 null 的含义是**「这一页这一框不许填」**，不是「出错了」：
/// 调用方要么退回擦字，要么整页退回擦字（哪个更好由上层判，见
/// `TranslatedPageBuilder` 的赋值处 —— 只要有一框不能填，填色档就不成立，
/// 因为「一半填一半擦」会在同一页上留下两种明显不同的底）。
BoxFill? sampleBoxFill({
  required Uint8List rgba,
  required int width,
  required int height,
  required List<double> quad,
}) {
  if (quad.length != 8) {
    throw ArgumentError('四角点必须是 8 个数，实际 ${quad.length}');
  }
  final xs = [quad[0], quad[2], quad[4], quad[6]];
  final ys = [quad[1], quad[3], quad[5], quad[7]];
  var x0 = xs.reduce(math.min).round() + _insetPx;
  var y0 = ys.reduce(math.min).round() + _insetPx;
  var x1 = xs.reduce(math.max).round() - _insetPx;
  var y1 = ys.reduce(math.max).round() - _insetPx;
  x0 = x0.clamp(0, width - 1);
  y0 = y0.clamp(0, height - 1);
  x1 = x1.clamp(0, width - 1);
  y1 = y1.clamp(0, height - 1);
  if (x1 <= x0 || y1 <= y0) return null;

  // 内缩之后仍然采**边圈**，不采内部：内部的墨水占比远高于边圈。
  final ring = <int>[];
  for (var y = y0; y <= y1; y++) {
    final edgeRow = y < y0 + _ringPx || y > y1 - _ringPx;
    for (var x = x0; x <= x1; x++) {
      final edgeCol = x < x0 + _ringPx || x > x1 - _ringPx;
      if (!edgeRow && !edgeCol) continue;
      final i = (y * width + x) * 4;
      if (i + 2 >= rgba.length) continue;
      ring.add(i);
    }
  }
  if (ring.length < 16) return null;

  final rs = _medianOf(ring.map((i) => rgba[i]));
  final gs = _medianOf(ring.map((i) => rgba[i + 1]));
  final bs = _medianOf(ring.map((i) => rgba[i + 2]));
  final tolerance = 12;
  var inside = 0;
  var lo = 255, hi = 0;
  for (final i in ring) {
    final dr = (rgba[i] - rs).abs();
    final dg = (rgba[i + 1] - gs).abs();
    final db = (rgba[i + 2] - bs).abs();
    final delta = math.max(dr, math.max(dg, db));
    if (delta <= tolerance) inside++;
    if (delta < lo) lo = delta;
    if (delta > hi) hi = delta;
  }
  final ratio = inside / ring.length;
  // spread 用「离中位色的最大偏离」而不是逐通道极差：
  // 一条穿过框边的深色线会同时抬高极差的两端，而这个量只说明「有一圈不像」。
  final fill = BoxFill(
    color: ui.Color.fromARGB(255, rs, gs, bs),
    flatRatio: ratio,
    spread: hi.toDouble(),
  );
  return fill.flatRatio >= _minFlatRatio && fill.spread <= _maxSpread ? fill : null;
}

/// 中位数（四舍五入成 0–255 的整数）。
int _medianOf(Iterable<int> values) {
  final sorted = values.toList()..sort();
  final n = sorted.length;
  if (n == 0) return 0;
  return n.isOdd ? sorted[n ~/ 2] : ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
}
