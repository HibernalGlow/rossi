import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_page_order_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_cubit.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/util/context/context_extensions.dart';

/// 当前画面的那一张图（章序 + 章节内源下标）。
class ReaderPageAnchor {
  const ReaderPageAnchor({
    required this.chapterOrder,
    required this.chapterPageIndex,
  });

  final int chapterOrder;
  final int chapterPageIndex;
}

/// 换页面排序档位，并把画面**钉回同一张图**。
///
/// 为什么不是「写个设置项就完事」：档位一改，条目序列整个重排，而阅读器停在
/// 「第 N 格」上 —— 切倒序会直接把人扔到对侧那一页。用户点的是「换个顺序看」，
/// 不是「换个页」。所以这里先记下当前格画的是哪一页，写完设置、等新排列建好，
/// 再按 (章序, 源下标) 把它找回来。
///
/// 为什么不监听设置变化来做这件事：`readerPageOrderMode` 的写者只有面板自己，
/// 而这条路径还要带一份**只在换档这一刻才知道**的信息（旧排列下的当前页）。
/// 把它做成设置监听器，就得为「别处也会改这个字段」这个假设养一份旧值缓存。
Future<void> applyReaderPageOrder({
  required BuildContext context,
  required ReaderPageOrderMode mode,
  List<int>? customOrder,
}) async {
  final seamlessCubit = context.read<ReaderSeamlessCubit>();
  final orderCubit = context.read<ReaderPageOrderCubit>();
  final readSetting = context.readEffectiveReadSetting();

  final anchor = currentReaderPageAnchor(
    context: context,
    readSetting: readSetting,
  );

  // 手动那一档：排列与档位一起提交，否则切到 custom 的那一帧会先按
  // 「没有排列」（= 退回原样）铺一次，画面闪一下才跳回正确位置。
  final chapterId = anchor == null ? null : _chapterIdOf(seamlessCubit, anchor);
  if (customOrder != null && chapterId != null) {
    orderCubit.applyCustomOrder(chapterId, customOrder);
  }

  context.read<GlobalSettingCubit>().updateReadSetting(
    (s) => s.copyWith(readerPageOrderMode: mode),
  );

  if (anchor == null || !context.mounted) return;
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;

  final nextSetting = context.readEffectiveReadSetting();
  final targetSlot = seamlessCubit.globalSlotForImagePage(
    chapterOrder: anchor.chapterOrder,
    chapterPageIndex: anchor.chapterPageIndex,
    readSetting: nextSetting,
  );
  if (targetSlot == null) return;
  final currentSlot = context.read<ReaderCubit>().state.currentSlot;
  if (targetSlot == currentSlot) return;
  await ReaderSessionCoordinator.instance.jumpTo(targetSlot);
}

/// 当前格画的那一张图；过渡卡片或还没建出条目时返回 `null`。
ReaderPageAnchor? currentReaderPageAnchor({
  required BuildContext context,
  required ReadSettingState readSetting,
}) {
  final slot = context.read<ReaderCubit>().state.currentSlot;
  final entries = context.read<ReaderSeamlessCubit>().imageEntriesAtGlobalSlot(
    globalSlot: slot,
    readSetting: readSetting,
  );
  for (final entry in entries) {
    final pageIndex = entry.chapterPageIndex;
    if (pageIndex != null) {
      return ReaderPageAnchor(
        chapterOrder: entry.chapterOrder,
        chapterPageIndex: pageIndex,
      );
    }
  }
  return null;
}

/// 锚点所在章的 `epId` —— 手动排列是按章存的。
String? _chapterIdOf(ReaderSeamlessCubit cubit, ReaderPageAnchor anchor) {
  for (final chapter in cubit.state.loadedChapters) {
    if (chapter.order == anchor.chapterOrder) return chapter.epInfo.epId;
  }
  return null;
}

/// 当前章的页表；阅读器还没进入成功态时返回 `null`。
///
/// 优先按 `state.currentChapterOrder` 找，找不到就退回队列第一节 ——
/// 章身份只在刚进书、还没观测过槽位时可能空着，那时队列里本来只有初始章。
NormalComicEpInfo? currentReaderChapterEpInfo({required BuildContext context}) {
  final cubit = context.read<ReaderSeamlessCubit>();
  final chapters = cubit.state.loadedChapters;
  if (chapters.isEmpty) return null;
  final order = cubit.state.currentChapterOrder;
  for (final chapter in chapters) {
    if (chapter.order == order) return chapter.epInfo;
  }
  return chapters.first.epInfo;
}
