import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';

/// 章节内「手动页面排列」的会话状态。
///
/// ## 为什么只存手动那一档的排列
///
/// 档位（`ReaderPageOrderMode`）落在 `ReadSettingState.readerPageOrderMode` 里，
/// 要跨书、跨重启保持；而**排列本身刻意不落盘**：它写的下标是
/// 「这一章页表的第几个」，图源换一次页表、甚至同一本重新拉一次章节，
/// 那些下标就可能不再指向同一页。把索引持久化等于把一份对不上号的表
/// 留给下一本书 —— 那比丢失排列更糟。
///
/// 所以这里只有一个 route 一份，换书换章自然归零，与
/// [ReaderPresentationCubit] 里「手动缩放/旋转只活在本次会话」同一口径。
///
/// ## 为什么不缓存档位
///
/// 读的时候一律现取 `readSetting.readerPageOrderMode`：档位有两个写者
/// （顶栏面板、设置页），在这里再存一份就会有两个真相，
/// 而且「顶栏改了档位、这里没同步」这种错编译器抓不到。
@immutable
class ReaderPageOrderState {
  const ReaderPageOrderState({this.customOrders = const <String, List<int>>{}});

  /// `chapterId -> 「显示位置 → 源下标」` 的排列。
  final Map<String, List<int>> customOrders;

  List<int>? operator [](String chapterId) => customOrders[chapterId];

  ReaderPageOrderState withCustom(String chapterId, List<int> order) {
    return ReaderPageOrderState(
      customOrders: Map<String, List<int>>.of(customOrders)
        ..[chapterId] = order,
    );
  }

  ReaderPageOrderState withoutCustom(String chapterId) {
    if (!customOrders.containsKey(chapterId)) return this;
    final next = Map<String, List<int>>.of(customOrders)..remove(chapterId);
    return ReaderPageOrderState(customOrders: next);
  }

  ReaderPageOrderState get cleared => const ReaderPageOrderState();

  @override
  bool operator ==(Object other) {
    if (other is! ReaderPageOrderState) return false;
    if (other.customOrders.length != customOrders.length) return false;
    for (final entry in customOrders.entries) {
      final theirs = other.customOrders[entry.key];
      if (theirs == null) return false;
      if (!_sameIntList(entry.value, theirs)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
    customOrders.entries.map(
      (entry) => Object.hash(entry.key, Object.hashAll(entry.value)),
    ),
  );

  static bool _sameIntList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 页面排序的会话侧。
class ReaderPageOrderCubit extends Cubit<ReaderPageOrderState> {
  ReaderPageOrderCubit() : super(const ReaderPageOrderState());

  /// 派生缓存：`chapterId -> (档位, 页表标识, 排列)`。
  ///
  /// 自然序要比较整章的文件名，列模式下每次构建都会重算一遍条目；
  /// 页表在一次阅读里几乎不变，所以按「档位 + 页表标识」缓存，
  /// 页表换了（下一章拼进来、图源刷新）才重算。
  /// 它不进 [state]：进 state 就要发通知，而阅读器里一票
  /// `context.select(currentSlot)` 的监听者会被拖进无谓重建
  /// （与 `ReaderSeamlessCubit._landscapeSplitIndexes` 同一条理由）。
  final Map<String, _CachedOrder> _cache = <String, _CachedOrder>{};

  bool hasCustomOrder(String chapterId) =>
      state.customOrders.containsKey(chapterId);

  List<int>? customOrderFor(String chapterId) => state.customOrders[chapterId];

  /// 用户拖出来的那份排列；页数对不上（页表变了）时直接丢掉而不是硬用。
  void applyCustomOrder(String chapterId, List<int> order) {
    emit(state.withCustom(chapterId, List<int>.unmodifiable(order)));
    _cache.remove(chapterId);
  }

  void clearCustomOrder(String chapterId) {
    emit(state.withoutCustom(chapterId));
    _cache.remove(chapterId);
  }

  void clearAllCustomOrders() {
    _cache.clear();
    emit(state.cleared);
  }

  /// 这一章的「显示位置 → 源下标」排列。
  ///
  /// 返回的列表长度恒等于 [docs] 长度，因此槽位计数、高度估算、
  /// 双页配对这些按下标算的逻辑都不需要知道排序存在。
  List<int> resolveOrder({
    required String chapterId,
    required ReaderPageOrderMode mode,
    required List<Doc> docs,
  }) {
    final pageCount = docs.length;
    if (pageCount == 0) return const <int>[];
    final source = readerSourceOrder(pageCount);

    final names = mode == ReaderPageOrderMode.natural
        ? _namesOf(docs)
        : const <String>[];
    final fingerprint = _pageTableFingerprint(docs);
    final cached = _cache[chapterId];
    if (cached != null &&
        cached.mode == mode &&
        cached.fingerprint == fingerprint &&
        cached.order.length == pageCount) {
      return cached.order;
    }

    final List<int> order;
    switch (mode) {
      case ReaderPageOrderMode.source:
        order = source;
      case ReaderPageOrderMode.reverse:
        order = List<int>.unmodifiable(source.reversed.toList(growable: false));
      case ReaderPageOrderMode.natural:
        order = readerNaturalOrder(names);
      case ReaderPageOrderMode.custom:
        order =
            normalizeReaderPageOrder(
              state.customOrders[chapterId],
              pageCount,
            ) ??
            source;
    }
    _cache[chapterId] = _CachedOrder(
      mode: mode,
      fingerprint: fingerprint,
      order: order,
    );
    return order;
  }

  /// 按当前档位排好的页表 —— 给「按下标取一页来显示」的那些下游用
  /// （缩略图条、滑动条预览、页名提示）。
  List<Doc> orderedDocs({
    required String chapterId,
    required ReaderPageOrderMode mode,
    required List<Doc> docs,
  }) {
    final order = resolveOrder(chapterId: chapterId, mode: mode, docs: docs);
    if (order.length != docs.length) return docs;
    return List<Doc>.unmodifiable(
      order.map((sourceIndex) => docs[sourceIndex]),
    );
  }

  /// 「正在看的那一页」在新排列里的位置 —— 换档位时用它把画面对齐回同一张图。
  int? positionOfSource(String chapterId, int sourceIndex) {
    final cached = _cache[chapterId];
    if (cached == null) return null;
    final position = cached.order.indexOf(sourceIndex);
    return position < 0 ? null : position;
  }

  void invalidate(String chapterId) => _cache.remove(chapterId);

  @override
  Future<void> close() {
    _cache.clear();
    return super.close();
  }

  /// 页表标识：长度 + 首尾页的 id。
  ///
  /// 不做全量哈希：一次构建里可能要问好几章，而「同一章的页表在一次阅读中
  /// 不会原地换内容」是本仓既有的前提（尺寸缓存也是按章下标复用的）。
  /// 首尾页变了就当整张表变了。
  String _pageTableFingerprint(List<Doc> docs) {
    if (docs.isEmpty) return 'empty';
    final first = docs.first;
    final last = docs.last;
    return '${docs.length}|${first.id}|${first.originalName}|${last.id}|${last.originalName}';
  }

  List<String> _namesOf(List<Doc> docs) => List<String>.unmodifiable(
    docs.map(
      (doc) => doc.originalName.isNotEmpty ? doc.originalName : doc.path,
    ),
  );
}

@immutable
class _CachedOrder {
  const _CachedOrder({
    required this.mode,
    required this.fingerprint,
    required this.order,
  });

  final ReaderPageOrderMode mode;
  final String fingerprint;
  final List<int> order;
}
