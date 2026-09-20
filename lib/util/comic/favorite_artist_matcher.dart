import 'package:flutter/foundation.dart';

/// 社团名（circle）在匹配里的地位。
///
/// 做成三档而不是开关：有人按画师收、有人按社团收（同人社团换马甲时只有社团名
/// 对得上），而「社团名撞上汉化组/活动名」正是乱匹的主要来源，所以默认只在
/// 这条本子拿不出画师证据时才认社团。
enum FavoriteArtistCircleMode {
  /// 完全不认社团名，只认画师位。
  off,

  /// 默认：只有这条本子**完全没有画师证据**时，社团名才算命中。
  fallbackOnly,

  /// 社团名独立参与匹配，但优先级仍排在画师证据之后。
  independent,
}

/// 命名空间与画师的关系。
enum FavoriteArtistRelevance { artist, circle, irrelevant }

/// 命中的证据来源，按可信度从高到低。
enum FavoriteArtistEvidence {
  /// 画师命名空间的标签（`artist:` / 插件的 `tag:artist` 分组 / 内置源的 author）。
  artistTag,

  /// 详情接口的作者字段。
  creator,

  /// 标题画师块里 `(画师)` 那一位。
  titleArtist,

  /// 标题画师块只有一个名字，社团与画师无从区分。
  titleAuthorBlock,

  /// 社团命名空间的标签。
  circleTag,

  /// 标题画师块里的社团位。
  titleCircle,

  /// 兜底：画师名作为**独立词**出现在标题正文里。
  titleToken,
}

@immutable
class FavoriteArtistMatchResult {
  final bool isMatched;

  /// 用户喜欢列表里的那条原文，用于「取消喜欢」这类反查。
  final String? matchedArtist;

  /// 实际对上的那个名字（漫画那一侧的写法），给徽标显示。
  final String? matchedName;

  final FavoriteArtistEvidence? evidence;

  const FavoriteArtistMatchResult({
    required this.isMatched,
    this.matchedArtist,
    this.matchedName,
    this.evidence,
  });

  static const notMatched = FavoriteArtistMatchResult(isMatched: false);
}

/// 漫画一侧的一个候选名字：[key] 用来比，[display] 用来说话。
@immutable
class _Name {
  final String key;
  final String display;

  const _Name(this.key, this.display);
}

/// 标题里解析出来的画师块（`(事件) [社团 (画师)] 作品名`）。
@immutable
class _AuthorBlock {
  final String? artist;
  final String? circle;

  /// 整块只有一个名字时它落在哪个变量上。
  final String? bare;

  /// 整块在标题里的区间。兜底那一档要把它挖掉：块里的社团位已经由 3~5 档按
  /// 优先级判过了，再让「独立词包含」认一遍就等于绕开 circleMode。
  final int start;
  final int end;

  const _AuthorBlock({
    this.artist,
    this.circle,
    this.bare,
    this.start = -1,
    this.end = -1,
  });
}

/// 一条喜欢项拆出来的候选名。
@immutable
class _FavoriteEntry {
  final String raw;
  final Set<String> artistKeys;
  final Set<String> circleKeys;

  const _FavoriteEntry({
    required this.raw,
    required this.artistKeys,
    required this.circleKeys,
  });
}

/// 把元数据按命名空间分成画师/社团两个桶。
///
/// 调用方给的元数据形状不止一种（`UnifiedComicMetadata` / `ComicInfoMetadata`），
/// 但都能给出 `type`、`name` 和值的文本；「哪些命名空间算画师」这条判定
/// 只在这里做一次，别在每个卡片里各写一份。
class FavoriteArtistBuckets {
  final List<String> artistTags = [];
  final List<String> circleTags = [];

  /// 无关命名空间（上传者、分类、语言、汉化组、角色、parody…）整组丢掉。
  void addGroup({
    required String type,
    required String name,
    required Iterable<String> values,
  }) {
    final relevance = FavoriteArtistMatcher.classifyNamespace(type, name);
    if (relevance == FavoriteArtistRelevance.irrelevant) return;
    final target = relevance == FavoriteArtistRelevance.artist
        ? artistTags
        : circleTags;
    for (final value in values) {
      final text = value.trim();
      if (text.isNotEmpty) target.add(text);
    }
  }
}

