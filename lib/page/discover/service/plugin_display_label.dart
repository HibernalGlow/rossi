// 发现页标签上的那截**插件名缩写**。
//
// 为什么要有缩写这件事：标签条很窄（泳道里更窄），全名会把功能名挤掉，
// 而「这是哪个插件的排行」恰恰是标签必须回答的问题 —— 两个插件都有「排行」。
//
// 规则只写在这里一份，判据：
//   dart run test/discover/plugin_display_label_check.dart
//
// 本文件**不 import** package:flutter/**（会拖进 dart:ui），所以能用 dart run 直接断言。

/// 名字里出现即视为「切词边界」的分隔符。
///
/// 不含 `.`：`e.hentai` 这类写法里点号是名字的一部分，切成两段只会得到 `eh`
/// 以外的巧合结果；也不含中文逗号之类 —— 插件名没有它们。
const String _separators = '-_/·| ';

bool _isSeparator(String unit) => _separators.contains(unit);

/// 表意文字 / 假名 / 谚文：这类名字前两字就足够区分（「绅士漫画」→「绅士」）。
bool _isWideUnit(int rune) =>
    (rune >= 0x3040 && rune <= 0x30ff) ||
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0xac00 && rune <= 0xd7af) ||
    (rune >= 0xf900 && rune <= 0xfaff);

List<String> _segments(String trimmed) {
  final out = <String>[];
  final current = StringBuffer();
  for (final unit in trimmed.split('')) {
    if (_isSeparator(unit)) {
      if (current.isNotEmpty) {
        out.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(unit);
  }
  if (current.isNotEmpty) out.add(current.toString());
  return out;
}

/// 按**码点**取前 [count] 个字符。
///
/// 不用 substring：代理对（emoji 名字）会被从中间劈开。
String _takeUnits(String source, int count) =>
    String.fromCharCodes(source.runes.take(count));

/// [name] → 标签上用的缩写。空名返回空串（调用方据此不画这一段）。
///
/// - 表意文字开头：取前两个字（「绅士漫画」→「绅士」，「禁漫」→「禁漫」）；
/// - 拉丁开头且**首段很短**（≤2 字符）而后面还有段：取前两段的首字母
///   （「e-hentai」→「eh」—— 截前三位会得到「e-h」，那看着像被截断了）；
/// - 其余拉丁：取首段前三个字符（「BikaACG」→「Bik」）。
String pluginShortName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';

  final segments = _segments(trimmed);
  if (segments.isEmpty) return '';

  final first = segments.first;
  if (_isWideUnit(first.runes.first)) {
    return _takeUnits(first, 2);
  }
  if (first.length <= 2 && segments.length > 1) {
    // 首段一定是拉丁（上面已按首个码点判过宽字符），所以 [0] 不会劈开代理对；
    // 第二段就不一定了，照样按码点取。
    return '${first[0]}${_takeUnits(segments[1], 1)}';
  }
  return _takeUnits(first, 3);
}

/// 标签正文：`缩写 · 标签`；缩写为空或关掉显示时只剩 [label]。
String joinTabLabel({required String? shortName, required String label}) {
  final short = shortName?.trim() ?? '';
  if (short.isEmpty) return label;
  return '$short · $label';
}

/// 同一个插件里已经摆着 [existingLabels] 这些标签，给新开的那条补序号。
///
/// 为什么要补：用户就是要同时开好几个「搜索」（各查一个词），不补序号的话
/// 标签条上一排字完全一样，切哪个全凭猜。**不限制重复标签**是刻意的口径，
/// 所以分辨的重任落在标题上。只在真的重名时才加，第一条保持干净。
String disambiguateLabel({
  required String label,
  required List<String> existingLabels,
}) {
  final taken = existingLabels.toSet();
  if (!taken.contains(label)) return label;
  var next = 2;
  while (taken.contains('$label $next')) {
    next++;
  }
  return '$label $next';
}

/// 一个字符串稳定落到 `[0, 360)` 的色相（度数）。
///
/// 生成图标按插件 id 取色相：同一个插件在任何地方都是同一个颜色，
/// 换主题也跟着走（饱和度与亮度由主题给）。
/// 用 FNV-1a 而不是 `hashCode`：Dart 的 String.hashCode 不保证跨进程稳定。
double hueOfSeed(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.runes) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash % 360).toDouble();
}
