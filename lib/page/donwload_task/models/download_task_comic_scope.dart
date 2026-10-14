/// 队列按漫画分组的纯判据：有哪几本、各占几章、这一行属不属于当前选中的那本。
///
/// 不 import 任何 app 代码 —— 页面把实体上的 `comicId / comicName` 读好传进来。
/// 这样这条判据在整仓编译不过时仍然可测，而分组本身是纯算术：它错只可能是
/// 「把同一本拆成两组」或「顺序跟着计数漂」，两种都能在这里钉死。
library;

/// 队列里的一本漫画。
class DownloadTaskComicGroup {
  const DownloadTaskComicGroup({
    required this.comicId,
    required this.comicName,
    required this.taskCount,
  });

  final String comicId;
  final String comicName;

  /// 这本在队列里占几章（未完成的任务数）。
  final int taskCount;
}

/// 队列行按漫画归组，**保持首次出现的顺序**：任务页的分段已经是「正在下载 /
/// 失败 / 等待中」，再按字母或章数重排会让同一本每次刷新都跳到别处。
///
/// 名字取这一本第一次出现时的那份：同一 `comicId` 的名字理论上不会变，但改过名
/// 的老任务也不该因此被拆成两组。
List<DownloadTaskComicGroup> downloadTasksGroupedByComic(
  Iterable<({String comicId, String comicName})> rows,
) {
  final order = <String>[];
  final names = <String, String>{};
  final counts = <String, int>{};

  for (final row in rows) {
    final comicId = row.comicId;
    if (!counts.containsKey(comicId)) {
      order.add(comicId);
      names[comicId] = row.comicName;
      counts[comicId] = 0;
    }
    counts[comicId] = counts[comicId]! + 1;
  }

  return [
    for (final comicId in order)
      DownloadTaskComicGroup(
        comicId: comicId,
        comicName: names[comicId]!,
        taskCount: counts[comicId]!,
      ),
  ];
}

/// 这一行是否落在当前选中的那本漫画里。未选中（`null`）时不筛任何行。
bool downloadTaskMatchesComicScope({
  required String? selectedComicId,
  required String comicId,
}) {
  if (selectedComicId == null) return true;
  return comicId == selectedComicId;
}
