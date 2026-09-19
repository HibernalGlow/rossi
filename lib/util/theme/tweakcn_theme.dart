// tweakcn（shadcn/ui 主题编辑器）导入格式的解析与落地。
//
// 两条链路：
//   1. [parseTweakcnTheme] —— 吃用户从 tweakcn 复制的**原文**（`globals.css` 片段、
//      Tailwind v4 的 `@theme` 块，或 shadcn registry 的 JSON），产出 [TweakcnTheme]。
//      解析结果再序列化成 hex 表存进设置（见 `GlobalSettingState.tweakcnThemeJson`），
//      所以运行时走的是 [TweakcnTheme.decode]，不必每次重建都重跑 CSS 扫描。
//   2. [TweakcnTheme.apply] —— 把 shadcn 的语义 token **覆盖**到 `ColorScheme.fromSeed`
//      的结果上。
//
// 为什么是「覆盖」而不是「整套换掉 ColorScheme」：本仓大量组件用的是 M3 的角色名
// （`surfaceContainerHigh`、`onSurfaceVariant`、`outlineVariant`…），而 shadcn 只有
// 二十来个扁平 token。整套换掉要么改所有调用点，要么留一堆 null；覆盖式的语义是
// 「导入的 token 说了算，没导入的槽位沿用派生值」，改动面收在这一个文件里。
//
// 一个必须说清的偏离：shadcn **没有** M3 那套 surface 色阶（它的 card/popover 与
// background 同色，靠描边与阴影分层）。直接不管的话，`fromSeed` 的色阶会带着种子色
// 的色相，和导入的中性 background 摆在一起就是「页面纯白、卡片发紫」。
// 所以 [surfaceLadder] 用 `background`→`muted` 这条**中性向量**外推出一套色阶，
// 让既有调用点继续拿得到正确的层级差，且不引入任何种子色残留。

import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart' show immutable;

// 本应用的主题栈是 `material_ui` 那套**平行实现**（它有自己的 ColorScheme /
// ThemeData / ThemeExtension），`main.dart` 里 `ColorScheme.fromSeed` 出来的也是它。
// 覆盖层必须吃同一个类型，否则在调用点就接不上。它的角色名与 copyWith 参数表和
// Flutter 的 M3 ColorScheme 一致，所以映射逻辑本身不用改。
import 'package:material_ui/material_ui.dart' show ColorScheme;

import 'package:zephyr/util/theme/tweakcn_color.dart';

/// 默认面板圆角（px）的权威定义在 `lib/config/global/theme_shape.dart`：
/// 那里是消费方（玻璃 / 卡片）读值的地方，本文件只负责把 `--radius` 换算成 px。

/// tweakcn token 名 → 归一化（去掉 `--`、去掉 Tailwind v4 的 `color-` 前缀、小写）。
String normalizeTokenName(String raw) {
  var name = raw.trim().toLowerCase();
  if (name.startsWith('--')) name = name.substring(2);
  if (name.startsWith('color-')) name = name.substring('color-'.length);
  return name;
}

/// `0.625rem` / `10px` / `10` → 逻辑像素；读不出单位则 null。
double? parseLengthToPx(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  final match = RegExp(r'^(-?\d*\.?\d+)\s*([a-z]*)$').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  return switch (match.group(2)!) {
    'rem' || 'em' => value * 16,
    'px' || '' => value,
    'pt' => value * 96 / 72,
    _ => null,
  };
}

/// 一次导入的结果：要么拿到主题，要么拿到一个失败原因。
///
/// [skipped] 是「认得 key 但读不出颜色」的 token 名（例如 `var(--x)` 这类转发），
/// UI 拿它提示用户哪些没生效 —— 静默丢掉一半 token 是最难查的那种坏。
class TweakcnImportResult {
  final TweakcnTheme? theme;
  final TweakcnImportFailure? failure;
  final List<String> skipped;

