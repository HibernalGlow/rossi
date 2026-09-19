import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/seamless_transition_state.dart';
import 'package:zephyr/page/comic_read/widgets/transition/chapter_transition_card.dart';

/// 阅读模式条目类型：图片或章节过渡卡片。
enum ReadModeEntryType { image, transition }

/// 列/行阅读模式共用的条目数据模型。
class ReadModeEntry {
  const ReadModeEntry._({
    required this.type,
    required this.doc,
    required this.chapterId,
    required this.chapterOrder,
    required this.chapterTitle,
    required this.chapterPageIndex,
    required this.transitionStatus,
    this.previousChapterOrder,
    this.previousChapterTitle,
  });

  const ReadModeEntry.image({
    required Doc doc,
    required String chapterId,
    required int chapterOrder,
    required String chapterTitle,
    required int chapterPageIndex,
  }) : this._(
         type: ReadModeEntryType.image,
         doc: doc,
         chapterId: chapterId,
         chapterOrder: chapterOrder,
         chapterTitle: chapterTitle,
         chapterPageIndex: chapterPageIndex,
         transitionStatus: SeamlessTransitionStatus.ready,
       );

  const ReadModeEntry.transition({
    required int chapterOrder,
    required String chapterTitle,
    required int previousChapterOrder,
    required String previousChapterTitle,
    required SeamlessTransitionStatus transitionStatus,
  }) : this._(
         type: ReadModeEntryType.transition,
         doc: null,
         chapterId: null,
         chapterOrder: chapterOrder,
         chapterTitle: chapterTitle,
         chapterPageIndex: null,
         previousChapterOrder: previousChapterOrder,
         previousChapterTitle: previousChapterTitle,
         transitionStatus: transitionStatus,
       );

  final ReadModeEntryType type;
  final Doc? doc;
  final String? chapterId;
  final int chapterOrder;
  final String chapterTitle;
  final int? chapterPageIndex;
  final int? previousChapterOrder;
  final String? previousChapterTitle;
  final SeamlessTransitionStatus transitionStatus;
}

/// 双页槽位中的单个条目包装。
class ReadModeSlotItem {
  const ReadModeSlotItem({required this.entryIndex, required this.entry});

  final int entryIndex;
  final ReadModeEntry entry;
}

/// 列/行双页模式共用的显示槽位：过渡卡片或左右两张图片。
class ReadModeDoublePageSlot {
  const ReadModeDoublePageSlot._({
    required this.transition,
    required this.left,
    required this.right,
  });

  const ReadModeDoublePageSlot.transition(ReadModeSlotItem transition)
    : this._(transition: transition, left: null, right: null);

  const ReadModeDoublePageSlot.images({
    ReadModeSlotItem? left,
    ReadModeSlotItem? right,
  }) : this._(transition: null, left: left, right: right);

  final ReadModeSlotItem? transition;
  final ReadModeSlotItem? left;
  final ReadModeSlotItem? right;
}

/// 把 [entries] 按顺序合并为双页显示槽位。
///
/// 规则：
/// - 遇到过渡条目单独占一个槽位；
/// - 普通图片两两合并为一个槽位（左 + 可选右），若下一条是过渡则右侧为空；
/// - [insertLeadingBlank] 为 true 时，每个连续图片段开头先插入「空白 | 首页」。
List<ReadModeDoublePageSlot> buildReadModeDoublePageSlots(
  List<ReadModeEntry> entries, {
  bool insertLeadingBlank = false,
}) {
  final slots = <ReadModeDoublePageSlot>[];
  var i = 0;
  var needLeadingBlank = insertLeadingBlank;
  while (i < entries.length) {
    final current = entries[i];
    if (current.type == ReadModeEntryType.transition) {
      slots.add(
        ReadModeDoublePageSlot.transition(
          ReadModeSlotItem(entryIndex: i, entry: current),
        ),
      );
      i++;
      needLeadingBlank = insertLeadingBlank;
      continue;
    }

    if (needLeadingBlank) {
      slots.add(
        ReadModeDoublePageSlot.images(
          right: ReadModeSlotItem(entryIndex: i, entry: current),
        ),
      );
      i++;
      needLeadingBlank = false;
      continue;
    }

    final left = ReadModeSlotItem(entryIndex: i, entry: current);
    i++;
    ReadModeSlotItem? right;
    if (i < entries.length && entries[i].type == ReadModeEntryType.image) {
      right = ReadModeSlotItem(entryIndex: i, entry: entries[i]);
      i++;
    }
    slots.add(ReadModeDoublePageSlot.images(left: left, right: right));
  }
  return slots;
}

