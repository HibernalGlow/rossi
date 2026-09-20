// tweakcn / shadcn 导出的 CSS 颜色值 → Flutter `Color`。
//
// tweakcn 现在整套 token 都是 **OKLCH**（Tailwind v4 的 `oklch(0.21 0 0)` 这种），
// 而 Flutter 的 `Color` 是 sRGB 编码值，所以中间必须做一次色彩空间转换。
//
// 超出色域时按 CSS Color 4 的建议**先收缩彩度、再截断通道**：直接截断 RGB 会把
// 亮色主题的强调色压成一块灰板，而人眼对色相偏移远比彩度损失敏感。二分搜索彩度
// 系数只有十几行，换来的是「导入的紫色主题不会变成蓝色」。
//
// 本文件保持**纯函数、零应用依赖**（只依赖 dart:ui 的 `Color`），这样单测不必
// 把 `main.dart`（连带 ObjectBox 与 Rust FFI）整棵拖起来。

import 'dart:math' as math;
import 'dart:ui' show Color;

/// 解析后的单个 CSS 数值：剥掉单位后的数字 + 它原本是百分比还是角度。
class _Num {
  final double value;
  final bool percent;

  /// 角度 token 换算成度数后的值（已取模 360）；非角度为 null。
  final double? degrees;

  const _Num(this.value, {this.percent = false, this.degrees});

  /// 归一到 0~1：`50%` → .5；`0.5` → .5；写成 `56` 的量按 0~100 读。
  double get normalized01 {
    if (percent) return (value / 100).clamp(0.0, 1.0);
    if (value > 1.001) return (value / 100).clamp(0.0, 1.0);
    return value.clamp(0.0, 1.0);
  }
}

const Map<String, Color> _namedColors = {
  'transparent': Color(0x00000000),
  'none': Color(0x00000000),
  'black': Color(0xFF000000),
  'white': Color(0xFFFFFFFF),
  'red': Color(0xFFFF0000),
  'green': Color(0xFF008000),
  'blue': Color(0xFF0000FF),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
};

/// 解析一个 CSS 颜色值；无法识别时返回 null（调用方按「该 token 缺失」处理）。
///
/// 支持：`#hex(3|4|6|8)`、`rgb()/rgba()`、`hsl()/hsla()`、`hwb()`、`oklab()`、
/// `oklch()`。`var(...)`、`color-mix(...)` 这类间接值一律返回 null ——
/// tweakcn 的 `@theme inline` 块里全是 `--color-x: var(--x)` 的转发，
/// 必须跳过才不会把字面量当成颜色。
Color? parseCssColor(String raw) {
  final parsed = _parseCssColorValue(raw);
  // 落到 8-bit：Flutter 绘制的 sRGB 就是 8bit，留着浮点尾巴只会让
  // 「编码成 hex 再读回来」对不上，单测里那些 `== Color(0xFF…)` 也全是假失败。
  return parsed == null ? null : quantize8(parsed);
}

Color? _parseCssColorValue(String raw) {
  final text = _stripImportant(raw);
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();

  final named = _namedColors[lower];
  if (named != null) return named;

  if (lower.startsWith('#')) return _parseHex(lower);

  final open = lower.indexOf('(');
  if (open == -1 || !lower.endsWith(')')) return null;
  final fn = lower.substring(0, open).trim();
  final args = _Args.parse(text.substring(open + 1, text.length - 1));
  if (args == null) return null;
  final alpha = args.alpha;

  switch (fn) {
    case 'rgb' || 'rgba':
      return _fromRgb(args, alpha);
    case 'hsl' || 'hsla':
      return _fromHsl(args, alpha);
    case 'hwb':
      return _fromHwb(args, alpha);
    case 'oklab':
      return _oklab(
        args.channel(0)?.normalized01 ?? 0,
        args.channel(1)?.value ?? 0,
        args.channel(2)?.value ?? 0,
        alpha,
      );
    case 'oklch':
      final c = args.channel(1);
      final chroma = c == null ? 0.0 : (c.percent ? c.value / 100 : c.value);
      final hue = args.hue(2);
      final radians = hue * math.pi / 180;
      return _oklab(
        args.channel(0)?.normalized01 ?? 0,
        chroma * math.cos(radians),
        chroma * math.sin(radians),
        alpha,
      );
    default:
      return null;
  }
}

