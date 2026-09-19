import 'package:flutter/foundation.dart';

/// 漫画的**语言 / 汉化**标记，只由标签与标题推出来。
///
/// 三种状态是有意分开的：插件（Bika / 禁漫 / …）给的标签词汇不一样，
/// 有的只写「漢化」，有的写「中文」，有的把日语原版标成「日本語」。
/// 把「我知道这本能读」和「我不知道」混成一个布尔值，就没法在提示里
/// 告诉用户**靠哪个标签**得出的结论（排查词表时这是唯一的线索）。
enum ChineseTranslationKind {
  /// 没有任何语言线索 —— 角标不显示。
  none,

  /// 明确是「别人译成中文」：汉化 / 漢化組 / 翻譯。
  translated,

  /// 只说明语言是中文（简体 / 繁體），不区分原生中文还是汉化。
  chinese,

  /// 日语原版（生肉）—— 先提示出来，免得下完才发现读不了。
  raw,
}

/// 判定结果。
@immutable
class ChineseTranslationMatch {
  const ChineseTranslationMatch({
    required this.kind,
    this.matchedText,
    this.matchedInTitle = false,
  });

  final ChineseTranslationKind kind;

  /// 命中的那一项：标签命中时是**标签原文**（`漢化組`），
  /// 标题命中时是命中的**关键词**（`汉化`）。提示条直接用。
  final String? matchedText;

  /// 命中来自标题（如 `[XX汉化组] 某作品`）还是标签。
  final bool matchedInTitle;

  static const none = ChineseTranslationMatch(
    kind: ChineseTranslationKind.none,
  );

  bool get hasBadge => kind != ChineseTranslationKind.none;
}

/// 从标签 + 标题里认出「汉化 / 中文 / 生肉」。
///
/// 为什么标题也要看：大量同人本的中文版**没有语言标签**，只有标题里挂着
/// `[XX漢化組]`；反过来只看标题又会漏掉插件用分类字段标的语言。
/// 两边都扫，命中优先级见 [match]。
class ChineseTranslationMatcher {
  ChineseTranslationMatcher._();

  /// 汉化：明确表示「有人把它译成中文」。
  static const translatedKeywords = <String>['汉化', '汉化组', '汉化版', '翻译', '中文化'];

  /// 中文：只说明语言是中文，不区分原生还是汉化。
  static const chineseKeywords = <String>[
    '中文',
    '中文版',
    '简体',
    '繁体',
    '简中',
    '繁中',
    'chinese',
  ];

  /// 生肉：日文原版。
  static const rawKeywords = <String>[
    '日语',
    '日文',
    '生肉',
    '原版',
    'japanese',
    'raw',
  ];

  /// 繁体 -> 简体。**两侧都折**（标签与关键词都过一遍），
  /// 所以只需覆盖关键词表里出现过的繁体字形。
  static const _foldMap = <String, String>{
    '漢': '汉',
    '組': '组',
    '譯': '译',
    '語': '语',
    '體': '体',
    '簡': '简',
    '無': '无',
    '畫': '画',
  };

  /// 标签可能带前缀（`标签：汉化` / `tag: 汉化` / `分类：漢化`），先剥掉。
  static final _tagPrefix = RegExp(
    r'^\s*(标签|標籤|分类|分類|tag|tags|category|categories)\s*[:：]\s*',
    caseSensitive: false,
  );

