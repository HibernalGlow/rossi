import 'package:flutter/foundation.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/text/tag_text.dart';
import 'package:zephyr/util/text/tag_translation.dart';

/// 一次收藏 tag 命中的结果。
@immutable
class FavoriteTagMatchResult {
  /// 命中的那条收藏（用它的 [FavoriteTag.name] 显示，而不是命中的原始串）。
  final FavoriteTag? tag;

  /// 实际对上号的那个 tag 文本，用于提示「命中了你的别名 xxx」。
  final String? matchedText;

  /// 命中的是别名而不是收藏项本名。
  final bool viaAlias;

  const FavoriteTagMatchResult({
    this.tag,
    this.matchedText,
    this.viaAlias = false,
  });

  bool get isMatched => tag != null;

  static const FavoriteTagMatchResult notMatched = FavoriteTagMatchResult();

  /// 徽标上该写什么：收藏项没有名字时（用户只填了别名）退回命中的文本。
  String? get label {
    final name = tag?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    return matchedText;
  }
}

/// 收藏 tag 的匹配工具。
///
/// 与喜欢画师的匹配（`FavoriteArtistMatcher`）同一档位，但**只有精确比较**：
/// 画师那条「标题包含画师名」的兜底放在 tag 上会大面积误报（`lolita` 命中
/// `school_lolita`、`complete` 命中任何带这个词的标题）。跨站点的写法差异由
/// 两路承担：内置的 `TagTranslation`（EhTagTranslation 译名↔原词）与用户
/// 显式登记的别名（`FavoriteTag.aliases`）。
class FavoriteTagMatcher {
  FavoriteTagMatcher._();

  /// 把收藏列表摊平成「归一化写法 → 条目」的查找表。
  ///
  /// 同一归一化键被多条收藏抢到时，先加入者赢：用户的列表顺序就是优先级。
  ///
  /// 除了本名与登记别名，还会挂上 `TagTranslation` 的**译名/原词**展开
  /// （收藏 `footjob` ⇒ 「足交」也进表，EH 详情页那种「插件已把 tag 翻成中文」
  /// 的胶囊才能命中）。展开排在第二遍：某条收藏的本名/别名永远优先于
  /// 另一条收藏的译名展开，否则列表靠前的翻译会把后面条目的原词抢走。
  static Map<String, FavoriteTag> buildAliasIndex(
    Iterable<FavoriteTag> favorites,
  ) {
    final index = <String, FavoriteTag>{};
    final exactKeys = <(String, FavoriteTag)>[];
    for (final favorite in favorites) {
      final nameKey = TagText.normalize(favorite.name);
      if (nameKey.isNotEmpty) {
        index.putIfAbsent(nameKey, () => favorite);
        exactKeys.add((nameKey, favorite));
      }
      for (final alias in favorite.aliases) {
        final aliasKey = TagText.normalize(alias);
        if (aliasKey.isNotEmpty) {
          index.putIfAbsent(aliasKey, () => favorite);
          exactKeys.add((aliasKey, favorite));
        }
      }
    }
    for (final (key, favorite) in exactKeys) {
      for (final expanded in TagTranslation.expansionsNormalized(key)) {
        index.putIfAbsent(expanded, () => favorite);
      }
    }
    return index;
  }

  /// [tags]：插件给的标签/元数据原始串。[title]：漫画标题，可空。
  ///
  /// 顺序是先标签后标题 —— 标签是图源自己标的，比从标题里猜括号更可信。
  static FavoriteTagMatchResult match({
    required Iterable<String> tags,
    required Iterable<FavoriteTag> favoriteTags,
    String? title,
  }) {
    if (favoriteTags.isEmpty) return FavoriteTagMatchResult.notMatched;
    final index = buildAliasIndex(favoriteTags);
    if (index.isEmpty) return FavoriteTagMatchResult.notMatched;

    for (final raw in tags) {
      final result = _lookup(index, raw);
      if (result != null) return result;
    }

    if (title != null && title.trim().isNotEmpty) {
      for (final candidate in TagText.bracketCandidates(title)) {
        final tag = index[candidate];
        if (tag != null) {
          return _result(tag, candidate, candidate);
        }
      }
    }

    return FavoriteTagMatchResult.notMatched;
  }

  /// 单个文本（详情页的一颗胶囊、一条元数据值）是否就是某条收藏 tag。
  ///
  /// 详情页一整组胶囊要逐颗判断，每颗重建一次索引就是把收藏列表扫 N 遍，
  /// 所以索引交给调用方建、这里只查表（传空表 ⇒ 全部不命中）。
  static bool hitInIndex(Map<String, FavoriteTag> index, String text) {
    if (index.isEmpty) return false;
    return _lookup(index, text) != null;
  }

  static FavoriteTagMatchResult? _lookup(
    Map<String, FavoriteTag> index,
    String raw,
  ) {
    final normalized = TagText.normalize(raw);
    if (normalized.isEmpty) return null;

    var hitKey = normalized;
    var tag = index[normalized];
    if (tag == null) {
      // `artist:xxx` 这类命名空间前缀：同一个 tag 在有的图源里带前缀、有的不带。
      hitKey = TagText.stripNamespace(normalized) ?? '';
      if (hitKey.isEmpty) return null;
      tag = index[hitKey];
      if (tag == null) return null;
    }
    return _result(tag, raw, hitKey);
  }

  /// [matchedKey] 是对上号的那个归一化写法，[matchedText] 是它的原始串（展示用）。
  static FavoriteTagMatchResult _result(
    FavoriteTag tag,
    String matchedText,
    String matchedKey,
  ) {
    // 「不是本名」就是走了别的写法：登记别名与内置译名同一语义，
    // 徽标上写的仍是本名。
    final viaAlias = TagText.normalize(tag.name) != matchedKey;
    return FavoriteTagMatchResult(
      tag: tag,
      matchedText: matchedText.trim(),
      viaAlias: viaAlias,
    );
  }
}
