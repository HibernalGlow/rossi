import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

import 'package:zephyr/src/rust/api/ocr.dart';

/// 把译文画到擦干净的底图上，产出**成品页**（ADR-0018 §决定 3）。
///
/// 为什么在 Dart 侧画：CJK 整形在 Flutter 里是现成的（bundled 文楷 + 引擎的断行），
/// 在 Rust 侧自己接 harfbuzz/swash 是长期成本（§决定 3）。
///
/// **一期是水平排版**：竖排（`vert`/`vrt2` 组版）明确排在后面 —— 它需要字号-行高-列距的
/// 联合求解，不是「把字转 90°」那么简单（见 ADR-0018 Consequences 的砍单顺序）。
class TranslatedPageRenderer {
  TranslatedPageRenderer._();

  /// 字号候选：从大到小试，第一个「装得下」的胜出。
  /// 太小会看不清，太大的下限由 [minFontSize] 兜底（装不下就截行，不许画到框外）。
  static const _candidates = <double>[
    40, 36, 32, 28, 24, 21, 18, 16, 14, 12.5, 11, 10, 9, 8, 7.5, 7,
  ];

  /// 与 `pubspec.yaml` 的 `assets:` 段一致的**注册名**（不是 TTF 内部的 family 名）。
  ///
  /// 实测：`FontLoader(别名)` 只会以别名注册，字体内部名 `LXGW WenKai Lite` 仍然是豆腐块；
  /// 所以画的时候必须用这个别名，改哪边都要同步。
  static const fontFamily = 'LXGWWenKaiLite-Regular';

  /// 字体不进 `pubspec.yaml` 的 `fonts:` 段，而是当普通 asset 在首次回填时显式注册。
  /// 原因见 [ensureFontLoaded]。
  static const fontAsset = 'asset/fonts/LXGWWenKaiLite-Regular.ttf';

  static Future<void>? _fontLoaded;

  /// 把文楷注册进引擎，幂等。
  ///
  /// 为什么不走 `pubspec.yaml` 的 `fonts:` 段：实测 `flutter test` **不会**加载 manifest 里的
  /// 自定义字体（`iiii`/`WWWW` 等宽 = 全是 .notdef），于是像素测试只能验出「有墨」，
  /// 验不出「是汉字」—— 而豆腐块恰好也是有墨的。显式注册让生产与测试走同一条路径，
  /// 测试才真的守得住这条回归。代价是首张成品页多一次字体加载（相对整页 ~14 s 可忽略）。
  static Future<void> ensureFontLoaded() => _fontLoaded ??= () async {
    final loader = FontLoader(fontFamily)..addFont(rootBundle.load(fontAsset));
    await loader.load();
  }();

  static Future<Uint8List> render({
    required Uint8List erasedPng,
    required List<OcrBlock> blocks,
    required List<String> translations,
    double padding = 3,
    double minFontSize = 7,
  }) async {
    assert(blocks.length == translations.length, '块与译文必须一一对应');
    await ensureFontLoaded();
    final codec = await ui.instantiateImageCodec(erasedPng);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());

    for (var i = 0; i < blocks.length; i++) {
      final text = translations[i].trim();
      if (text.isEmpty) continue;
      final rect = _aabb(blocks[i]);
      _paintFitted(canvas, rect, text, padding: padding, minFontSize: minFontSize);
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('成品页编码失败（toByteData 返回 null）');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      out.dispose();
      image.dispose();
    }
  }

  static ui.Rect _aabb(OcrBlock block) {
    final q = block.quad;
    assert(q.length == 8, '四角点必须是 8 个数，实际 ${q.length}');
    final xs = [q[0], q[2], q[4], q[6]];
    final ys = [q[1], q[3], q[5], q[7]];
    return ui.Rect.fromLTRB(
      xs.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a < b ? a : b),
      xs.reduce((a, b) => a > b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    );
  }

  static void _paintFitted(
    ui.Canvas canvas,
    ui.Rect rect,
    String text, {
    required double padding,
    required double minFontSize,
  }) {
    final maxWidth = (rect.width - 2 * padding).clamp(8.0, double.infinity);
    final maxHeight = (rect.height - 2 * padding).clamp(8.0, double.infinity);

    ui.Paragraph? chosen;
    var chosenSize = 0.0;
    for (final size in _candidates) {
      if (size < minFontSize) break;
      final p = _paragraph(text, size, maxWidth);
      if (p.height <= maxHeight) {
        chosen = p;
        chosenSize = size;
        break;
      }
    }
    if (chosen == null) {
      // 连最小字号都装不下：用最小字号 + 限行数，宁可截断也不许溢出到别人的框上。
      final p = _paragraph(text, minFontSize, maxWidth, maxLines: 3, ellipsis: '…');
      chosen = p;
      chosenSize = minFontSize;
    }
    if (chosenSize == 0) return;
    final dx = rect.left + (rect.width - chosen.width) / 2;
    final dy = rect.top + (rect.height - chosen.height) / 2;
    canvas.drawParagraph(chosen, ui.Offset(dx, dy));
  }

  static ui.Paragraph _paragraph(
    String text,
    double fontSize,
    double maxWidth, {
    int? maxLines,
    String? ellipsis,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: ellipsis,
      ),
    )..pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFF111111),
        fontSize: fontSize,
        height: 1.15,
        fontFamily: fontFamily,
      ),
    );
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    return paragraph;
  }
}
