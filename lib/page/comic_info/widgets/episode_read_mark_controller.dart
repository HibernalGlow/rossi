import 'dart:async';

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/cubit/episode_read_mark_cubit.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/chapter_read_mark_service.dart';
import 'package:zephyr/widgets/toast.dart';

/// 漫画详情页的章节阅读状态控制器 —— 与 [EpisodeDownloadController] 平级的那一半。
///
/// 下载控制器管「下没下」，这一份管「读没读、以及用户自己怎么判」。
/// **选中态不在这里**：多选仍然用下载控制器的 `selectionCubit` / `selectedIds`，
/// 两套选中模型迟早会各说各话。
///
/// 写入只落 `ComicChapterReadMark`。书签行 `UnifiedComicHistory` 由阅读器独占，
/// 这里既不写也不删，所以标了已读不会把「继续阅读」的位置挪走，读完一章也不会
/// 把用户手标的未读洗掉。口径见 `docs/chapter-read-state.md`。
class EpisodeReadMarkController {
  EpisodeReadMarkController();

  static const _service = ChapterReadMarkService.instance;

  final EpisodeReadMarkCubit cubit = EpisodeReadMarkCubit();

  String _from = '';
  String _comicId = '';
  StreamSubscription? _markSubscription;
  StreamSubscription? _historySubscription;

  /// 详情数据加载完成后调用；key 不变时无动作（与下载控制器同一口径）。
  void attach({required String from, required String comicId}) {
    final nextFrom = from.trim();
    final nextComicId = comicId.trim();
    if (_from == nextFrom && _comicId == nextComicId) return;
    _from = nextFrom;
    _comicId = nextComicId;
    _resubscribe();
    _loadInitial();
  }

  bool get enabled => _from.isNotEmpty && _comicId.isNotEmpty;

  void _resubscribe() {
    unawaited(_markSubscription?.cancel());
    unawaited(_historySubscription?.cancel());
    _markSubscription = null;
    _historySubscription = null;
    if (!enabled) return;

    final markQuery = objectbox.comicChapterReadMarkBox
        .query(
          ComicChapterReadMark_.source
              .equals(_from)
              .and(ComicChapterReadMark_.comicId.equals(_comicId)),
        )
        .watch();
    _markSubscription = markQuery.listen(
      (query) => cubit.update(marks: _marksFrom(query.find())),
    );

    final historyQuery = objectbox.unifiedHistoryBox
        .query(
          UnifiedComicHistory_.uniqueKey.equals(
            _service.comicKey(_from, _comicId),
          ),
        )
        .watch();
    _historySubscription = historyQuery.listen(
      (query) => cubit.update(bookmarkOrder: _bookmarkOrderOf(query.find())),
    );
  }

  void _loadInitial() {
    if (!enabled) return;
    cubit.update(
      marks: _marksFrom(_findMarks()),
      bookmarkOrder: _bookmarkOrderOf(_findHistories()),
    );
  }