/// 喜欢画师提取与匹配工具类。
///
/// **口径**：命中只认「结构化解析出来的画师名 / 社团名」，来源依次是
/// 1. 带画师命名空间的标签（`artist:`、插件的 `tag:artist` 分组、内置源的 `author`），
/// 2. 详情接口的作者字段，
/// 3. 标题里**第一个非噪声方括号块**（同人志的 `[社团 (画师)]` 约定），
/// 4. 兜底：画师名作为独立词出现在标题正文里（长度 >=3，前后不接字母/数字/汉字）。
///
/// 为什么要拧到这个程度：列表卡片的元数据里根本没有画师命名空间（e-hentai 插件
/// 只给 category + uploader），把「上传者：xxx」「分类：[English]」也拿去等值比较，
/// 或者把 `(C100)`「[xxx汉化]」当画师块，就是乱匹的来源；标题整串包含则会让
/// 「水龙敬乐园」匹上喜欢画师「水龙敬」。
class FavoriteArtistMatcher {
  FavoriteArtistMatcher._();

  /// 方括号组：画师块的候选。内容里允许带圆括号，所以只排除嵌套方括号。
  static final _squareGroupRegex = RegExp(r'\[([^\[\]]*)\]|【([^【】]*)】');

  /// 任意括号组：兜底搜索前用来把噪声括号挖掉。
  static final _anyGroupRegex = RegExp(
    r'\[[^\[\]]*\]|【[^【】]*】|（[^（）]*）|\([^()]*\)',
  );

  /// 画师位：`A (B)` / `A （B）`。社团名自己可能带括号，所以取最后一个括号对。
  static final _circleArtistRegex = RegExp(
    r'^(.+?)\s*[\(（]([^()（）]+)[\)）]\s*$',
  );

  /// 标签自带的命名空间前缀：`artist:xxx`、`上传者：xxx`。
  static final _tagPrefixRegex = RegExp(
    r'^\s*([a-zA-Z][a-zA-Z0-9_ +\-]*|[\u4e00-\u9fff]{1,8})\s*[:：]\s*',
  );

  /// 整块就是事件码 / 卷号 / 日期 / 大小的算噪声。
  static final _structuralNoise = RegExp(
    r'^(?:c\d{2,3}[a-z]?|m\d+|comic\d+|\d{2,4}[-/.年]\d{1,2}(?:[-/.月]\d{1,2}日?)?'
    r'|\d+(?:st|nd|rd|th)|(?:vol|v)\.?\d+|第?\d+[话話卷冊]\d*|\d+(?:\.\d+)?'
    r'(?:kb|mb|gb|p|页))$',
    caseSensitive: false,
  );

  /// 含这些词的括号块不是画师块（中日文按包含判，拉丁词按整词判）。
  static const _noiseCjk = <String>[
    '汉化',
    '漢化',
    '扫图',
    '掃圖',
    '清洗',
    '嵌字',
    '校对',
    '校對',
    '翻译',
    '翻譯',
    '压制',
    '样本',
    '樣本',
    '样章',
    '预览',
    '預覽',
    '特典',
    '附录',
    '附録',
    '合集',
    '合刊',
    '无码',
    '無碼',
    '禁漫',
    '封面',
    '彩页',
    '彩頁',
    '完结',
    '完結',
  ];

  static const _noiseWords = <String>[
    'sample',
    'samples',
    'preview',
    'digital',
    'webdl',
    'web-dl',
    'complete',
    'english',
    'chinese',
    'japanese',
    'ocr',
  ];

  static const _noiseLanguageCodes = <String>{
    'zh',
    'zh-cn',
    'zh-tw',
    'zh-hans',
    'zh-hant',
    'chs',
    'cht',
    'cn',
    'en',
    'ja',
    'jp',
    'ko',
    'es',
    'raw',
    'tl',
  };

