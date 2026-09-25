/// 文件浏览卡片「上次打开的页签」：页签的目录按顺序，以及哪一个是当前的。
///
/// 刻意不 import Flutter、也不 import Rust 的生成物：这份东西的正本是
/// SharedPreferences 里的一段 JSON，判据要能脱离界面跑完「存进去再读出来」的
/// 往返（同 `shelf_view_state.dart` 的理由）。所以这里只存**路径字符串**，
/// 由卡片自己把它喂给 `fileManagerNewTab`。
///
/// 只存目录、不存页签标题 / 后退栈 / 搜索结果：那几样都活在 Rust 会话里，
/// 而会话本来就只活到卡片卸载为止。要把它们一起落盘，等于在 Dart 侧再造一个
/// 页签模型 —— 那正是这张卡片刻意不做的事（见 `file_manager_card.dart` 的类注释）。
library;

import 'dart:convert';

/// 整份文档在 SharedPreferences 里的那一个键。
const String kFileManagerTabSessionNamespace = 'rossi.fileManager.openTabs';

/// 最多记住几个页签。与核心的 `MAX_FILE_MANAGER_TABS` 同值：
/// 存多了也没用，恢复时第 9 个会被 `new_tab` 的上限直接拒掉。
const int kFileManagerTabSessionMaxTabs = 8;

/// 少于这个页数就**不记**。一个页签谈不上「页签条」——
/// 卡片在只剩一个页签时把整行都收起来了（见 `file_manager_card.dart` 的
/// `_buildBody`），记它等于悄悄把「启动时默认打开主页」那条设置顶掉。
const int kFileManagerTabSessionMinTabs = 2;

/// 一次要恢复的页签集合。
class FileManagerTabSession {
  const FileManagerTabSession({required this.paths, required this.activeIndex});

  /// 页签目录，按页签条上的顺序。首个用来建会话，其余逐个开新页签。
  final List<String> paths;

  /// 当前页签在 [paths] 里的下标，已经夹在 `[0, paths.length - 1]` 内。
  final int activeIndex;

  /// 落盘去重用的签名。用 `\u0000` 分隔：路径里不可能出现它，所以两份不同的
  /// 页签集合不会撞出同一个签名（撞了的表现是「改动没写进去」）。
  String get signature => '$activeIndex\u0000${paths.join("\u0000")}';

  Map<String, Object?> encode() => <String, Object?>{
    'p': paths,
    'a': activeIndex,
  };

  /// 认不出来 ⇒ null（宁可回到「这次没有要恢复的页签」，也不要恢复出一个空页签条）。
  ///
  /// 逐项校验而不是整份信任：这份 JSON 可能被用户手改过，也可能来自一个已经
  /// 改了上限的更新版本。多出来的页签**夹掉**而不是判整份无效 —— 用户记住的
  /// 前 8 个目录仍然是他要的，为了第 9 个把 8 个全丢掉是说不过去的。
  static FileManagerTabSession? decode(Object? raw) {
    if (raw is! Map) return null;
    final json = raw['p'];
    if (json is! List) return null;
    final paths = <String>[];
    for (final item in json) {
      if (item is! String || item.isEmpty) continue;
      paths.add(item);
      if (paths.length == kFileManagerTabSessionMaxTabs) break;
    }
    if (paths.isEmpty) return null;
    final active = raw['a'];
    // 缺失、不是整数、越界都退回首个页签：当前页签记不准只是「焦点在第一个」，
    // 而页签本身还是那一批。
    final activeIndex = active is int ? active.clamp(0, paths.length - 1) : 0;
    return FileManagerTabSession(paths: paths, activeIndex: activeIndex);
  }

  @override
  bool operator ==(Object other) =>
      other is FileManagerTabSession &&
      other.activeIndex == activeIndex &&
      other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() => 'FileManagerTabSession(${paths.length}, @$activeIndex)';
}

/// 从磁盘文本读出文档。读不出 JSON、或读出来不是对象 ⇒ null。
///
/// 这里必须把 `FormatException` 一起吞掉：页签记忆是**可重建**的东西，
/// 为一段坏文本抛异常等于让用户每次启动都看见一张红屏卡片。
FileManagerTabSession? parseFileManagerTabSession(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return FileManagerTabSession.decode(jsonDecode(raw));
  } on Object {
    return null;
  }
}