/// 把每个显示槽位装着的条目下标按显示顺序列出来。
///
/// 这是「槽位 ↔ 图片」的权威映射，两种配对共用同一份规则：
/// - 单页：每个条目独占一个槽位；
/// - 双页：与 [buildReadModeDoublePageSlots] 同源 —— 过渡卡片独占一个槽位，
///   图片两两合成一个槽位（首页留白时，每段第一张单独占那个左侧空白的槽位）。
///
/// 双页槽位的**首条**就是渲染时排在前面（LTR 下即在左）的那一条，
/// 与 `ReaderSeamlessCubit._forEachDisplaySlot` 的 primary 约定一致。
///
/// [insertLeadingBlank] 只在双页下有意义：单页配对没有配对的「左右」，
/// 自然也没有留白位，传什么都一样。
List<List<int>> buildReadModeSlotEntryIndexes(
  List<ReadModeEntry> entries, {
  required bool enableDoublePage,
  bool insertLeadingBlank = false,
}) {
  if (entries.isEmpty) return const <List<int>>[];

  if (!enableDoublePage) {
    return List<List<int>>.generate(
      entries.length,
      (index) => <int>[index],
      growable: false,
    );
  }

  final slots = buildReadModeDoublePageSlots(
    entries,
    insertLeadingBlank: insertLeadingBlank,
  );
  return List<List<int>>.generate(slots.length, (index) {
    final slot = slots[index];
    final transition = slot.transition;
    if (transition != null) return <int>[transition.entryIndex];
    return <int>[
      if (slot.left != null) slot.left!.entryIndex,
      if (slot.right != null) slot.right!.entryIndex,
    ];
  }, growable: false);
}

/// 配对方式变了以后，把 [slotIndex] 重新指向「同一张图」所在的槽位。
///
/// 切换单/双页（或首页留白）时槽位下标换了含义：同样是第 10 个槽位，
/// 单页下是第 11 张图，双页下是第 21 张图。所以只能**以图为准**重算：
/// 先取当前槽位的首图当锚点（双页 → 单页时停在左页，单页 → 双页时停在原来那张），
/// 再到新配对里找装着这张图的槽位。
///
/// 纯函数，输入相同必然输出相同 —— 「切一下单双页，页数就跳回开头」那类回归
/// 全靠它钉住（见 `test/comic_read/read_mode_pairing_remap_test.dart`）。
int remapReadModeSlotIndexForPairingChange({
  required List<ReadModeEntry> entries,
  required int slotIndex,
  required bool wasDoublePage,
  required bool wasLeadingBlank,
  required bool useDoublePage,
  required bool useLeadingBlank,
}) {
  final nextSlots = buildReadModeSlotEntryIndexes(
    entries,
    enableDoublePage: useDoublePage,
    insertLeadingBlank: useLeadingBlank,
  );
  if (nextSlots.isEmpty) return 0;

  final previousSlots = buildReadModeSlotEntryIndexes(
    entries,
    enableDoublePage: wasDoublePage,
    insertLeadingBlank: wasLeadingBlank,
  );
  if (previousSlots.isEmpty) return slotIndex.clamp(0, nextSlots.length - 1);

  final previousSlot = previousSlots[slotIndex.clamp(
    0,
    previousSlots.length - 1,
  )];
  if (previousSlot.isEmpty) return slotIndex.clamp(0, nextSlots.length - 1);

  final anchorEntryIndex = previousSlot.first;
  for (var i = 0; i < nextSlots.length; i++) {
    if (nextSlots[i].contains(anchorEntryIndex)) return i;
  }

  // 条目顺序在新旧配对里是同一份 ⇒ 新配对必然有槽位装得下锚点。真走到这里
  // 说明上面的分槽规则跟渲染侧漂移了，退化成「夹回合法范围」而不是抛异常。
  return slotIndex.clamp(0, nextSlots.length - 1);
}

/// 为 [entry] 构建一个居中的过渡卡片容器。
///
/// [containerWidth] 为外层容器宽度；[fixedCardSize] 非空时会把卡片约束为固定
/// 尺寸（列模式正方形），否则卡片在水平方向内边距中自适应。
Widget buildReadModeTransitionItem({
  required ReadModeEntry entry,
  required Color backgroundColor,
  required VoidCallback onTap,
  required double containerWidth,
  Size? fixedCardSize,
  EdgeInsets? outerPadding,
  EdgeInsets cardPadding = const EdgeInsets.symmetric(horizontal: 24),
  double minHeight = 320,
  double lineSpacing = 34,
}) {
  Widget card = ChapterTransitionCard(
    previousChapterOrder: entry.previousChapterOrder,
    previousChapterTitle: entry.previousChapterTitle,
    nextChapterOrder: entry.chapterOrder,
    nextChapterTitle: entry.chapterTitle,
    transitionStatus: entry.transitionStatus,
    backgroundColor: backgroundColor,
    minHeight: minHeight,
    padding: cardPadding,
    lineSpacing: lineSpacing,
    onTap: onTap,
  );

  if (fixedCardSize != null) {
    card = SizedBox(
      width: fixedCardSize.width,
      height: fixedCardSize.height,
      child: card,
    );
  }

  return Container(
    color: backgroundColor,
    width: containerWidth,
    alignment: Alignment.center,
    padding: outerPadding,
    child: card,
  );
}