/// 逐通道线性混合，允许 [t] 落在 0~1 之外（用于从两个锚点外推色阶），
/// 结果按 8bit 截断。
Color mixClamped(Color a, Color b, double t) => quantize8(
  Color.from(
    alpha: a.a + (b.a - a.a) * t,
    red: a.r + (b.r - a.r) * t,
    green: a.g + (b.g - a.g) * t,
    blue: a.b + (b.b - a.b) * t,
  ),
);

/// 把每个通道量化到 8bit（0~255），越界按端点截断。
Color quantize8(Color c) {
  double q(double v) => (v * 255).round().clamp(0.0, 255.0) / 255;
  return Color.from(alpha: q(c.a), red: q(c.r), green: q(c.g), blue: q(c.b));
}

/// 按亮度自动配前景色：深底配白字、浅底配黑字。
///
/// shadcn 的 token 表里 `*-foreground` 与底色是成对给的，但用户手改或只粘贴
/// 半套 CSS 时会缺；缺了就自己算，而不是留着 `fromSeed` 的前景 —— 那会出现
/// 「浅灰底 + 浅灰字」这种读不得的组合。
///
/// 阈值取 **0.179**：那是 WCAG 相对亮度上「黑字与白字对比度相等」的交叉点
/// （`computeLuminance()` 用的就是这条公式），所以它不是审美选择而是最优解的分界。
/// 中灰 `#808080`（亮度约 .216）在这里配**黑字**；按 0.45 那种保守阈值会错配白字。
Color contrastOn(Color background) => background.computeLuminance() > 0.179
    ? const Color(0xFF0A0A0A)
    : const Color(0xFFFFFFFF);

// ---------------------------------------------------------------------------
// 参数串拆解
// ---------------------------------------------------------------------------

class _Args {
  final List<_Num> main;
  final double alpha;

  _Args(this.main, this.alpha);

  _Num? channel(int index) => index < main.length ? main[index] : null;

  /// CSS 里色相既写 `292deg` 也写裸数字 `292`（tweakcn 全是后者），
  /// 两者都要落到同一个 0~360 的值上。
  double hue(int index) {
    final n = channel(index);
    if (n == null) return 0;
    return n.degrees ?? n.value % 360;
  }

  /// 拆解 `a b c / d` 与 `a, b, c, d`；任一主通道不是数字则返回 null。
  ///
  /// 老式逗号写法把透明度当第 4 个通道（`rgba(0, 0, 0, .5)`），这里把它从主参数
  /// 里摘出来，免得 `_fromRgb` 拿 alpha 当蓝色通道用。
  static _Args? parse(String body) {
    final slash = body.indexOf('/');
    final mainRaw = slash == -1 ? body : body.substring(0, slash);
    final alphaRaw = slash == -1 ? null : body.substring(slash + 1);

    final main = <_Num>[];
    for (final token in mainRaw.split(RegExp(r'[,\s]+'))) {
      if (token.isEmpty) continue;
      final n = _parseNum(token);
      if (n == null) return null;
      main.add(n);
    }
    if (main.isEmpty) return null;

    if (alphaRaw != null) {
      final a = _parseNum(alphaRaw);
      if (a == null) return null;
      return _Args(main, a.normalized01);
    }
    if (main.length > 3) return _Args(main.sublist(0, 3), main[3].normalized01);
    return _Args(main, 1);
  }
}

/// CSS 数值 token：`50%` / `240deg` / `.4` / `none`。
_Num? _parseNum(String token) {
  final text = token.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower == 'none') return const _Num(0);

  if (lower.endsWith('%')) {
    final raw = double.tryParse(lower.substring(0, lower.length - 1));
    return raw == null ? null : _Num(raw, percent: true);
  }
  for (final (unit, factor) in const [
    ('deg', 1.0),
    ('grad', 0.9),
    ('turn', 360.0),
    ('rad', 57.29577951308232),
  ]) {
    if (lower.endsWith(unit)) {
      final raw = double.tryParse(
        lower.substring(0, lower.length - unit.length),
      );
      if (raw == null) return null;
      return _Num(raw * factor, degrees: (raw * factor) % 360);
    }
  }
  final raw = double.tryParse(lower);
  return raw == null ? null : _Num(raw);
}

String _stripImportant(String raw) {
  var text = raw.trim();
  final bang = text.indexOf('!important');
  if (bang != -1) text = text.substring(0, bang);
  return text.trim();
}

// ---------------------------------------------------------------------------
// 具体格式
// ---------------------------------------------------------------------------

