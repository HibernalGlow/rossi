import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';

/// 章节人为标记的读写口（`ComicChapterReadMark` 表的唯一持有者）。
///
/// 这里**只有**标记表的操作：书签行（`UnifiedComicHistory`，= 实际读到哪里）
/// 由 `ReaderHistoryService` 独占，本服务一概不碰。两套事实的合成口径在
/// `lib/page/comic_info/models/chapter_read_state.dart`，设计说明见
/// `docs/chapter-read-state.md`。
///
/// 「取消标记」写墓碑（`deleted=true`）而不是物理删行：这张表要参与 LWW 同步，
/// 物理删掉的那一条在对端还是活的，同步回来就复活了。
class ChapterReadMarkService {
  const ChapterReadMarkService();

  static const instance = ChapterReadMarkService();

  /// 同步与唯一约束用的键拼法，与历史表同源；不要反向切分它。
  String markKey(String source, String comicId, String chapterId) =>
      '${source.trim()}:${comicId.trim()}:${chapterId.trim()}';

  /// 追更页/统计侧按漫画聚合用的键，与 `ComicFollow.uniqueKey` 同形。
  String comicKey(String source, String comicId) =>
      '${source.trim()}:${comicId.trim()}';

  /// 某部漫画的人为标记：`chapterId -> ChapterMark`，已排除墓碑行。
  Map<String, ChapterMark> marksOf(String source, String comicId) {
    final query = objectbox.comicChapterReadMarkBox
        .query(
          ComicChapterReadMark_.source
              .equals(source.trim())
              .and(ComicChapterReadMark_.comicId.equals(comicId.trim())),
        )
        .build();
    try {
      return _marksOfRows(query.find());
    } finally {
      query.close();
    }
  }

  /// 全库标记，按 `comicKey` 聚合，供追更统计一次性取数（不逐部漫画查库）。
  Map<String, Map<String, ChapterMark>> allMarksByComic() {
    final grouped = <String, Map<String, ChapterMark>>{};
    for (final row in objectbox.comicChapterReadMarkBox.getAll()) {
      if (row.deleted) continue;
      grouped.putIfAbsent(
        comicKey(row.source, row.comicId),
        () => <String, ChapterMark>{},
      )[row.chapterId] = ChapterMark(
        markedRead: row.markedRead,
        order: row.chapterOrder,
      );
    }
    return grouped;
  }

  static Map<String, ChapterMark> _marksOfRows(
    List<ComicChapterReadMark> rows,
  ) {
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

  /// 写入或复活一批标记。同一批共用一个时间戳，LWW 才有可比性。
  ///
  /// **同 uniqueKey 必须复用库里那一行**：`Box.putMany` 按 ObjectBox id 覆盖，
  /// 拿一条 id=0 的新对象去插「已经有行（哪怕是墓碑）的 uniqueKey」会直接抛
  /// `Unique constraint for ComicChapterReadMark.uniqueKey would be violated`。
  /// 轻点两次同一章、以及「撤销标记后再标一次」都走到这条路，所以先按 uniqueKey
  /// 把旧行捞回来改字段，而不是另起一行。
  ///
  /// [Box.putMany] 自己包一个写事务，整批原子落库（「标记至此为已读」上千行也是
  /// 一次写入），所以这里不再另开 `runInTransaction`。
  void putMarks(Iterable<ComicChapterReadMark> marks, {DateTime? updatedAt}) {
    final list = marks.toList();
    if (list.isEmpty) return;
    final now = (updatedAt ?? DateTime.now().toUtc()).toUtc();
    final box = objectbox.comicChapterReadMarkBox;

    final priorQuery = box
        .query(
          ComicChapterReadMark_.uniqueKey.oneOf([
            for (final mark in list) mark.uniqueKey,
          ]),
        )
        .build();
    final Map<String, ComicChapterReadMark> existing;
    try {
      existing = {for (final row in priorQuery.find()) row.uniqueKey: row};
    } finally {
      priorQuery.close();
    }

    final toPut = <ComicChapterReadMark>[];
    for (final mark in list) {
      final row = existing[mark.uniqueKey];
      if (row == null) {
        mark.updatedAt = now;
        mark.deleted = false;
        toPut.add(mark);
        continue;
      }
      // 复用旧行的 id，只换判决与时间戳。
      row
        ..chapterOrder = mark.chapterOrder
        ..markedRead = mark.markedRead
        ..deleted = false
        ..updatedAt = now;
      toPut.add(row);
    }

    box.putMany(toPut);
    logger.d('[chapterReadMark] 写入 ${toPut.length} 条章节标记');
  }

  /// 墓碑化某部漫画里的一批章节标记（库里没有的键跳过）。
  ///
  /// 一次查询 + 一次 [Box.putMany]：逐键查询在「清除整段标记」这种规模下会变成
  /// N 次查询。
  void removeMarksOf(
    String source,
    String comicId,
    Iterable<String> chapterIds, {
    DateTime? updatedAt,
  }) {
    final targets = chapterIds.map((e) => e.trim()).toSet();
    if (targets.isEmpty) return;
    final now = (updatedAt ?? DateTime.now().toUtc()).toUtc();
    final query = objectbox.comicChapterReadMarkBox
        .query(
          ComicChapterReadMark_.source
              .equals(source.trim())
              .and(ComicChapterReadMark_.comicId.equals(comicId.trim())),
        )
        .build();
    final List<ComicChapterReadMark> tombstones;
    try {
      tombstones = [
        for (final mark in query.find())
          if (!mark.deleted && targets.contains(mark.chapterId)) mark,
      ];
    } finally {
      query.close();
    }
    if (tombstones.isEmpty) return;
    for (final mark in tombstones) {
      mark.deleted = true;
      mark.updatedAt = now;
    }
    objectbox.comicChapterReadMarkBox.putMany(tombstones);
    logger.d('[chapterReadMark] 墓碑化 ${tombstones.length} 条章节标记');
  }

  /// 组装一条标记（`updatedAt`/`deleted` 由 [putMarks] 统一落）。
  ///
  /// 不存章节名：这一章叫什么以当前章节列表为准，标记表整表要进同步快照，
  /// 把一个没人读的可变字符串按章抄一份进去是最亏的体积。
  ComicChapterReadMark buildMark({
    required String source,
    required String comicId,
    required String chapterId,
    required int chapterOrder,
    required bool markedRead,
  }) {
    final now = DateTime.now().toUtc();
    return ComicChapterReadMark(
      uniqueKey: markKey(source, comicId, chapterId),
      source: source.trim(),
      comicId: comicId.trim(),
      chapterId: chapterId.trim(),
      chapterOrder: chapterOrder,
      markedRead: markedRead,
      updatedAt: now,
      deleted: false,
    );
  }
}
