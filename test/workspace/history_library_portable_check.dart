// 阅读历史导出 / 导入文档的**纯 Dart** 判据。
//
//   dart run test/workspace/history_library_portable_check.dart
//
// 这里钉的是「导入会不会悄悄做错的事」，尤其是历史特有的那一半：
//
//   1. **进度必须往返不丢** —— 历史相对书签的全部价值就是 chapterId/页码/
//      lastReadAt，导入完停在第 0 页等于把这次导入的意义抹掉；
//   2. **按 lastReadAt 裁决，而不是「有就不动」也不是「无条件覆盖」**：
//      严格更新才覆盖，同一时刻与更旧都保留本地 —— 把读者从第 80 页拽回
//      第 3 页不会报错，只会让人觉得 App 吞了进度；
//   3. **uniqueKey 与 source:comicId 不一致必须拒收** —— 这种记录写进库后
//      阅读器再也查不到它的进度；
//   4. **坏条目不连累整份文件**，每条都要有自己的理由；
//   5. **软删的要复活而不是新起一行**，`uniqueKey` 上有 Unique 约束；
//   6. **导入不清库、不删除**：桶里只有新增/复活/更新/保留/重复/跳过。
//
// 每条「会跳过/会拒收」的断言都配一条**近在咫尺的正对照**（差 1 毫秒、
// 键写成对的、时间戳写成 ISO 的），否则阈值写错了也没人发现。
//
// 没有 package:test 依赖（跟 `bookmark_library_portable_check.dart` 同一套路：
// 这个外壳里 `dart run` 稳，`flutter test` 要拖起整套 workbench binding）。
// 失败计数并以其非零时 exit(1)。
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:zephyr/workspace/model/history_library_portable.dart';

int _passed = 0;
int _failed = 0;

void check(String label, bool condition, [String? detail]) {
  if (condition) {
    _passed++;
    return;
  }
  _failed++;
  print('FAIL: $label${detail == null ? '' : ' — $detail'}');
}

HistoryLibraryItem _item({
  String source = 'bika',
  String comicId = '1',
  String? uniqueKey,
  String title = '标题',
  String chapterId = '',
  String chapterTitle = '',
  int chapterOrder = 0,
  int pageIndex = 0,
  DateTime? lastReadAt,
}) {
  return HistoryLibraryItem(
    uniqueKey:
        uniqueKey ??
        HistoryLibraryItem.keyFor(source: source, comicId: comicId),
    source: source,
    comicId: comicId,
    title: title,
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    chapterOrder: chapterOrder,
    pageIndex: pageIndex,
    lastReadAt: lastReadAt,
  );
}

String _doc(List<Object> items, {String version = kHistoryLibraryVersion}) {
  return jsonEncode({'version': version, 'items': items});
}

/// 钉一个基准时刻，用它派生「差 1 毫秒」的正反对照。
final DateTime _t0 = DateTime.utc(2026, 9, 1, 12);

void main() {
  _roundTripKeepsProgress();
  _rejectsBadKeys();
  _badItemsDoNotSinkTheFile();
  _datesAndVersionsAreTolerant();
  _mergeDecisions();
  _newerWinsThreshold();
  _reviveIgnoresStaleness();
  _duplicateKeysInFile();
  _summaryMentionsEveryBucketAndNoDeletion();

  print(
    'history_library_portable_check: $_passed checks passed, '
    '$_failed failed',
  );
  if (_failed > 0) exitCode = 1;
}