  const TweakcnImportResult._({
    this.theme,
    this.failure,
    this.skipped = const [],
  });

  factory TweakcnImportResult.ok(
    TweakcnTheme theme, {
    List<String> skipped = const [],
  }) => TweakcnImportResult._(theme: theme, skipped: skipped);

  factory TweakcnImportResult.fail(TweakcnImportFailure failure) =>
      TweakcnImportResult._(failure: failure);

  bool get isSuccess => theme != null;
}

/// 导入失败的原因（文案在 UI 侧本地化，这里只给判据）。
enum TweakcnImportFailure { empty, unrecognized, noColors }

/// 一套已解析的 tweakcn 主题。
@immutable
class TweakcnTheme {
  const TweakcnTheme({
    this.name = '',
    this.radius,
    this.light = const {},
    this.dark = const {},
  });

  final String name;

  /// `--radius` 换算成的 px；null 表示主题没给，保持应用默认。
  final double? radius;

  final Map<String, Color> light;
  final Map<String, Color> dark;

  bool get isEmpty => light.isEmpty && dark.isEmpty;

  /// 只给了半套时，另一套亮度沿用这一套（比回落到种子色更符合直觉）。
  Map<String, Color> tokensOrFallback(Brightness brightness) {
    final primary = brightness == Brightness.dark ? dark : light;
    if (primary.isNotEmpty) return primary;
    return brightness == Brightness.dark ? light : dark;
  }

  // --- 存储形式：`{"name":…,"radius":…,"light":{"background":"#ffffffff"}}` ---
  //
  // 颜色存成 hex 字符串而不是 ARGB 整数：人能直接读懂，且读回来复用
  // [parseCssColor]，不必再写一套编解码。

  String encode() => jsonEncode({
    'name': name,
    if (radius != null) 'radius': radius,
    'light': {for (final e in light.entries) e.key: _hex(e.value)},
    'dark': {for (final e in dark.entries) e.key: _hex(e.value)},
  });

  /// 解析存储串；空串或结构不符返回 null（调用方按「未导入主题」处理）。
  ///
  /// 带一层「最后一次输入 → 结果」的记忆：`main.dart` 的主题构建挂在字体配置
  /// 的 AnimatedBuilder 上，动画每一帧都会重新算一遍 ColorScheme，
  /// 而这里读的字符串几乎从不变化。
  static TweakcnTheme? decode(String raw) {
    if (raw == _cachedRaw) return _cachedTheme;
    final theme = _decodeUncached(raw);
    _cachedRaw = raw;
    _cachedTheme = theme;
    return theme;
  }

  static String? _cachedRaw;
  static TweakcnTheme? _cachedTheme;

  static TweakcnTheme? _decodeUncached(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final theme = TweakcnTheme(
      name: (json['name'] as String?) ?? '',
      radius: (json['radius'] as num?)?.toDouble(),
      light: _colorMap(json['light']),
      dark: _colorMap(json['dark']),
    );
    return theme.isEmpty ? null : theme;
  }

