/// 章节勾选的纯逻辑：正选、反选、跳过已下载各自改哪几张表。
///
/// 抽出来是因为这几条判据在页面里没法单独测，而它们一次点击就决定要不要重下
/// 30 章：`skipDownloaded` 开启时把已下载的勾选一起清掉，`selectableIds`
/// 决定「全选/反选」能碰到哪些行，`selectedIds` 是最终真正入队的那批。
class DownloadChapterSelection {
  const DownloadChapterSelection({
    required this.orderedIds,
    required this.downloadedIds,
    this.selectedIds = const <String>{},
    this.skipDownloaded = false,
  });

  /// 页面上出现的章节，按图源给的顺序。
  final List<String> orderedIds;

  /// 本地已经下载过的章节 id。
  final Set<String> downloadedIds;

  /// 当前勾中的章节。开启 [skipDownloaded] 时这里面不会有已下载的 id。
  final Set<String> selectedIds;

  /// 跳过已下载：本地已有的行不参与勾选，也不会被入队。
  final bool skipDownloaded;

  /// 「全选 / 反选」能作用的行。
  List<String> get selectableIds =>
      orderedIds.where(_isSelectable).toList(growable: false);

  bool _isSelectable(String id) =>
      !(skipDownloaded && downloadedIds.contains(id));

  /// 空列表时不算「已全选」，否则标题栏一进页就显示成「取消全选」。
  bool get isAllSelected =>
      selectableIds.isNotEmpty &&
      selectableIds.every((id) => selectedIds.contains(id));

  DownloadChapterSelection toggled(String id) {
    if (!_isSelectable(id)) return this;
    final next = Set<String>.from(selectedIds);
    if (!next.remove(id)) next.add(id);
    return copyWith(selectedIds: next);
  }

  DownloadChapterSelection withAllSelected(bool on) =>
      copyWith(selectedIds: on ? {...selectableIds} : const <String>{});

  /// 反选只翻转可作用的行；被跳过的行保持原样（它们的勾选本来就被清掉了）。
  DownloadChapterSelection inverted() {
    final next = Set<String>.from(selectedIds);
    for (final id in selectableIds) {
      if (!next.remove(id)) next.add(id);
    }
    return copyWith(selectedIds: next);
  }

  /// 开启「跳过已下载」要顺手把已下载的勾选清掉：留着它们，计数就会说出
  /// 一个「开始下载」时并不属实的数字。
  DownloadChapterSelection withSkipDownloaded(bool on) {
    if (!on) return copyWith(skipDownloaded: false);
    return copyWith(
      skipDownloaded: true,
      selectedIds: selectedIds
          .where((id) => !downloadedIds.contains(id))
          .toSet(),
    );
  }

  DownloadChapterSelection copyWith({
    Set<String>? selectedIds,
    bool? skipDownloaded,
  }) => DownloadChapterSelection(
    orderedIds: orderedIds,
    downloadedIds: downloadedIds,
    selectedIds: selectedIds ?? this.selectedIds,
    skipDownloaded: skipDownloaded ?? this.skipDownloaded,
  );

  /// 按页面顺序排好的待入队章节。
  List<String> get orderedSelectedIds =>
      orderedIds.where(selectedIds.contains).toList(growable: false);

  int get selectedCount => selectedIds.length;

  bool isSelected(String id) => selectedIds.contains(id);

  /// 这一行是否因为「跳过已下载」而被禁掉。
  bool isSkipped(String id) => skipDownloaded && downloadedIds.contains(id);
}
