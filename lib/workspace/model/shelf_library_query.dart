/// 书签 / 历史面板的搜索与排序口径。
///
/// 刻意不 import Flutter、不 import ObjectBox：这张列表「留下哪些条目、按什么
/// 排」是可以脱离界面断言的纯函数，和 `shelf_entry_menu_spec.dart` 同一个理由
/// —— 本机的 `flutter test` 要拖起整棵工作台，判据跑不动。
///
/// 繁简转换（`t2s`）走 Rust，纯 Dart 侧碰不到，所以归一化函数由调用方注入：
/// 卡片传 `t2s`，判据传默认的小写化。
///
/// 唯一引进来的应用侧依赖是 [isLocalComicSource]（`util/path_util.dart`，只吃
/// `package:path`）——「这条记录是不是本地的」必须与 `openComicItem` 点开时用的
/// 是同一个判据，否则行上写着「本地」、点下去却进了详情页。
library;

import 'dart:convert';

import 'package:zephyr/util/path_util.dart';

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

/// 本地漫画在行上的来源标记。库里存的 `source` 是 `local` 或整条路径，照插件
/// 那一套大写会显示成「LOCAL」甚至一长串 `/storage/emulated/0/…`。
const String kShelfLocalSourceLabel = '本地';

/// 归档后缀。本地漫画的章节名常常就是它自己的文件名，判「有没有重复书名」时
/// 要先剥掉再比（`cp.zip` 与标题 `cp` 是同一个东西）。
const List<String> _kArchiveExtensions = [
  '.zip',
  '.cbz',
  '.cbr',
  '.rar',
  '.7z',
  '.tar',
];

/// 把「这一本叫什么」压成一个可以相等比较的串：去尾部分隔符、取最后一段路径、
/// 剥掉归档后缀、小写。
String _shelfNameKey(String value) {
  var text = value.trim();
  if (text.isEmpty) return '';
  while (text.endsWith('/') || text.endsWith('\\')) {
    text = text.substring(0, text.length - 1);
  }
  final slash = text.lastIndexOf('/');
  final backslash = text.lastIndexOf('\\');
  final cut = slash > backslash ? slash : backslash;
  if (cut >= 0) text = text.substring(cut + 1);
  final lower = text.toLowerCase();
  for (final ext in _kArchiveExtensions) {
    if (lower.endsWith(ext) && lower.length > ext.length) {
      return lower.substring(0, lower.length - ext.length);
    }
  }
  return lower;
}

/// 要显示在标题下面的章节名；没有可说的信息时返回空串。
///
/// 本地漫画的「章节」就是它自己那个文件或目录（`cp.zip` 这一本的章节名就是
/// `cp.zip`），标题行已经是同一个名字，第二行再写一遍纯属占地方。插件给的
/// 章节名（`全1话 (37P)`）与书名不同，照原样留。
String shelfChapterLabel({
  required String title,
  required String chapterTitle,
}) {
  final chapter = chapterTitle.trim();
  if (chapter.isEmpty) return '';
  final key = _shelfNameKey(chapter);
  if (key.isEmpty || key == _shelfNameKey(title)) return '';
  return chapter;
}

/// 来源标记：本地 ⇒ [kShelfLocalSourceLabel]，插件 ⇒ 插件 id 大写。
String shelfSourceLabel({required String source, required String comicId}) {
  if (isLocalComicSource(source, comicId)) return kShelfLocalSourceLabel;
  return source.trim().toUpperCase();
}

/// 用 ` · ` 拼一行元信息，丢掉空段 —— 章节名判重之后不能留下孤零零的「 · 」。
String joinShelfMeta(Iterable<String> parts) =>
    parts.where((part) => part.trim().isNotEmpty).join(' · ');

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