Color? _parseHex(String text) {
  final body = text.substring(1);
  final digits = <int>[];
  for (final c in body.split('')) {
    final v = int.tryParse(c, radix: 16);
    if (v == null) return null;
    digits.add(v);
  }
  List<int> expand(int per) {
    final out = <int>[];
    for (var i = 0; i < digits.length; i += per) {
      final slice = digits.sublist(i, i + per);
      out.add(per == 1 ? slice[0] * 17 : slice.reduce((a, b) => a * 16 + b));
    }
    return out;
  }

  final channels = switch (body.length) {
    3 || 4 => expand(1),
    6 || 8 => expand(2),
    _ => null,
  };
  if (channels == null) return null;
  return Color.from(
    alpha: (channels.length > 3 ? channels[3] : 255) / 255,
    red: channels[0] / 255,
    green: channels[1] / 255,
    blue: channels[2] / 255,
  );
}

Color? _fromRgb(_Args args, double alpha) {
  if (args.main.length < 3) return null;
  // 通道允许 0~255 与 0~1 两种量纲（CSS 只承认 0~255 与百分比，
  // 但用户手写的主题里两种都见得到）。
  double ch(_Num n) => n.percent
      ? (n.value / 100).clamp(0.0, 1.0)
      : n.value > 1.001
      ? (n.value / 255).clamp(0.0, 1.0)
      : n.value.clamp(0.0, 1.0);
  return Color.from(
    alpha: alpha,
    red: ch(args.main[0]),
    green: ch(args.main[1]),
    blue: ch(args.main[2]),
  );
}

Color? _fromHsl(_Args args, double alpha) {
  if (args.main.length < 3) return null;
  final (r, g, b) = _hslToRgb(
    args.main[0].degrees ?? args.main[0].value % 360,
    args.main[1].normalized01,
    args.main[2].normalized01,
  );
  return Color.from(alpha: alpha, red: r, green: g, blue: b);
}

(double, double, double) _hslToRgb(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  final (r, g, b) = switch (((h / 60).floor() % 6 + 6) % 6) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return (r + m, g + m, b + m);
}

Color? _fromHwb(_Args args, double alpha) {
  if (args.main.length < 3) return null;
  final h = args.main[0].degrees ?? args.main[0].value % 360;
  final w = args.main[1].normalized01;
  final b = args.main[2].normalized01;
  if (w + b >= 1) {
    final gray = w / (w + b);
    return Color.from(alpha: alpha, red: gray, green: gray, blue: gray);
  }
  final (r, g, bl) = _hslToRgb(h, 1, 0.5);
  double f(double v) => (v * (1 - w - b) + w).clamp(0.0, 1.0);
  return Color.from(alpha: alpha, red: f(r), green: f(g), blue: f(bl));
}

/// OKLab → sRGB，带色域外的彩度收缩。
Color _oklab(double l, double a, double b, double alpha) {
  Color at(double scale) => _oklabChannels(l, a * scale, b * scale, alpha);
  final direct = at(1);
  if (_inGamut(direct)) return direct;

  // 灰轴（彩度 0）必定在色域内，所以二分始终有一个可退的解。
  var lo = 0.0;
  var hi = 1.0;
  var best = at(0);
  for (var i = 0; i < 14; i++) {
    final mid = (lo + hi) / 2;
    final probe = at(mid);
    if (_inGamut(probe)) {
      lo = mid;
      best = probe;
    } else {
      hi = mid;
    }
  }
  return best;
}

Color _oklabChannels(double l, double a, double b, double alpha) {
  final lp = l + 0.3963377774 * a + 0.2158037573 * b;
  final mp = l - 0.1055613458 * a - 0.0638541728 * b;
  final sp = l - 0.0894841775 * a - 1.2914855480 * b;
  final lc = lp * lp * lp;
  final mc = mp * mp * mp;
  final sc = sp * sp * sp;
  return Color.from(
    alpha: alpha,
    red: _gammaEncode(
      4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
    ),
    green: _gammaEncode(
      -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
    ),
    blue: _gammaEncode(
      -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc,
    ),
  );
}

/// 色域判据带一点容差：边界上的浮点毛刺不该触发整轮二分。
bool _inGamut(Color c) {
  bool ok(double v) => v >= -0.003 && v <= 1.003;
  return ok(c.r) && ok(c.g) && ok(c.b);
}

double _gammaEncode(double linear) {
  final v = linear <= 0.0031308
      ? linear * 12.92
      : 1.055 * math.pow(linear < 0 ? 0.0 : linear, 1 / 2.4) - 0.055;
  return v.clamp(0.0, 1.0);
}
