import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

import 'package:zephyr/src/rust/api/ocr.dart';

/// 一框的排法。
enum LayoutMode { horizontal, vertical }

/// [TranslatedPageRenderer.plan] 的返回：排法、字号、竖排列数。
///
/// 用 record 而不是自建类，是为了让 `==` 与 `hashCode` 免费成立 —— 测试要直接断言
/// 「这个框该开 2 列、字号 21」，而不是靠猜像素。
typedef PageLayout = ({LayoutMode mode, double fontSize, int columns});

/// 把译文画到擦干净的底图上，产出**成品页**（ADR-0018 §决定 3）。
///
/// 为什么在 Dart 侧画：CJK 整形在 Flutter 里是现成的（bundled 文楷 + 引擎的断行），
/// 在 Rust 侧自己接 harfbuzz/swash 是长期成本（§决定 3）。
///
/// **排版是「横排换行」+「窄高框竖排多列（右→左）」两种**（见 [TranslatedPageRenderer.plan]）：
/// 仍然不是真竖排 —— 标点旋转与 `vert`/`vrt2` 组版明确排在后面（见 ADR-0018 Consequences
/// 的砍单顺序），但**列读序**这次有了，因为缺它就得靠缩字号把长句塞进一列，直接不可读。
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
    double minFontSize = defaultMinFontSize,
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

  /// 框的长短边之比超过这个值就改走竖排（多列、从右往左）。
  ///
  /// 判据来自端到端那张真页（`REFERENCE_RESEARCH.md` §8.6.9）：漫画气泡**多是窄高框**，
  /// 横排换行会排成 3–4 字一行的「假竖排」，读起来是竖着断句的一串。
  static const _tallAspect = 1.6;

  /// 列间距相对字号的比例：太挤会糊成一团，太松又开不了几列。
  static const _colGapRatio = 0.18;

  /// 字号下限（[render] 的默认值，也是 [plan] 兜底时用的那个数）。
  static const defaultMinFontSize = 7.0;

  /// 一框的排版决策：哪种排法、多大字号、竖排开几列。
  ///
  /// 抽成纯函数是为了能断言 —— 「窄高框只许排一列」这个缺陷是看图看出来的，
  /// 像素断言看得见「有没有越框」，看不见「字号小到根本读不了」。
  static PageLayout plan(
    ui.Rect rect,
    String text, {
    double padding = 3,
    double minFontSize = defaultMinFontSize,
  }) {
    final maxWidth = (rect.width - 2 * padding).clamp(8.0, double.infinity);
    final maxHeight = (rect.height - 2 * padding).clamp(8.0, double.infinity);
    final chars = text.runes.length;
    final vertical =
        rect.height >= rect.width * _tallAspect &&
        chars > 3 &&
        _stackable(text);

    if (!vertical) {
      for (final size in _candidates) {
        final p = _paragraph(text, size, maxWidth);
        final fits = p.height <= maxHeight;
        p.dispose();
        if (fits) {
          return (mode: LayoutMode.horizontal, fontSize: size, columns: 1);
        }
      }
      return (mode: LayoutMode.horizontal, fontSize: minFontSize, columns: 1);
    }

    // 竖排：字号从大到小，第一个「列数 × 每列字数 ≥ 总字数」的胜出。
    // 旧实现把宽度锁死成一个字（`size * 1.12`），于是长句只能靠缩字号塞进那一列 ——
    // 20 字的旁白框会被压到 7–13 px，这正是「一行纵向根本没办法阅读」的成因。
    for (final size in _candidates) {
      final colWidth = size * 1.12;
      final gap = size * _colGapRatio;
      final rows = (maxHeight / (size * 1.15)).floor();
      if (rows < 1) continue;
      final columns = ((maxWidth + gap) / (colWidth + gap)).floor();
      if (columns < 1) continue;
      if (columns * rows >= chars) {
        return (
          mode: LayoutMode.vertical,
          fontSize: size,
          // 列数按实际需要收：18 格只装 5 个字时别画 4 列。
          columns: (chars / rows).ceil().clamp(1, columns),
        );
      }
    }
    return (mode: LayoutMode.vertical, fontSize: minFontSize, columns: 1);
  }

  /// 这串字能不能「一字一行」地竖着堆。
  ///
  /// 拉丁字母与空格不行：把 "danger" 拆成 6 行竖排等于不可读，那种译文只能横排换行。
  /// 目标语言是用户随便填的（设置里能选 en），所以不能假设译文一定中日韩。
  static bool _stackable(String text) {
    var stackable = 0;
    var total = 0;
    for (final r in text.runes) {
      total++;
      final latin =
          (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a) || r == 0x20;
      if (!latin) stackable++;
    }
    if (total == 0) return false;
    return stackable / total >= 0.8;
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
    final layout = plan(rect, text, padding: padding, minFontSize: minFontSize);

    if (layout.mode == LayoutMode.horizontal) {
      final chosen = _fitHorizontal(
        text,
        maxWidth,
        maxHeight,
        layout.fontSize,
        minFontSize,
      );
      canvas.drawParagraph(
        chosen,
        ui.Offset(
          rect.left + (rect.width - chosen.width) / 2,
          rect.top + (rect.height - chosen.height) / 2,
        ),
      );
      return;
    }
    _paintVerticalColumns(canvas, rect, text, layout, padding, maxHeight);
  }

  /// 横排：从决策字号起一路试到下限；连下限都装不下就限行数截断（宁可截断也不许越框）。
  static ui.Paragraph _fitHorizontal(
    String text,
    double maxWidth,
    double maxHeight,
    double fromSize,
    double minFontSize,
  ) {
    for (final size in _candidates) {
      if (size > fromSize) continue;
      final p = _paragraph(text, size, maxWidth);
      if (p.height <= maxHeight) return p;
      p.dispose();
    }
    final lines = (maxHeight / (minFontSize * 1.15)).floor().clamp(1, 999);
    return _paragraph(
      text,
      minFontSize,
      maxWidth,
      maxLines: lines,
      ellipsis: '…',
    );
  }

  /// 竖排：切成若干列，**从右往左**落位（日文列读序），每列内部仍是单字一行。
  static void _paintVerticalColumns(
    ui.Canvas canvas,
    ui.Rect rect,
    String text,
    PageLayout layout,
    double padding,
    double maxHeight,
  ) {
    final size = layout.fontSize;
    final colWidth = size * 1.12;
    final gap = size * _colGapRatio;
    final runes = text.runes.toList(growable: false);
    final rows = (runes.length / layout.columns).ceil();

    final columns = <ui.Paragraph>[];
    for (var i = 0; i < layout.columns; i++) {
      final start = i * rows;
      if (start >= runes.length) break;
      final end = (start + rows).clamp(0, runes.length);
      columns.add(
        _paragraph(
          String.fromCharCodes(runes.sublist(start, end)),
          size,
          colWidth,
        ),
      );
    }
    final tallest = columns.fold<double>(
      0,
      (max, c) => c.height > max ? c.height : max,
    );
    final top =
        rect.top +
        padding +
        ((maxHeight - tallest) / 2).clamp(0.0, double.infinity);
    final blockWidth = columns.length * colWidth + (columns.length - 1) * gap;
    // 整块在框里水平居中；列与列之间仍按右→左的读序落位。
    var x = rect.left + (rect.width - blockWidth) / 2 + blockWidth - colWidth;
    for (final column in columns) {
      canvas.drawParagraph(column, ui.Offset(x, top));
      x -= colWidth + gap;
    }
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