  /// 画师命名空间。刻意**不含**「原作」：EhTagTranslation 把 `parody` 译作「原作」，
  /// 那一栏是作品来源（东方Project 之类），拿它当画师名正是乱匹。
  static const _artistNamespace = <String>{
    'artist',
    'artists',
    'author',
    'authors',
    'creator',
    'creators',
    'illustrator',
    'painter',
    'drawer',
    '作者',
    '画师',
    '畫師',
    '绘者',
    '繪者',
    '漫画家',
  };

  static const _circleNamespace = <String>{
    'group',
    'groups',
    'circle',
    '社团',
    '社團',
    '团体',
    '團體',
    '同人社团',
  };

  /// 归一化画师名称：去首尾空白、剥掉整层多余括号、转小写。
  static String normalizeArtist(String? value) {
    if (value == null) return '';
    var text = value.trim();
    if (text.isEmpty) return '';

    bool stripped;
    do {
      stripped = false;
      if ((text.startsWith('[') && text.endsWith(']')) ||
          (text.startsWith('(') && text.endsWith(')')) ||
          (text.startsWith('【') && text.endsWith('】')) ||
          (text.startsWith('（') && text.endsWith('）'))) {
        text = text.substring(1, text.length - 1).trim();
        stripped = true;
      }
    } while (stripped && text.isNotEmpty);

    return text.toLowerCase();
  }

  /// 命名空间归类。[type] 与 [name] 一起看，因为插件两边写得不一样：
  /// e-hentai 插件的 `type` 是 `tag:artist`、`name` 是 EhTagTranslation 的「作者」，
  /// 内置源与历史数据用 `author` / `works` / `actors` 这套。
  static FavoriteArtistRelevance classifyNamespace(String type, String name) {
    final keys = {
      normalizeArtist(type).replaceFirst(RegExp(r'^tag[:：]'), ''),
      normalizeArtist(name),
    }.where((k) => k.isNotEmpty);
    for (final key in keys) {
      if (_circleNamespace.contains(key)) return FavoriteArtistRelevance.circle;
    }
    for (final key in keys) {
      if (_artistNamespace.contains(key)) {
        return FavoriteArtistRelevance.artist;
      }
    }
    return FavoriteArtistRelevance.irrelevant;
  }

  /// 单个标签值要不要按「喜欢画师」点亮（详情页 chip 用）。
  ///
  /// 命名空间明写着画师/社团的，按拆出来的候选名比 —— 这样喜欢项存成
  /// `[社团 (画师)]` 时，画师那颗 chip 也会亮。命名空间与画师无关时退回整条等值，
  /// 保证用户在任意 chip 上「设为喜欢画师」之后，那颗 chip 自己会亮。
  static bool chipIsFavorite({
    required String label,
    required String namespaceType,
    required String namespaceName,
    required Iterable<String> favoriteArtists,
    FavoriteArtistCircleMode circleMode = FavoriteArtistCircleMode.fallbackOnly,
  }) {
    final key = normalizeArtist(label);
    if (key.isEmpty) return false;
    final relevance = classifyNamespace(namespaceType, namespaceName);
    for (final artist in favoriteArtists) {
      final entry = _parseFavorite(artist);
      switch (relevance) {
        case FavoriteArtistRelevance.artist:
          if (entry.artistKeys.contains(key)) return true;
        case FavoriteArtistRelevance.circle:
          if (circleMode == FavoriteArtistCircleMode.off) continue;
          if (entry.circleKeys.contains(key)) return true;
        case FavoriteArtistRelevance.irrelevant:
          if (entry.artistKeys.contains(key) ||
              entry.circleKeys.contains(key)) {
            return true;
          }
      }
    }
    return false;
  }

  /// 从标题解析画师块；没有非噪声方括号块时返回 null（此时只剩兜底一档）。
  static _AuthorBlock? _parseAuthorBlock(String title) {
    for (final match in _squareGroupRegex.allMatches(title)) {
      final content = (match.group(1) ?? match.group(2) ?? '').trim();
      if (content.isEmpty || _looksLikeNoise(content)) continue;
      final inner = _circleArtistRegex.firstMatch(content);
      if (inner != null) {
        final circle = inner.group(1)?.trim() ?? '';
        final artist = inner.group(2)?.trim() ?? '';
        if (artist.isEmpty) continue;
        return _AuthorBlock(
          artist: artist,
          circle: circle.isEmpty ? null : circle,
          start: match.start,
          end: match.end,
        );
      }
      return _AuthorBlock(bare: content, start: match.start, end: match.end);
    }
    return null;
  }