void _roundTripKeepsProgress() {
  final items = [
    HistoryLibraryItem(
      uniqueKey: 'jm:abc',
      source: 'jm',
      comicId: 'abc',
      title: '禁漫一本',
      description: '简介',
      cover: '{"url":"https://x/1.jpg"}',
      creator: '{"name":"作者"}',
      titleMeta: '[{"text":"tag"}]',
      metadata: '{"extra":1}',
      chapterId: 'ch-7',
      chapterTitle: '第 7 话',
      chapterOrder: 7,
      pageIndex: 42,
      createdAt: _t0,
      lastReadAt: _t0.add(const Duration(minutes: 30)),
      updatedAt: _t0.add(const Duration(hours: 1)),
    ),
    _item(source: 'local', comicId: '/manga/x', title: '本地一本'),
  ];
  final raw = encodeHistoryLibrary(items);
  final back = parseHistoryLibrary(raw);
  check('往返不丢条目', back.items.length == 2, '${back.rejected}');
  check('坏条目为空（正对照）', back.rejected.isEmpty, '${back.rejected}');

  final first = back.items.first;
  check('往返不丢标题', first.title == '禁漫一本');
  check('往返不丢键', first.uniqueKey == 'jm:abc');
  check('往返不丢简介', first.description == '简介');
  check('往返不丢 cover 原样 JSON 串', first.cover == items.first.cover);
  check('往返不丢 creator 原样 JSON 串', first.creator == items.first.creator);
  check('往返不丢 titleMeta 原样 JSON 串', first.titleMeta == items.first.titleMeta);
  check('往返不丢 metadata 原样 JSON 串', first.metadata == items.first.metadata);
  check('往返不丢章节 id', first.chapterId == 'ch-7', first.chapterId);
  check('往返不丢章节标题', first.chapterTitle == '第 7 话');
  check('往返不丢章节序号', first.chapterOrder == 7, '${first.chapterOrder}');
  check('往返不丢页码', first.pageIndex == 42, '${first.pageIndex}');
  check(
    '往返不丢 createdAt',
    first.createdAt == items.first.createdAt,
    '${first.createdAt}',
  );
  check(
    '往返不丢 lastReadAt',
    first.lastReadAt == items.first.lastReadAt,
    '${first.lastReadAt}',
  );
  check('往返不丢 updatedAt', first.updatedAt == items.first.updatedAt);

  // 上面这些断言若字段压根没写进 JSON，会一起失败；这条把它们钉在「真的写出去了」，
  // 免得哪天 toJson 漏一行、解析端补了个默认 0 也照样「往返相等」。
  check('页码真的落到文件里（不是靠默认值蒙对）', raw.contains('"pageIndex": 42'), raw);
  check('章节序号真的落到文件里', raw.contains('"chapterOrder": 7'));
  check('lastReadAt 真的落到文件里', raw.contains('"lastReadAt"'));

  // 正对照的镜像：0 页 / 空章节会被 toJson 省掉，读回来仍然是 0，而不是 null 或崩。
  final second = back.items.last;
  check(
    '省掉默认字段后页码仍是 0',
    second.pageIndex == 0 && second.chapterOrder == 0,
    '${second.pageIndex}/${second.chapterOrder}',
  );
  check('省掉默认字段后章节 id 仍是空串', second.chapterId.isEmpty);
  check('缺时间字段解析成 null 而不是抛', second.lastReadAt == null);
  check('本地键原样带斜杠', second.uniqueKey == 'local:/manga/x');

  check('导出的 JSON 是人能读的（带缩进）', raw.contains('\n  "version"'));
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  check('带版本与条数', decoded['version'] == 'v1' && decoded['count'] == 2);
  check('带导出时间', decoded['exportedAt'] is String);
}

void _rejectsBadKeys() {
  final result = parseHistoryLibrary(
    _doc([
      {
        'uniqueKey': 'wrong:key',
        'source': 'bika',
        'comicId': '1',
        'title': 'T',
      },
    ]),
  );
  check('键不一致被拒收', result.items.isEmpty && result.rejected.length == 1);
  check(
    '拒收理由说清了该是什么键',
    result.rejected.single.reason.contains('bika:1'),
    result.rejected.single.reason,
  );

  // 正对照：键写成对的就该放行。
  final ok = parseHistoryLibrary(
    _doc([
      {'uniqueKey': 'bika:1', 'source': 'bika', 'comicId': '1', 'title': 'T'},
    ]),
  );
  check(
    '键与 source:comicId 一致时放行',
    ok.items.length == 1 && ok.rejected.isEmpty,
    '${ok.rejected}',
  );
  // 正对照的第二档：压根不写键，按 source:comicId 补出来。
  final filled = parseHistoryLibrary(
    _doc([
      {'source': 'bika', 'comicId': '9', 'title': 'T'},
    ]),
  );
  check(
    '缺 uniqueKey 时补齐而不是拒收',
    filled.items.single.uniqueKey == 'bika:9',
    '${filled.items}',
  );
}

