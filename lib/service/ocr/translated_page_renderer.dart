import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

import 'package:zephyr/src/rust/api/ocr.dart';

/// 把译文画到擦干净的底图上，产出**成品页**（ADR-0018 §决定 3）。
///
/// 为什么在 Dart 侧画：CJK 整形在 Flutter 里是现成的（bundled 文楷 + 引擎的断行），
/// 在 Rust 侧自己接 harfbuzz/swash 是长期成本（§决定 3）。
///
/// **一期是水平排版 + 窄高框的「一字一行」竖堆**（[_tallAspect]）：真竖排（`vert`/`vrt2`
/// 组版、标点旋转、列读序）明确排在后面 —— 它需要字号-行高-列距的联合求解，
/// 不是「把字转 90°」那么简单（见 ADR-0018 Consequences 的砍单顺序）。
class TranslatedPageRenderer {
  TranslatedPageRenderer._();

  /// 字号候选：从大到小试，第一个「装得下」的胜出。
  /// 太小会看不清，太大的下限由 [minFontSize] 兜底（装不下就截行，不许画到框外）。
  static const _candidates = <double>[
    40,
    36,
    32,
    28,
    24,
    21,
    18,
    16,
    14,
    12.5,
    11,
    10,
    9,
    8,
    7.5,
    7,
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
    // 用真抛而不是 assert：release 下 assert 会被整个跳过，
    // 那时条数不符会崩成一句按下标越界的 RangeError，看不出是这件事。
    if (blocks.length != translations.length) {
      throw ArgumentError(
        '块与译文必须一一对应：块 ${blocks.length}，译文 ${translations.length}',
      );
    }
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
      _paintFitted(
        canvas,
        rect,
        text,
        padding: padding,
        minFontSize: minFontSize,
      );
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
    if (q.length != 8) {
      throw ArgumentError('四角点必须是 8 个数，实际 ${q.length}');
    }
    final xs = [q[0], q[2], q[4], q[6]];
    final ys = [q[1], q[3], q[5], q[7]];
    return ui.Rect.fromLTRB(
      xs.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a < b ? a : b),
      xs.reduce((a, b) => a > b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    );
  }

  /// 框的长短边之比超过这个值就改走「一字一行」的竖堆。
  ///
  /// 判据来自端到端那张真页（`REFERENCE_RESEARCH.md` §8.6.9）：漫画气泡**多是窄高框**，
  /// 横排换行会排成 3–4 字一行的「假竖排」，读起来是竖着断句的一串。
  /// 这里不是真竖排（没有标点旋转、没有列序），只是让窄框至少能正常读。
  static const _tallAspect = 1.6;

  static void _paintFitted(
    ui.Canvas canvas,
    ui.Rect rect,
    String text, {
    required double padding,
    required double minFontSize,
  }) {
    final maxWidth = (rect.width - 2 * padding).clamp(8.0, double.infinity);
    final maxHeight = (rect.height - 2 * padding).clamp(8.0, double.infinity);
    // 竖堆：把可用宽度收到约一个字，引擎每行只放得下一个字（见下面传进 _paragraph 的宽度）。
    final vertical =
        rect.height >= rect.width * _tallAspect && text.runes.length > 3;

    ui.Paragraph? chosen;
    var chosenSize = 0.0;
    for (final size in _candidates) {
      if (size < minFontSize) break;
      final p = _paragraph(text, size, vertical ? size * 1.12 : maxWidth);
      if (p.height <= maxHeight) {
        chosen = p;
        chosenSize = size;
        break;
      }
    }
    if (chosen == null) {
      // 连最小字号都装不下：按能放几行就限行数，宁可截断也不许溢出到别人的框上。
      final lines = (maxHeight / (minFontSize * 1.15)).floor().clamp(1, 999);
      chosen = _paragraph(
        text,
        minFontSize,
        vertical ? minFontSize * 1.12 : maxWidth,
        maxLines: lines,
        ellipsis: '…',
      );
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
    final builder =
        ui.ParagraphBuilder(
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