  /// 一条喜欢项拆成画师候选与社团候选。
  static _FavoriteEntry _parseFavorite(String raw) {
    final artistKeys = <String>{};
    final circleKeys = <String>{};
    final text = raw.trim();
    final inner = text.isEmpty
        ? null
        : _circleArtistRegex.firstMatch(_stripBrackets(text));
    if (inner != null) {
      final circle = normalizeArtist(inner.group(1));
      final artist = normalizeArtist(inner.group(2));
      if (artist.isNotEmpty) artistKeys.add(artist);
      if (circle.isNotEmpty) {
        circleKeys.add(circle);
        // `社团 (画师)` 整块也是画师证据：它唯一指向这一家。
        artistKeys.add(normalizeArtist('$circle ($artist)'));
      }
    } else {
      final bare = normalizeArtist(text);
      if (bare.isNotEmpty) {
        // 裸名字无从判断是社团还是画师，两边都收；社团那一侧仍受 circleMode 约束。
        artistKeys.add(bare);
        circleKeys.add(bare);
      }
    }
    return _FavoriteEntry(
      raw: raw,
      artistKeys: artistKeys,
      circleKeys: circleKeys,
    );
  }

  /// 判断漫画是否命中喜欢画师。
  ///
  /// - [artistTags]：画师命名空间的标签值（可带 `artist:` 前缀，自己剥）。
  /// - [circleTags]：社团命名空间的标签值。
  /// - [creator]：详情接口的作者字段。
  /// 其余元数据（上传者、分类、语言、汉化组、角色、parody…）不要传进来：
  /// 就算传了，[FavoriteArtistRelevance.irrelevant] 那一侧也不会认它。
  static FavoriteArtistMatchResult match({
    required String title,
    Iterable<String> artistTags = const [],
    Iterable<String> circleTags = const [],
    String? creator,
    required Iterable<String> favoriteArtists,
    FavoriteArtistCircleMode circleMode = FavoriteArtistCircleMode.fallbackOnly,
  }) {
    final entries = <_FavoriteEntry>[];
    for (final artist in favoriteArtists) {
      final entry = _parseFavorite(artist);
      if (entry.artistKeys.isNotEmpty || entry.circleKeys.isNotEmpty) {
        entries.add(entry);
      }
    }
    if (entries.isEmpty) return FavoriteArtistMatchResult.notMatched;

    final block = _parseAuthorBlock(title);
    final artistTagNames = _namesFromTags(artistTags, artistPosition: true);
    final circleTagNames = _namesFromTags(circleTags, artistPosition: false);
    final creatorName = _name(creator);
    final titleArtist = _name(block?.artist);
    final titleCircle = _name(block?.circle);
    final titleBare = _name(block?.bare);

    FavoriteArtistMatchResult firstHit(
      Iterable<_Name> names,
      FavoriteArtistEvidence evidence, {
      required bool circleSide,
    }) {
      for (final entry in entries) {
        final keys = circleSide ? entry.circleKeys : entry.artistKeys;
        for (final name in names) {
          if (name.key.isNotEmpty && keys.contains(name.key)) {
            return FavoriteArtistMatchResult(
              isMatched: true,
              matchedArtist: entry.raw,
              matchedName: name.display,
              evidence: evidence,
            );
          }
        }
      }
      return FavoriteArtistMatchResult.notMatched;
    }

    // 1. 画师命名空间的标签：插件明写的，最可信。
    var result = firstHit(
      artistTagNames,
      FavoriteArtistEvidence.artistTag,
      circleSide: false,
    );
    if (result.isMatched) return result;

    // 2. 详情作者字段。
    if (creatorName != null) {
      result = firstHit(
        [creatorName],
        FavoriteArtistEvidence.creator,
        circleSide: false,
      );
      if (result.isMatched) return result;
    }

    // 3. 标题画师块的画师位。
    if (titleArtist != null) {
      result = firstHit(
        [titleArtist],
        FavoriteArtistEvidence.titleArtist,
        circleSide: false,
      );
      if (result.isMatched) return result;
    }

    // 4. 标题画师块只有一个名字：社团/画师不分，先按画师认一次。
    if (titleBare != null) {
      result = firstHit(
        [titleBare],
        FavoriteArtistEvidence.titleAuthorBlock,
        circleSide: false,
      );
      if (result.isMatched) return result;
    }

    // 5. 社团证据。fallbackOnly 的前提是这条本子压根没有画师证据；
    //    independent 时社团照样参与，只是排在上面几档之后。
    if (circleMode != FavoriteArtistCircleMode.off) {
      final hasArtistEvidence =
          artistTagNames.isNotEmpty ||
          creatorName != null ||
          titleArtist != null;
      final allowed =
          circleMode == FavoriteArtistCircleMode.independent ||
          !hasArtistEvidence;
      if (allowed) {
        result = firstHit(
          circleTagNames,
          FavoriteArtistEvidence.circleTag,
          circleSide: true,
        );
        if (result.isMatched) return result;
        for (final name in [titleCircle, titleBare]) {
          if (name == null) continue;
          result = firstHit(
            [name],
            FavoriteArtistEvidence.titleCircle,
            circleSide: true,
          );
          if (result.isMatched) return result;
        }
      }
    }

    // 6. 兜底：画师名以独立词的形式出现在标题正文里。
    //    噪声括号（事件码、汉化组、语言标记）内部不算，画师块本身也不算 ——
    //    块里的社团位已经由 3~5 档按 circleMode 判过，这里再认一遍等于绕开开关。
    final haystack = _noiseMaskedTitle(
      title,
      maskFrom: block?.start ?? -1,
      maskTo: block?.end ?? -1,
    );
    final tokenKeys = <({String key, String raw})>[];
    for (final entry in entries) {
      for (final key in entry.artistKeys) {
        // `社团 (画师)` 这种复合键不可能作为独立词出现，跳过。
        if (key.contains('(') || key.contains('（')) continue;
        tokenKeys.add((key: key, raw: entry.raw));
      }
      if (circleMode == FavoriteArtistCircleMode.independent) {
        for (final key in entry.circleKeys) {
          if (key.contains('(') || key.contains('（')) continue;
          tokenKeys.add((key: key, raw: entry.raw));
        }
      }
    }
    tokenKeys.sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final token in tokenKeys) {
      // 两个字的画师名几乎一定撞上标题里的别的词，宁可不认。
      if (token.key.length < 3) continue;
      final at = _standaloneTokenAt(haystack, token.key);
      if (at == null) continue;
      return FavoriteArtistMatchResult(
        isMatched: true,
        matchedArtist: token.raw,
        matchedName: title.substring(at, at + token.key.length),
        evidence: FavoriteArtistEvidence.titleToken,
      );
    }