void _badItemsDoNotSinkTheFile() {
  final result = parseHistoryLibrary(
    _doc([
      {'source': 'bika', 'comicId': '1', 'title': '好的'},
      {'source': '', 'comicId': '2', 'title': '缺来源'},
      {'source': '   ', 'comicId': '2b', 'title': '来源只有空格'},
      {'source': 'bika', 'comicId': '', 'title': '缺 id'},
      {'source': 'bika', 'comicId': '  ', 'title': 'id 只有空格'},
      {'title': '来源和 id 都没有'},
      '不是对象',
      {'source': 'bika', 'comicId': '8', 'title': '', 'pageIndex': 99},
    ]),
  );
  check('坏条目不影响好条目入库', result.items.length == 2, '${result.items}');
  check('每条坏条目都有理由', result.rejected.length == 6, '${result.rejected}');
  check(
    '理由不是空话',
    result.rejected.every((r) => r.reason.trim().isNotEmpty),
    '${result.rejected}',
  );
  // 正对照：条目认不出是哪本（缺 source/comicId）才扔；只是标题空的，
  // 带着页码照样收 —— 扔它就等于扔进度。
  check(
    '空标题但认得出哪本 ⇒ 收下并保住进度',
    result.items.any((i) => i.uniqueKey == 'bika:8' && i.pageIndex == 99),
    '${result.items.map((i) => i.uniqueKey).toList()}',
  );
  check(
    '同一条文件里好的那条没被连累',
    result.items.first.uniqueKey == 'bika:1' &&
        result.items.first.title == '好的',
  );
}

void _datesAndVersionsAreTolerant() {
  // epoch 毫秒与 ISO-8601 两种写法都要能进；这是「别的工具生成的文件」的常见形状。
  final epoch = _t0.millisecondsSinceEpoch;
  final result = parseHistoryLibrary(
    _doc([
      {'source': 'bika', 'comicId': 'ms', 'title': '毫秒', 'lastReadAt': epoch},
      {
        'source': 'bika',
        'comicId': 'iso',
        'title': 'ISO',
        'lastReadAt': _t0.toIso8601String(),
      },
      {
        'source': 'bika',
        'comicId': 'broken',
        'title': '写坏的时间',
        'lastReadAt': '不是个时间',
        'pageIndex': '42',
      },
    ]),
  );
  check('两种日期写法都读进来了', result.items.length == 3, '${result.rejected}');
  final byId = {for (final i in result.items) i.comicId: i};
  check(
    'epoch 毫秒解析成同一时刻',
    byId['ms']?.lastReadAt?.toUtc() == _t0,
    '${byId['ms']?.lastReadAt}',
  );
  check(
    'ISO-8601 解析成同一时刻',
    byId['iso']?.lastReadAt == _t0,
    '${byId['iso']?.lastReadAt}',
  );
  // 正对照：时间读不出来 ⇒ 该条留下、字段为 null（扔整条等于扔进度）。
  check('时间写坏不整条拒收', byId['broken'] != null);
  check('时间写坏时字段是 null', byId['broken']?.lastReadAt == null);
  check('页码写成字符串也算数', byId['broken']?.pageIndex == 42);

  // 只认主版本号：v1.2 是同一代格式，放行；v9 才是换代。
  final minor = parseHistoryLibrary(_doc(const [], version: 'v1.2'));
  check('次要版本号放行', minor.version == 'v1.2');
  for (final raw in [
    '{',
    '[]',
    '{"items":[]}',
    '{"version":"","items":[]}',
    '{"version":"v9","items":[]}',
    '{"version":"v9.1","items":[]}',
  ]) {
    var threw = false;
    try {
      parseHistoryLibrary(raw);
    } on HistoryLibraryFormatException {
      threw = true;
    }
    check('读不了的文件要明说而不是返回空：$raw', threw);
  }
  // 正对照：items 为空数组本身是合法文件（空库导出）。
  check('空 items 不算格式错误', parseHistoryLibrary(_doc(const [])).items.isEmpty);
}

