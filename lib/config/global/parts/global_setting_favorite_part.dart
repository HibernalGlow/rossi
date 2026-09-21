part of '../global_setting.dart';
// 喜欢画师与收藏


@freezed
abstract class FavoriteArtistSettingState with _$FavoriteArtistSettingState {
  const factory FavoriteArtistSettingState({
    @Default(true) bool highlightEnabled,
    @Default([]) List<String> artists,
    // 社团名算不算命中。默认 fallbackOnly：只有这条本子拿不出画师证据时才认社团，
    // 因为社团名最容易撞上汉化组与活动名。口径见 `FavoriteArtistCircleMode`。
    @Default(FavoriteArtistCircleMode.fallbackOnly)
    FavoriteArtistCircleMode circleMode,
  }) = _FavoriteArtistSettingState;

  factory FavoriteArtistSettingState.fromJson(Map<String, dynamic> json) =>
      _$FavoriteArtistSettingStateFromJson(json);
}


/// 一条收藏的 tag。
///
/// [name] 是给用户看的本名（也是高亮徽标上写的那个词），[aliases] 是同一个 tag
/// 在各个图源里的其它写法。别名必须是显式登记的：匹配只做归一化后的整串相等
/// （见 `TagText.normalize`），刻意不做子串兜底 —— `lolita` 命中 `school_lolita`
/// 那种放宽在画师上尚可、在 tag 上会把列表刷成一片琥珀色。
///
/// 为什么需要别名：同一含义在不同网站拼法不同（`school_lolita` / `School Lolita` /
/// `学校萝莉`），插件给回的原始串对不上就没有高亮。归一化已经吃掉了大小写、
/// 全半角和 `_`／空格这三类差异，剩下的是真正的不同词，只能由用户登记。
@freezed
abstract class FavoriteTag with _$FavoriteTag {
  const factory FavoriteTag({
    @Default('') String name,
    @Default([]) List<String> aliases,
  }) = _FavoriteTag;

  factory FavoriteTag.fromJson(Map<String, dynamic> json) =>
      _$FavoriteTagFromJson(json);
}


@freezed
abstract class FavoriteTagSettingState with _$FavoriteTagSettingState {
  const factory FavoriteTagSettingState({
    @Default(true) bool highlightEnabled,
    @Default([]) List<FavoriteTag> tags,
  }) = _FavoriteTagSettingState;

  factory FavoriteTagSettingState.fromJson(Map<String, dynamic> json) =>
      _$FavoriteTagSettingStateFromJson(json);
}


/// 归一化键 → 条目，用于收藏 tag 的去重与定位。
///
/// 比较一律走 [TagText.normalize]：添加、删除、批量导入与匹配必须同一个口径，
/// 否则「列表里看着是两条、匹配时算成一条」这类裂缝就会出现（喜欢画师那份就留了
/// 这个裂缝，见 `FavoriteArtistMatcher.normalizeArtist` 与 `addFavoriteArtist`）。
int? _indexOfFavoriteTag(List<FavoriteTag> tags, String key) {
  if (key.isEmpty) return null;
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    if (TagText.normalize(tag.name) == key) return i;
    if (tag.aliases.any((a) => TagText.normalize(a) == key)) return i;
  }
  return null;
}


/// 洗一条别名列表：去空白、按归一化键去重、丢掉与本名同形的那条。
List<String> _cleanTagAliases(
  Iterable<String> aliases, {
  required String nameKey,
}) {
  final seen = <String>{};
  final cleaned = <String>[];
  for (final alias in aliases) {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) continue;
    final key = TagText.normalize(trimmed);
    // 归一化后与本名相同的别名是纯噪声（匹配本来就等价），留着只会让列表变长。
    if (key.isEmpty || key == nameKey) continue;
    if (seen.add(key)) cleaned.add(trimmed);
  }
  return cleaned;
}


/// 整表规整：同名（归一化后）条目合并成一条，后来的那条只并进它的别名，空名条目丢弃。
List<FavoriteTag> _dedupeFavoriteTags(Iterable<FavoriteTag> input) {
  final byKey = <String, FavoriteTag>{};
  final order = <String>[];
  for (final tag in input) {
    final name = tag.name.trim();
    final key = TagText.normalize(name);
    if (name.isEmpty || key.isEmpty) continue;
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = FavoriteTag(
        name: name,
        aliases: _cleanTagAliases(tag.aliases, nameKey: key),
      );
      order.add(key);
      continue;
    }
    byKey[key] = existing.copyWith(
      aliases: _cleanTagAliases([
        ...existing.aliases,
        ...tag.aliases,
      ], nameKey: key),
    );
  }
  return [for (final key in order) byKey[key]!];
}
