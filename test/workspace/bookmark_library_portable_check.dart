// 书签导出 / 导入文档的**纯 Dart** 判据。
//
//   dart run test/workspace/bookmark_library_portable_check.dart
//
// 这里钉的是「导入会不会悄悄做错的事」：
//
//   1. **uniqueKey 与 source:comicId 不一致必须拒收** —— 这种记录写进库后
//      再也查不到，取消收藏与同步会绕着它走，属于静默腐坏；
//   2. **同一文件里重复的键只写第一条** —— 否则后写的覆盖先写的；
//   3. **软删过的记录要复活，已经在书签里的不能被动** —— 前者是用户重新
//      导入想拿回来，后者是导入不该把本地更新过的字段冲掉；
//   4. **导入不清库**：结论里只有新增/复活/已存在/跳过，没有删除。
//
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:zephyr/workspace/model/bookmark_library_portable.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

BookmarkLibraryItem _item({
  String source = 'bika',
  String comicId = '1',
  String? uniqueKey,
  String title = '标题',
}) {
  return BookmarkLibraryItem(
    uniqueKey: uniqueKey ?? BookmarkLibraryItem.keyFor(
      source: source,
      comicId: comicId,
    ),
    source: source,
    comicId: comicId,
    title: title,
  );
}

String _doc(List<Object> items, {String version = kBookmarkLibraryVersion}) {
  return jsonEncode({'version': version, 'items': items});
}

void main() {
  _roundTrip();
  _rejectsBadKeys();
  _badItemsDoNotSinkTheFile();
  _unreadableDocumentThrows();
  _mergeDecisions();
  _duplicateKeysInFile();
  _summaryMentionsNoDeletion();

  print('bookmark_library_portable_check: $_passed checks passed');
}

void _roundTrip() {
  final items = [
    _item(source: 'jm', comicId: 'abc', title: '禁漫一本'),
    _item(source: 'local', comicId: '/manga/x', title: '本地一本'),
  ];
  final raw = encodeBookmarkLibrary(items);
  final back = parseBookmarkLibrary(raw);
  check('往返不丢条目', back.items.length == 2, '${back.rejected}');
  check('往返不丢标题', back.items.first.title == '禁漫一本');
  check('往返不丢键', back.items.last.uniqueKey == 'local:/manga/x');
  check('导出的 JSON 是人能读的（带缩进）', raw.contains('\n  "version"'));
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  check('带版本与条数', decoded['version'] == 'v1' && decoded['count'] == 2);
}

void _rejectsBadKeys() {
  final result = parseBookmarkLibrary(
    _doc([
      {'uniqueKey': 'wrong:key', 'source': 'bika', 'comicId': '1', 'title': 'T'},
    ]),
  );
  check('键不一致被拒收', result.items.isEmpty && result.rejected.length == 1);
  check(
    '拒收理由说清了该是什么键',
    result.rejected.single.reason.contains('bika:1'),
    result.rejected.single.reason,
  );
}

void _badItemsDoNotSinkTheFile() {
  final result = parseBookmarkLibrary(
    _doc([
      {'source': 'bika', 'comicId': '1', 'title': '好的'},
      {'source': '', 'comicId': '2', 'title': '缺来源'},
      {'source': 'bika', 'comicId': '', 'title': '缺 id'},
      {'source': 'bika', 'comicId': '4', 'title': '  '},
      '不是对象',
    ]),
  );
  check('坏条目不影响好条目入库', result.items.length == 1, '${result.items}');
  check('每条坏条目都有理由', result.rejected.length == 4, '${result.rejected}');
  check('缺 key 时按 source:comicId 补齐', result.items.single.uniqueKey == 'bika:1');
}

void _unreadableDocumentThrows() {
  for (final raw in ['{', '[]', '{"items":[]}', '{"version":"v9","items":[]}']) {
    var threw = false;
    try {
      parseBookmarkLibrary(raw);
    } on BookmarkLibraryFormatException {
      threw = true;
    }
    check('读不了的文件要明说而不是返回空：$raw', threw);
  }
}

void _mergeDecisions() {
  final plan = planBookmarkImport(
    items: [
      _item(comicId: 'new'),
      _item(comicId: 'alive'),
      _item(comicId: 'dead'),
    ],
    localState: {'bika:alive': false, 'bika:dead': true},
    rejected: const [BookmarkRejection(label: '第 9 条', reason: '缺 source')],
  );
  check('本地没有 ⇒ 新增', plan.addCount == 1);
  check('本地软删 ⇒ 复活', plan.reviveCount == 1);
  check('本地已有 ⇒ 不动', plan.duplicateCount == 1);
  check(
    '只写该写的',
    plan.writes.map((i) => i.comicId).join() == 'newdead',
    plan.writes.map((i) => i.comicId).toList().toString(),
  );
  check('解析阶段的拒收条目一并带出', plan.rejected.length == 1);
}

void _duplicateKeysInFile() {
  final plan = planBookmarkImport(
    items: [
      _item(comicId: '1', title: '第一条'),
      _item(comicId: '1', title: '第二条同名键'),
    ],
    localState: const {},
  );
  check('文件内重复键只写一条', plan.writes.length == 1);
  check('写进去的是第一条', plan.writes.single.title == '第一条');
}

void _summaryMentionsNoDeletion() {
  final plan = planBookmarkImport(items: [_item()], localState: const {});
  final summary = plan.summary;
  check('结论里有新增数', summary.contains('新增 1 条'), summary);
  check('结论不含删除动作', !summary.contains('删除'), summary);
}
