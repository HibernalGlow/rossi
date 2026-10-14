import 'dart:async';
import 'package:zephyr/reader/page_trim_layout.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/method/image_size_cache_store.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

class ImageSizeState {
  final Map<int, Size> sizeCache;
  final Set<int> resolvedIndices;
  final double defaultWidth;
  final double defaultHeight;

  /// 图片**原始像素**尺寸（`index` → 未缩放的 px 尺寸）。
  ///
  /// 与 [sizeCache] 分开存，因为 `sizeCache` 记的是「上次按某个宽度铺出来的显示尺寸」，
  /// 只有宽高比是可信的；`reader.original`（原始大小）要的是绝对像素，比例给不出。
  /// 刻意**不落盘**：它只在当前这一章有意义。
  final Map<int, Size> intrinsicCache;

  ImageSizeState({
    required this.sizeCache,
    required this.resolvedIndices,
    required this.defaultWidth,
    required this.defaultHeight,
    this.intrinsicCache = const {},
  });

  Size getSizeValue(int index) {
    return sizeCache[index] ?? Size(defaultWidth, defaultHeight);
  }

  /// 该页的原始像素尺寸；还没解出来时为 null。
  Size? getIntrinsic(int index) => intrinsicCache[index];
}

class ImageSizeCubit extends Cubit<ImageSizeState> {
  final trimLayout = PageTrimLayout();
  static const Duration _saveDebounceDuration = Duration(milliseconds: 300);

  final int count;
  final double defaultWidth;
  final double defaultHeight;
  final String sourceTag;
  final List<String> pageKeys;
  final int _chapterOrder;
  final ImageSizeCacheStore _cacheStore;

  /// 本次阅读会话里**已经探测过**的页（量到尺寸与否都算）。
  ///
  /// 与 `state.resolvedIndices` 分开，因为后者只记「量到了」：阅读器在章节边界
  /// 会把手上**所有**已加载章节重新交给预解析，只看 `resolvedIndices` 的话，
  /// 磁盘上还不存在的那些页（在线未下载的、以及本地压缩包里的每一页）
  /// 每次边界都要重跑一遍多候选路径解析 —— 每页十几次**同步**跨桥
  /// （`encodePath`）加若干次 mkdir/stat，代价按「已加载章数 × 页」增长，
  /// 而它恰好落在用户翻到最后一页的那一刻，表现就是「卡一下」。
  ///
  /// 负缓存不会把布局钉在占位高度：图片真正上屏时 `ImageDisplay` 仍走
  /// [updateSize] 照常上报，那条路不看这个集合。
  final Set<int> _probedIndices = <int>{};

  Timer? _saveTimer;
  bool _hasPendingSave = false;
  bool _isFlushing = false;
  bool _isDisposed = false;

  ImageSizeCubit({
    required this.count,
    required this.defaultWidth,
    required this.defaultHeight,
    required this.sourceTag,
    required this.pageKeys,
    required this._chapterOrder,
    required bool hydrateOnInit,
    required Map<int, Size> initialCache,
    required Set<int> initialResolved,
  }) : _cacheStore = ImageSizeCacheStore(
         sourceTag: sourceTag,
         pageKeys: pageKeys,
       ),
       super(
         ImageSizeState(
           sizeCache: initialCache,
           resolvedIndices: initialResolved,
           defaultWidth: defaultWidth,
           defaultHeight: defaultHeight,
         ),
       ) {
    if (hydrateOnInit) {
      unawaited(_hydrateFromDisk());
    }
  }

