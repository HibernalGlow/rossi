import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_state.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/get_local_info.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/method/get_plugin_read_snapshot.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/model/seamless_transition_state.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';
import 'package:zephyr/type/enum.dart';

/// 边界解析动作的结果。
///
/// [didLoad] 表示是否实际加载了章节；[targetGlobalSlot] 表示加载后需要跳转到的
/// 全局槽位（prepend 场景下需要把当前视觉位置平移），为 null 时无需跳转。
/// [prependedSlotCount] 仅在 prepend 场景下非 0，供 UI 层同步修正滚动偏移。
class SeamlessBoundaryResult {
  const SeamlessBoundaryResult({
    this.didLoad = false,
    this.targetGlobalSlot,
    this.prependedSlotCount = 0,
  });

  final bool didLoad;
  final int? targetGlobalSlot;
  final int prependedSlotCount;
}

/// 管理竖向半无缝章节拼接的状态与逻辑。
///
/// 职责：
/// - 维护已加载章节列表、过渡卡片状态、前后章预加载。
/// - 提供列/行模式条目构建、总槽位计算、全局/本地槽位映射。
/// - 在滚动到边界或点击过渡卡片时触发章节加载。
///
/// 注意：该类不直接操作 [ReaderCubit]；UI 层负责把 Cubit 的输出同步到阅读器状态。
class ReaderSeamlessCubit extends Cubit<ReaderSeamlessState> {
  ReaderSeamlessCubit({
    required this._comicId,
    required this._from,
    required this._type,
    required this._comicInfo,
    required this._initialOrder,
    this.pageOrderResolver,
  }) : super(const ReaderSeamlessState()) {
    _initChapterCatalog();
  }

  final String _comicId;
  final String _from;
  final ComicEntryType _type;
  final dynamic _comicInfo;
  final int _initialOrder;

  /// 章节内页面显示顺序的解析器：给「显示位置 → 源下标」的排列。
  ///
  /// 由宿主注入，因为这个 cubit 只管章节队列与槽位，不该认识读设置里的档位、
  /// 也不该认识存手动排列的那个 cubit。`null` 一律按图源顺序 = 改造前的行为。
  ///
  /// 返回值长度必须等于传入页表的长度；对不上时按原样顺序铺，
  /// 宁可「这一章暂时没排序」也不要越界取页。
  final List<int> Function(String chapterId, List<Doc> docs)? pageOrderResolver;

  /// 这一章按显示顺序排好的源下标；页数少一个都会退回原样。
  List<int> _pageOrderOf(String chapterId, List<Doc> docs) {
    final resolver = pageOrderResolver;
    if (resolver == null || docs.isEmpty) {
      return List<int>.generate(docs.length, (index) => index);
    }
    final order = resolver(chapterId, docs);
    if (order.length != docs.length) {
      return List<int>.generate(docs.length, (index) => index);
    }
    return order;
  }

  static const int _nextPrefetchThreshold = 2;
  static const int _nextAutoResolveThreshold = 1;

  List<UnifiedComicChapterRef> _chapterRefs = <UnifiedComicChapterRef>[];
  Map<int, int> _chapterOrderToCatalogIndex = <int, int>{};

  bool get _isDownloadEntryType =>
      _type == ComicEntryType.download ||
      _type == ComicEntryType.historyAndDownload;

  // ==================== 生命周期 / 初始化 ====================

  void _initChapterCatalog() {
    _chapterRefs = resolveUnifiedComicChapters(_comicInfo, _from);
    if (_chapterRefs.isEmpty && isLocalComicSource(_from, _comicId)) {
      _chapterRefs = <UnifiedComicChapterRef>[
        UnifiedComicChapterRef(
          id: _comicId,
          name: t.reader.wholeBook,
          order: _initialOrder,
        ),
      ];
    }
    _chapterOrderToCatalogIndex = <int, int>{};
    for (var i = 0; i < _chapterRefs.length; i++) {
      _chapterOrderToCatalogIndex[_chapterRefs[i].order] = i;
    }
  }

  /// 初始章节加载成功后调用，把初始章节加入已加载队列。
  void bootstrap(
    NormalComicEpInfo initialEpInfo,
    int initialOrder,
    ReadSettingState readSetting,
  ) {
    if (state.loadedChapters.isNotEmpty) return;
    _addLoadedChapter(order: initialOrder, epInfo: initialEpInfo);
    _ensureEdgeTransitionsVisible(notify: false);
    final contextByOrder = _resolveImageSlotContextByChapterOrder(
      chapterOrder: initialOrder,
      readSetting: readSetting,
    );
    _emit(
      state.copyWith(
        currentChapterOrder: initialOrder,
        currentChapterStartSlot: contextByOrder?.chapterStartSlot ?? 0,
        currentChapterSlotCount:
            contextByOrder?.chapterImageCount ??
            getReadModeSlotCount(
              imageCount: initialEpInfo.length,
              enableDoublePage: readSetting.doublePageMode,
              insertLeadingBlank: _insertLeadingBlank(readSetting),
            ),
      ),
    );
    unawaited(_prefetchNextChaptersIfNeeded(readSetting.preloadChapterCount));
  }

  // ==================== 公共查询接口 ====================

  bool isSeamlessEnabled() => _catalogChapters().length > 1;

  bool canLoadPreviousChapter() {
    final chapters = _catalogChapters();
    if (chapters.isEmpty || state.loadedChapters.isEmpty) return false;
    final index = _catalogIndexByOrder(state.loadedChapters.first.order);
    return index > 0;
  }

  bool canLoadNextChapter() {
    final chapters = _catalogChapters();
    if (chapters.isEmpty || state.loadedChapters.isEmpty) return false;
    final index = _catalogIndexByOrder(state.loadedChapters.last.order);
    if (index < 0) return false;
    return index < chapters.length - 1;
  }

  int? get currentChapterOrder => state.currentChapterOrder;

  int get currentChapterStartSlot => state.currentChapterStartSlot;

  int get currentChapterSlotCount => state.currentChapterSlotCount;

