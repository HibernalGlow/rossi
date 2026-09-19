/// 书签库的导出 / 导入文档。
///
/// 对应 neoview 的导入导出习惯（`TranslationOverlayCard`、
/// `UpscaleConditionsCard`）：**导出一个可读的 JSON，导入时逐条校验，
/// 不认识的条目跳过并说清楚为什么跳过**，而不是整个文件一起失败或者
/// 悄悄丢掉一半。
///
/// 与整库备份（`page/setting/data_backup`）的区别是刻意的：备份是
/// `config.json + objectbox.json` 的 zip，导入会**先清库**；书签导出只是
/// 一份书签，导入只按 `uniqueKey` 合并，绝不动其他数据。
///
/// 纯 Dart：不 import Flutter，不 import ObjectBox，判据见
/// `test/workspace/bookmark_library_portable_check.dart`。
library;

import 'dart:convert';

const String kBookmarkLibraryVersion = 'v1';

/// 一条书签。`cover` / `creator` / `titleMeta` / `metadata` 保持库内原样
/// （它们本来就是 JSON 串），导入时不再解析一遍 —— 解析规则变了也不该让
/// 一份旧导出文件读不进来。
class BookmarkLibraryItem {
  const BookmarkLibraryItem({
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    this.description = '',
    this.cover = '',
    this.creator = '',
    this.titleMeta = '',
    this.metadata = '',
    this.createdAt,
    this.updatedAt,
    this.lists = const [],
  });

  final String uniqueKey;
  final String source;
  final String comicId;
  final String title;
  final String description;
  final String cover;
  final String creator;
  final String titleMeta;
  final String metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 所属书签列表的路径（`/日漫`）。导入时按名字建夹，已经有了就复用。
  final List<String> lists;

  /// 库内的复合唯一键口径：`来源:漫画id`（见 `collect_comic.dart`）。
  static String keyFor({required String source, required String comicId}) =>
      '$source:$comicId';

  Map<String, dynamic> toJson() => {
    'uniqueKey': uniqueKey,
    'source': source,
    'comicId': comicId,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    if (cover.isNotEmpty) 'cover': cover,
    if (creator.isNotEmpty) 'creator': creator,
    if (titleMeta.isNotEmpty) 'titleMeta': titleMeta,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (lists.isNotEmpty) 'lists': lists,
  };
}

/// 一条被跳过的条目及其原因。
class BookmarkRejection {
  const BookmarkRejection({required this.label, required this.reason});

  /// 用来指认是哪一条：uniqueKey，或者它所在位置。
  final String label;
  final String reason;

  @override
  String toString() => '$label: $reason';
}

/// 解析结果。`items` 只含通过校验的条目，坏条目进 `rejected` 而不抛。
class BookmarkLibraryParseResult {
  const BookmarkLibraryParseResult({
    required this.version,
    required this.items,
    this.rejected = const [],
  });

  final String version;
  final List<BookmarkLibraryItem> items;
  final List<BookmarkRejection> rejected;
}

/// 整个文件读不了才抛这个。
class BookmarkLibraryFormatException implements Exception {
  const BookmarkLibraryFormatException(this.message);

  final String message;

  @override
  String toString() => 'BookmarkLibraryFormatException: $message';
}