void _mergeDecisions() {
  final plan = planHistoryImport(
    items: [
      _item(comicId: 'new'),
      _item(comicId: 'dead', lastReadAt: _t0),
      _item(comicId: 'alive-older', lastReadAt: _t0),
      _item(
        comicId: 'alive-newer',
        lastReadAt: _t0.add(const Duration(seconds: 1)),
      ),
    ],
    localState: {
      'bika:new': null, // 显式 null：与「不在字典里」同义
      'bika:dead': HistoryLocalState(deleted: true, lastReadAt: _t0),
      'bika:alive-older': HistoryLocalState(
        deleted: false,
        lastReadAt: _t0.add(const Duration(seconds: 30)),
      ),
      'bika:alive-newer': HistoryLocalState(
        deleted: false,
        lastReadAt: _t0.subtract(const Duration(seconds: 30)),
      ),
    },
    rejected: const [HistoryRejection(label: '第 9 条', reason: '缺 source')],
  );
  check('本地没有 ⇒ 新增', plan.addCount == 1, plan.summary);
  check('本地软删 ⇒ 复活', plan.reviveCount == 1, plan.summary);
  check('本地在册且文件更新 ⇒ 覆盖进度', plan.overwriteCount == 1, plan.summary);
  check('本地在册且文件更旧 ⇒ 保留本地', plan.staleCount == 1, plan.summary);
  check('重复桶此时为 0（正对照）', plan.duplicateCount == 0, plan.summary);
  check(
    '只写该写的：更旧那条被挡在写入之外',
    plan.writes.map((i) => i.comicId).join() == 'newdeadalive-newer',
    plan.writes.map((i) => i.comicId).toList().toString(),
  );
  check('解析阶段的拒收条目一并带出', plan.rejected.length == 1);

  // 字典里压根没有这个键 = 本地没有 ⇒ 新增（与上面显式 null 同结果）。
  final absent = planHistoryImport(
    items: [_item(comicId: 'new')],
    localState: const {},
  );
  check('键完全不在字典里也判新增', absent.addCount == 1 && absent.staleCount == 0);
}

void _newerWinsThreshold() {
  HistoryMergeAction action({DateTime? incoming, DateTime? local}) {
    final plan = planHistoryImport(
      items: [_item(comicId: 'x', lastReadAt: incoming)],
      localState: {
        'bika:x': HistoryLocalState(deleted: false, lastReadAt: local),
      },
    );
    return plan.decisions.single.action;
  }

  // 阈值两侧：+1ms 覆盖，−1ms 与恰好相等都保留本地。
  check(
    '严格更新 1 毫秒 ⇒ 覆盖',
    action(incoming: _t0.add(const Duration(milliseconds: 1)), local: _t0) ==
        HistoryMergeAction.overwrite,
  );
  check(
    '恰好相等 ⇒ 不动本地（阈值不容「四舍五入」）',
    action(incoming: _t0, local: _t0) == HistoryMergeAction.stale,
  );
  check(
    '旧 1 毫秒 ⇒ 不动本地',
    action(
          incoming: _t0.subtract(const Duration(milliseconds: 1)),
          local: _t0,
        ) ==
        HistoryMergeAction.stale,
  );

  // 跨表示法的同一裁决：epoch 毫秒（本地时区对象）对 ISO UTC。
  final newer = DateTime.fromMillisecondsSinceEpoch(
    _t0.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
  );
  final plan = planHistoryImport(
    items: [_item(comicId: 'tz', lastReadAt: newer)],
    localState: {'bika:tz': HistoryLocalState(deleted: false, lastReadAt: _t0)},
  );
  check('epoch 与 UTC 混写时比的仍是绝对时刻', plan.overwriteCount == 1, plan.summary);

  // 缺时间的一侧：文件里没有 lastReadAt 不许盖掉本地有时间的记录。
  check(
    '文件缺时间 ⇒ 保留本地',
    action(incoming: null, local: _t0) == HistoryMergeAction.stale,
  );
  // 正对照：本地那份没时间（视为最旧），文件里有时间就该赢。
  check(
    '本地缺时间 ⇒ 覆盖',
    action(incoming: _t0, local: null) == HistoryMergeAction.overwrite,
  );
}

