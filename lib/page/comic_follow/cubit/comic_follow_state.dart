import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';

part 'comic_follow_state.freezed.dart';

enum ComicFollowStatus { initial, loading, success, failure }

enum ComicFollowFilter { all, unread }

enum ComicFollowSort { lastRead, update }

@freezed
abstract class ComicFollowState with _$ComicFollowState {
  const ComicFollowState._();

  const factory ComicFollowState({
    @Default(ComicFollowStatus.initial) ComicFollowStatus status,
    @Default(<ComicFollow>[]) List<ComicFollow> items,
    @Default(false) bool isCheckingUpdates,
    @Default('') String result,
    @Default(0) int revision,
    @Default(<String, UnifiedComicHistory>{})
    Map<String, UnifiedComicHistory> histories,
    @Default(<String, Map<String, ChapterMark>>{})
    Map<String, Map<String, ChapterMark>> chapterMarks,
    @Default(ComicFollowFilter.all) ComicFollowFilter filter,
    @Default(ComicFollowSort.lastRead) ComicFollowSort sort,
  }) = _ComicFollowState;

  int get updateCount => items.where(hasUnreadUpdate).length;

  List<ComicFollow> get visibleItems {
    final result = items
        .where(
          (item) => filter == ComicFollowFilter.all || hasUnreadUpdate(item),
        )
        .toList();
    result.sort(_compareItems);
    return result;
  }

  UnifiedComicHistory? historyFor(ComicFollow follow) =>
      histories[follow.uniqueKey];

  /// 这部漫画的人为标记（`chapterId -> ChapterMark`）。
  Map<String, ChapterMark> marksFor(ComicFollow follow) =>
      chapterMarks[follow.uniqueKey] ?? const {};

  /// 未读章数：闸门与修正量都在 `followUnreadChapterCount`（纯层）里，
  /// 那里有遍历参数空间的恒等门禁；这里只负责按 uniqueKey 取数。
  int unreadChapterCount(ComicFollow follow) {
    final history = historyFor(follow);
    return followUnreadChapterCount(
      hasUpdate: follow.hasUpdate,
      detectedChapterCount: follow.detectedChapterCount,
      lastChapterCount: follow.lastChapterCount,
      bookmarkOrder: history?.chapterOrder ?? 0,
      marks: marksFor(follow),
    );
  }

  bool hasUnreadUpdate(ComicFollow follow) => unreadChapterCount(follow) > 0;

  int _compareItems(ComicFollow left, ComicFollow right) {
    if (filter == ComicFollowFilter.unread) {
      final rightUnread = hasUnreadUpdate(right);
      final leftUnread = hasUnreadUpdate(left);
      final unreadCompare = rightUnread == leftUnread
          ? 0
          : (rightUnread ? 1 : -1);
      if (unreadCompare != 0) return unreadCompare;
    }

    if (sort == ComicFollowSort.lastRead) {
      final leftTime = historyFor(left)?.lastReadAt;
      final rightTime = historyFor(right)?.lastReadAt;
      if (leftTime == null && rightTime != null) return 1;
      if (leftTime != null && rightTime == null) return -1;
      if (leftTime != null && rightTime != null) {
        final timeCompare = rightTime.compareTo(leftTime);
        if (timeCompare != 0) return timeCompare;
      }
    } else {
      final timeCompare = right.updateTime.compareTo(left.updateTime);
      if (timeCompare != 0) return timeCompare;
    }

    return right.createdAt.compareTo(left.createdAt);
  }

  bool isFollowing(String source, String comicId) {
    final key = '${source.trim()}:${comicId.trim()}';
    return items.any((item) => item.uniqueKey == key && !item.deleted);
  }
}
