/// 一条搜索历史：关键词 + 它是在哪个图源下搜的。
///
/// 为什么不再是 `List<String>`：归属只在**发起搜索的那一刻**存在
/// （`SearchStates.from`），事后从一串关键词里问不出来。要按插件分时间线，
/// 就必须在写下的时候把它记住。
library;

import 'package:flutter/foundation.dart';

/// 一次跨全部插件的聚合搜索。
///
/// 它不隶属某一个插件，所以不能记成任何一个 uuid —— 与 `on_search.dart` 给
/// 标签 `source: ''` 的口径一致。用假哨兵而不是空串，是因为空串已经被留给
/// 「归属未知」的老历史（见 [SearchHistoryEntry.source]）。
const String kAggregateSearchSource = 'aggregate';

@immutable
class SearchHistoryEntry {
  const SearchHistoryEntry({required this.keyword, this.source = ''});

  final String keyword;

  /// 插件 uuid / [kAggregateSearchSource] / 空串。
  ///
  /// 空串 = 本次改造之前存下来的记录，归属已经救不回来了：v1→v2 迁移把老
  /// `关键词&&来源` 格式里的来源主动删掉过
  /// （`lib/object_box/migration/migration_v1_to_v2.dart:369`）。
  /// 界面把这类归进「未分类」，不假装它们是聚合搜索。
  final String source;

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SearchHistoryEntry(
        keyword: json['keyword'] as String? ?? '',
        source: json['source'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'keyword': keyword, 'source': source};

  @override
  bool operator ==(Object other) =>
      other is SearchHistoryEntry &&
      other.keyword == keyword &&
      other.source == source;

  @override
  int get hashCode => Object.hash(keyword, source);

  @override
  String toString() => 'SearchHistoryEntry($keyword @ $source)';
}

/// 兼容读：老版本存的是纯 `List<String>`（只有词、没有归属）。
///
/// 必须有这一层，否则老库里那份历史会让 `fromJson` 直接抛 —— 而它跑在
/// `UserSetting.globalSetting` 的读取路径上，等于开屏就崩。
/// 同一份兼容也覆盖了「云端块来自老版本」的情况。
List<SearchHistoryEntry> searchHistoryFromJson(Object? raw) {
  if (raw is! List) return const [];
  final entries = <SearchHistoryEntry>[];
  for (final item in raw) {
    final entry = item is String
        ? SearchHistoryEntry(keyword: item)
        : item is Map
        ? SearchHistoryEntry.fromJson(Map<String, dynamic>.from(item))
        : null;
    if (entry != null && entry.keyword.isNotEmpty) entries.add(entry);
  }
  return entries;
}

/// 合并成一条时间线时用：同一个词在多个插件下各有一条记录，界面上只留
/// **最近**的那一条（入参已按时间排好，所以首次出现即最近）。
///
/// 返回的是原记录而不是光秃秃的词 —— 长按删除要按 (词, 来源) 这一对来删，
/// 只带词会把另一个插件下的同名记录一起删掉。
List<SearchHistoryEntry> distinctSearchHistoryByKeyword(
  List<SearchHistoryEntry> ordered,
) {
  final seen = <String>{};
  final result = <SearchHistoryEntry>[];
  for (final entry in ordered) {
    if (seen.add(entry.keyword)) result.add(entry);
  }
  return result;
}

/// 一个图源的历史分组。[source] 是要拿去查显示名的原始值，不是显示名。
@immutable
class SearchHistoryGroup {
  const SearchHistoryGroup({required this.source, required this.keywords});

  final String source;
  final List<String> keywords;
}

/// 按来源分桶，桶内保持入参顺序 ⇒ 每个插件各自一条时间线。
///
/// 桶的先后 = 该插件**最近一次**搜索的先后（Dart 的 Map 保序，首次遇到某个
/// 来源就开桶）。所以入参必须先按 [_isNewestFirst] 排好，这里不再排序。
List<SearchHistoryGroup> groupSearchHistoryBySource(
  List<SearchHistoryEntry> ordered,
) {
  final buckets = <String, List<String>>{};
  for (final entry in ordered) {
    (buckets[entry.source] ??= <String>[]).add(entry.keyword);
  }
  return [
    for (final bucket in buckets.entries)
      SearchHistoryGroup(source: bucket.key, keywords: bucket.value),
  ];
}
