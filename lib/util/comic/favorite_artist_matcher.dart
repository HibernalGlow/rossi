import 'package:flutter/foundation.dart';

@immutable
class FavoriteArtistMatchResult {
  final bool isMatched;
  final String? matchedArtist;

  const FavoriteArtistMatchResult({
    required this.isMatched,
    this.matchedArtist,
  });

  static const notMatched = FavoriteArtistMatchResult(isMatched: false);
}

/// 喜欢画师提取与匹配工具类（参考 wn09-direct.js）
class FavoriteArtistMatcher {
  FavoriteArtistMatcher._();

  /// 归一化画师名称（参考 wn09-direct.js: normalizeArtist）
  /// 1. 去除首尾空白
  /// 2. 剥离首尾的多余括号: [], (), 【】, （）
  /// 3. 转换为小写
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

  /// 从标题中提取画师/社团候选信息（参考 wn09-direct.js: extractArtist）
  /// 支持格式：
  /// - `[circle (artist)]` -> circle, artist, [circle (artist)]
  /// - `[artist]` -> artist, [artist]
  /// - `(circle (artist))` / `【社团 (画师)】` 等
  static List<String> extractArtistCandidates(String title) {
    if (title.trim().isEmpty) return const [];
    final candidates = <String>{};

    final bracketRegex = RegExp(
      r'\[([^\[\]]+)\]|\(([^()]+)\)|【([^【】]+)】|（([^（）]+)）',
    );
    final matches = bracketRegex.allMatches(title);

    final groupArtistRegex = RegExp(r'^(.+?)\s*[\(（]([^()（）]+)[\)）]$');

    for (final m in matches) {
      final content = (m.group(1) ??
              m.group(2) ??
              m.group(3) ??
              m.group(4))
          ?.trim();
      if (content == null || content.isEmpty) continue;

      final gaMatch = groupArtistRegex.firstMatch(content);
      if (gaMatch != null) {
        final group = gaMatch.group(1)?.trim() ?? '';
        final artist = gaMatch.group(2)?.trim() ?? '';
        if (artist.isNotEmpty) {
          candidates.add(artist);
        }
        if (group.isNotEmpty) {
          candidates.add(group);
        }
        if (group.isNotEmpty && artist.isNotEmpty) {
          candidates.add('[$group ($artist)]');
          candidates.add('$group ($artist)');
        }
      } else {
        candidates.add(content);
        candidates.add('[$content]');
      }
    }

    return candidates.toList();
  }

  /// 判断漫画是否命中喜欢画师
  /// [title]: 漫画标题
  /// [tags]: 标签/分类/元数据列表（例如作者、画师、标签、副标题）
  /// [favoriteArtists]: 用户配置的喜欢画师列表
  static FavoriteArtistMatchResult match({
    required String title,
    Iterable<String>? tags,
    required Iterable<String> favoriteArtists,
  }) {
    if (favoriteArtists.isEmpty) return FavoriteArtistMatchResult.notMatched;

    final preferredMap = <String, String>{};
    for (final artist in favoriteArtists) {
      final norm = normalizeArtist(artist);
      if (norm.isNotEmpty && !preferredMap.containsKey(norm)) {
        preferredMap[norm] = artist.trim();
      }
    }

    if (preferredMap.isEmpty) return FavoriteArtistMatchResult.notMatched;

    // 1. 从标题提取出的括号候选词进行严格匹配 (wn09-direct 规范)
    final titleCandidates = extractArtistCandidates(title);
    for (final candidate in titleCandidates) {
      final norm = normalizeArtist(candidate);
      if (preferredMap.containsKey(norm)) {
        return FavoriteArtistMatchResult(
          isMatched: true,
          matchedArtist: preferredMap[norm],
        );
      }
    }

    // 2. 从标签与元数据中匹配
    if (tags != null) {
      final tagPrefixRegex = RegExp(
        r'^(artist|author|tag|作者|画师|社团|原作)[:：]\s*',
        caseSensitive: false,
      );
      for (final tag in tags) {
        final cleanTag = tag.trim().replaceFirst(tagPrefixRegex, '');
        final normTag = normalizeArtist(cleanTag);
        if (normTag.isNotEmpty && preferredMap.containsKey(normTag)) {
          return FavoriteArtistMatchResult(
            isMatched: true,
            matchedArtist: preferredMap[normTag],
          );
        }
        final tagCandidates = extractArtistCandidates(tag);
        for (final tc in tagCandidates) {
          final normTc = normalizeArtist(tc);
          if (preferredMap.containsKey(normTc)) {
            return FavoriteArtistMatchResult(
              isMatched: true,
              matchedArtist: preferredMap[normTc],
            );
          }
        }
      }
    }

    // 3. 标题整体包含匹配（针对标题未严格用中括号包裹但包含画师名字的情况）
    final lowerTitle = title.toLowerCase();
    for (final entry in preferredMap.entries) {
      final normArtist = entry.key;
      if (normArtist.length >= 2 && lowerTitle.contains(normArtist)) {
        return FavoriteArtistMatchResult(
          isMatched: true,
          matchedArtist: entry.value,
        );
      }
    }

    return FavoriteArtistMatchResult.notMatched;
  }
}
