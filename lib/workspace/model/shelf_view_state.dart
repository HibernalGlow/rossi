/// 书架卡片（书签 / 历史）的视图状态：当前那一档视图 + 排序。
///
/// 刻意不 import Flutter、也不 import 视图层的枚举：这份东西的正本是
/// SharedPreferences 里的一段 JSON，判据要能脱离界面跑完「存进去再读出来」
/// 的往返（同 `shelf_library_query.dart` 的理由）。所以这里只存**枚举名字**，
/// 卡片自己用 [shelfEnumByName] 把它换回枚举。
library;

import 'dart:convert';

/// 整份文档在 SharedPreferences 里的那一个键。
const String kShelfViewStateNamespace = 'rossi.shelf.viewState';

/// 一张卡片记住的视图与排序。
class ShelfViewState {
  const ShelfViewState({
    required this.viewMode,
    required this.sortField,
    required this.sortAscending,
  });

  /// `LibraryViewMode.name`。
  final String viewMode;

  /// `ShelfSortField.name`。
  final String sortField;
  final bool sortAscending;

  Map<String, Object?> encode() => <String, Object?>{
    'v': viewMode,
    'f': sortField,
    'a': sortAscending,
  };

  /// 名字为空或缺项 ⇒ null（宁可退回默认，也不要恢复出一个「没有视图」的状态）。
  static ShelfViewState? decode(Object? json) {
    if (json is! Map) return null;
    final viewMode = json['v'];
    final sortField = json['f'];
    if (viewMode is! String || viewMode.isEmpty) return null;
    if (sortField is! String || sortField.isEmpty) return null;
    return ShelfViewState(
      viewMode: viewMode,
      sortField: sortField,
      sortAscending: json['a'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShelfViewState &&
      other.viewMode == viewMode &&
      other.sortField == sortField &&
      other.sortAscending == sortAscending;

  @override
  int get hashCode => Object.hash(viewMode, sortField, sortAscending);

  @override
  String toString() =>
      'ShelfViewState($viewMode, $sortField, ${sortAscending ? "asc" : "desc"})';
}

/// 整份落盘文档：卡片 id ⇒ 视图状态。
///
/// 一条坏记录只丢那一条，不牵连别的 —— 手改过的偏好文件、或者以后删掉某个
/// 视图档位，都不该让另一张卡片的记忆跟着一起没。
Map<String, ShelfViewState> decodeShelfViewStates(Object? raw) {
  if (raw is! Map) return {};
  final states = <String, ShelfViewState>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) continue;
    final state = ShelfViewState.decode(entry.value);
    if (state == null) continue;
    states[entry.key as String] = state;
  }
  return states;
}

/// 编码成可以直接 `jsonEncode` 的结构。
Map<String, Object?> encodeShelfViewStates(Map<String, ShelfViewState> states) {
  return <String, Object?>{
    for (final entry in states.entries) entry.key: entry.value.encode(),
  };
}

/// 从磁盘文本读出文档。读不出 JSON、或读出来不是对象 ⇒ 空文档。
///
/// 这里必须把 `FormatException` 一起吞掉：视图状态是**可重建**的东西，
/// 为一段坏文本抛异常等于让用户每次启动都看见一张红屏卡片。
Map<String, ShelfViewState> parseShelfViewStates(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  try {
    return decodeShelfViewStates(jsonDecode(raw));
  } on Object {
    return {};
  }
}

/// 名字 ⇒ 枚举值；名字不认识时返回 null，由调用方退回默认。
///
/// 不用 `values.byName`：枚举改过名（或用户手上的偏好文件来自更新的版本）时
/// 它会直接抛，而这个调用点在卡片的 build 之后，抛出就是整张卡片红屏。
T? shelfEnumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null || name.isEmpty) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
