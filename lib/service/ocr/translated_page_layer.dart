import 'dart:convert';

import 'package:flutter/painting.dart' show Color, Rect;

/// 一页译文的**图层描述**：一份可以按任意底图尺寸重新合成的数据
/// （ADR-0018 §决定 4 在 2026-10-03 解冻出来的那一半）。
///
/// # 为什么要它
///
/// 成品页那条路把 OCR 的全部产出**烧成一张 PNG 就扔了**：框在哪、哪句译文、开几列，
/// 这些之后再也问不回来。于是三种代价：
/// 1. 换显示模式（叠层 / 双语 / 只擦字）= 重跑那十几秒 OCR；
/// 2. 换超分档 = 同样重跑；
/// 3. 翻回来那一帧被呈现器淘汰之后，能拿回来的只有那张已经烧死的图。
///
/// 这一层把「算什么」与「怎么画」分开：`TranslatedPageBuilder` 负责算一次并落这份 JSON，
/// 画的那一侧（`TranslatedPageRenderer` 的烘焙模式、叠层模式的 painter）按它自己的
/// 尺寸与底图去合成。**排版计划只有一份**（`TranslatedPageRenderer.plan`）——
/// 叠层与烘焙各写一套字号策略正是 ADR 当初否决 overlay-first 的理由（§决定 3），
/// 共用同一个 planner 才是那一否决的正解。
///
/// # 坐标系
///
/// 一律是**被分析那张图的物理像素**，与 `rust/src/api/ocr.rs` 交回来的 `quad` 同一把尺子，
/// 归一化留给绘制侧按 `displayWidth / pageWidth` 现算。这样超分只改变一个数：倍率。
class TranslatedPageLayer {
  const TranslatedPageLayer({
    required this.pageWidth,
    required this.pageHeight,
    required this.boxes,
  });

  /// 被分析那张图的宽 —— 所有坐标的基准。
  final int pageWidth;
  final int pageHeight;

  /// 一框一框的译文盒，顺序与 OCR 交回来的块序一致。
  final List<TranslatedBox> boxes;

  /// 四角点的**外接矩形**（底图物理像素）。
  ///
  /// AABB 只在这里定义一次：烘焙那条路（`TranslatedPageRenderer._aabb`）与叠层
  /// 画的是同一个框，各算一份就会有一条悄悄偏一点 —— 而那种偏差在两张图上都
  /// 「看着有字」，只有像素不一样。
  static Rect rectForQuad(List<double> q) {
    if (q.length != 8) {
      throw ArgumentError('四角点必须是 8 个数，实际 ${q.length}');
    }
    final xs = [q[0], q[2], q[4], q[6]];
    final ys = [q[1], q[3], q[5], q[7]];
    return Rect.fromLTRB(
      xs.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a < b ? a : b),
      xs.reduce((a, b) => a > b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    );
  }

  /// 落盘格式。`boxes` 用**定长 8 元数组**存四角点，与 Rust 侧 `quad` 一字不差 ——
  /// 换成 `{x,y,w,h}` 就要在这里重新定义一次 AABB。
  Map<String, dynamic> toJson() => {
    'v': formatVersion,
    'w': pageWidth,
    'h': pageHeight,
    'boxes': [for (final b in boxes) b.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 解盘。**格式不对就返回 null**，不抛：这份文件是给「叠层模式」用的，
  /// 读不出来时正确行为是回落到同一目录里那张烘焙成品页（ADR §决定 3 的
  /// 「产物缺失或损坏时静默回落到原图」同一条纪律），而不是让那一页整个翻不出字。
  static TranslatedPageLayer? tryDecode(String source) {
    final Object? parsed;
    try {
      parsed = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (parsed is! Map) return null;
    if (parsed['v'] != formatVersion) return null;
    final w = parsed['w'];
    final h = parsed['h'];
    final raw = parsed['boxes'];
    if (w is! int || h is! int || w <= 0 || h <= 0) return null;
    if (raw is! List) return null;
    final boxes = <TranslatedBox>[];
    for (final entry in raw) {
      final b = TranslatedBox.tryDecode(entry);
      if (b == null) return null;
      boxes.add(b);
    }
    return TranslatedPageLayer(pageWidth: w, pageHeight: h, boxes: boxes);
  }

  /// 格式版本：字段含义变了就 +1，让旧文件一律解不出来（宁可回落到烘焙图，
  /// 也不要拿旧语义画新语义）。
  static const formatVersion = 1;
}

/// 一个译文盒。
class TranslatedBox {
  const TranslatedBox({
    required this.quad,
    required this.source,
    required this.text,
    this.fill,
    this.truncated = false,
  });

  /// 四角点（左上/右上/右下/左下），底图物理像素，长度恒为 8。
  final List<double> quad;

  /// OCR 认出来的原文。留着是为了「双语 / 只显示原文 / 手改译文后重合成」这三条
  /// 都不必重跑识别 —— 少了它，那三种模式每一种都要从 OCR 开始。
  final String source;

  /// 译文。空串是合法的：那条块画的时候跳过（与烘焙侧同一个规矩）。
  final String text;

  /// 该框的背景填充色（「不擦字、按气泡轮廓填色」那一档用的）。
  ///
  /// 可以是 null：填色要的是**这一框自己的底色**（白气泡、黄气泡、压在网点上），
  /// 那一步要采样原图，明确排在后面。没有它的时候叠层就是「透明底 + 只画字」，
  /// 此时原文字还露在下面 —— 那种状态下正确的选择是走擦字那一条，不是硬叠。
  final Color? fill;

  /// 识别被上限截断的块：译文可疑，界面要标出来（与烘焙侧同一个证据）。
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'q': quad,
    's': source,
    't': text,
    if (fill != null) 'f': fill!.toARGB32().toRadixString(16),
    if (truncated) 'x': true,
  };

  static TranslatedBox? tryDecode(Object? entry) {
    if (entry is! Map) return null;
    final q = entry['q'];
    final s = entry['s'];
    final t = entry['t'];
    if (q is! List || q.length != 8) return null;
    final quad = <double>[];
    for (final v in q) {
      if (v is! num) return null;
      quad.add(v.toDouble());
    }
    if (s is! String || t is! String) return null;
    final f = entry['f'];
    Color? fill;
    if (f is String) {
      final argb = int.tryParse(f, radix: 16);
      if (argb != null) fill = Color(argb);
    }
    return TranslatedBox(
      quad: List<double>.unmodifiable(quad),
      source: s,
      text: t,
      fill: fill,
      truncated: entry['x'] == true,
    );
  }
}