  /// 一次性读标记：Query 用完必须 close，attach 每次进来都会建一对。
  List<ComicChapterReadMark> _findMarks() {
    final query = objectbox.comicChapterReadMarkBox
        .query(
          ComicChapterReadMark_.source
              .equals(_from)
              .and(ComicChapterReadMark_.comicId.equals(_comicId)),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  List<UnifiedComicHistory> _findHistories() {
    final query = objectbox.unifiedHistoryBox
        .query(
          UnifiedComicHistory_.uniqueKey.equals(
            _service.comicKey(_from, _comicId),
          ),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  static Map<String, ChapterMark> _marksFrom(List<ComicChapterReadMark> rows) {
    final marks = <String, ChapterMark>{};
    for (final row in rows) {
      if (row.deleted) continue;
      marks[row.chapterId] = ChapterMark(
        markedRead: row.markedRead,
        order: row.chapterOrder,
      );
    }
    return marks;
  }

  /// 实际读到哪里：同一部漫画可能留着墓碑行，取未删除那一条。
  static int _bookmarkOrderOf(List<UnifiedComicHistory> rows) {
    for (final row in rows) {
      if (row.deleted) continue;
      return row.chapterOrder;
    }
    return 0;
  }

  // ---------- 查询 ----------

  ChapterReadState stateOf(DownloadChapter chapter) =>
      cubit.state.model.stateOf(chapterId: chapter.id, order: chapter.order);

  // ---------- 动作 ----------

  /// 轻点前导标记：把这一章的**显示状态**翻过来。
  ///
  /// 显示成已读（读到过或已标已读）⇒ 落成「已标记未读」；显示成未读 ⇒ 落成
  /// 「已标记已读」。要回到「没标过、跟着书签推断」用面板里的「清除标记」。
  void toggle(DownloadChapter chapter) {
    writeMarks([chapter], markedRead: !stateOf(chapter).isRead);
  }

  /// 批量：标记为已读。
  void markRead(List<DownloadChapter> chapters) {
    writeMarks(chapters, markedRead: true);
  }

  /// 批量：标记为未读。
  void markUnread(List<DownloadChapter> chapters) {
    writeMarks(chapters, markedRead: false);
  }

  /// 批量：清除人为标记，退回「跟着实际进度走」。
  void clearMarks(List<DownloadChapter> chapters) {
    final targets = _toClear(chapters);
    if (targets.isEmpty) return;
    _service.removeMarksOf(
      _from,
      _comicId,
      targets.map((chapter) => chapter.id),
    );
    final clearedIds = targets.map((chapter) => chapter.id).toSet();
    final next = Map<String, ChapterMark>.from(cubit.state.marks)
      ..removeWhere((chapterId, _) => clearedIds.contains(chapterId));
    cubit.update(marks: next);
    // 不弹 toast：这一章立刻退回书签推断的样子，行上的变化本身就是回执。
  }

  /// 标记至此为已读：显示列表里 [target] 之前（含它）的每一章都落成人为已读。
  ///
  /// 一章一行显式落库，而不是把书签往前推 —— 那样才会弄乱「实际读到哪里」。
  void markThroughRead({
    required DownloadChapter target,
    required List<DownloadChapter> displayChapters,
    required bool displayReversed,
  }) {
    final prefix = chaptersThrough(
      displayChapters: displayChapters,
      targetId: target.id,
      displayReversed: displayReversed,
    );
    if (prefix.isEmpty) return;
    writeMarks(prefix, markedRead: true, labelCount: prefix.length);
  }

  /// 要批量落成 [markedRead] 的章节：已经显式标成同一档的跳过。
  ///
  /// 判据只看「有没有这条显式标记」，不看合成后的显示状态 ——
  /// 书签推出来的已读并不等于标记行存在，用户点「标记未读」就是要压过它。
  List<DownloadChapter> _toWrite(
    List<DownloadChapter> chapters,
    bool markedRead,
  ) {
    final marks = cubit.state.marks;
    return chapters
        .where((chapter) => marks[chapter.id]?.markedRead != markedRead)
        .toList();
  }

  /// 要清除标记的章节：只有真的存在标记行才值得写墓碑。
  ///
  /// 墓碑也会推进 `updatedAt`，给没标过的章写墓碑等于给同步攒无意义的新时间戳。
  List<DownloadChapter> _toClear(List<DownloadChapter> chapters) {
    final marks = cubit.state.marks;
    return chapters.where((chapter) => marks.containsKey(chapter.id)).toList();
  }

  void writeMarks(
    List<DownloadChapter> chapters, {
    required bool markedRead,
    int? labelCount,
  }) {
    if (!enabled) return;
    final targets = _toWrite(chapters, markedRead);
    if (targets.isEmpty) return;

    _service.putMarks([
      for (final chapter in targets)
        _service.buildMark(
          source: _from,
          comicId: _comicId,
          chapterId: chapter.id,
          chapterOrder: chapter.order,
          markedRead: markedRead,
        ),
    ]);

    // 先按本地结果 emit 一次，界面立刻变色；query watch 随后带回落库后的同一份数据。
    cubit.update(
      marks: {
        ...cubit.state.marks,
        for (final chapter in targets)
          chapter.id: ChapterMark(markedRead: markedRead, order: chapter.order),
      },
    );

    final count = labelCount ?? targets.length;
    showInfoToast(
      markedRead
          ? t.comicInfo.markReadDone(count: count)
          : t.comicInfo.markUnreadDone(count: count),
    );
  }

  void dispose() {
    unawaited(_markSubscription?.cancel());
    unawaited(_historySubscription?.cancel());
    _markSubscription = null;
    _historySubscription = null;
    if (!cubit.isClosed) unawaited(cubit.close());
  }
}