  factory ImageSizeCubit.create({
    required double defaultWidth,
    required int count,
    required String sourceTag,
    required List<String> pageKeys,
    required int chapterOrder,
    Map<int, Size>? persistedCache,
  }) {
    final double defaultHeight = defaultWidth * 1.2;

    final initialCache = <int, Size>{};
    final initialResolved = <int>{};

    for (int i = 0; i < count; i++) {
      double currentHeight;
      currentHeight = defaultHeight;
      initialCache[i] = Size(defaultWidth, currentHeight);
    }

    if (persistedCache != null && persistedCache.isNotEmpty) {
      for (final entry in persistedCache.entries) {
        if (entry.key < 0 || entry.key >= count) continue;
        // 持久化以本地页索引为键，运行时以章节哈希索引为键，这里做映射。
        final cacheIndex = resolveStableSizeCacheIndex(
          chapterOrder: chapterOrder,
          localPageIndex: entry.key,
        );
        initialCache[cacheIndex] = entry.value;
        initialResolved.add(cacheIndex);
      }
    }

    return ImageSizeCubit(
      count: count,
      defaultWidth: defaultWidth,
      defaultHeight: defaultHeight,
      sourceTag: sourceTag,
      pageKeys: pageKeys,
      chapterOrder: chapterOrder,
      hydrateOnInit: persistedCache == null,
      initialCache: initialCache,
      initialResolved: initialResolved,
    );
  }

  ({Size size, bool isCached}) getSize(int index) {
    final size = state.sizeCache[index] ?? Size(defaultWidth, defaultHeight);
    final isCached = state.resolvedIndices.contains(index);
    return (size: size, isCached: isCached);
  }

  void updateSize(int index, Size newSize) {
    final isAlreadyResolved = state.resolvedIndices.contains(index);
    final isSizeChanged = state.sizeCache[index] != newSize;

    if (!isAlreadyResolved || isSizeChanged) {
      final newCache = Map<int, Size>.from(state.sizeCache);
      newCache[index] = newSize;
      final newResolved = Set<int>.from(state.resolvedIndices);
      newResolved.add(index);

      emit(
        ImageSizeState(
          sizeCache: newCache,
          resolvedIndices: newResolved,
          defaultWidth: state.defaultWidth,
          defaultHeight: state.defaultHeight,
          intrinsicCache: state.intrinsicCache,
        ),
      );
      _markDirtyAndScheduleSave();
    }
  }

  /// 这一页在本会话里是否已经探测过了（探测过 ≠ 量到了）。
  ///
  /// 预解析用它做「一次会话只探一次」的判断，见 [_probedIndices]。
  bool isProbed(int index) =>
      _probedIndices.contains(index) || state.resolvedIndices.contains(index);

  /// 在真正去做 IO **之前**占坑。
  ///
  /// 章节边界会把所有章节重新交给预解析，同一章可能被并发启动；先占坑，
  /// 后到的那一份就看不到这一页还没探过，不会重复跑多候选路径解析。
  void claimProbe(int index) => _probedIndices.add(index);

  /// 批量写入尺寸：一次只 emit 一条。
  ///
  /// 预解析一个章节会连续命中几十页，逐页 [updateSize] 等于
  /// 「每页复制一遍整份尺寸表 + 每页通知一次所有监听者」—— 页数的平方级
  /// 拷贝，而且重建正好和章节边界那几帧叠在一起。攒批是唯一能把这两条
  /// 都压下去的落点。
  void updateSizes(Map<int, Size> sizes) {
    if (sizes.isEmpty) return;

    final newCache = Map<int, Size>.from(state.sizeCache);
    final newResolved = Set<int>.from(state.resolvedIndices);
    var changed = false;

    for (final entry in sizes.entries) {
      final index = entry.key;
      final size = entry.value;
      _probedIndices.add(index);
      if (newResolved.contains(index) && newCache[index] == size) continue;
      newCache[index] = size;
      newResolved.add(index);
      changed = true;
    }

    if (!changed) return;
    emit(
      ImageSizeState(
        sizeCache: newCache,
        resolvedIndices: newResolved,
        defaultWidth: state.defaultWidth,
        defaultHeight: state.defaultHeight,
        intrinsicCache: state.intrinsicCache,
      ),
    );
    _markDirtyAndScheduleSave();
  }

