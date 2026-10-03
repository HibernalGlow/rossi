/// 叠层在**半页槽位**上的裁剪（横长页拆半读）。
///
/// 为什么单开一份：图层里的坐标是**整页**物理像素，而拆半读时这一格只画整页的一半。
/// 上层曾经的处理是「半页干脆不挂叠层」，于是芯片说「译文页」、画面上一个中文都没有 ——
/// 状态是真的（那一页确实翻好了），只是没画出来，属于最难发现的一类错。
/// 现在按 `PageSlice.uvRect` 裁，这一份就是钉住「裁对了」的判据。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
import 'package:zephyr/reader/translated_page_overlay.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';

/// 一页 200×200：左框在 x 10..80，右框在 x 120..190，纵向都落在 80..120。
/// 两框之间留了一段**谁都盖不到**的空档（x 81..119），下面的判据就靠它分辨
/// 「裁对了」与「整页照画然后被盒子切掉」。
TranslatedPageLayer _layer() => const TranslatedPageLayer(
  pageWidth: 200,
  pageHeight: 200,
  boxes: [
    TranslatedBox(
      quad: [10.0, 80.0, 80.0, 80.0, 80.0, 120.0, 10.0, 120.0],
      source: 'L',
      text: 'LEFT',
    ),
    TranslatedBox(
      quad: [120.0, 80.0, 190.0, 80.0, 190.0, 120.0, 120.0, 120.0],
      source: 'R',
      text: 'RIGHT',
    ),
  ],
);

typedef _Raster = ({Uint8List rgba, int width, int height});

Future<_Raster> _paint(PageSlice slice, double boxWidth, double boxHeight) async {
  final size = ui.Size(boxWidth, boxHeight);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintTranslatedPageLayer(canvas, layer: _layer(), size: size, slice: slice);
  final image = await recorder
      .endRecording()
      .toImage(boxWidth.round(), boxHeight.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: boxWidth.round(),
    height: boxHeight.round(),
  );
}

/// 有墨的列号集合。
///
/// 必须先看 alpha：这张图是**透明底**，没画到的像素是 (0,0,0,0)，
/// 只按「三个通道都暗」判会把整张空白画布读成满屏墨（第一版就是这么假的绿→红都判不对）。
Set<int> _inkColumns(_Raster r) {
  final out = <int>{};
  for (var y = 0; y < r.height; y++) {
    for (var x = 0; x < r.width; x++) {
      final i = (y * r.width + x) * 4;
      if (r.rgba[i + 3] == 0) continue;
      if (r.rgba[i] < 64 && r.rgba[i + 1] < 64 && r.rgba[i + 2] < 64) {
        out.add(x);
      }
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('overlaySliceRect：与底图那一路同一把尺', () {
    test('整页 = 全幅', () {
      expect(
        overlaySliceRect(pageWidth: 800, pageHeight: 1200, slice: PageSlice.full),
        const ui.Rect.fromLTRB(0, 0, 800, 1200),
      );
    });

    test('左右半页各占一半，且两半严丝合缝拼成整页', () {
      final left = overlaySliceRect(
        pageWidth: 800,
        pageHeight: 1200,
        slice: PageSlice.left,
      );
      final right = overlaySliceRect(
        pageWidth: 800,
        pageHeight: 1200,
        slice: PageSlice.right,
      );
      expect(left, const ui.Rect.fromLTRB(0, 0, 400, 1200));
      expect(right, const ui.Rect.fromLTRB(400, 0, 800, 1200));
      expect(right.left, left.right, reason: '两半之间不许有缝或有叠');
      expect(left.height, 1200, reason: '只切左右，纵向不许被动');
    });
  });

  test('整页：两框都有墨，中间那段空档没有墨', () async {
    final ink = _inkColumns(await _paint(PageSlice.full, 200, 200));
    expect(ink, isNotEmpty, reason: '一个墨点都没有 = 尺子无效，后面的断言全是假绿');
    final leftMost = ink.reduce((a, b) => a < b ? a : b);
    final rightMost = ink.reduce((a, b) => a > b ? a : b);
    expect(leftMost, lessThan(81), reason: '左框没画出来');
    expect(rightMost, greaterThan(119), reason: '右框没画出来');
    expect(
      ink.where((x) => x >= 82 && x <= 118),
      isEmpty,
      reason: '两框之间的空档出现墨 = 有什么被画到了不该在的位置',
    );
  });

  test('左半页：只留左框，右框一个字都不许漏进来', () async {
    final raster = await _paint(PageSlice.left, 100, 200);
    final ink = _inkColumns(raster);
    expect(ink, isNotEmpty, reason: '左半页连墨都没有 = 这一格根本没画');
    expect(
      ink.reduce((a, b) => a > b ? a : b),
      lessThan(90),
      reason: '左半页上出现了 x≥90 的墨 —— 右框（x≥120）漏进来了',
    );
  });

  test('右半页：右框被搬进这一格（不裁不搬就一个墨点都没有）', () async {
    final ink = _inkColumns(await _paint(PageSlice.right, 100, 200));
    expect(
      ink,
      isNotEmpty,
      reason:
          '右半页没有墨 = 没按槽位平移：右框在整页上是 x 120..190，'
          '不裁不搬就落在 100 宽的盒子外面，被切干净了',
    );
    final leftMost = ink.reduce((a, b) => a < b ? a : b);
    expect(
      leftMost,
      greaterThan(10),
      reason: '左框（整页 x 10..80 → 这一格 x -90..-20）该完全在盒子外',
    );
  });

  test('左右两半各自与整页对得上：同一框在两边是同一批字', () async {
    // 阳性对照：把整页的墨列按 100 切成两半，与两个半页各自量到的墨列比。
    // 只比「有没有墨」会漏掉「裁了但没搬」这一种错（那时两半都还是左框）。
    final full = _inkColumns(await _paint(PageSlice.full, 200, 200));
    final left = _inkColumns(await _paint(PageSlice.left, 100, 200));
    final right = _inkColumns(await _paint(PageSlice.right, 100, 200));
    expect(
      left.union(right.map((x) => x + 100).toSet()),
      equals(full),
      reason: '两半拼回去应当正好是整页那批墨列，差一个都不行',
    );
  });
}
