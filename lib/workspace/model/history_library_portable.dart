/// 阅读历史库的导出 / 导入文档。
///
/// 形状与书签那份（`bookmark_library_portable.dart`）刻意保持一致：
/// **导出一个可读的 JSON，导入时逐条校验，不认识的条目跳过并说清楚为什么
/// 跳过**，而不是整个文件一起失败或者悄悄丢掉一半。
///
/// 与整库备份（`page/setting/data_backup`）的区别同样是刻意的：备份是
/// `config.json + objectbox.json` 的 zip，导入会**先清库**；历史导出只是
/// 一份阅读进度，导入只按 `uniqueKey` 合并，绝不删除、绝不清库。
///
/// 历史与书签唯一的实质差别：**历史条目带着阅读进度**。书签的「已存在就不动」
/// 搬不过来 —— 本地那条可能已经翻到第 80 页，导出文件里还是第 3 页；反过来
/// 无脑覆盖又会把读者从第 80 页拽回第 3 页。合并规则见 [HistoryMergeAction]
/// 与 [planHistoryImport] 里的说明。
///
/// 纯 Dart：不 import Flutter，不 import ObjectBox，判据见
/// `test/workspace/history_library_portable_check.dart`。
library;

import 'dart:convert';

const String kHistoryLibraryVersion = 'v1';