  /// 把 token 覆盖到 [base]（`ColorScheme.fromSeed` 的结果）上。
  ColorScheme apply(ColorScheme base, Brightness brightness) {
    final tokens = tokensOrFallback(brightness);
    if (tokens.isEmpty) return base;

    Color? t(String key) => tokens[key];
    // `*-foreground` 缺了自己按亮度配一个，别留种子色的前景。
    Color? paired(String bgKey, Color? bg) =>
        bg == null ? null : t('$bgKey-foreground') ?? contrastOn(bg);

    final dark = brightness == Brightness.dark;
    final background = t('background');
    final foreground = t('foreground');
    final muted =
        t('muted') ??
        (background != null && foreground != null
            ? mixClamped(background, foreground, 0.06)
            : null);
    final border = t('border');
    final input = t('input') ?? border;

    var scheme = base;

    if (background != null) {
      final ladder = surfaceLadder(background, muted ?? background, brightness);
      // 只给底色没给前景时自己配一个对比色，别把种子色的前景留在导入的主题上。
      final text = foreground ?? contrastOn(background);
      scheme = scheme.copyWith(
        surface: background,
        onSurface: text,
        onSurfaceVariant: t('muted-foreground'),
        surfaceContainerLowest: ladder.lowest,
        surfaceContainerLow: ladder.low,
        surfaceContainer: ladder.container,
        surfaceContainerHigh: ladder.high,
        surfaceContainerHighest: ladder.highest,
        surfaceBright: muted,
        // 深色下比 background 更暗、浅色下更亮一档，两个方向的 lowest/dim 才对称。
        surfaceDim: muted == null
            ? null
            : mixClamped(background, muted, dark ? -0.35 : 0.15),
        inverseSurface: text,
        scrim: mixClamped(text, const Color(0xFF000000), 0.5),
      );
    } else if (t('muted-foreground') != null) {
      scheme = scheme.copyWith(onSurfaceVariant: t('muted-foreground'));
    }

    final primary = t('primary');
    if (primary != null) {
      scheme = scheme.copyWith(
        primary: primary,
        onPrimary: paired('primary', primary),
        inversePrimary: primary,
        surfaceTint: primary,
      );
    } else if (t('ring') != null) {
      scheme = scheme.copyWith(surfaceTint: t('ring'));
    }

    final secondary = t('secondary');
    if (secondary != null) {
      scheme = scheme.copyWith(
        secondary: secondary,
        onSecondary: paired('secondary', secondary),
        // shadcn 没有 tertiary 槽位。让它跟着 secondary，否则 M3 派生的第三色相
        // 会在个别组件里漏出来，和导入主题的中性灰打架。
        tertiary: secondary,
        onTertiary: paired('secondary', secondary),
      );
    }

    final accent = t('accent');
    if (accent != null) {
      final onAccent = t('accent-foreground') ?? contrastOn(accent);
      scheme = scheme.copyWith(
        secondaryContainer: accent,
        onSecondaryContainer: onAccent,
        tertiaryContainer: accent,
        onTertiaryContainer: onAccent,
      );
    }

    final destructive = t('destructive');
    if (destructive != null) {
      scheme = scheme.copyWith(
        error: destructive,
        onError: t('destructive-foreground') ?? contrastOn(destructive),
        errorContainer: background == null
            ? null
            : mixClamped(background, destructive, dark ? 0.28 : 0.16),
        onErrorContainer: background == null
            ? null
            : (foreground ?? mixClamped(background, destructive, 0.9)),
      );
    }

    if (border != null) {
      scheme = scheme.copyWith(outlineVariant: border, outline: input);
    }
    // `card` / `popover` 在这里**故意不单独落地**：shadcn 的这两个值通常与
    // background 同色（分层靠描边和阴影），而本仓的卡片 / 对话框读的是
    // `surfaceContainer*` 色阶 —— 那条已经由上面的 [surfaceLadder] 铺好了。
    if (t('shadow-color') != null) {
      scheme = scheme.copyWith(shadow: t('shadow-color'));
    }

    return scheme;
  }

  @override
  bool operator ==(Object other) =>
      other is TweakcnTheme &&
      other.name == name &&
      other.radius == radius &&
      _mapEquals(other.light, light) &&
      _mapEquals(other.dark, dark);

  @override
  int get hashCode => Object.hash(
    name,
    radius,
    Object.hashAllUnordered([
      for (final e in light.entries) '${e.key}=${_hex(e.value)}',
      for (final e in dark.entries) '${e.key}=${_hex(e.value)}',
    ]),
  );
}