String encodeBookmarkLibrary(
  List<BookmarkLibraryItem> items, {
  DateTime? exportedAt,
}) {
  final payload = {
    'version': kBookmarkLibraryVersion,
    'exportedAt': (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'count': items.length,
    'items': [for (final item in items) item.toJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

/// 读出书签导出文件。
///
/// 版本策略：**只认主版本号**。字段少一个多一个不算错，读进来能用的就用；
/// 真正的格式换代才需要抬版本号并在这里拒绝。
BookmarkLibraryParseResult parseBookmarkLibrary(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw BookmarkLibraryFormatException('不是合法的 JSON：${e.message}');
  }
  if (decoded is! Map) {
    throw BookmarkLibraryFormatException('顶层必须是一个对象');
  }
  final version = decoded['version']?.toString();
  if (version == null || version.isEmpty) {
    throw BookmarkLibraryFormatException('缺少 version 字段');
  }
  if (version.split('.').first != kBookmarkLibraryVersion) {
    throw BookmarkLibraryFormatException('不支持的格式版本 $version');
  }
  final list = decoded['items'];
  if (list is! List) {
    throw BookmarkLibraryFormatException('缺少 items 数组');
  }

  final items = <BookmarkLibraryItem>[];
  final rejected = <BookmarkRejection>[];
  for (var index = 0; index < list.length; index++) {
    final entry = list[index];
    if (entry is! Map) {
      rejected.add(BookmarkRejection(label: '第 ${index + 1} 条', reason: '不是对象'));
      continue;
    }
    final parsed = _itemAt(entry, index);
    switch (parsed) {
      case BookmarkLibraryItem():
        items.add(parsed);
      case BookmarkRejection():
        rejected.add(parsed);
    }
  }
  return BookmarkLibraryParseResult(
    version: version,
    items: items,
    rejected: rejected,
  );
}

/// 单条校验。返回 item 或 rejection，二者之一。
Object _itemAt(Map<dynamic, dynamic> json, int index) {
  final source = json['source']?.toString().trim() ?? '';
  final comicId = json['comicId']?.toString().trim() ?? '';
  final label = '第 ${index + 1} 条';
  if (source.isEmpty || comicId.isEmpty) {
    return BookmarkRejection(label: label, reason: '缺少 source 或 comicId');
  }
  final expected = BookmarkLibraryItem.keyFor(source: source, comicId: comicId);
  final declared = json['uniqueKey']?.toString().trim() ?? '';
  // 键与来源:id 对不上必须拒收：这样的记录写进库后就再也查不到它，
  // 取消收藏、去重、同步都会绕着它走。
  if (declared.isNotEmpty && declared != expected) {
    return BookmarkRejection(
      label: '$label（$declared）',
      reason: 'uniqueKey 与 source:comicId 不一致，应为 $expected',
    );
  }
  final title = json['title']?.toString().trim() ?? '';
  if (title.isEmpty) {
    return BookmarkRejection(label: '$label（$expected）', reason: '缺少标题');
  }
  return BookmarkLibraryItem(
    uniqueKey: expected,
    source: source,
    comicId: comicId,
    title: title,
    description: json['description']?.toString() ?? '',
    cover: _stringifyField(json['cover']),
    creator: _stringifyField(json['creator']),
    titleMeta: _stringifyField(json['titleMeta']),
    metadata: _stringifyField(json['metadata']),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    lists: json['lists'] is List
        ? [
            for (final entry in (json['lists'] as List))
              if (entry.toString().trim().isNotEmpty) entry.toString().trim(),
          ]
        : const [],
  );
}

/// 库里的 cover/creator 等本来就是 JSON 串；导出文件里也可能被写成对象
/// （人手改过、或者别的工具生成的）。两种都收，统一落回 JSON 串。
String _stringifyField(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return jsonEncode(value);
}

DateTime? _date(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// 一条书签相对本地库该怎么处理。
enum BookmarkMergeAction {
  /// 本地没有 ⇒ 新建。
  add,

  /// 本地有但已经被软删（用户取消过收藏）⇒ 复活并刷新字段。
  revive,

  /// 本地已经在书签里 ⇒ 不动。
  duplicate,
}

class BookmarkMergeDecision {
  const BookmarkMergeDecision({required this.item, required this.action});

  final BookmarkLibraryItem item;
  final BookmarkMergeAction action;
}

class BookmarkMergePlan {
  const BookmarkMergePlan({
    required this.decisions,
    this.rejected = const [],
  });

  final List<BookmarkMergeDecision> decisions;

  /// 解析阶段就被拒掉的条目（缺字段、键不一致）。
  final List<BookmarkRejection> rejected;

  List<BookmarkLibraryItem> get writes => [
    for (final decision in decisions)
      if (decision.action != BookmarkMergeAction.duplicate) decision.item,
  ];

  int get addCount =>
      decisions.where((d) => d.action == BookmarkMergeAction.add).length;

  int get reviveCount =>
      decisions.where((d) => d.action == BookmarkMergeAction.revive).length;

  int get duplicateCount =>
      decisions.where((d) => d.action == BookmarkMergeAction.duplicate).length;

  /// 给用户看的一句话结论。
  String get summary {
    final parts = ['新增 $addCount 条', '复活 $reviveCount 条', '已存在 $duplicateCount 条'];
    if (rejected.isNotEmpty) parts.add('跳过 ${rejected.length} 条');
    return parts.join(' · ');
  }
}

/// 依据本地库现状定出合并计划。
///
/// [localState] 的键是 uniqueKey，值表示这条本地记录**是否已被软删**；
/// 不在字典里 = 本地根本没有。
///
/// 同一个文件里重复出现的键，只有第一条会被写入，后面的按重复处理 ——
/// 否则第二条会覆盖第一条刚写进去的字段，且结果取决于条目顺序。
BookmarkMergePlan planBookmarkImport({
  required List<BookmarkLibraryItem> items,
  required Map<String, bool> localState,
  List<BookmarkRejection> rejected = const [],
}) {
  final seen = <String>{};
  final decisions = <BookmarkMergeDecision>[];
  for (final item in items) {
    if (!seen.add(item.uniqueKey)) {
      decisions.add(
        BookmarkMergeDecision(item: item, action: BookmarkMergeAction.duplicate),
      );
      continue;
    }
    final deleted = localState[item.uniqueKey];
    final action = deleted == null
        ? BookmarkMergeAction.add
        : deleted
        ? BookmarkMergeAction.revive
        : BookmarkMergeAction.duplicate;
    decisions.add(BookmarkMergeDecision(item: item, action: action));
  }
  return BookmarkMergePlan(decisions: decisions, rejected: rejected);
}
