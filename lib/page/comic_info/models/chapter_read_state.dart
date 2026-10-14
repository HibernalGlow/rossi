/// 章节阅读状态的解析口径（纯函数层，不碰 ObjectBox、不碰 Widget）。
///
/// 这里同时管着本功能最关键的一条界线：
///
/// | 事实 | 唯一写入方 | 存哪 |
/// |------|------------|------|
/// | **实际读到哪里** | 阅读器（滚动时周期保存） | `UnifiedComicHistory.chapterOrder` / `pageIndex` |
/// | **用户人为判决** | 详情页的标记操作 | `ComicChapterReadMark`（一章一行） |
///
/// 标记操作**永不**写书签行，书签变化也**永不**删标记行。两者只在这里合成，
/// 所以「读到第 3 章」和「手动把第 80 章标成已读」是两个可以各自独立成立的事实。
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:zephyr/page/download/models/download_chapter.dart';

/// 一个章节的阅读状态，四个值把「来源」也带在类型上。
enum ChapterReadState {
  /// 没读到过，也没标过。
  unread,

  /// 书签推出来的已读：实际读到过这一章。
  inferredRead,

  /// 人为标了已读，书签并没有读到这里。
  manualRead,

  /// 人为标了未读，把书签推断的已读显式拉回来。
  manualUnread;

  /// 是否算「已读」（章节行淡色用这个判据）。
  bool get isRead => this == inferredRead || this == manualRead;

  /// 是否是人为判决（UI 要把这两档和推断档分开显示）。
  bool get isManual => this == manualRead || this == manualUnread;
}

/// 一条人为标记的只读视图。
///
/// [order] 是标记当时记录的章节序号，只有追更统计用它（那边拿不到章节列表）；
/// 详情页逐章显示用不到它，行上是按 `chapterId` 直接查这张表。
@immutable
class ChapterMark {
  const ChapterMark({required this.markedRead, required this.order});

  final bool markedRead;
  final int order;
}

/// 章节阅读状态的解析输入。
///
/// [bookmarkOrder] 是「实际读到哪里」（`UnifiedComicHistory.chapterOrder`，无历史时 0）；
/// [marks] 是 `chapterId -> ChapterMark`，只放**存在标记行**的章节。
///
/// 这里**故意不接受**追更基线（`ComicFollow.lastChapterCount`）：那个数只是徽标基线，
/// 含义是「你上次看到这儿的章数」，不是「你读过」。把它用在行上会让从没打开的章节
/// 显示成已读。追更统计那边另有一套算法（见 [unreadChapterCountWithMarks]）。
class ChapterReadStateModel {
  const ChapterReadStateModel({
    required this.bookmarkOrder,
    required this.marks,
  });

  /// 空模型：没有任何阅读记录，也没有任何标记。
  static const ChapterReadStateModel empty = ChapterReadStateModel(
    bookmarkOrder: 0,
    marks: {},
  );

  final int bookmarkOrder;
  final Map<String, ChapterMark> marks;

  /// 这一章有没有人为标记（章节行要不要占位显示标记符号）。
  bool hasMark(String chapterId) => marks.containsKey(chapterId);

  ChapterReadState stateOf({required String chapterId, required int order}) {
    final mark = marks[chapterId];
    if (mark != null) {
      return mark.markedRead
          ? ChapterReadState.manualRead
          : ChapterReadState.manualUnread;
    }
    // 书签序号是「读到过第 1..N 章」的唯一推断来源。
    return order > 0 && order <= bookmarkOrder
        ? ChapterReadState.inferredRead
        : ChapterReadState.unread;
  }
}

/// 追更未读章数：前缀基线 + 人为标记的修正量。
///
/// 没有任何标记时，结果与「`detectedChapterCount - max(bookmarkOrder, followBaseline)`
/// 再 clamp」逐位相同 —— 这条恒等关系有回归测试兜着，就是「别把追更统计弄乱」的
/// 机器证明：不点标记的用户看到的数字一个都不变。
///
/// 修正量只在既有窗口内生效：
/// - 标了已读、落在基线之后到检测章数之间 ⇒ 少算（用户提前认了这些章）
/// - 标了未读、落在基线之内 ⇒ 多算（用户显式把读过的章拉回未读）
///
/// 基线之前、以及超出检测章数的标记都不参与统计：前者本来就计成已读，后者不属于
/// 这一轮更新窗口。
int unreadChapterCountWithMarks({
  required int detectedChapterCount,
  required int bookmarkOrder,
  required int followBaseline,
  required Map<String, ChapterMark> marks,
}) {
  if (detectedChapterCount <= 0) return 0;
  final rawBaseline = bookmarkOrder > followBaseline
      ? bookmarkOrder
      : followBaseline;
  final baseline = rawBaseline.clamp(0, detectedChapterCount);
  final prefixUnread = detectedChapterCount - baseline;

  var extraUnread = 0;
  var saved = 0;
  for (final mark in marks.values) {
    final order = mark.order;
    if (order <= 0 || order > detectedChapterCount) continue;
    if (mark.markedRead) {
      // 只有基线之后的「提前认了」才减得动；基线之内本来就已算读。
      if (order > baseline) saved++;
    } else if (order <= baseline) {
      extraUnread++;
    }
  }

  return (prefixUnread + extraUnread - saved).clamp(0, detectedChapterCount);
}

/// 追更未读章数，含「有没有更新窗口」这道闸。
///
/// 闸门的口径与改动前一致：**人为标未读不制造「有更新」**。
/// 没在更新窗口里的漫画（已经追平、或压根没追更），标未读只改详情页章节行的显示，
/// 不会让追更页多出红点 —— 否则「我还有章节没读完」和「这本书更新了」就混成一件事。
///
/// 放在纯层而不是 `ComicFollowState` 里，是为了让这条门禁今天就能被遍历参数空间跑出来：
/// 状态类 import 了 ObjectBox 实体，而这个工作树里只要有任何在途改动编不过，
/// 整批实体级测试就一起 `loading failed`（本仓的测试辅助文件还 import 了 `main.dart`）。
int followUnreadChapterCount({
  required bool hasUpdate,
  required int detectedChapterCount,
  required int lastChapterCount,
  required int bookmarkOrder,
  required Map<String, ChapterMark> marks,
}) {
  if (!hasUpdate || detectedChapterCount <= lastChapterCount) return 0;
  return unreadChapterCountWithMarks(
    detectedChapterCount: detectedChapterCount,
    bookmarkOrder: bookmarkOrder,
    followBaseline: lastChapterCount,
    marks: marks,
  );
}

/// 「至此」的范围：显示列表里 [targetId] 之前、含目标的那一段。
///
/// 按**列表下标**切，不按 `DownloadChapter.order`：详情页的行号本来就是宿主按显示
/// 位置自己编排的（插件返回的 order 不可信，见 `eps.dart` 同类注释），倒序显示时
/// 「此前」落在数组另一头。目标不在列表里就返回空，不猜。
List<DownloadChapter> chaptersThrough({
  required List<DownloadChapter> displayChapters,
  required String targetId,
  required bool displayReversed,
}) {
  final index = displayChapters.indexWhere((chapter) => chapter.id == targetId);
  if (index < 0) return const [];
  return displayReversed
      ? displayChapters.sublist(index)
      : displayChapters.sublist(0, index + 1);
}