/// shadcn 的 `background`→`muted` 中性向量外推出 M3 的五档 surface 色阶。
///
/// 浅色：lowest 就是 background，往上逼近 muted。深色：M3 的 lowest 比 surface
/// 还暗一档，所以从负系数开始，往上到 muted。
({Color lowest, Color low, Color container, Color high, Color highest})
surfaceLadder(Color background, Color muted, Brightness brightness) {
  final steps = brightness == Brightness.dark
      ? (-0.25, 0.25, 0.5, 0.75, 1.0)
      : (0.0, 0.25, 0.5, 0.72, 0.9);
  return (
    lowest: mixClamped(background, muted, steps.$1),
    low: mixClamped(background, muted, steps.$2),
    container: mixClamped(background, muted, steps.$3),
    high: mixClamped(background, muted, steps.$4),
    highest: mixClamped(background, muted, steps.$5),
  );
}

// ---------------------------------------------------------------------------
// 导入文本 → TweakcnTheme
// ---------------------------------------------------------------------------

/// 解析用户粘贴的 tweakcn 内容。
///
/// 认三种形态（都是 tweakcn 界面上能直接复制到的东西）：
/// - CSS：`:root { --background: oklch(…) }` / `.dark { … }`，可以包在
///   `@layer base` 或 `@media (prefers-color-scheme: dark)` 里；
/// - registry JSON：`{"name":"zen","$cssVars":{"theme":{…},"dark":{…}}}`
///   （`npx shadcn add https://tweakcn.com/r/themes/xxx` 拿到的那份）；
/// - 裸变量表：`{"--background": "oklch(…)"}`，或没有选择器的 `--x: y;` 片段。
TweakcnImportResult parseTweakcnTheme(String input) {
  final text = input.trim();
  if (text.isEmpty) return TweakcnImportResult.fail(TweakcnImportFailure.empty);

  final light = <String, String>{};
  final dark = <String, String>{};
  var name = '';

  if (text.startsWith('{') || text.startsWith('[')) {
    final parsed = _fromJson(text);
    if (parsed == null) {
      return TweakcnImportResult.fail(TweakcnImportFailure.unrecognized);
    }
    name = parsed.name;
    light.addAll(parsed.light);
    dark.addAll(parsed.dark);
  } else {
    final cleaned = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
    _parseRegion(cleaned, 0, cleaned.length, const [], light, dark);
  }

  final skipped = <String>[];
  final lightColors = <String, Color>{};
  final darkColors = <String, Color>{};
  double? radius;

  for (final key in {...light.keys, ...dark.keys}) {
    if (key == 'radius') {
      radius = parseLengthToPx(light[key] ?? dark[key] ?? '');
      continue;
    }
    if (_nonColorKeys.contains(key)) continue;
    final l = light[key] == null ? null : parseCssColor(light[key]!);
    final d = dark[key] == null ? null : parseCssColor(dark[key]!);
    if (l == null && d == null) skipped.add(key);
    if (l != null) lightColors[key] = l;
    if (d != null) darkColors[key] = d;
  }

  if (lightColors.isEmpty && darkColors.isEmpty) {
    return TweakcnImportResult.fail(TweakcnImportFailure.noColors);
  }
  return TweakcnImportResult.ok(
    TweakcnTheme(
      name: name,
      radius: radius,
      light: lightColors,
      dark: darkColors,
    ),
    skipped: skipped,
  );
}

/// font / shadow / spacing 这些 tweakcn 也导出，但本仓不吃 —— 别当「读不出的颜色」报出去。
const Set<String> _nonColorKeys = {
  'font-sans',
  'font-serif',
  'font-mono',
  'tracking',
  'tracking-normal',
  'letter-spacing',
  'spacing',
  'shadow-opacity',
  'shadow-blur',
  'shadow-spread',
  'shadow-offset-x',
  'shadow-offset-y',
  'radius-sm',
  'radius-md',
  'radius-lg',
  'radius-xl',
};

final RegExp _declPattern = RegExp(r'--([A-Za-z0-9_-]+)\s*:\s*([^;{}]+)');

