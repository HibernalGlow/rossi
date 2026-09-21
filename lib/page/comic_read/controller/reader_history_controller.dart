import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_history_service.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 阅读器历史记录控制器。
///
/// 封装历史服务调用、状态文本同步与历史位置恢复。
/// 所有 ObjectBox 与 worker isolate 副作用均已下沉到 [ReaderHistoryService]。
class ReaderHistoryController {
  ReaderHistoryController({
    required this.comicId,
    required this.order,
    required this.from,
    required this.comicInfo,
    required this.stringSelectCubit,
    required this.getStoredPageIndex,
    required this.getCurrentChapterOrder,
    required this.getEpInfo,
    required this.isHistoryEntry,
    required this.jumpToGlobalSlot,
    this.entryHintName,
  });

  final String comicId;
  final int order;
  final String from;
  final dynamic comicInfo;
  final StringSelectCubit stringSelectCubit;
  final int Function() getStoredPageIndex;
  final int Function() getCurrentChapterOrder;
  final NormalComicEpInfo Function() getEpInfo;
  final bool Function() isHistoryEntry;
  final Future<void> Function(int target) jumpToGlobalSlot;

  /// 松散图片被提升到「所在目录那一本书」时，点开的那一张的文件名。
  final String? entryHintName;

  final _service = ReaderHistoryService.instance;
  StreamSubscription<String>? _statusSubscription;
  bool isSkipped = false;
  bool _stopped = false;

  Future<void> init() async {
    await _service.loadHistory(
      source: from,
      comicId: comicId,
      comicInfo: comicInfo,
    );
    _statusSubscription = _service.statusStream.listen((status) {
      if (!stringSelectCubit.isClosed) {
        stringSelectCubit.setDate(status);
      }
    });
  }

  void markLoaded() {
    _service.markLoaded();
    _service.startPeriodicSave(
      () => HistorySnapshot(
        pageIndex: getStoredPageIndex(),
        chapterOrder: getCurrentChapterOrder(),
        epInfo: getEpInfo(),
      ),
    );
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _statusSubscription?.cancel();
    await _service.stop();
  }

  int getHistoryPageIndex() => _service.lastPageIndex;

  /// 点开的那一张在当前这一本的页表里排第几；对不上（图片被移动、改名，或者
  /// 目录里根本没有它）时返回 null，退回按历史续读。
  int? _entryHintDocIndex() {
    final hint = entryHintName;
    if (hint == null || hint.isEmpty) return null;
    return findLocalEntryHintIndex(getEpInfo().docs, hint);
  }

  /// 章节成功加载后恢复历史阅读位置，仅执行一次。
  Future<void> handleHistoryScroll(BuildContext context) async {
    final isLocal = isLocalComicSource(from, comicId);
    final hintIndex = isLocal ? _entryHintDocIndex() : null;
    // 点击的意图优先于同一个目录的上次位置；历史页码是 displayPage + 1，
    // 因此 0 基的页下标加 2 正好落在同一刻度上。
    final historyIndex = hintIndex != null
        ? hintIndex + 2
        : getHistoryPageIndex();
    var shouldScroll =
        (isHistoryEntry() || (isLocal && historyIndex > 1)) && !isSkipped;
    if (shouldScroll) {
      shouldScroll &= (historyIndex - 1 != 0);
    }

    if (!shouldScroll) {
      if (isHistoryEntry() || (isLocal && historyIndex > 1) || isSkipped) {
        return;
      }
      final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
      final seamlessCubit = context.read<ReaderSeamlessCubit>();
      if (!seamlessCubit.isSeamlessEnabled()) {
        isSkipped = true;
        return;
      }

      final totalSlots = context.read<ReaderCubit>().state.totalSlots;
      if (totalSlots <= 0) return;
      final targetIndex = seamlessCubit
          .resolveEntryDefaultGlobalSlot(readSetting)
          .clamp(0, totalSlots - 1);
      if (targetIndex == 0) {
        isSkipped = true;
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(Duration.zero);
        if (!context.mounted) return;
        await jumpToGlobalSlot(targetIndex);
        isSkipped = true;
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 延迟到下一事件循环，确保列表/分页容器完成首次布局。
      await Future.delayed(Duration.zero);
      if (!context.mounted) return;

      final cubit = context.read<ReaderCubit>();
      final globalSettingState = context.read<GlobalSettingCubit>().state;
      final totalSlots = cubit.state.totalSlots;
      if (totalSlots <= 0) return;

      final enableDoublePage = globalSettingState.readSetting.doublePageMode;
      var targetIndex = getSlotIndexFromStoredHistoryPage(
        storedHistoryPage: historyIndex,
        enableDoublePage: enableDoublePage,
        insertLeadingBlank:
            enableDoublePage &&
            globalSettingState.readSetting.doublePageLeadingBlank,
      );
      final seamlessCubit = context.read<ReaderSeamlessCubit>();
      if (seamlessCubit.isSeamlessEnabled()) {
        targetIndex = seamlessCubit.resolveHistoryGlobalSlot(
          targetIndex,
          globalSettingState.readSetting,
        );
      }
      targetIndex = targetIndex.clamp(0, totalSlots - 1);
      await jumpToGlobalSlot(targetIndex);
      isSkipped = true;
    });
  }
}