    return FavoriteArtistMatchResult.notMatched;
  }

  static _Name? _name(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final key = normalizeArtist(text);
    if (key.isEmpty) return null;
    return _Name(key, text);
  }

  /// 标签值 → 候选名字。
  ///
  /// 自带命名空间前缀的值只认它自己那一侧：`artist:X` 进画师，`group:Y` 进社团，
  /// `uploader:Z` 直接丢。没有前缀的裸值按调用方分桶时的判断算，整块 `A (B)` 拆开。
  static List<_Name> _namesFromTags(
    Iterable<String> tags, {
    required bool artistPosition,
  }) {
    final names = <_Name>[];
    final seen = <String>{};
    void add(_Name? name) {
      if (name == null || name.key.isEmpty || !seen.add(name.key)) return;
      names.add(name);
    }

    for (final tag in tags) {
      final text = tag.trim();
      if (text.isEmpty) continue;
      var value = text;
      final prefix = _tagPrefixRegex.firstMatch(text);
      if (prefix != null) {
        final namespace = (prefix.group(1) ?? '').toLowerCase();
        final relevance = classifyNamespace(namespace, namespace);
        final wanted = artistPosition
            ? FavoriteArtistRelevance.artist
            : FavoriteArtistRelevance.circle;
        if (relevance == FavoriteArtistRelevance.irrelevant) continue;
        // 画师桶里的 `group:Y` 不算画师证据，社团桶反之亦然。
        if (relevance != wanted) continue;
        value = text.substring(prefix.start + prefix.group(0)!.length).trim();
      }
      if (value.isEmpty) continue;
      final inner = _circleArtistRegex.firstMatch(_stripBrackets(value));
      if (inner == null) {
        add(_name(value));
        continue;
      }
      final circle = _name(inner.group(1));
      final artist = _name(inner.group(2));
      if (artistPosition) {
        add(artist);
        if (circle != null && artist != null) {
          add(_name('${circle.display} (${artist.display})'));
        }
      } else {
        add(circle ?? artist);
      }
    }
    return names;
  }

  static String _stripBrackets(String value) {
    var text = value.trim();
    bool stripped;
    do {
      stripped = false;
      if ((text.startsWith('[') && text.endsWith(']')) ||
          (text.startsWith('【') && text.endsWith('】'))) {
        text = text.substring(1, text.length - 1).trim();
        stripped = true;
      }
    } while (stripped && text.isNotEmpty);
    return text;
  }

  static final _noiseWordRegex = RegExp(
    '(?:^\$|[^a-z0-9])(?:${_noiseWords.map(RegExp.escape).join('|')})(?:\$|[^a-z0-9])',
  );

  static bool _looksLikeNoise(String content) {
    final normalized = normalizeArtist(content);
    if (normalized.isEmpty) return true;
    if (_noiseLanguageCodes.contains(normalized)) return true;
    if (_structuralNoise.hasMatch(normalized)) return true;
    for (final word in _noiseCjk) {
      if (normalized.contains(word)) return true;
    }
    return _noiseWordRegex.hasMatch(' $normalized ');
  }

  /// 兜底搜索区：整串转小写，噪声括号与画师块整段换成空格。
  static String _noiseMaskedTitle(
    String title, {
    int maskFrom = -1,
    int maskTo = -1,
  }) {
    final lower = title.toLowerCase();
    final chars = lower.split('');
    for (final match in _anyGroupRegex.allMatches(title)) {
      final content = lower.substring(match.start + 1, match.end - 1);
      if (_looksLikeNoise(content)) {
        for (var i = match.start; i < match.end; i++) {
          chars[i] = ' ';
        }
      }
    }
    final from = maskFrom < 0 ? 0 : maskFrom;
    final to = maskTo > chars.length ? chars.length : maskTo;
    for (var i = from; i < to; i++) {
      chars[i] = ' ';
    }
    return chars.join();
  }

  /// [token] 在 [haystack] 里作为独立词出现的位置；没有则 null。
  ///
  /// 「独立词」= 前后不是字母、数字或汉字。汉字之间没有空格，所以
  /// 「水龙敬乐园特别篇」里的「水龙敬」不算独立词，正是这一条挡掉乱匹。
  static int? _standaloneTokenAt(String haystack, String token) {
    var index = haystack.indexOf(token);
    while (index != -1) {
      if (!_isWordChar(haystack, index - 1) &&
          !_isWordChar(haystack, index + token.length)) {
        return index;
      }
      index = haystack.indexOf(token, index + 1);
    }
    return null;
  }

  static bool _isWordChar(String text, int index) {
    if (index < 0 || index >= text.length) return false;
    final code = text.codeUnitAt(index);
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    if (code >= 0x41 && code <= 0x5a) return true; // A-Z
    if (code >= 0x61 && code <= 0x7a) return true; // a-z
    if (code >= 0x2e80 && code <= 0x9fff) return true; // 部首/假名/注音/汉字
    if (code >= 0xac00 && code <= 0xd7af) return true; // 谚文
    if (code >= 0xf900 && code <= 0xfaff) return true; // 兼容汉字
    if (code >= 0xff00 && code <= 0xff60) return true; // 全角
    if (code >= 0xffe0 && code <= 0xffe6) return true;
    return false;
  }
}
