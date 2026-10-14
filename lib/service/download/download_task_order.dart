/// 启动顺序的纯判据：谁先拿到本轮的下载槽位。
///
/// 队列本来就是「先到先得」（ObjectBox 按 id 升序递给调度），这格补的是另一件事：
/// 用户明确说「这章我现在就想看」时，它要插到队首去。判据拆在这里是因为
/// 它只吃 `id / key` 两个值，能脱离实体与文件系统单独测 —— 别人把整包编译拖红的时候
/// 这条还得跑得动。
library;

/// 一行待启动任务的排序输入。
typedef DownloadTaskOrderRow = ({int id, String key});

/// 置顶的那批先走，组内按 [pinnedKeys] 自己的先后（表头 = 最先启动；
/// [pinTaskKey] 保证最新点的那颗在表头 —— 用户刚点的就是他现在最想要的那章）；
/// 其余保持入队顺序（id 升序）。
///
/// [pinnedKeys] 是设备本地的排序意图，不是任务的一部分：队列里没了的 key 由
/// [prunePinnedKeys] 清掉，这里只按「在不在表里」判。
List<DownloadTaskOrderRow> sortDownloadTasksForStart({
  required Iterable<DownloadTaskOrderRow> rows,
  List<String> pinnedKeys = const <String>[],
}) {
  if (pinnedKeys.isEmpty) {
    final sorted = rows.toList();
    sorted.sort((a, b) => a.id.compareTo(b.id));
    return sorted;
  }

  // 表里的位置就是启动先后；同一个 key 写重了以最靠前的那次为准。
  final rank = <String, int>{};
  for (var index = 0; index < pinnedKeys.length; index++) {
    rank.putIfAbsent(pinnedKeys[index], () => index);
  }

  final result = rows.toList();
  result.sort((a, b) {
    final aRank = rank[a.key];
    final bRank = rank[b.key];
    if (aRank != null && bRank != null) return aRank.compareTo(bRank);
    if (aRank != null) return -1;
    if (bRank != null) return 1;
    return a.id.compareTo(b.id);
  });
  return result;
}

/// 只保留仍在队列里的置顶 key，并按给定顺序去重（同一章被点两次不占两个位置）。
List<String> prunePinnedKeys({
  required Iterable<String> pinnedKeys,
  required Set<String> queuedKeys,
}) {
  final kept = <String>[];
  final seen = <String>{};
  for (final key in pinnedKeys) {
    if (!queuedKeys.contains(key) || !seen.add(key)) continue;
    kept.add(key);
  }
  return kept;
}

/// 点「优先」：把这一章挪到置顶表的最前面（已在前面的不动，避免反复点同一章时
/// 把它挤到自己后面去）。
List<String> pinTaskKey({
  required List<String> pinnedKeys,
  required String key,
}) {
  if (pinnedKeys.isNotEmpty && pinnedKeys.first == key) return pinnedKeys;
  return [key, ...pinnedKeys.where((existing) => existing != key)];
}