/// 库内实体是 `UnifiedComicHistory`（`object_box/model.dart:509`）。
///
/// 这里带上它的全部业务字段。**没带**的三样是有意为之：
///   * `id` —— ObjectBox 的本地自增主键，换库换设备就该不一样；
///   * `deleted` —— 软删标记是「本地现状」，不是「这条历史的内容」，
///     导出的时候已经被 `collect()` 过滤掉了，导入时由 [HistoryLocalState] 提供；
///   * `schemaVersion` —— 由写入侧固定（见 `reader_history_service.dart`），
///     不该由一份导出文件来指定。
///
/// 也没有书签那份的 `lists`：历史**没有文件夹体系**，面板直接查历史表
/// （见 `folder_shelf_bloc.dart` 的 `_loadHistoryShelf`），无归属可导。
///
/// `cover` / `creator` / `titleMeta` / `metadata` 保持库内原样（它们本来就是
/// JSON 串），导入时不再解析一遍 —— 解析规则变了也不该让一份旧导出文件读不进来。
class HistoryLibraryItem {
  const HistoryLibraryItem({
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    this.description = '',
    this.cover = '',
    this.creator = '',
    this.titleMeta = '',
    this.metadata = '',
    this.chapterId = '',
    this.chapterTitle = '',
    this.chapterOrder = 0,
    this.pageIndex = 0,
    this.createdAt,
    this.lastReadAt,
    this.updatedAt,
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

  // ── 进度：历史区别于书签的那半条命 ──────────────────────────────────────

  /// 读到哪一话（`UnifiedComicHistory.chapterId`）。
  final String chapterId;
  final String chapterTitle;

  /// 该话在章节列表里的序号，阅读器用它定位「上一话/下一话」。
  final int chapterOrder;

  /// 该话内的页码（0 基）。
  final int pageIndex;

  final DateTime? createdAt;

  /// 最后一次阅读的时间 —— **合并时的裁决依据**，见 [planHistoryImport]。
  final DateTime? lastReadAt;
  final DateTime? updatedAt;

  /// 库内的复合唯一键口径：`来源:漫画id`。
  ///
  /// 与书签同式，照抄写入侧 `reader_history_service.dart:292`
  /// （`final key = '$source:$comicId';`）；`uniqueKey` 在实体上是
  /// `@Unique()`（`model.dart:513`），所以同一个键只能有一条记录。
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
    if (chapterId.isNotEmpty) 'chapterId': chapterId,
    if (chapterTitle.isNotEmpty) 'chapterTitle': chapterTitle,
    if (chapterOrder != 0) 'chapterOrder': chapterOrder,
    if (pageIndex != 0) 'pageIndex': pageIndex,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}

/// 一条被跳过的条目及其原因。
class HistoryRejection {
  const HistoryRejection({required this.label, required this.reason});

  /// 用来指认是哪一条：uniqueKey，或者它所在位置。
  final String label;
  final String reason;

  @override
  String toString() => '$label: $reason';
}

/// 本地库里某个键的现状 —— [planHistoryImport] 的比对材料。
///
/// 只带**决策要用的**字段：软删标记 + 上次的阅读时间。页码本身不参与裁决
/// （见 [planHistoryImport] 的说明），带上只会多一个「两处不一致该信谁」。
class HistoryLocalState {
  const HistoryLocalState({required this.deleted, this.lastReadAt});

  /// 本地这条是不是被软删过（用户在历史上点过「移除」）。
  final bool deleted;

  /// 本地记的最后阅读时间；本地记录缺时间时传 `null`（视为最旧，让 incoming 赢）。
  final DateTime? lastReadAt;
}

/// 解析结果。`items` 只含通过校验的条目，坏条目进 `rejected` 而不抛。
class HistoryLibraryParseResult {
  const HistoryLibraryParseResult({
    required this.version,
    required this.items,
    this.rejected = const [],
  });

  final String version;
  final List<HistoryLibraryItem> items;
  final List<HistoryRejection> rejected;
}

/// 整个文件读不了才抛这个。
class HistoryLibraryFormatException implements Exception {
  const HistoryLibraryFormatException(this.message);

  final String message;

  @override
  String toString() => 'HistoryLibraryFormatException: $message';
}

String encodeHistoryLibrary(
  List<HistoryLibraryItem> items, {
  DateTime? exportedAt,
}) {
  final payload = {
    'version': kHistoryLibraryVersion,
    'exportedAt': (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'count': items.length,
    'items': [for (final item in items) item.toJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

/// 读出历史导出文件。
///
/// 版本策略：与书签一致，**只认主版本号**。字段少一个多一个不算错，读进来
/// 能用的就用；真正的格式换代才需要抬版本号并在这里拒绝。
HistoryLibraryParseResult parseHistoryLibrary(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw HistoryLibraryFormatException('不是合法的 JSON：${e.message}');
  }
  if (decoded is! Map) {
    throw HistoryLibraryFormatException('顶层必须是一个对象');
  }
  final version = decoded['version']?.toString();
  if (version == null || version.isEmpty) {
    throw HistoryLibraryFormatException('缺少 version 字段');
  }
  if (version.split('.').first != kHistoryLibraryVersion) {
    throw HistoryLibraryFormatException('不支持的格式版本 $version');
  }
  final list = decoded['items'];
  if (list is! List) {
    throw HistoryLibraryFormatException('缺少 items 数组');
  }

  final items = <HistoryLibraryItem>[];
  final rejected = <HistoryRejection>[];
  for (var index = 0; index < list.length; index++) {
    final entry = list[index];
    if (entry is! Map) {
      rejected.add(HistoryRejection(label: '第 ${index + 1} 条', reason: '不是对象'));
      continue;
    }
    final parsed = _itemAt(entry, index);
    switch (parsed) {
      case HistoryLibraryItem():
        items.add(parsed);
      case HistoryRejection():
        rejected.add(parsed);
    }
  }
  return HistoryLibraryParseResult(
    version: version,
    items: items,
    rejected: rejected,
  );
}

/// 单条校验。返回 item 或 rejection，二者之一。
///
/// 只按**结构性**理由拒收（键对不上、认不出是哪本）。进度字段一律宽容解析：
/// 一条时间戳写坏的历史仍然知道「读的是哪本、大概读到哪」，把它整条丢掉等于
/// 丢用户的阅读位置，比带着一页之差的进度严重得多。
Object _itemAt(Map<dynamic, dynamic> json, int index) {
  final source = json['source']?.toString().trim() ?? '';
  final comicId = json['comicId']?.toString().trim() ?? '';
  final label = '第 ${index + 1} 条';
  if (source.isEmpty || comicId.isEmpty) {
    return HistoryRejection(label: label, reason: '缺少 source 或 comicId');
  }
  final expected = HistoryLibraryItem.keyFor(source: source, comicId: comicId);
  final declared = json['uniqueKey']?.toString().trim() ?? '';
  // 键与来源:id 对不上必须拒收：这样的记录写进库后就再也查不到它，
  // 阅读器找不到它的进度，去重与同步也会绕着它走。
  if (declared.isNotEmpty && declared != expected) {
    return HistoryRejection(
      label: '$label（$declared）',
      reason: 'uniqueKey 与 source:comicId 不一致，应为 $expected',
    );
  }
  return HistoryLibraryItem(
    uniqueKey: expected,
    source: source,
    comicId: comicId,
    // 标题不像书签那样是硬要求：书签列表靠标题认人，历史卡片缺标题只是
    // 显示得难看，进度还是真的。
    title: json['title']?.toString().trim() ?? '',
    description: json['description']?.toString() ?? '',
    cover: _stringifyField(json['cover']),
    creator: _stringifyField(json['creator']),
    titleMeta: _stringifyField(json['titleMeta']),
    metadata: _stringifyField(json['metadata']),
    chapterId: json['chapterId']?.toString() ?? '',
    chapterTitle: json['chapterTitle']?.toString() ?? '',
    chapterOrder: _int(json['chapterOrder']),
    pageIndex: _int(json['pageIndex']),
    createdAt: _date(json['createdAt']),
    lastReadAt: _date(json['lastReadAt']),
    updatedAt: _date(json['updatedAt']),
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

/// 页码/章节序号：写成字符串（`"pageIndex": "12"`）也算，读不出来当 0。
/// 数值字段没有「拒收」这条退路 —— 拒一整条等于连进度一起扔。
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 一条历史相对本地库该怎么处理。
///
/// **这里就是历史与书签分岔的地方。** 书签的三条是「本地有就别动」，因为
/// 一条书签的内容只有元数据，本地那份大概率更新。历史不同：本地那条带着
/// **读到的位置**，而它可能比文件新，也可能比文件旧 ——
///
///   * 一律「已存在就不动」：从别的设备导回来的**新进度**永远进不来，
///     导完还是停在上次那页；
///   * 一律覆盖：把读者从第 80 页**拽回**第 3 页（导出文件是三个月前存的），
///     而且这种回退不会报错，只会让人以为 App 吞了自己的进度。
///
/// 所以按数据裁决：**最后读的那条赢**（newest `lastReadAt` wins）。incoming
/// 只在**严格晚于**本地时才覆盖；同一时刻算本地赢 —— 本地那条是用户此刻
/// 真正看到的页码，没有理由为一次时间戳完全相同的导入动他的屏幕。
enum HistoryMergeAction {
  /// 本地没有 ⇒ 新建。
  add,

  /// 本地有但已经被软删（用户从历史上移除过）⇒ 复活并写入。
  ///
  /// 软删的那条**不在屏上**，「别把读者往后拽」这条顾虑不成立：用户重新导入
  /// 就是想把它拿回来，哪怕文件里的进度更旧，也比一条被藏起来的记录有用。
  /// 因此 `revive` 不看 `lastReadAt`。
  revive,

  /// 本地在册，且文件的 `lastReadAt` 严格更新 ⇒ 覆盖本地进度。
  overwrite,

  /// 本地在册，且文件的进度不比本地新 ⇒ 保留本地，不写。
  stale,

  /// 同一个文件里重复出现的键 ⇒ 只有第一条算数。
  ///
  /// 与书签同理：否则第二条会覆盖第一条刚写进去的进度，结果取决于条目顺序。
  /// （书签那边把这情况并进 `duplicate`；这里 `duplicate` 名字太笼统，
  /// 单开一个桶，结论里「文件内重复」和「本地更新」要分开报数。）
  duplicate,
}

class HistoryMergeDecision {
  const HistoryMergeDecision({required this.item, required this.action});

  final HistoryLibraryItem item;
  final HistoryMergeAction action;
}

class HistoryMergePlan {
  const HistoryMergePlan({required this.decisions, this.rejected = const []});

  final List<HistoryMergeDecision> decisions;

  /// 解析阶段就被拒掉的条目（缺字段、键不一致）。
  final List<HistoryRejection> rejected;

  /// 真的要落库的那些。
  List<HistoryLibraryItem> get writes => [
    for (final decision in decisions)
      if (decision.action == HistoryMergeAction.add ||
          decision.action == HistoryMergeAction.revive ||
          decision.action == HistoryMergeAction.overwrite)
        decision.item,
  ];

  int _countOf(HistoryMergeAction action) =>
      decisions.where((d) => d.action == action).length;

  int get addCount => _countOf(HistoryMergeAction.add);
  int get reviveCount => _countOf(HistoryMergeAction.revive);
  int get overwriteCount => _countOf(HistoryMergeAction.overwrite);
  int get staleCount => _countOf(HistoryMergeAction.stale);
  int get duplicateCount => _countOf(HistoryMergeAction.duplicate);

  /// 给用户看的一句话结论。每个桶都点名，包括不动的那两个 —— 用户最需要
  /// 知道的是「为什么导入 100 条只变了 3 条」。
  String get summary {
    final parts = [
      '新增 $addCount 条',
      '复活 $reviveCount 条',
      '更新进度 $overwriteCount 条',
      '保留本地 $staleCount 条',
      '文件内重复 $duplicateCount 条',
    ];
    if (rejected.isNotEmpty) parts.add('跳过 ${rejected.length} 条');
    return parts.join(' · ');
  }
}

/// 依据本地库现状定出合并计划。
///
/// [localState] 的键是 uniqueKey，值是这条本地记录的现状（`deleted` +
/// `lastReadAt`）；**不在字典里、或者值为 `null`** 都表示本地根本没有。
///
/// 裁决顺序：先看键在文件内是否重复（`duplicate`），再看本地有没有
/// （`add`）、是不是软删（`revive`），最后才比时间：incoming 的 `lastReadAt`
/// **严格晚于**本地才 `overwrite`，否则 `stale`。
///
/// 比较用 `DateTime.isAfter`，它比的是绝对时刻，所以文件里 ISO-8601 带 `Z`
/// 的 UTC 时间与本地解析出来的时间戳可以直接比，不会因为时区整体错一位。
/// incoming 没有 `lastReadAt`（字段缺失或写坏）时**不算新**，本地在册的一律
/// 保留本地；本地那份没有时间则视为最旧，让 incoming 赢。
HistoryMergePlan planHistoryImport({
  required List<HistoryLibraryItem> items,
  required Map<String, HistoryLocalState?> localState,
  List<HistoryRejection> rejected = const [],
}) {
  final seen = <String>{};
  final decisions = <HistoryMergeDecision>[];
  for (final item in items) {
    if (!seen.add(item.uniqueKey)) {
      decisions.add(
        HistoryMergeDecision(item: item, action: HistoryMergeAction.duplicate),
      );
      continue;
    }
    final local = localState[item.uniqueKey];
    if (local == null) {
      decisions.add(
        HistoryMergeDecision(item: item, action: HistoryMergeAction.add),
      );
      continue;
    }
    if (local.deleted) {
      decisions.add(
        HistoryMergeDecision(item: item, action: HistoryMergeAction.revive),
      );
      continue;
    }
    decisions.add(
      HistoryMergeDecision(
        item: item,
        action: _isNewer(item.lastReadAt, local.lastReadAt)
            ? HistoryMergeAction.overwrite
            : HistoryMergeAction.stale,
      ),
    );
  }
  return HistoryMergePlan(decisions: decisions, rejected: rejected);
}

/// 「incoming 是否严格新于本地」。见 [planHistoryImport] 的时间规则。
bool _isNewer(DateTime? incoming, DateTime? local) {
  if (incoming == null) return false;
  if (local == null) return true;
  return incoming.isAfter(local);
}
