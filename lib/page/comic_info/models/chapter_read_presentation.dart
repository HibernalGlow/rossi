import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';

/// 阅读状态 → 界面表示的映射（只有词表和图标，不碰 BuildContext，所以能单测）。
///
/// 拆在这里而不是 `episode_read_marker.dart` 里，是因为那两个槽位组件要拉弹层与
/// 提示组件，测试不该为了断言「四档必须互不相同」而编译整个 app。

/// 一个标记状态该画成什么样。
///
/// [primary] 只给人为判决两档用：推断出来的「读到过」不该借用主色，
/// 否则用户分不清那是系统猜的还是自己标的。
({Glyph glyph, double alpha, bool primary}) readMarkerVisual(
  ChapterReadState state,
) {
  switch (state) {
    case ChapterReadState.unread:
      return (glyph: AppGlyphs.ring, alpha: 0.32, primary: false);
    case ChapterReadState.inferredRead:
      return (glyph: AppGlyphs.check, alpha: 0.42, primary: false);
    case ChapterReadState.manualRead:
      return (glyph: AppGlyphs.checkCircle, alpha: 0.75, primary: true);
    case ChapterReadState.manualUnread:
      return (glyph: AppGlyphs.ring, alpha: 1.0, primary: true);
  }
}

/// 标记状态的文案（tooltip 与面板副标题共用，也是「人话」的唯一披露口）。
String readStateLabel(ChapterReadState state) {
  switch (state) {
    case ChapterReadState.unread:
      return t.comicInfo.readStateUnread;
    case ChapterReadState.inferredRead:
      return t.comicInfo.readStateInferred;
    case ChapterReadState.manualRead:
      return t.comicInfo.readStateManualRead;
    case ChapterReadState.manualUnread:
      return t.comicInfo.readStateManualUnread;
  }
}