  /// 记下图片的原始像素尺寸（`reader.original` 用）。不触发落盘。
  void updateIntrinsicSize(int index, Size intrinsic) {
    if (state.intrinsicCache[index] == intrinsic) return;
    final newIntrinsic = Map<int, Size>.from(state.intrinsicCache);
    newIntrinsic[index] = intrinsic;
    emit(
      ImageSizeState(
        sizeCache: state.sizeCache,
        resolvedIndices: state.resolvedIndices,
        defaultWidth: state.defaultWidth,
        defaultHeight: state.defaultHeight,
        intrinsicCache: newIntrinsic,
      ),
    );
  }

  Future<void> _hydrateFromDisk() async {
    try {
      final persisted = await _cacheStore.readIndexedSizes(
        pageKeys: pageKeys,
        count: count,
      );
      if (persisted.isEmpty || _isDisposed) return;

      final newCache = Map<int, Size>.from(state.sizeCache);
      final newResolved = Set<int>.from(state.resolvedIndices);
      var changed = false;

      for (final entry in persisted.entries) {
        // 与 create 一致：本地页索引 → 运行时章节哈希索引。
        final cacheIndex = resolveStableSizeCacheIndex(
          chapterOrder: _chapterOrder,
          localPageIndex: entry.key,
        );
        // 水合现在是异步的，可能比首屏测量更晚回来。已经量到真实尺寸的页
        // 不能被「上一次存的」盖回去 —— 那会让刚稳定的布局再跳一次。
        if (newResolved.contains(cacheIndex)) continue;
        newCache[cacheIndex] = entry.value;
        newResolved.add(cacheIndex);
        changed = true;
      }

      if (changed) {
        emit(
          ImageSizeState(
            sizeCache: newCache,
            resolvedIndices: newResolved,
            defaultWidth: state.defaultWidth,
            defaultHeight: state.defaultHeight,
            intrinsicCache: state.intrinsicCache,
          ),
        );
      }
    } catch (_) {}
  }

  void _markDirtyAndScheduleSave() {
    _hasPendingSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounceDuration, () {
      unawaited(flushNow());
    });
  }

  Future<void> flushNow() async {
    if (_isDisposed || !_hasPendingSave) return;
    if (_isFlushing) return;

    _isFlushing = true;
    _hasPendingSave = false;
    try {
      // 运行时索引（章节哈希）→ 本地页索引，持久化层只认本地页索引。
      final localSizes = <int, Size>{};
      final localResolved = <int>{};
      final max = count < pageKeys.length ? count : pageKeys.length;
      for (var i = 0; i < max; i++) {
        final runtimeIndex = resolveStableSizeCacheIndex(
          chapterOrder: _chapterOrder,
          localPageIndex: i,
        );
        if (!state.resolvedIndices.contains(runtimeIndex)) continue;
        final size = state.sizeCache[runtimeIndex];
        if (size == null) continue;
        localSizes[i] = size;
        localResolved.add(i);
      }
      await _cacheStore.write(
        pageKeys: pageKeys,
        sizeCache: localSizes,
        resolvedIndices: localResolved,
        count: count,
      );
    } catch (_) {
      _hasPendingSave = true;
    } finally {
      _isFlushing = false;
    }
  }

  Future<({int recordCount, int fileBytes, String filePath})>
  getCacheStats() async {
    return _cacheStore.getStats();
  }

  Future<void> debugPrintCacheStats() async {
    final stats = await getCacheStats();
    logger.d(
      '[ImageSizeCache] source=$sourceTag records=${stats.recordCount} bytes=${stats.fileBytes} path=${stats.filePath}',
    );
  }

  @override
  Future<void> close() async {
    _saveTimer?.cancel();
    await flushNow();
    _isDisposed = true;
    trimLayout.dispose();
    return super.close();
  }
}
