/// 书签 / 历史面板的搜索与排序口径。
///
/// 刻意不 import Flutter、不 import ObjectBox：这张列表「留下哪些条目、按什么
/// 排」是可以脱离界面断言的纯函数，和 `shelf_entry_menu_spec.dart` 同一个理由
/// —— 本机的 `flutter test` 要拖起整棵工作台，判据跑不动。
///
/// 繁简转换（`t2s`）走 Rust，纯 Dart 侧碰不到，所以归一化函数由调用方注入：
/// 卡片传 `t2s`，判据传默认的小写化。
library;

import 'dart:convert';

/// 可排序的字段。四个字段都是「条目自己有的东西」，不需要问图源。
enum ShelfSortField { title, author, source, time }

extension ShelfSortFieldX on ShelfSortField {
  String get label {
    switch (this) {
      case ShelfSortField.title:
        return '标题';
      case ShelfSortField.author:
        return '作者';
      case ShelfSortField.source:
        return '来源';
      case ShelfSortField.time:
        return '时间';
    }
  }
}

class ShelfSort {
  const ShelfSort({required this.field, this.ascending = false});

  final ShelfSortField field;
  final bool ascending;

  /// 点同一个字段翻转方向，点别的字段换到新字段（时间类默认新的在前）。
  ShelfSort toggled(ShelfSortField target) {
    if (target != field) return ShelfSort(field: target);
    return ShelfSort(field: field, ascending: !ascending);
  }

  @override
  bool operator ==(Object other) =>
      other is ShelfSort &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);

  @override
  String toString() => 'ShelfSort($field, ${ascending ? "asc" : "desc"})';
}

/// 一条能参与搜索与排序的书架条目。书签与历史各自把实体折成它。
class ShelfSearchable {
  const ShelfSearchable({
    required this.key,
    required this.title,
    required this.time,
    this.author = '',
    this.source = '',
    this.haystack = '',
  });

  final String key;
  final String title;
  final String author;
  final String source;

  /// 排序用的时间。书签是最后更新，历史是最后阅读。
  final DateTime time;

  /// 搜索要扫的全部文本（标题 + 作者 + 简介 + id + 元数据），由调用方拼好。
  final String haystack;
}

/// 「09/20 14:05」。详细信息视图的列与横幅的副标题都用它；
/// 不带年份是刻意的 —— 泳道卡片宽度有限，年份挤掉了标题。
String formatShelfTime(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

/// 库里的 `creator` 有两种历史形态：纯文本作者名，或者 `{"name": ...}` 的
/// JSON 串。两种都要能搜到、能按作者排 —— `bookshelf_bloc.dart` 里那个同名
/// 私有函数做的就是这件事，这里收成一份可用的。
String shelfCreatorName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (!trimmed.startsWith('{')) return trimmed;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return decoded['name']?.toString().trim() ?? '';
  } catch (_) {}
  return trimmed;
}

/// 搜索要扫的那一坨文本。口径照抄书架那边：id、标题、简介、作者、
/// 标题元数据、标签元数据全都在内。
String shelfHaystack({
  required String comicId,
  required String title,
  required String description,
  required String creator,
  String titleMeta = '',
  String metadata = '',
}) {
  return [
    comicId,
    title,
    description,
    shelfCreatorName(creator),
    titleMeta,
    metadata,
  ].join();
}

/// 默认归一化：去空白 + 小写。繁简转换由调用方叠加在之后。
String normalizeShelfText(String text) => text.trim().toLowerCase();

/// 保留原顺序地过滤出命中关键词的条目。关键词为空时原样返回。
List<ShelfSearchable> filterShelf(
  List<ShelfSearchable> items, {
  required String keyword,
  String Function(String)? normalize,
}) {
  final norm = normalize ?? normalizeShelfText;
  final query = norm(keyword);
  if (query.isEmpty) return items;
  return items.where((item) => norm(item.haystack).contains(query)).toList();
}

/// 排序。同一字段值相等时按 key 兜底，保证两次构建的顺序一致
/// （ObjectBox 的流不保证并列项稳定，不兜底会出现刷新一下顺序换一换）。
List<ShelfSearchable> sortShelf(
  List<ShelfSearchable> items,
  ShelfSort sort, {
  String Function(String)? normalize,
}) {
  final norm = normalize ?? normalizeShelfText;
  final sorted = [...items];
  sorted.sort((a, b) {
    final primary = switch (sort.field) {
      ShelfSortField.title => norm(a.title).compareTo(norm(b.title)),
      ShelfSortField.author => norm(a.author).compareTo(norm(b.author)),
      ShelfSortField.source => norm(a.source).compareTo(norm(b.source)),
      ShelfSortField.time => a.time.compareTo(b.time),
    };
    if (primary != 0) return sort.ascending ? primary : -primary;
    return a.key.compareTo(b.key);
  });
  return sorted;
}

/// 搜索 + 排序一条龙。顺序有讲究：先筛后排，省掉对注定要丢的条目做比较。
List<ShelfSearchable> searchAndSortShelf(
  List<ShelfSearchable> items, {
  required String keyword,
  required ShelfSort sort,
  String Function(String)? normalize,
}) {
  return sortShelf(
    filterShelf(items, keyword: keyword, normalize: normalize),
    sort,
    normalize: normalize,
  );
}

/// 把当前选择下应该出现的条目挑出来。
///
/// [memberKeys] 为空集表示「全部」；未分类传根目录的成员集合，注意 null 与
/// 空集含义不同 —— 空集的未分类是真的没有条目。
List<ShelfSearchable> selectShelf(
  List<ShelfSearchable> items, {
  Set<String>? memberKeys,
}) {
  if (memberKeys == null) return items;
  return items.where((item) => memberKeys.contains(item.key)).toList();
}
