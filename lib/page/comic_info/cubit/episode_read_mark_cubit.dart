import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';

/// 章节阅读状态（人为标记 + 书签推断）在详情页的只读快照。
///
/// 与 [EpisodeDownloadStatusCubit] 同一套分工：状态由这个 cubit 持有，
/// [EpisodeReadMarkController] 负责取数与写入，章节行按章订阅自己那一份，
/// 别章变化不重建整列表。
class EpisodeReadMarkState {
  const EpisodeReadMarkState({this.marks = const {}, this.bookmarkOrder = 0});

  /// `chapterId -> ChapterMark`，只含存在标记行（非墓碑）的章节。
  final Map<String, ChapterMark> marks;

  /// 实际读到哪里：`UnifiedComicHistory.chapterOrder`，无历史时 0。
  final int bookmarkOrder;

  ChapterReadStateModel get model =>
      ChapterReadStateModel(bookmarkOrder: bookmarkOrder, marks: marks);

  EpisodeReadMarkState copyWith({
    Map<String, ChapterMark>? marks,
    int? bookmarkOrder,
  }) {
    return EpisodeReadMarkState(
      marks: marks ?? this.marks,
      bookmarkOrder: bookmarkOrder ?? this.bookmarkOrder,
    );
  }
}

class EpisodeReadMarkCubit extends Cubit<EpisodeReadMarkState> {
  EpisodeReadMarkCubit() : super(const EpisodeReadMarkState());

  void update({Map<String, ChapterMark>? marks, int? bookmarkOrder}) {
    emit(state.copyWith(marks: marks, bookmarkOrder: bookmarkOrder));
  }
}