/// 选择器链 → 这一段属于 light 还是 dark（null = 与主题无关，整块跳过）。
///
/// 判据按「链里出现过 dark 就算暗色」：`@media (prefers-color-scheme: dark) { :root }`
/// 与 `.dark { :root }` 都能盖到。
_BrightnessSlot? _classifySelector(String selectorPath) {
  final path = selectorPath.toLowerCase();
  if (path.contains('dark')) return _BrightnessSlot.dark;
  if (path.isEmpty ||
      path.contains(':root') ||
      path.contains(':host') ||
      path.contains('theme')) {
    return _BrightnessSlot.light;
  }
  return null;
}

enum _BrightnessSlot { light, dark }

/// 递归走 CSS：把每一层块里的**直接**声明按祖先选择器链归到 light/dark。
///
/// 「直接」很关键 —— 不把嵌套块的内容算进外层，否则 `.dark` 里的声明会被
/// `@layer base` 抢走一份，两套值互相覆盖。
void _parseRegion(
  String text,
  int start,
  int end,
  List<String> path,
  Map<String, String> light,
  Map<String, String> dark,
) {
  var cursor = start;
  while (cursor < end) {
    final open = text.indexOf('{', cursor);
    if (open == -1 || open >= end) break;
    // 块之前的文本属于本层：可能带声明，末尾那段是选择器。
    _collect(text.substring(cursor, open), path, light, dark);
    final selector = text
        .substring(cursor, open)
        .split(RegExp(r'[;}]'))
        .last
        .trim();
    final close = _matchingBrace(text, open, end);
    _parseRegion(text, open + 1, close, [...path, selector], light, dark);
    cursor = close + 1;
  }
  _collect(text.substring(cursor, end), path, light, dark);
}

/// 找 [open] 处 `{` 配对的 `}`；没有配对则返回 [end]。
int _matchingBrace(String text, int open, int end) {
  var depth = 0;
  for (var i = open; i < end; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}' && --depth == 0) return i;
  }
  return end - 1;
}

void _collect(
  String chunk,
  List<String> path,
  Map<String, String> light,
  Map<String, String> dark,
) {
  if (chunk.trim().isEmpty) return;
  final slot = _classifySelector(path.join(' > '));
  if (slot == null) return;
  final into = slot == _BrightnessSlot.light ? light : dark;
  for (final match in _declPattern.allMatches(chunk)) {
    final name = normalizeTokenName(match.group(1)!);
    final value = match.group(2)!.trim();
    if (name.isEmpty || value.isEmpty) continue;
    into[name] = value;
  }
}

class _VarBlocks {
  final Map<String, String> light;
  final Map<String, String> dark;
  final String name;

  _VarBlocks({
    Map<String, String>? light,
    Map<String, String>? dark,
    this.name = '',
  }) : light = light ?? const {},
       dark = dark ?? const {};
}

_VarBlocks? _fromJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final name = (decoded['name'] as String?) ?? '';
  final vars =
      decoded[r'$cssVars'] ?? decoded['cssVars'] ?? decoded['variables'];
  if (vars is Map) {
    return _VarBlocks(
      name: name,
      light: _stringMap(
        vars['theme'] ?? vars['light'] ?? vars[':root'] ?? vars['root'],
      ),
      dark: _stringMap(vars['dark'] ?? vars['.dark']),
    );
  }
  // 扁平的 `{"--background": "oklch(…)"}`：按 light 读。
  final flat = _stringMap(decoded);
  return flat.isEmpty ? null : _VarBlocks(name: name, light: flat);
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final e in raw.entries)
      if (e.value is String) normalizeTokenName('${e.key}'): '${e.value}',
  };
}

Map<String, Color> _colorMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Color>{};
  for (final e in raw.entries) {
    final color = e.value is String ? parseCssColor('${e.value}') : null;
    if (color != null) out[normalizeTokenName('${e.key}')] = color;
  }
  return out;
}

String _hex(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}${two(c.a)}';
}

bool _mapEquals(Map<String, Color> a, Map<String, Color> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
