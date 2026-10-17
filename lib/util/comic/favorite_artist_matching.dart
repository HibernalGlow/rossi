part of 'package:zephyr/util/comic/favorite_artist_matcher.dart';

// 只保存当前喜欢名单的解析结果与有限的文字匹配结果，不持有图片或 Widget。
final _favoriteArtistMatching = _FavoriteArtistMatching();

class _FavoriteArtistMatching {
  List<String> _favorites = const [];
  List<_FavoriteEntry> entries = const [];
  final _tokens =
      <FavoriteArtistCircleMode, List<({String key, String raw})>>{};
  final _results = <String, FavoriteArtistMatchResult>{};
  final _artistIndex = <String, ({String raw, int rank})>{};
  final _circleIndex = <String, ({String raw, int rank})>{};

  void prepare(Iterable<String> favoriteArtists) {
    final favorites = favoriteArtists.toList(growable: false);
    // 比较快照内容：支持 Freezed 包装列表和原地增删，不能只按 List 身份失效。
    if (!listEquals(_favorites, favorites)) {
      _favorites = favorites;
      entries =
          [
                for (final raw in favorites)
                  FavoriteArtistMatcher._parseFavorite(raw),
              ]
              .where((e) => e.artistKeys.isNotEmpty || e.circleKeys.isNotEmpty)
              .toList();
      _artistIndex.clear();
      _circleIndex.clear();
      for (var rank = 0; rank < entries.length; rank++) {
        final entry = entries[rank];
        final value = (raw: entry.raw, rank: rank);
        for (final key in entry.artistKeys) {
          _artistIndex.putIfAbsent(key, () => value);
        }
        for (final key in entry.circleKeys) {
          _circleIndex.putIfAbsent(key, () => value);
        }
      }
      _tokens.clear();
      _results.clear();
    }
  }

  bool contains(String key, {required bool circleSide}) =>
      (circleSide ? _circleIndex : _artistIndex).containsKey(key);

  FavoriteArtistMatchResult match({
    required String title,
    required Iterable<String> artistTags,
    required Iterable<String> circleTags,
    required String? creator,
    required Iterable<String> favoriteArtists,
    required FavoriteArtistCircleMode circleMode,
  }) {
    prepare(favoriteArtists);
    if (entries.isEmpty) return FavoriteArtistMatchResult.notMatched;
    final artists = artistTags.toList(growable: false);
    final circles = circleTags.toList(growable: false);
    final key = jsonEncode([title, artists, circles, creator, circleMode.name]);
    final cached = _results.remove(key);
    if (cached != null) {
      _results[key] = cached;
      return cached;
    }
    final result = _match(title, artists, circles, creator, circleMode);
    _results[key] = result;
    if (_results.length > 512) _results.remove(_results.keys.first);
    return result;
  }

  FavoriteArtistMatchResult _match(
    String title,
    List<String> artistTags,
    List<String> circleTags,
    String? creator,
    FavoriteArtistCircleMode circleMode,
  ) {
    final block = FavoriteArtistMatcher._parseAuthorBlock(title);
    final artistTagNames = FavoriteArtistMatcher._namesFromTags(
      artistTags,
      artistPosition: true,
    );
    final circleTagNames = FavoriteArtistMatcher._namesFromTags(
      circleTags,
      artistPosition: false,
    );
    final creatorNames = FavoriteArtistMatcher._nameWithSplits(creator);
    final titleArtists = FavoriteArtistMatcher._nameWithSplits(block?.artist);
    final titleCircles = FavoriteArtistMatcher._nameWithSplits(block?.circle);
    final titleBares = FavoriteArtistMatcher._nameWithSplits(block?.bare);

    FavoriteArtistMatchResult firstHit(
      Iterable<_Name> names,
      FavoriteArtistEvidence evidence, {
      required bool circleSide,
    }) {
      final candidates = names
          .where(
            (name) =>
                name.key.isNotEmpty && !FavoriteArtistMatcher.isNoise(name.key),
          )
          .toList();
      if (candidates.isEmpty) return FavoriteArtistMatchResult.notMatched;
      final index = circleSide ? _circleIndex : _artistIndex;
      ({String raw, int rank})? best;
      _Name? matched;
      for (final name in candidates) {
        final hit = index[name.key];
        if (hit != null && (best == null || hit.rank < best.rank)) {
          best = hit;
          matched = name;
        }
      }
      if (best != null) {
        return FavoriteArtistMatchResult(
          isMatched: true,
          matchedArtist: best.raw,
          matchedName: matched!.display,
          evidence: evidence,
        );
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
    if (creatorNames.isNotEmpty) {
      result = firstHit(
        creatorNames,
        FavoriteArtistEvidence.creator,
        circleSide: false,
      );
      if (result.isMatched) return result;
    }

    // 3. 标题画师块的画师位。
    if (titleArtists.isNotEmpty) {
      result = firstHit(
        titleArtists,
        FavoriteArtistEvidence.titleArtist,
        circleSide: false,
      );
      if (result.isMatched) return result;
    }

    // 4. 标题画师块只有一个名字：社团/画师不分，先按画师认一次。
    if (titleBares.isNotEmpty) {
      result = firstHit(
        titleBares,
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
          creatorNames.isNotEmpty ||
          titleArtists.isNotEmpty;
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
        for (final names in [titleCircles, titleBares]) {
          if (names.isEmpty) continue;
          result = firstHit(
            names,
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
    final haystack = FavoriteArtistMatcher._noiseMaskedTitle(
      title,
      maskFrom: block?.start ?? -1,
      maskTo: block?.end ?? -1,
    );
    final tokenKeys = _tokens.putIfAbsent(circleMode, () {
      final tokenKeys = <({String key, String raw})>[];
      for (final entry in entries) {
        for (final key in entry.artistKeys) {
          // `社团 (画师)` 这种复合键不可能作为独立词出现，跳过。
          if (key.contains('(') ||
              key.contains('（') ||
              FavoriteArtistMatcher.isNoise(key)) {
            continue;
          }
          tokenKeys.add((key: key, raw: entry.raw));
        }
        if (circleMode == FavoriteArtistCircleMode.independent) {
          for (final key in entry.circleKeys) {
            if (key.contains('(') ||
                key.contains('（') ||
                FavoriteArtistMatcher.isNoise(key)) {
              continue;
            }
            tokenKeys.add((key: key, raw: entry.raw));
          }
        }
      }
      tokenKeys.sort((a, b) => b.key.length.compareTo(a.key.length));
      return tokenKeys;
    });
    for (final token in tokenKeys) {
      // 两个字的画师名几乎一定撞上标题里的别的词，宁可不认。
      if (token.key.length < 3) continue;
      final at = FavoriteArtistMatcher._standaloneTokenAt(haystack, token.key);
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
}