void _reviveIgnoresStaleness() {
  // 软删的记录不在屏上，复活不看时间。
  final revive = planHistoryImport(
    items: [_item(comicId: 'dead', pageIndex: 1)],
    localState: {
      'bika:dead': HistoryLocalState(
        deleted: true,
        lastReadAt: _t0.add(const Duration(days: 365)),
      ),
    },
  );
  check(
    '软删的即使文件进度更旧也复活',
    revive.reviveCount == 1 && revive.writes.length == 1,
    revive.summary,
  );
  // 正对照：同一份数据、只是没被删过 ⇒ 就落回时间裁决（证明 revive 不是万能放行）。
  final alive = planHistoryImport(
    items: [_item(comicId: 'dead', pageIndex: 1)],
    localState: {
      'bika:dead': HistoryLocalState(
        deleted: false,
        lastReadAt: _t0.add(const Duration(days: 365)),
      ),
    },
  );
  check(
    '没被删过的同一份数据走保留本地',
    alive.staleCount == 1 && alive.writes.isEmpty,
    alive.summary,
  );
}

void _duplicateKeysInFile() {
  final plan = planHistoryImport(
    items: [
      _item(comicId: '1', pageIndex: 10, lastReadAt: _t0),
      _item(comicId: '1', pageIndex: 99, lastReadAt: _t0),
    ],
    localState: const {},
  );
  check('文件内重复键只写一条', plan.writes.length == 1);
  check('写进去的是第一条', plan.writes.single.pageIndex == 10);
  check('重复桶记了数', plan.duplicateCount == 1, plan.summary);

  // 正对照：同键出现一次 ⇒ 新增，不占重复桶。
  final once = planHistoryImport(
    items: [_item(comicId: '1', pageIndex: 10, lastReadAt: _t0)],
    localState: const {},
  );
  check('只出现一次时不算重复', once.duplicateCount == 0 && once.addCount == 1);
}

void _summaryMentionsEveryBucketAndNoDeletion() {
  final plan = planHistoryImport(
    items: [
      _item(comicId: 'new'),
      // 同键第二次：dedup 在查本地之前发生 ⇒ 落 duplicate 桶。
      _item(comicId: 'new', lastReadAt: _t0),
      _item(comicId: 'dead', lastReadAt: _t0),
      _item(comicId: 'alive', lastReadAt: _t0),
      _item(comicId: 'alive2', lastReadAt: _t0.add(const Duration(hours: 1))),
    ],
    localState: {
      'bika:dead': HistoryLocalState(deleted: true, lastReadAt: _t0),
      'bika:alive': HistoryLocalState(
        deleted: false,
        lastReadAt: _t0.add(const Duration(hours: 1)),
      ),
      'bika:alive2': HistoryLocalState(
        deleted: false,
        lastReadAt: _t0.subtract(const Duration(hours: 1)),
      ),
    },
    rejected: const [HistoryRejection(label: '第 9 条', reason: '缺 source')],
  );
  final summary = plan.summary;
  check('结论里有新增数', summary.contains('新增 1 条'), summary);
  check('结论里有复活数', summary.contains('复活 1 条'), summary);
  check('结论里有进度更新数', summary.contains('更新进度 1 条'), summary);
  check('结论里有保留本地数', summary.contains('保留本地 1 条'), summary);
  check('结论里有文件内重复数', summary.contains('文件内重复 1 条'), summary);
  check('结论里有跳过数', summary.contains('跳过 1 条'), summary);
  check('结论不含删除动作', !summary.contains('删除'), summary);
  check('结论不含清库字样', !summary.contains('清空'), summary);

  // 正对照：桶为 0 时也要点名，用户才知道「导入 100 条只变了 1 条」不是丢了。
  final only = planHistoryImport(items: [_item()], localState: const {});
  check('空桶照样写出来', only.summary.contains('保留本地 0 条'), only.summary);
  check('没有拒收时不写跳过字样', !only.summary.contains('跳过'), only.summary);
}
