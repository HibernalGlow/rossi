/// tag 文本的归一化原语。
///
/// 单独一个文件、零项目依赖，是为了让「归一化」这件事只有一份实现：
/// 收藏列表去重（`GlobalSettingCubit`）与命中判断（`FavoriteTagMatcher`）必须用
/// 同一个口径，否则会出现「加进去以为去重了、匹配时又算它是另一个 tag」。
/// 喜欢画师那边就留了这个裂缝（去重用 `trim().toLowerCase()`，匹配用
/// `normalizeArtist`），不再重复一次。
class TagText {
  TagText._();

  static final _wrappers = const [
    ('[', ']'),
    ('(', ')'),
    ('【', '】'),
    ('（', '）'),
  ];

  static final _namespacePrefix = RegExp(r'^([a-z][a-z0-9_]{0,15}):');

  static final _bracketContent = RegExp(
    r'\[([^\[\]]+)\]|\(([^()]+)\)|【([^【】]+)】|（([^（）]+)）',
  );

  /// 归一化成一个用于比较的键：剥掉包裹括号、全角转半角、`_` 与空格等价、小写。
  ///
  /// 刻意**不**做子串折叠：`lolita` 不该命中 `school_lolita`。跨站点的写法差异
  /// 交给用户显式登记的别名（见 `FavoriteTag.aliases`），而不是靠放宽比较。
  static String normalize(String? value) {
    if (value == null) return '';
    var text = foldFullWidth(value).trim();
    if (text.isEmpty) return '';

    bool stripped;
    do {
      stripped = false;
      for (final (open, close) in _wrappers) {
        if (text.startsWith(open) && text.endsWith(close) && text.length > 2) {
          text = foldFullWidth(text.substring(1, text.length - 1)).trim();
          stripped = true;
          break;
        }
      }
    } while (stripped && text.isNotEmpty);

    return collapseSeparators(text).toLowerCase();
  }

  /// 全角形式（U+FF01–U+FF5E）折到对应的半角 ASCII，`U+3000` 折成空格。
  ///
  /// 日文站与中文站混用时 `：` `（）` 与半角形式是同一个 tag 的两种写法。
  static String foldFullWidth(String value) {
    if (!value.runes.any((r) => r >= 0x3000 && r <= 0xff5e)) return value;
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// `_` 与空白串视为同一个分隔符（`school_lolita` == `School Lolita`）。
  static String collapseSeparators(String value) {
    return value.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 剥掉 `artist:` / `language:` 这类命名空间前缀；不是前缀时返回 null。
  ///
  /// 只认「纯 ASCII 小写词 + 可选下划线」且后面紧跟 `:` 的形状，且要求冒号后没有
  /// 空格 —— `Fate/Grand Order: ...` 这种冒号属于正文，不能当命名空间削掉。
  static String? stripNamespace(String normalized) {
    final match = _namespacePrefix.matchAsPrefix(normalized);
    // `match.end` 已经**包含**冒号，再 +1 就把值的第一格吃掉了。
    final rest = match == null ? '' : normalized.substring(match.end);
    if (rest.isEmpty || rest.startsWith(' ')) return null;
    return rest;
  }

  /// 标题里各层括号的内容，逐个归一化后作为候选 tag。
  ///
  /// EH 系标题常写成 `[Chinese] [社团 (画师)] 本子名`，语言/完备性这类 tag 只在
  /// 标题里出现，插件的 metadata 里没有对应项，所以卡片也要看一眼标题。
  static List<String> bracketCandidates(String title) {
    if (title.trim().isEmpty) return const [];
    final candidates = <String>{};
    for (final match in _bracketContent.allMatches(title)) {
      final content =
          (match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4))
              ?.trim();
      if (content == null || content.isEmpty) continue;
      candidates.add(normalize(content));
    }
    candidates.remove('');
    return candidates.toList();
  }
}
