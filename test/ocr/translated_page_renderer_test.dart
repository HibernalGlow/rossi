/// 译文回填与翻译解析的验证。
///
/// 两件事分开测：
/// 1. `parseTranslatedLines` 是纯函数 —— 模型输出格式千奇百怪（漏制表符、编号加粗、
///    前面写一句「好的」），但**条数必须对得上**，因为漏译在成品页上表现为某个气泡空白，
///    而空白比错译更难被发现；
/// 2. 回填是真的画出了墨 —— 判据是**像素**：给定框内有深色像素，框与框之间的空白带一个墨点都没有
///    （字画到别人的地盘上，是最难靠肉眼发现的那类错）；
/// 3. 那团墨是**汉字**而不是豆腐块 —— 「有墨」这条太弱，豆腐块照样过，所以另有一条排列对照测试。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

/// 整页纯白的 PNG 底。所有像素断言都以它为参照，所以它必须**真的**铺满整页 ——
/// 下面「夹具本身铺满整页」那条就是专门守这个的：夹具漏了洞，其余像素断言全会变成假绿。
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

/// 「本不该有内容」的两种表现都算：深色像素，**或者透明像素**。
/// 透明单独算一类，是因为底图没铺满时它会让「没有墨」的断言假绿。
int _untouchedViolations(Uint8List rgba, int stride, ui.Rect rect) {
  var count = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * stride + x) * 4;
      if (rgba[i + 3] < 128) {
        count++;
        continue;
      }
      if (rgba[i] < 128 && rgba[i + 1] < 128 && rgba[i + 2] < 128) count++;
    }
  }
  return count;
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

/// 用**生产同一套**注册方式（[TranslatedPageRenderer.ensureFontLoaded]）把一段字打成正方形位图。
/// 固定 48 px 高、220 px 宽，两种排列的总宽相同，所以逐像素比较才有意义。
Future<Uint8List> _raster(String text) async {
  await TranslatedPageRenderer.ensureFontLoaded();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final builder =
      ui.ParagraphBuilder(
        ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
      )..pushStyle(
        ui.TextStyle(
          color: const ui.Color(0xFF111111),
          fontSize: 32,
          fontFamily: TranslatedPageRenderer.fontFamily,
        ),
      );
  builder.addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 220));
  canvas.drawParagraph(paragraph, const ui.Offset(4, 4));
  final image = await recorder.endRecording().toImage(240, 48);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 给定范围内墨的包围盒（找不到墨时返回零矩形）。