  /// 归一化：剥前缀、去首尾空白、去包裹的括号、折繁体、转小写。
  static String fold(String value) {
    var text = value.trim().replaceFirst(_tagPrefix, '').trim();
    text = _stripWrappingBrackets(text);
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_foldMap[char] ?? char);
    }
    return buffer.toString().toLowerCase();
  }

  static String _stripWrappingBrackets(String text) {
    var current = text;
    bool stripped;
    do {
      stripped = false;
      if (current.length >= 2 &&
          ((current.startsWith('[') && current.endsWith(']')) ||
              (current.startsWith('【') && current.endsWith('】')) ||
              (current.startsWith('(') && current.endsWith(')')) ||
              (current.startsWith('（') && current.endsWith('）')))) {
        current = current.substring(1, current.length - 1).trim();
        stripped = true;
      }
    } while (stripped && current.length >= 2);
    return current;
  }

  /// 只在标签里找「生肉」，不扫标题。
  ///
  /// 标题扫的是自由文本，`原版` 这种词在中文标题里太容易误伤
  /// （「原版封面」「原版剧情」）；而日语原版的标题**本来**也很少写「日本語」，
  /// 扫了几乎只有误报、没有召回。
  static const _titleScannableKinds = <ChineseTranslationKind>{
    ChineseTranslationKind.translated,
    ChineseTranslationKind.chinese,
  };

  /// 判定。
  ///
  /// 优先级：**汉化 > 中文 > 生肉**，且**标签优先于标题**。
  /// 理由：标签是插件的结构化字段，比标题里的自由文本可信；
  /// 而同时挂着「汉化」和「日本語」（多语言版本）时，用户要能读的那本。
  ///
  /// [extraTranslatedKeywords] 是用户自定义的补充词（与内置表同优先级）。
  static ChineseTranslationMatch match({
    required String title,
    Iterable<String>? tags,
    Iterable<String> extraTranslatedKeywords = const [],
  }) {
    final needlesByKind = <ChineseTranslationKind, List<String>>{
      ChineseTranslationKind.translated: <String>[
        ...translatedKeywords,
        ...extraTranslatedKeywords,
      ],
      ChineseTranslationKind.chinese: chineseKeywords,
      ChineseTranslationKind.raw: rawKeywords,
    };

    final rawTags = <String>[
      for (final tag in tags ?? const <String>[])
        if (tag.trim().isNotEmpty) tag.trim(),
    ];

    for (final kind in const [
      ChineseTranslationKind.translated,
      ChineseTranslationKind.chinese,
      ChineseTranslationKind.raw,
    ]) {
      final needles = needlesByKind[kind]!;

      // 1) 标签优先：报出命中标签的原文。
      for (final tag in rawTags) {
        if (_firstHit(fold(tag), needles) != null) {
          return ChineseTranslationMatch(kind: kind, matchedText: tag);
        }
      }

      // 2) 再看标题：报出命中的关键词（只对汉化 / 中文两类，见
      //    [_titleScannableKinds]）。
      if (!_titleScannableKinds.contains(kind)) continue;
      final hit = _firstHit(fold(title), needles);
      if (hit != null) {
        return ChineseTranslationMatch(
          kind: kind,
          matchedText: hit,
          matchedInTitle: true,
        );
      }
    }

    return ChineseTranslationMatch.none;
  }

  /// 返回第一个命中的关键词（按词表顺序，内置词在前）。
  static String? _firstHit(String haystack, List<String> needles) {
    if (haystack.isEmpty) return null;
    for (final needle in needles) {
      if (_contains(haystack, needle)) {
        return needle;
      }
    }
    return null;
  }

  /// CJK 关键词直接子串匹配；纯 ASCII 关键词（`raw` / `chinese` / `japanese`）
  /// 必须落在词边界上，否则 `raw` 会命中 `draw`、`straw`。
  static bool _contains(String haystack, String needle) {
    final foldedNeedle = fold(needle);
    if (foldedNeedle.isEmpty) return false;
    if (!_isAscii(foldedNeedle)) {
      return haystack.contains(foldedNeedle);
    }
    final pattern = RegExp(
      '(^|[^a-z0-9])${RegExp.escape(foldedNeedle)}([^a-z0-9]|\$)',
    );
    return pattern.hasMatch(haystack);
  }

  static bool _isAscii(String value) {
    for (final rune in value.runes) {
      if (rune > 0x7f) return false;
    }
    return true;
  }
}
