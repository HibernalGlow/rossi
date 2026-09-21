// 书架卡片视图状态落盘的**纯 Dart** 判据。
//
//   dart test/workspace/shelf_view_state_check.dart
//
// 钉住几条不看代码想不到的行为：
//
//   1. **降序也要能回来** —— `ascending` 是布尔，`json['a'] ?? true` 那种写法
//      会让「用户选了升序」在下次启动静默变回降序；
//   2. **改了名的枚举值退回默认，而不是抛** —— 恢复发生在 build 之后，
//      `values.byName` 抛出就是整张卡片红屏；
//   3. **坏 JSON 与坏记录都只丢那一条** —— 视图状态是可重建的东西，
//      为它抛异常等于让一次手滑毁掉两张卡片的记忆；
//   4. 走一遍真 `jsonEncode` / `jsonDecode`，别只测内存里的对象。
//
// 没有 package:test 依赖（跟 `shelf_library_query_check.dart` 同一套路）。
//
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

/// 走一遍真实的落盘形态：编码 → 字符串 → 解码。
Map<String, ShelfViewState> _roundTrip(Map<String, ShelfViewState> states) {
  return decodeShelfViewStates(
    jsonDecode(jsonEncode(encodeShelfViewStates(states))),
  );
}

void main() {
  _bothDirectionsSurvive();
  _unknownNamesFallBackInsteadOfThrowing();
  _brokenJsonIsNoRecord();
  _oneBadRecordKeepsTheOthers();
  _keyIsTheCardId();

  print('shelf_view_state_check: $_passed checks passed');
}

void _bothDirectionsSurvive() {
  const states = <String, ShelfViewState>{
    'history': ShelfViewState(
      viewMode: 'coverGrid',
      sortField: 'title',
      sortAscending: false,
    ),
    'favorite': ShelfViewState(
      viewMode: 'compact',
      sortField: 'time',
      sortAscending: true,
    ),
  };
  final back = _roundTrip(states);
  check('两张卡片各回各的', back.length == 2);
  check('视图档位原样回来', back['history']?.viewMode == 'coverGrid');
  check('排序字段原样回来', back['history']?.sortField == 'title');
  check(
    '降序（false）不会被读成 true',
    back['history']?.sortAscending == false,
    '${back['history']}',
  );
  check('升序仍是升序', back['favorite']?.sortAscending == true);
  check('整条相等，比较用的是值', back['history'] == states['history']);
}

void _unknownNamesFallBackInsteadOfThrowing() {
  final values = ShelfSortField.values;
  check('认识的名字换得到枚举', shelfEnumByName(values, 'author') == ShelfSortField.author);
  check('改了名的名字返回 null 而不是抛', shelfEnumByName(values, 'uploader') == null);
  check('空名返回 null', shelfEnumByName(values, '') == null);
  check('缺项返回 null', shelfEnumByName(values, null) == null);
  // 视图档位同理：卡片传的是 LibraryViewMode.values，这里用同一个函数换。
  final restored = ShelfViewState.decode(<String, Object?>{'v': 'nope', 'f': 'time', 'a': true});
  check('档位名字不认识时状态本身仍留得住', restored?.viewMode == 'nope');
  check('排序字段仍换得到', shelfEnumByName(values, restored?.sortField) == ShelfSortField.time);
}

void _brokenJsonIsNoRecord() {
  check('没存过 ⇒ 空文档', parseShelfViewStates(null).isEmpty);
  check('空串 ⇒ 空文档', parseShelfViewStates('   ').isEmpty);
  check(
    '手改坏的 JSON ⇒ 空文档而不是抛',
    parseShelfViewStates('{"history": {"v": "coverGrid"').isEmpty,
  );
  check(
    '合法但不是对象 ⇒ 空文档',
    parseShelfViewStates('[1,2,3]').isEmpty,
  );
  check(
    '布尔值当文档 ⇒ 空文档',
    parseShelfViewStates('true').isEmpty,
  );
}

void _oneBadRecordKeepsTheOthers() {
  // 直接喂解码后的形态（真 JSON 的键一定是字符串，非字符串键只可能来自
  // 别的来源，所以这里绕开 jsonEncode 单独验那一条守卫）。
  final states = decodeShelfViewStates(<Object?, Object?>{
    'history': <String, Object?>{'v': 'details', 'f': 'source', 'a': false},
    // 缺 sortField：过去某个版本写出来的半条记录。
    'broken': <String, Object?>{'v': 'details'},
    'nullish': null,
    42: <String, Object?>{'v': 'details', 'f': 'source', 'a': false},
  });
  check('好记录照旧读出来', states['history']?.viewMode == 'details');
  check('缺项的坏记录被丢掉', states['broken'] == null);
  check('null 记录被丢掉', states['nullish'] == null);
  check('非字符串的键被丢掉', states.length == 1, '${states.keys}');
  check(
    '丢掉坏记录不牵连好记录',
    states['history'] ==
        const ShelfViewState(
          viewMode: 'details',
          sortField: 'source',
          sortAscending: false,
        ),
  );
}

void _keyIsTheCardId() {
  const states = <String, ShelfViewState>{
    WorkspacePanelId.history: ShelfViewState(
      viewMode: 'mosaicList',
      sortField: 'author',
      sortAscending: true,
    ),
  };
  final back = _roundTrip(states);
  check(
    '键就是面板 id（两张卡片各写各的那一条）',
    back[WorkspacePanelId.history]?.sortField == 'author',
  );
  check(
    '写一条不会带上另一条',
    back[WorkspacePanelId.favorite] == null,
  );
}