ui.Rect _inkBounds(Uint8List rgba, int stride, ui.Rect area) {
  var x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
  for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
    for (var x = area.left.toInt(); x < area.right.toInt(); x++) {
      final i = (y * stride + x) * 4;
      if (rgba[i] < 128 && rgba[i + 1] < 128 && rgba[i + 2] < 128) {
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x > x1) x1 = x;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return ui.Rect.zero;
  return ui.Rect.fromLTWH(
    x0.toDouble(),
    y0.toDouble(),
    (x1 - x0 + 1).toDouble(),
    (y1 - y0 + 1).toDouble(),
  );
}

OcrBlock _block(ui.Rect r) => OcrBlock(
  // FRB 把 Rust 的 Vec<f32> 映射成 Float32List，不是 List<double>。
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
  text: '原文',
  boxes: 1,
  truncated: false,
);

void main() {
  // 必须有 binding：没有它 `Picture.toImage` 在测试里产出的是**透明黑**，
  // 于是「框内有没有墨」这类像素断言会全假绿（这一条就是被它咬出来的）。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseTranslatedLines', () {
    test('吃得下制表符、编号加粗、以及句首的客套话', () {
      const raw = '''
好的，这是译文：
1\t你好，世界！
**2**  这是第二条。
3: 第三条
''';
      expect(parseTranslatedLines(raw, expected: 3), [
        '你好，世界！',
        '这是第二条。',
        '第三条',
      ]);
    });

    test('顺序打乱也能按编号归位（编号是 1 基）', () {
      expect(parseTranslatedLines('3\t丙\n1\t甲\n2\t乙', expected: 3), [
        '甲',
        '乙',
        '丙',
      ]);
    });

    test('少一条就抛，不许静默留空', () {
      expect(
        () => parseTranslatedLines('1\t只有一条', expected: 2),
        throwsA(isA<OcrTranslationException>()),
      );
    });

    test('多出来的编号被忽略，不影响对齐', () {
      expect(parseTranslatedLines('1\t甲\n2\t乙\n9\t不该存在', expected: 2), [
        '甲',
        '乙',
      ]);
    });
  });

  group('TranslatedPageRenderer', () {
    test('夹具本身铺满整页（先证明参照物是白的）', () async {
      const w = 400, h = 300;
      final rgba = await _rgba(await _whitePng(w, h));
      expect(rgba.length, w * h * 4);
      expect(
        _untouchedViolations(rgba, w, const ui.Rect.fromLTWH(0, 0, 400, 300)),
        0,
      );
    });

    test('框内真的落了墨，框外没动', () async {
      const w = 400, h = 300;
      final erased = await _whitePng(w, h);
      const boxA = ui.Rect.fromLTWH(40, 30, 140, 90);
      const boxB = ui.Rect.fromLTWH(220, 160, 140, 90);

      final filled = await TranslatedPageRenderer.render(
        erasedPng: erased,
        blocks: [_block(boxA), _block(boxB)],
        translations: ['你好，世界！这是一句比较长的译文，用来触发换行。', '第二块'],
      );

      final rgba = await _rgba(filled);
      expect(rgba.length, w * h * 4, reason: '尺寸必须与原页一致');
      expect(_darkPixels(rgba, w, boxA), greaterThan(200), reason: 'A 框内应当有字');
      expect(_darkPixels(rgba, w, boxB), greaterThan(50), reason: 'B 框内应当有字');
      expect(
        _untouchedViolations(rgba, w, const ui.Rect.fromLTWH(0, 130, 400, 20)),
        0,
        reason: '字溢出到两框之间的空白带',
      );
      expect(
        _untouchedViolations(rgba, w, const ui.Rect.fromLTWH(0, 0, 30, 300)),
        0,
        reason: '左边距不该有字',
      );

      // 落到 /tmp 供人眼复核：断言只能证明「有墨」，像不像成品页得看画。
      final dump = File('/tmp/ocr-lab/filled_test.png');
      await dump.parent.create(recursive: true);
      await dump.writeAsBytes(filled, flush: true);
    });

    test('回填画的是真字形，不是 .notdef 豆腐块', () async {
      // 「有墨」这条断言挡不住豆腐块：方框也是墨。判据换成**排列**：
      // 同一组字换个顺序，豆腐块逐像素不变（每个字符都是同一个方框），真字形必须变。
      final ab = await _raster('你好世界');
      final ba = await _raster('世界你好');
      expect(
        ab,
        isNot(equals(ba)),
        reason: '两种排列逐像素相同 —— 说明每个字都落到了 .notdef 方框，字体没注册上',
      );
    });

    test('窄高框走「一字一行」，宽扁框才横排换行', () async {
      // 端到端那张真页看图看出的缺陷（REFERENCE_RESEARCH §8.6.9）：漫画气泡多是窄高框，
      // 一律横排会排成 3–4 字一行的「假竖排」。断言用**墨的包围盒宽度**分辨两种排法：
      // 竖堆只有一个字宽，横排会铺满框宽。
      const w = 400, h = 300;
      const tall = ui.Rect.fromLTWH(300, 20, 60, 240);
      const wide = ui.Rect.fromLTWH(20, 200, 240, 60);
      const text = 'どっから捕まえてきたんだよお前';

      final filled = await TranslatedPageRenderer.render(
        erasedPng: await _whitePng(w, h),
        blocks: [_block(tall), _block(wide)],
        translations: [text, text],
      );
      final rgba = await _rgba(filled);
      final tallInk = _inkBounds(rgba, w, tall);
      final wideInk = _inkBounds(rgba, w, wide);

      expect(
        tallInk.width,
        lessThan(tall.width * 0.55),
        reason: '窄框里墨铺满了宽度 = 还在横排换行',
      );
      expect(
        tallInk.height,
        greaterThan(tall.height * 0.6),
        reason: '竖堆应该把框的高度用起来',
      );
      expect(wideInk.width, greaterThan(wide.width * 0.5), reason: '宽框该横排铺开');
      expect(wideInk.height, lessThan(wide.height), reason: '宽框不该占满高度');

      final dump = File('/tmp/ocr-lab/filled_tall_wide.png');
      await dump.parent.create(recursive: true);
      await dump.writeAsBytes(filled, flush: true);
    });

    test('空译文跳过，不画空段落', () async {
      const w = 200, h = 120;
      final filled = await TranslatedPageRenderer.render(
        erasedPng: await _whitePng(w, h),
        blocks: [_block(const ui.Rect.fromLTWH(20, 20, 160, 80))],
        translations: ['   '],
      );
      final rgba = await _rgba(filled);
      expect(
        _untouchedViolations(rgba, w, const ui.Rect.fromLTWH(0, 0, 200, 120)),
        0,
      );
    });
  });
}