  /// 返回当前槽位之后需要提前缓存的图片条目，按显示顺序排列。
  ///
  /// 这里按显示槽位遍历而不是直接按 entry 下标切片，兼容双页模式和章节
  /// 过渡卡片，避免把“预加载数量”误算成槽位数量。
  List<ReadModeEntry> resolveImageEntriesForPrefetch({
    required int globalSlot,
    required ReadSettingState readSetting,
    required int count,
  }) {
    if (count <= 0) return const <ReadModeEntry>[];

    final entries = isColumnReadMode(readSetting.readMode)
        ? buildColumnEntries(readSetting)
        : buildRowEntries(readSetting);
    if (entries.isEmpty) return const <ReadModeEntry>[];

    final result = <ReadModeEntry>[];
    // 拆分后同一页会连着占两个槽位（左半、右半），预取按槽位走就会把它数两次。
    // 所以按条目下标去重：提前缓存的是「后面的几张图」，不是「同一个半页」。
    final addedEntryIndexes = <int>{};
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isColumnReadMode(readSetting.readMode) ? null : _splitAtOrNull,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        if (slotIndex <= globalSlot || result.length >= count) return;

        void addImageEntry(int entryIndex) {
          if (result.length >= count) return;
          if (!addedEntryIndexes.add(entryIndex)) return;
          final entry = entries[entryIndex];
          if (entry.type == ReadModeEntryType.image) {
            result.add(entry);
          }
        }

        addImageEntry(primaryEntryIndex);
        if (secondaryEntryIndex != null) {
          addImageEntry(secondaryEntryIndex);
        }
      },
    );
    return result;
  }

  /// 槽位上正在显示的那几张图（双页=两张，横长页拆半=同一页的两半）。
  ///
  /// 与预取那条共用 [_forEachDisplaySlot]，所以「哪一格画的是哪一页」只有一处判据：
  /// 页面排序换档要把画面钉回同一张图、幻灯片要在下一页真的解出来才推进，
  /// 两边问的都是这一个问题。
  List<ReadModeEntry> imageEntriesAtGlobalSlot({
    required int globalSlot,
    required ReadSettingState readSetting,
  }) {
    final entries = isColumnReadMode(readSetting.readMode)
        ? buildColumnEntries(readSetting)
        : buildRowEntries(readSetting);
    if (entries.isEmpty) return const <ReadModeEntry>[];

    final result = <ReadModeEntry>[];
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isColumnReadMode(readSetting.readMode) ? null : _splitAtOrNull,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        if (slotIndex != globalSlot) return;
        void addImageEntry(int entryIndex) {
          final entry = entries[entryIndex];
          if (entry.type == ReadModeEntryType.image) result.add(entry);
        }

        addImageEntry(primaryEntryIndex);
        if (secondaryEntryIndex != null) {
          addImageEntry(secondaryEntryIndex);
        }
      },
    );
    return result;
  }

  /// 某一页（章序 + 章节内源下标）在当前排列里占哪个槽位；找不到返回 `null`。
  ///
  /// 换排序档位时靠它把画面钉回**同一张图**：不钉的话，切「倒序」会整章跳到
  /// 对侧那一页上 —— 用户点的是「换个顺序看」，不是「换个页」。
  int? globalSlotForImagePage({
    required int chapterOrder,
    required int chapterPageIndex,
    required ReadSettingState readSetting,
  }) {
    final entries = isColumnReadMode(readSetting.readMode)
        ? buildColumnEntries(readSetting)
        : buildRowEntries(readSetting);
    if (entries.isEmpty) return null;

    int? found;
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isColumnReadMode(readSetting.readMode) ? null : _splitAtOrNull,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        if (found != null) return;
        bool matches(int entryIndex) {
          final entry = entries[entryIndex];
          return entry.type == ReadModeEntryType.image &&
              entry.chapterOrder == chapterOrder &&
              entry.chapterPageIndex == chapterPageIndex;
        }

        if (matches(primaryEntryIndex) ||
            (secondaryEntryIndex != null && matches(secondaryEntryIndex))) {
          found = slotIndex;
        }
      },
    );
    return found;
  }

  UnifiedComicChapterRef? chapterRefByOrder(int order) {
    final chapters = _catalogChapters();
    final index = _catalogIndexByOrder(order);
    if (index < 0 || index >= chapters.length) return null;
    return chapters[index];
  }

  int catalogIndexByOrder(int order) => _catalogIndexByOrder(order);

  int get catalogLength => _catalogChapters().length;

  String chapterTitleByOrder(int order) {
    final loaded = state.loadedChapters.where(
      (chapter) => chapter.order == order,
    );
    if (loaded.isNotEmpty) {
      final title = loaded.first.epInfo.epName.trim();
      if (title.isNotEmpty) return title;
    }
    final chapters = _catalogChapters();
    final index = _catalogIndexByOrder(order);
    if (index >= 0 && index < chapters.length) {
      final name = chapters[index].name.trim();
      if (name.isNotEmpty) return name;
    }
    return t.reader.chapterOrder(order: order);
  }

  // ==================== 条目构建与槽位计算 ====================

  List<ReadModeEntry> buildColumnEntries(ReadSettingState readSetting) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) {
      final epInfo = state.loadedChapters.isNotEmpty
          ? state.loadedChapters.first.epInfo
          : NormalComicEpInfo();
      final order = _pageOrderOf(epInfo.epId, epInfo.docs);
      return List<ReadModeEntry>.generate(epInfo.docs.length, (position) {
        final pageIndex = order[position];
        final doc = epInfo.docs[pageIndex];
        return ReadModeEntry.image(
          doc: doc,
          chapterId: epInfo.epId,
          chapterOrder: _initialOrder,
          chapterTitle: epInfo.epName,
          chapterPageIndex: pageIndex,
        );
      }, growable: false);
    }

    final entries = <ReadModeEntry>[];
    for (var i = 0; i < state.loadedChapters.length; i++) {
      final chapter = state.loadedChapters[i];
      final chapterOrder = chapter.order;

      if (_shouldShowTransition(nextOrder: chapterOrder)) {
        final previousOrder = _previousOrderOf(chapterOrder);
        if (previousOrder != null) {
          entries.add(
            ReadModeEntry.transition(
              chapterOrder: chapterOrder,
              chapterTitle: chapterTitleByOrder(chapterOrder),
              previousChapterOrder: previousOrder,
              previousChapterTitle: chapterTitleByOrder(previousOrder),
              transitionStatus: _transitionStatusByNextOrderValue(chapterOrder),
            ),
          );
        }
      }

      final chapterDocs = chapter.epInfo.docs;
      for (final pageIndex in _pageOrderOf(chapter.epInfo.epId, chapterDocs)) {
        entries.add(
          ReadModeEntry.image(
            doc: chapterDocs[pageIndex],
            chapterId: chapter.epInfo.epId,
            chapterOrder: chapter.order,
            chapterTitle: chapter.epInfo.epName,
            chapterPageIndex: pageIndex,
          ),
        );
      }
    }

    final endBoundaryNextOrder = _nextOrderOf(state.loadedChapters.last.order);
    if (endBoundaryNextOrder != null &&
        _shouldShowTransition(nextOrder: endBoundaryNextOrder)) {
      final previousOrder = _previousOrderOf(endBoundaryNextOrder);
      if (previousOrder != null) {
        entries.add(
          ReadModeEntry.transition(
            chapterOrder: endBoundaryNextOrder,
            chapterTitle: chapterTitleByOrder(endBoundaryNextOrder),
            previousChapterOrder: previousOrder,
            previousChapterTitle: chapterTitleByOrder(previousOrder),
            transitionStatus: _transitionStatusByNextOrderValue(
              endBoundaryNextOrder,
            ),
          ),
        );
      }
    }

    return entries;
  }

  /// 估算列模式下目标全局槽位对应的滚动偏移（不含 paddingTop 与微调值）。
  ///
  /// 用于在历史恢复、滑动条跳转等场景中先做粗略同步偏移，
  /// 再由 observerController.jumpTo 做精确修正，减弱视觉跳变。
  ///
  /// 必须按**槽位**累加，而不是按条目：双页下每张图只占半宽、两张并排算一行，
  /// 按条目全宽累加会比实际高一倍以上 —— 粗略跳转先冲过头，`jumpTo` 的精确
  /// 修正又够不着（目标根本还没建出来），表现为「跳过去停在不该停的地方」。
  double estimateColumnHeightBeforeGlobalSlot(
    int targetGlobalSlot,
    ReadSettingState readSetting,
    ImageSizeCubit imageSizeCubit,
    double contentWidth,
  ) {
    if (targetGlobalSlot <= 0) return 0.0;

    final entries = buildColumnEntries(readSetting);
    if (entries.isEmpty) return 0.0;

    final enableDoublePage = readSetting.doublePageMode;
    final panelWidth = enableDoublePage ? contentWidth / 2 : contentWidth;

    double entryHeight(int entryIndex) {
      final entry = entries[entryIndex];
      if (entry.type == ReadModeEntryType.transition) return contentWidth;

      final size = imageSizeCubit.state.getSizeValue(
        resolveStableSizeCacheIndex(
          chapterOrder: entry.chapterOrder,
          localPageIndex: entry.chapterPageIndex ?? 0,
        ),
      );
      if (size.width <= 0 || size.height <= 0) {
        final defaultWidth = imageSizeCubit.state.defaultWidth;
        if (defaultWidth <= 0) return imageSizeCubit.state.defaultHeight;
        return imageSizeCubit.state.defaultHeight * (panelWidth / defaultWidth);
      }
      return size.height * (panelWidth / size.width);
    }

    var totalHeight = 0.0;
    var slotCount = 0;
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        slotCount = slotIndex + 1;
        if (slotIndex >= targetGlobalSlot) return;

        // 双页一行的高度取左右两张里更高的那张（与 `_buildColumnDoublePageImage`
        // 的 rowHeight 同规则）。
        var slotHeight = entryHeight(primaryEntryIndex);
        if (secondaryEntryIndex != null) {
          final secondaryHeight = entryHeight(secondaryEntryIndex);
          if (secondaryHeight > slotHeight) slotHeight = secondaryHeight;
        }
        totalHeight += slotHeight;
      },
    );

    // 目标槽位不存在（越界）时不猜，交给 observerController 自己兜。
    if (targetGlobalSlot >= slotCount) return 0.0;
    return totalHeight;
  }

  List<ReadModeEntry> buildRowEntries(ReadSettingState readSetting) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) {
      final epInfo = state.loadedChapters.isNotEmpty
          ? state.loadedChapters.first.epInfo
          : NormalComicEpInfo();
      final order = _pageOrderOf(epInfo.epId, epInfo.docs);
      return List<ReadModeEntry>.generate(epInfo.docs.length, (position) {
        final pageIndex = order[position];
        final doc = epInfo.docs[pageIndex];
        return ReadModeEntry.image(
          doc: doc,
          chapterId: epInfo.epId,
          chapterOrder: _initialOrder,
          chapterTitle: epInfo.epName,
          chapterPageIndex: pageIndex,
        );
      }, growable: false);
    }

    final entries = <ReadModeEntry>[];
    for (var i = 0; i < state.loadedChapters.length; i++) {
      final chapter = state.loadedChapters[i];
      final chapterOrder = chapter.order;
      if (_shouldShowTransition(nextOrder: chapterOrder)) {
        final previousOrder = _previousOrderOf(chapterOrder);
        if (previousOrder != null) {
          entries.add(
            ReadModeEntry.transition(
              chapterOrder: chapterOrder,
              chapterTitle: chapterTitleByOrder(chapterOrder),
              previousChapterOrder: previousOrder,
              previousChapterTitle: chapterTitleByOrder(previousOrder),
              transitionStatus: _transitionStatusByNextOrderValue(chapterOrder),
            ),
          );
        }
      }
      final chapterDocs = chapter.epInfo.docs;
      for (final pageIndex in _pageOrderOf(chapter.epInfo.epId, chapterDocs)) {
        entries.add(
          ReadModeEntry.image(
            doc: chapterDocs[pageIndex],
            chapterId: chapter.epInfo.epId,
            chapterOrder: chapter.order,
            chapterTitle: chapter.epInfo.epName,
            chapterPageIndex: pageIndex,
          ),
        );
      }
    }

    final endBoundaryNextOrder = _nextOrderOf(state.loadedChapters.last.order);
    if (endBoundaryNextOrder != null &&
        _shouldShowTransition(nextOrder: endBoundaryNextOrder)) {
      final previousOrder = _previousOrderOf(endBoundaryNextOrder);
      if (previousOrder != null) {
        entries.add(
          ReadModeEntry.transition(
            chapterOrder: endBoundaryNextOrder,
            chapterTitle: chapterTitleByOrder(endBoundaryNextOrder),
            previousChapterOrder: previousOrder,
            previousChapterTitle: chapterTitleByOrder(previousOrder),
            transitionStatus: _transitionStatusByNextOrderValue(
              endBoundaryNextOrder,
            ),
          ),
        );
      }
    }

    return entries;
  }

  /// 横长页拆分的条目下标集合（行模式显示列表里的**全局条目下标**），
  /// 由阅读页在图片尺寸到齐时写入。
  ///
  /// 刻意不进 `state`：它只是「渲染侧与查询侧必须共用」的那一份判据，而每一页
  /// 解码出来都可能改它 —— 一进 state 就要发通知，阅读器里一票
  /// `context.select(currentSlot)` 的监听者会被拖进无谓重建。
  ///
  /// 条漫（列模式）不接这条，与 `_buildColumnDoublePageImage` 同一口径：
  /// 竖滚动里一张宽图本就该占满宽，拆两半要同时满足横向配对与纵向拼接。
  Set<int> _landscapeSplitIndexes = const <int>{};

  /// 由阅读页写入「哪些条目该拆」；集合没变时什么都不做。
  void setLandscapeSplitIndexes(Set<int> indexes) {
    final current = _landscapeSplitIndexes;
    final changed =
        indexes.length != current.length || !indexes.every(current.contains);
    if (!changed) return;
    _landscapeSplitIndexes = Set<int>.unmodifiable(indexes);
  }

  /// 交给遍历器的判据。集合为空时给 `null`，让遍历走原来的条目序列 ——
  /// 这样「没开拆分」这条路径连一次列表展开都不会发生。
  bool Function(int entryIndex)? get _splitAtOrNull =>
      _landscapeSplitIndexes.isEmpty
      ? null
      : (entryIndex) => _landscapeSplitIndexes.contains(entryIndex);

  /// 落在 `[0, entryCount)` 内的拆分条目数，给闭式计数用。
  int _splitCountWithin(int entryCount) => _landscapeSplitIndexes
      .where((entryIndex) => entryIndex >= 0 && entryIndex < entryCount)
      .length;

  int resolveTotalSlots(ReadSettingState readSetting) {
    final fallback = state.loadedChapters.isNotEmpty
        ? state.loadedChapters.first.epInfo.length
        : 0;

    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) {
      // 单话加载时全局条目下标就是本话局部下标，两个索引空间重合。
      return getReadModeSlotCount(
        imageCount: fallback,
        enableDoublePage: readSetting.doublePageMode,
        insertLeadingBlank: _insertLeadingBlank(readSetting),
        splitCount: _splitCountWithin(fallback),
      );
    }

    if (isColumnReadMode(readSetting.readMode)) {
      final entries = buildColumnEntries(readSetting);
      return _resolveDisplaySlotCount(
        entryCount: entries.length,
        enableDoublePage: readSetting.doublePageMode,
        insertLeadingBlank: _insertLeadingBlank(readSetting),
        isTransitionAt: (entryIndex) =>
            entries[entryIndex].type == ReadModeEntryType.transition,
      );
    }
    final entries = buildRowEntries(readSetting);
    return _resolveDisplaySlotCount(
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: _splitAtOrNull,
    );
  }

  // ==================== 槽位映射 ====================

  int mapGlobalToLocalSlot(int globalIndex) {
    final local = globalIndex - state.currentChapterStartSlot;
    final maxLocal = effectiveCurrentChapterSlotCount() - 1;
    return local.clamp(0, maxLocal);
  }

  int mapLocalToGlobalSlot(int localIndex) {
    final maxLocal = effectiveCurrentChapterSlotCount() - 1;
    final clampedLocal = localIndex.clamp(0, maxLocal);
    return state.currentChapterStartSlot + clampedLocal;
  }

  int effectiveCurrentChapterSlotCount() {
    if (state.currentChapterSlotCount > 0) return state.currentChapterSlotCount;
    return 1;
  }

  bool isTransitionSlot(int globalSlot, ReadSettingState readSetting) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) return false;
    if (globalSlot < 0) return false;

    if (isColumnReadMode(readSetting.readMode)) {
      final entries = buildColumnEntries(readSetting);
      final slotEntries = _resolveDisplaySlotEntries(
        targetSlot: globalSlot,
        entryCount: entries.length,
        enableDoublePage: readSetting.doublePageMode,
        insertLeadingBlank: _insertLeadingBlank(readSetting),
        isTransitionAt: (entryIndex) =>
            entries[entryIndex].type == ReadModeEntryType.transition,
      );
      if (slotEntries == null) return false;
      return entries[slotEntries.$1].type == ReadModeEntryType.transition;
    }

    final entries = buildRowEntries(readSetting);
    final slotEntries = _resolveDisplaySlotEntries(
      targetSlot: globalSlot,
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: _splitAtOrNull,
    );
    if (slotEntries == null) return false;
    return entries[slotEntries.$1].type == ReadModeEntryType.transition;
  }

  int? transitionNextOrderByGlobalSlot(
    int globalSlot,
    ReadSettingState readSetting,
  ) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) return null;
    if (globalSlot < 0) return null;

    if (isColumnReadMode(readSetting.readMode)) {
      final entries = buildColumnEntries(readSetting);
      final slotEntries = _resolveDisplaySlotEntries(
        targetSlot: globalSlot,
        entryCount: entries.length,
        enableDoublePage: readSetting.doublePageMode,
        insertLeadingBlank: _insertLeadingBlank(readSetting),
        isTransitionAt: (entryIndex) =>
            entries[entryIndex].type == ReadModeEntryType.transition,
      );
      if (slotEntries == null) return null;
      final entry = entries[slotEntries.$1];
      if (entry.type != ReadModeEntryType.transition) return null;
      return entry.chapterOrder;
    }

    final entries = buildRowEntries(readSetting);
    final slotEntries = _resolveDisplaySlotEntries(
      targetSlot: globalSlot,
      entryCount: entries.length,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: _splitAtOrNull,
    );
    if (slotEntries == null) return null;
    final entry = entries[slotEntries.$1];
    if (entry.type != ReadModeEntryType.transition) return null;
    return entry.chapterOrder;
  }

  // ==================== 历史恢复辅助 ====================

  int resolveHistoryGlobalSlot(
    int baseGlobalSlot,
    ReadSettingState readSetting,
  ) {
    var result = baseGlobalSlot;
    if (_hasLeadingTransition(readSetting)) {
      result += 1;
    }
    return result;
  }

  int resolveEntryDefaultGlobalSlot(ReadSettingState readSetting) {
    return _hasLeadingTransition(readSetting) ? 1 : 0;
  }

  bool _hasLeadingTransition(ReadSettingState readSetting) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) return false;
    final leadingChapterOrder = state.loadedChapters.first.order;
    return _shouldShowTransition(nextOrder: leadingChapterOrder);
  }

  // ==================== 用户动作入口 ====================

  /// 仅同步"当前章节"映射，不触发边界解析/预加载。
  ///
  /// 用于章节跳转后保持当前章节身份一致，避免额外副作用。
  void applyCurrentChapterByGlobalSlot(
    int globalSlot,
    ReadSettingState readSetting,
  ) {
    _applyCurrentChapterByGlobalSlot(globalSlot, readSetting);
  }

  /// 当前显示的全局槽位发生变化时调用（滚动/翻页）。
  ///
  /// 返回值包含边界解析动作的结果；如果发生了 prepend，调用方需要根据
  /// [SeamlessBoundaryResult.targetGlobalSlot] 重新定位视图。
  Future<SeamlessBoundaryResult> onGlobalSlotObserved(
    int globalSlot,
    ReadSettingState readSetting,
  ) async {
    _applyCurrentChapterByGlobalSlot(globalSlot, readSetting);
    if (state.loadedChapters.isEmpty || isClosed) {
      return const SeamlessBoundaryResult();
    }

    final transitionNextOrder = transitionNextOrderByGlobalSlot(
      globalSlot,
      readSetting,
    );
    if (transitionNextOrder != null) {
      return _ensureBoundaryResolved(
        nextOrder: transitionNextOrder,
        currentGlobalSlot: globalSlot,
        readSetting: readSetting,
      );
    }

    final totalSlots = resolveTotalSlots(readSetting);
    if (totalSlots <= 0) return const SeamlessBoundaryResult();

    final remainToEnd = totalSlots - globalSlot - 1;
    if (remainToEnd <= _nextAutoResolveThreshold && canLoadNextChapter()) {
      final nextOrder = _resolveAdjacentChapterOrder(previous: false);
      if (nextOrder != null) {
        return _ensureBoundaryResolved(
          nextOrder: nextOrder,
          currentGlobalSlot: globalSlot,
          readSetting: readSetting,
        );
      }
    }

    if (remainToEnd <= _nextPrefetchThreshold && canLoadNextChapter()) {
      await _prefetchNextChaptersIfNeeded(readSetting.preloadChapterCount);
    }
    return const SeamlessBoundaryResult();
  }

  /// 用户通过边缘拉取或边界按钮触发前后章加载。
  Future<SeamlessBoundaryResult> triggerBoundary({
    required bool previous,
    required ReadSettingState readSetting,
  }) async {
    if (state.loadedChapters.isEmpty || isClosed) {
      return const SeamlessBoundaryResult();
    }

    if (previous) {
      if (!canLoadPreviousChapter()) {
        return const SeamlessBoundaryResult();
      }
      final nextOrder = state.loadedChapters.first.order;
      final revealed = _revealTransition(nextOrder: nextOrder);
      if (revealed) {
        _setTransitionStatus(nextOrder, SeamlessTransitionStatus.hidden);
        return SeamlessBoundaryResult(
          targetGlobalSlot: state.currentChapterStartSlot + 1,
        );
      }
      return _ensureBoundaryResolved(
        nextOrder: nextOrder,
        currentGlobalSlot: state.currentChapterStartSlot,
        readSetting: readSetting,
      );
    }

    if (!canLoadNextChapter()) {
      return const SeamlessBoundaryResult();
    }
    final nextOrder = _resolveAdjacentChapterOrder(previous: false);
    if (nextOrder == null) return const SeamlessBoundaryResult();
    final revealed = _revealTransition(nextOrder: nextOrder);
    if (revealed) {
      _setTransitionStatus(nextOrder, SeamlessTransitionStatus.hidden);
    }
    final status = _transitionStatusByNextOrderValue(nextOrder);
    if (status == SeamlessTransitionStatus.hidden ||
        status == SeamlessTransitionStatus.error) {
      return _ensureBoundaryResolved(
        nextOrder: nextOrder,
        currentGlobalSlot: state.currentChapterStartSlot,
        readSetting: readSetting,
      );
    } else {
      await _prefetchNextChaptersIfNeeded(readSetting.preloadChapterCount);
      return const SeamlessBoundaryResult();
    }
  }

  /// 用户点击过渡卡片时调用。
  Future<SeamlessBoundaryResult> onTransitionAction(
    int nextOrder,
    ReadSettingState readSetting,
    int currentGlobalSlot,
  ) async {
    _revealTransition(nextOrder: nextOrder);
    return _ensureBoundaryResolved(
      nextOrder: nextOrder,
      currentGlobalSlot: currentGlobalSlot,
      readSetting: readSetting,
    );
  }

  // ==================== 内部：章节加载 ====================

  Future<void> _prefetchNextChaptersIfNeeded(int requestedCount) async {
    if (state.loadedChapters.isEmpty || isClosed) return;

    final count = requestedCount.clamp(1, 3).toInt();
    var anchorOrder = state.loadedChapters.last.order;
    for (var i = 0; i < count; i++) {
      if (isClosed) return;
      final nextOrder = _nextOrderOf(anchorOrder);
      if (nextOrder == null) return;
      await _prefetchChapterByOrderIfNeeded(nextOrder);
      anchorOrder = nextOrder;
    }
  }

  Future<void> _prefetchChapterByOrderIfNeeded(int order) async {
    if (_isOrderLoaded(order)) return;
    if (state.prefetchedChapterInfoByOrder.containsKey(order)) return;
    if (state.prefetchingChapterOrders.contains(order)) return;
    if (state.loadingChapterOrders.contains(order)) return;

    final isVisible = state.visibleTransitionNextOrders.contains(order);
    _addPrefetchingOrder(order);
    if (isVisible) {
      _setTransitionStatus(order, SeamlessTransitionStatus.loading);
    }

    try {
      final chapterInfo = await _readChapterByOrder(order);
      if (isClosed) return;
      if (chapterInfo.length <= 0 || chapterInfo.docs.isEmpty) {
        if (isVisible) {
          _setTransitionStatus(order, SeamlessTransitionStatus.error);
        }
        return;
      }

      _setPrefetchedChapterInfo(order, chapterInfo);
      if (isVisible) {
        _setTransitionStatus(order, SeamlessTransitionStatus.ready);
      }
    } catch (_) {
      if (isVisible) {
        _setTransitionStatus(order, SeamlessTransitionStatus.error);
      }
    } finally {
      _removePrefetchingOrder(order);
    }
  }

  Future<SeamlessBoundaryResult> _ensureBoundaryResolved({
    required int nextOrder,
    required int currentGlobalSlot,
    required ReadSettingState readSetting,
  }) async {
    if (!state.visibleTransitionNextOrders.contains(nextOrder)) {
      _revealTransition(nextOrder: nextOrder);
    }

    final targetOrder = _resolveTargetOrderForBoundary(nextOrder);
    if (targetOrder == null) {
      _setTransitionStatus(nextOrder, SeamlessTransitionStatus.ready);
      return const SeamlessBoundaryResult();
    }
    if (state.loadingChapterOrders.contains(targetOrder)) {
      return const SeamlessBoundaryResult();
    }

    _addLoadingOrder(targetOrder);
    _setTransitionStatus(nextOrder, SeamlessTransitionStatus.loading);

    try {
      final prefetched = state.prefetchedChapterInfoByOrder[targetOrder];
      final chapterInfo = prefetched ?? await _readChapterByOrder(targetOrder);
      if (prefetched != null) {
        _removePrefetchedChapterInfo(targetOrder);
      }
      if (isClosed) {
        return const SeamlessBoundaryResult();
      }
      if (chapterInfo.length <= 0 || chapterInfo.docs.isEmpty) {
        _setTransitionStatus(nextOrder, SeamlessTransitionStatus.error);
        return const SeamlessBoundaryResult();
      }

      final shouldPrepend = _shouldPrependOrder(targetOrder);
      final previousTotalSlots = resolveTotalSlots(readSetting);
      if (!_isOrderLoaded(targetOrder)) {
        _addLoadedChapter(order: targetOrder, epInfo: chapterInfo);
        unawaited(
          _prefetchNextChaptersIfNeeded(readSetting.preloadChapterCount),
        );
      }

      _ensureEdgeTransitionsVisible();
      _setTransitionStatus(nextOrder, SeamlessTransitionStatus.ready);

      if (shouldPrepend) {
        final latestTotalSlots = resolveTotalSlots(readSetting);
        final shiftBy = (latestTotalSlots - previousTotalSlots).clamp(
          0,
          999999999,
        );
        return SeamlessBoundaryResult(
          didLoad: true,
          targetGlobalSlot: currentGlobalSlot + shiftBy,
          prependedSlotCount: shiftBy,
        );
      }
      return const SeamlessBoundaryResult(didLoad: true);
    } catch (_) {
      _setTransitionStatus(nextOrder, SeamlessTransitionStatus.error);
      return const SeamlessBoundaryResult();
    } finally {
      _removeLoadingOrder(targetOrder);
    }
  }

  Future<NormalComicEpInfo> _readChapterByOrder(int order) async {
    if (_isDownloadEntryType) {
      return getPluginInfoFromLocal(_from, _comicId, order);
    }
    final chapterRefs = resolveUnifiedComicChapters(_comicInfo, _from);
    const adapter = DownloadChapterAdapter();
    const matcher = DownloadChapterMatcher();
    final chapters = chapterRefs.map(adapter.fromChapterRef).toList();
    final chapter =
        matcher.findByOrder(chapters, order) ??
        (chapters.isNotEmpty ? chapters.first : null);
    return getPluginReadSnapshot(
      _comicId,
      order,
      _from,
      _comicInfo,
      chapter?.id,
      chapter?.effectiveRequestId ?? '',
      chapter?.id ?? '',
      chapter?.effectiveStorageId ?? '',
      Map<String, dynamic>.from(chapter?.extern ?? const <String, dynamic>{}),
    );
  }

  // ==================== 内部：状态更新辅助 ====================

  void _emit(ReaderSeamlessState nextState) {
    if (!isClosed) emit(nextState);
  }

  void _addLoadedChapter({
    required int order,
    required NormalComicEpInfo epInfo,
  }) {
    final updated = List<SeamlessChapter>.from(state.loadedChapters)
      ..add(SeamlessChapter(order: order, epInfo: epInfo));
    _sortLoadedChapters(updated);
    _emit(state.copyWith(loadedChapters: updated));
  }

  void _sortLoadedChapters(List<SeamlessChapter> list) {
    list.sort((a, b) {
      final left = _catalogIndexByOrder(a.order);
      final right = _catalogIndexByOrder(b.order);
      if (left == right) return a.order.compareTo(b.order);
      if (left < 0) return 1;
      if (right < 0) return -1;
      return left.compareTo(right);
    });
  }

  void _addLoadingOrder(int order) {
    _emit(
      state.copyWith(
        loadingChapterOrders: {...state.loadingChapterOrders, order},
      ),
    );
  }

  void _removeLoadingOrder(int order) {
    _emit(
      state.copyWith(
        loadingChapterOrders: state.loadingChapterOrders
            .where((o) => o != order)
            .toSet(),
      ),
    );
  }

  void _addPrefetchingOrder(int order) {
    _emit(
      state.copyWith(
        prefetchingChapterOrders: {...state.prefetchingChapterOrders, order},
      ),
    );
  }

  void _removePrefetchingOrder(int order) {
    _emit(
      state.copyWith(
        prefetchingChapterOrders: state.prefetchingChapterOrders
            .where((o) => o != order)
            .toSet(),
      ),
    );
  }

  void _setPrefetchedChapterInfo(int order, NormalComicEpInfo info) {
    _emit(
      state.copyWith(
        prefetchedChapterInfoByOrder: {
          ...state.prefetchedChapterInfoByOrder,
          order: info,
        },
      ),
    );
  }

  void _removePrefetchedChapterInfo(int order) {
    final updated = {...state.prefetchedChapterInfoByOrder}..remove(order);
    _emit(state.copyWith(prefetchedChapterInfoByOrder: updated));
  }

  void _ensureEdgeTransitionsVisible({bool notify = true}) {
    if (state.loadedChapters.isEmpty) return;

    final firstOrder = state.loadedChapters.first.order;
    final lastOrder = state.loadedChapters.last.order;
    final requiredTransitionNextOrders = <int>{};

    if (_previousOrderOf(firstOrder) != null) {
      requiredTransitionNextOrders.add(firstOrder);
    }

    final tailNextOrder = _nextOrderOf(lastOrder);
    if (tailNextOrder != null) {
      requiredTransitionNextOrders.add(tailNextOrder);
    }

    final needUpdate = requiredTransitionNextOrders.any(
      (order) =>
          !state.visibleTransitionNextOrders.contains(order) ||
          !state.transitionStatusByNextOrder.containsKey(order),
    );
    if (!needUpdate) return;

    final updatedVisible = {...state.visibleTransitionNextOrders}
      ..addAll(requiredTransitionNextOrders);
    final updatedStatus = {...state.transitionStatusByNextOrder};
    for (final order in requiredTransitionNextOrders) {
      updatedStatus.putIfAbsent(order, () => SeamlessTransitionStatus.hidden);
    }

    if (notify) {
      _emit(
        state.copyWith(
          visibleTransitionNextOrders: updatedVisible,
          transitionStatusByNextOrder: updatedStatus,
        ),
      );
    } else {
      _emit(
        state.copyWith(
          visibleTransitionNextOrders: updatedVisible,
          transitionStatusByNextOrder: updatedStatus,
        ),
      );
    }
  }

  void _applyCurrentChapterByGlobalSlot(
    int globalSlot,
    ReadSettingState readSetting,
  ) {
    if (state.loadedChapters.isEmpty) return;

    final slotContext = _resolveImageSlotContextByGlobalSlot(
      globalSlot,
      readSetting,
    );
    if (slotContext == null) return;

    final chapter = state.loadedChapters.firstWhere(
      (item) => item.order == slotContext.chapterOrder,
      orElse: () => state.loadedChapters.last,
    );

    final chapterChanged =
        state.currentChapterOrder != chapter.order ||
        state.currentChapterStartSlot != slotContext.chapterStartSlot ||
        state.currentChapterSlotCount != slotContext.chapterImageCount;
    if (!chapterChanged) return;

    _emit(
      state.copyWith(
        currentChapterOrder: chapter.order,
        currentChapterStartSlot: slotContext.chapterStartSlot,
        currentChapterSlotCount: slotContext.chapterImageCount,
      ),
    );
  }

  bool _revealTransition({required int nextOrder}) {
    if (state.visibleTransitionNextOrders.contains(nextOrder)) return false;
    _emit(
      state.copyWith(
        visibleTransitionNextOrders: {
          ...state.visibleTransitionNextOrders,
          nextOrder,
        },
      ),
    );
    return true;
  }

  void _setTransitionStatus(int nextOrder, SeamlessTransitionStatus status) {
    if (state.transitionStatusByNextOrder[nextOrder] == status) return;
    _emit(
      state.copyWith(
        transitionStatusByNextOrder: {
          ...state.transitionStatusByNextOrder,
          nextOrder: status,
        },
      ),
    );
  }

  SeamlessTransitionStatus _transitionStatusByNextOrderValue(int nextOrder) {
    final previousOrder = _previousOrderOf(nextOrder);
    if (previousOrder == null) {
      return SeamlessTransitionStatus.hidden;
    }
    final bothSidesLoaded =
        _isOrderLoaded(previousOrder) && _isOrderLoaded(nextOrder);
    if (bothSidesLoaded) {
      return SeamlessTransitionStatus.ready;
    }

    final targetOrder = _resolveTargetOrderForBoundary(nextOrder);
    if (targetOrder != null &&
        state.prefetchingChapterOrders.contains(targetOrder)) {
      return SeamlessTransitionStatus.loading;
    }
    if (targetOrder != null &&
        state.prefetchedChapterInfoByOrder.containsKey(targetOrder)) {
      return SeamlessTransitionStatus.ready;
    }

    return state.transitionStatusByNextOrder[nextOrder] ??
        SeamlessTransitionStatus.hidden;
  }

  // ==================== 内部：章节目录与边界判断 ====================

  int? _resolveAdjacentChapterOrder({required bool previous}) {
    final chapters = _catalogChapters();
    if (chapters.isEmpty || state.loadedChapters.isEmpty) return null;
    final anchorOrder = previous
        ? state.loadedChapters.first.order
        : state.loadedChapters.last.order;
    final anchorIndex = _catalogIndexByOrder(anchorOrder);
    if (anchorIndex < 0) return null;

    final targetIndex = previous ? anchorIndex - 1 : anchorIndex + 1;
    if (targetIndex < 0 || targetIndex >= chapters.length) return null;
    return chapters[targetIndex].order;
  }

  int? _resolveTargetOrderForBoundary(int nextOrder) {
    final previousOrder = _previousOrderOf(nextOrder);
    if (previousOrder == null) return null;

    final previousLoaded = _isOrderLoaded(previousOrder);
    final nextLoaded = _isOrderLoaded(nextOrder);

    if (!previousLoaded) return previousOrder;
    if (!nextLoaded) return nextOrder;
    return null;
  }

  bool _shouldPrependOrder(int order) {
    if (state.loadedChapters.isEmpty) return false;
    final firstLoadedIndex = _catalogIndexByOrder(
      state.loadedChapters.first.order,
    );
    final targetIndex = _catalogIndexByOrder(order);
    if (firstLoadedIndex < 0 || targetIndex < 0) return false;
    return targetIndex < firstLoadedIndex;
  }

  bool _shouldShowTransition({required int nextOrder}) {
    if (!state.visibleTransitionNextOrders.contains(nextOrder)) return false;
    final previousOrder = _previousOrderOf(nextOrder);
    return previousOrder != null;
  }

  bool _isOrderLoaded(int order) {
    return state.loadedChapters.any((chapter) => chapter.order == order);
  }

  List<UnifiedComicChapterRef> _catalogChapters() {
    if (_chapterRefs.isNotEmpty) return _chapterRefs;
    return const <UnifiedComicChapterRef>[];
  }

  int _catalogIndexByOrder(int order) {
    final mappedIndex = _chapterOrderToCatalogIndex[order];
    if (mappedIndex != null && mappedIndex >= 0) return mappedIndex;
    final chapters = _catalogChapters();
    return chapters.indexWhere((chapter) => chapter.order == order);
  }

  int? _previousOrderOf(int order) {
    final chapters = _catalogChapters();
    if (chapters.isEmpty) return null;
    final index = _catalogIndexByOrder(order);
    if (index <= 0) return null;
    return chapters[index - 1].order;
  }

  int? _nextOrderOf(int order) {
    final chapters = _catalogChapters();
    if (chapters.isEmpty) return null;
    final index = _catalogIndexByOrder(order);
    if (index < 0 || index >= chapters.length - 1) return null;
    return chapters[index + 1].order;
  }

  // ==================== 内部：槽位解析 ====================

  _ImageSlotContext? _resolveImageSlotContextByGlobalSlot(
    int globalSlot,
    ReadSettingState readSetting,
  ) {
    if (globalSlot < 0) return null;

    final entries = isColumnReadMode(readSetting.readMode)
        ? buildColumnEntries(readSetting)
        : buildRowEntries(readSetting);
    return _resolveImageSlotContextFromEntries(
      globalSlot,
      entries,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isSplitAt: isColumnReadMode(readSetting.readMode) ? null : _splitAtOrNull,
    );
  }

  _ImageSlotContext? _resolveImageSlotContextByChapterOrder({
    required int chapterOrder,
    required ReadSettingState readSetting,
  }) {
    if (!isSeamlessEnabled() || state.loadedChapters.isEmpty) return null;

    final entries = isColumnReadMode(readSetting.readMode)
        ? buildColumnEntries(readSetting)
        : buildRowEntries(readSetting);
    return _resolveChapterSlotContextFromEntries(
      chapterOrder,
      entries,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank: _insertLeadingBlank(readSetting),
      isSplitAt: isColumnReadMode(readSetting.readMode) ? null : _splitAtOrNull,
    );
  }

  bool _insertLeadingBlank(ReadSettingState readSetting) =>
      readSetting.doublePageMode && readSetting.doublePageLeadingBlank;

  int? _chapterOrderOfImageEntry(ReadModeEntry entry) =>
      entry.type == ReadModeEntryType.image ? entry.chapterOrder : null;

  _ImageSlotContext? _resolveImageSlotContextFromEntries(
    int globalSlot,
    List<ReadModeEntry> entries, {
    required bool enableDoublePage,
    required bool insertLeadingBlank,
    bool Function(int entryIndex)? isSplitAt,
  }) {
    final slotEntries = _resolveDisplaySlotEntries(
      targetSlot: globalSlot,
      entryCount: entries.length,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: insertLeadingBlank,
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isSplitAt,
    );
    if (slotEntries == null) return null;
    final current = entries[slotEntries.$1];
    final chapterOrder = _chapterOrderOfImageEntry(current);
    if (chapterOrder == null) return null;

    var chapterStartSlot = -1;
    var chapterSlotCount = 0;
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: insertLeadingBlank,
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isSplitAt,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        final order = _chapterOrderOfImageEntry(entries[primaryEntryIndex]);
        if (order == null || order != chapterOrder) return;
        chapterStartSlot = chapterStartSlot < 0 ? slotIndex : chapterStartSlot;
        chapterSlotCount++;
      },
    );
    if (chapterStartSlot < 0 || chapterSlotCount <= 0) return null;
    return _ImageSlotContext(
      chapterOrder: chapterOrder,
      chapterStartSlot: chapterStartSlot,
      chapterImageCount: chapterSlotCount,
    );
  }

  _ImageSlotContext? _resolveChapterSlotContextFromEntries(
    int chapterOrder,
    List<ReadModeEntry> entries, {
    required bool enableDoublePage,
    required bool insertLeadingBlank,
    bool Function(int entryIndex)? isSplitAt,
  }) {
    var chapterStartSlot = -1;
    var chapterSlotCount = 0;
    _forEachDisplaySlot(
      entryCount: entries.length,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: insertLeadingBlank,
      isTransitionAt: (entryIndex) =>
          entries[entryIndex].type == ReadModeEntryType.transition,
      isSplitAt: isSplitAt,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        final order = _chapterOrderOfImageEntry(entries[primaryEntryIndex]);
        if (order == null || order != chapterOrder) return;
        chapterStartSlot = chapterStartSlot < 0 ? slotIndex : chapterStartSlot;
        chapterSlotCount++;
      },
    );
    if (chapterStartSlot < 0 || chapterSlotCount <= 0) return null;
    return _ImageSlotContext(
      chapterOrder: chapterOrder,
      chapterStartSlot: chapterStartSlot,
      chapterImageCount: chapterSlotCount,
    );
  }

  int _resolveDisplaySlotCount({
    required int entryCount,
    required bool enableDoublePage,
    required bool insertLeadingBlank,
    required bool Function(int entryIndex) isTransitionAt,
    bool Function(int entryIndex)? isSplitAt,
  }) {
    if (entryCount <= 0) return 0;
    var count = 0;
    _forEachDisplaySlot(
      entryCount: entryCount,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: insertLeadingBlank,
      isTransitionAt: isTransitionAt,
      isSplitAt: isSplitAt,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        count = slotIndex + 1;
      },
    );
    return count;
  }

  (int, int?)? _resolveDisplaySlotEntries({
    required int targetSlot,
    required int entryCount,
    required bool enableDoublePage,
    required bool insertLeadingBlank,
    required bool Function(int entryIndex) isTransitionAt,
    bool Function(int entryIndex)? isSplitAt,
  }) {
    if (targetSlot < 0 || entryCount <= 0) return null;
    (int, int?)? result;
    _forEachDisplaySlot(
      entryCount: entryCount,
      enableDoublePage: enableDoublePage,
      insertLeadingBlank: insertLeadingBlank,
      isTransitionAt: isTransitionAt,
      isSplitAt: isSplitAt,
      onSlot: (slotIndex, primaryEntryIndex, secondaryEntryIndex) {
        if (slotIndex != targetSlot || result != null) return;
        result = (primaryEntryIndex, secondaryEntryIndex);
      },
    );
    return result;
  }

  /// 与 [buildReadModeDoublePageSlots] 保持一致的槽位遍历。
  ///
  /// 首页留白槽位以「该页图片 entry 为 primary、secondary 为 null」表示，
  /// 仅用于槽位计数/章节归属；UI 侧单独渲染左侧空白。
  void _forEachDisplaySlot({
    required int entryCount,
    required bool enableDoublePage,
    required bool insertLeadingBlank,
    required bool Function(int entryIndex) isTransitionAt,
    bool Function(int entryIndex)? isSplitAt,
    required void Function(
      int slotIndex,
      int primaryEntryIndex,
      int? secondaryEntryIndex,
    )
    onSlot,
  }) {
    // 拆分把「一个条目」变成「两个展示项」，而双页的配对是在**项**上进行的
    // （`[0, 1L]` 与 `[1R, 2]`，绝不把同一张的两半配成一对空转）。所以这里先把
    // 条目展开成项、再走原来那套配对规则 —— 与渲染侧
    // `buildReadModeSinglePageSlots` / `buildReadModeDoublePageSlots` 同一条展开，
    // 两边共用同一份「谁是横图」判据，槽位数与条目序列才不会各算各的。
    final splitAt = isSplitAt;
    final items = <int>[
      for (var entryIndex = 0; entryIndex < entryCount; entryIndex++) ...[
        entryIndex,
        if (splitAt != null &&
            !isTransitionAt(entryIndex) &&
            splitAt(entryIndex))
          entryIndex,
      ],
    ];

    var slotIndex = 0;
    var itemIndex = 0;
    var needLeadingBlank = enableDoublePage && insertLeadingBlank;
    while (itemIndex < items.length) {
      final primaryEntryIndex = items[itemIndex];
      if (!enableDoublePage || isTransitionAt(primaryEntryIndex)) {
        onSlot(slotIndex, primaryEntryIndex, null);
        slotIndex++;
        itemIndex++;
        if (enableDoublePage && isTransitionAt(primaryEntryIndex)) {
          needLeadingBlank = insertLeadingBlank;
        }
        continue;
      }

      if (needLeadingBlank) {
        onSlot(slotIndex, primaryEntryIndex, null);
        slotIndex++;
        itemIndex++;
        needLeadingBlank = false;
        continue;
      }

      itemIndex++;
      int? secondaryEntryIndex;
      if (itemIndex < items.length && !isTransitionAt(items[itemIndex])) {
        secondaryEntryIndex = items[itemIndex];
        itemIndex++;
      }
      onSlot(slotIndex, primaryEntryIndex, secondaryEntryIndex);
      slotIndex++;
    }
  }
}

class _ImageSlotContext {
  const _ImageSlotContext({
    required this.chapterOrder,
    required this.chapterStartSlot,
    required this.chapterImageCount,
  });

  final int chapterOrder;
  final int chapterStartSlot;
  final int chapterImageCount;
}
