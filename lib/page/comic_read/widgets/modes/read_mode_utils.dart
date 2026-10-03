import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
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
///
/// [slice] 为这一格要显示原图的哪一半 —— 横长页被拆开时同一个 [entryIndex]
/// 会占两格，靠它区分；其余情况恒为 [PageSlice.full]。
class ReadModeSlotItem {
  const ReadModeSlotItem({
    required this.entryIndex,
    required this.entry,
    this.slice = PageSlice.full,
  });

  final int entryIndex;
  final ReadModeEntry entry;
  final PageSlice slice;
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

/// 把条目序列展开成「一格一条」的展示项：横长页拆成左右两格。
///
/// [isLandscape] 按**原始条目下标**回答这张图是不是横长页 —— 判定要读图片尺寸，
/// 由调用方提供，这里保持纯函数。只有图片条目会被拆：过渡卡片是一张卡片，
/// 拆成两半就变成两张半截卡片。[splitLandscapePages] 关掉时每条占一格，
/// [slice] 全是 [PageSlice.full]，与拆分之行为逐项一致。
List<ReadModeSlotItem> _expandReadModeSlotItems(
  List<ReadModeEntry> entries, {
  required bool splitLandscapePages,
  required SplitDirection direction,
  required bool Function(int entryIndex)? isLandscape,
}) {
  final items = <ReadModeSlotItem>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final split =
        splitLandscapePages &&
        entry.type == ReadModeEntryType.image &&
        (isLandscape?.call(i) ?? false);
    if (split) {
      items.add(
        ReadModeSlotItem(entryIndex: i, entry: entry, slice: direction.first),
      );
      items.add(
        ReadModeSlotItem(entryIndex: i, entry: entry, slice: direction.second),
      );
    } else {
      items.add(ReadModeSlotItem(entryIndex: i, entry: entry));
    }
  }
  return items;
}

/// 单页模式的展示槽位：每格一张（半）图。
///
/// 横长页拆分后一格只画半页，翻页因此多出一格 —— 目录/进度条跳转要落回原图，
/// 得靠 [ReadModeSlotItem.entryIndex] 反查，不能把槽位下标当页码用。
List<ReadModeSlotItem> buildReadModeSinglePageSlots(
  List<ReadModeEntry> entries, {
  bool splitLandscapePages = false,
  SplitDirection direction = SplitDirection.leftFirst,
  bool Function(int entryIndex)? isLandscape,
}) {
  return _expandReadModeSlotItems(
    entries,
    splitLandscapePages: splitLandscapePages,
    direction: direction,
    isLandscape: isLandscape,
  );
}

/// 把 [entries] 按顺序合并为双页显示槽位。
///
/// 规则：
/// - 遇到过渡条目单独占一个槽位；
/// - 普通图片两两合并为一个槽位（左 + 可选右），若下一条是过渡则右侧为空；
/// - [insertLeadingBlank] 为 true 时，每个连续图片段开头先插入「空白 | 首页」。
///
/// 配对在 [buildReadModeSinglePageSlots] 那套展开结果上进行，所以开了横长页拆分后
/// 一个槽位可能是「上一张的右半 + 下一张的左半」。
List<ReadModeDoublePageSlot> buildReadModeDoublePageSlots(
  List<ReadModeEntry> entries, {
  bool insertLeadingBlank = false,
  bool splitLandscapePages = false,
  SplitDirection direction = SplitDirection.leftFirst,
  bool Function(int entryIndex)? isLandscape,
}) {
  final items = _expandReadModeSlotItems(
    entries,
    splitLandscapePages: splitLandscapePages,
    direction: direction,
    isLandscape: isLandscape,
  );

  final slots = <ReadModeDoublePageSlot>[];
  var i = 0;
  var needLeadingBlank = insertLeadingBlank;
  while (i < items.length) {
    final current = items[i];
    if (current.entry.type == ReadModeEntryType.transition) {
      slots.add(ReadModeDoublePageSlot.transition(current));
      i++;
      needLeadingBlank = insertLeadingBlank;
      continue;
    }

    if (needLeadingBlank) {
      slots.add(ReadModeDoublePageSlot.images(right: current));
      i++;
      needLeadingBlank = false;
      continue;
    }

    final left = current;
    i++;
    ReadModeSlotItem? right;
    if (i < items.length && items[i].entry.type == ReadModeEntryType.image) {
      right = items[i];
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

  final previousSlot =
      previousSlots[slotIndex.clamp(0, previousSlots.length - 1)];
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
