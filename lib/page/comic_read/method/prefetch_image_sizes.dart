import 'package:flutter/widgets.dart' show Size;
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/image_header_size.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 本地路径解析缝：默认走 `findCachedPicturePath`，测试注入一个能计数的假解析器。
typedef CachedPicturePathResolver =
    Future<String> Function({
      required String from,
      required String path,
      required String cartoonId,
      required String chapterId,
      required String storageChapterId,
    });

/// 攒够几页命中就发一次通知。
///
/// 太小（1）等于回到逐页 emit；太大则高度铺得太晚，自动滚动的跳动窗口变宽。
/// 8 页 ≈ 一屏多一点，批与批之间还能让出帧。
const int _prefetchFlushBatch = 8;

/// 后台预解析章节图片尺寸并写入 [ImageSizeCubit]。
///
/// 列表项在图片加载前使用默认占位高度（宽 × 1.2），图片解析出真实尺寸后
/// 高度突变会造成可见的布局跳动（自动平滑滚动时尤其明显）。
/// 本函数在章节就绪后主动解析**已存在于本地**（缓存/下载目录）的图片
/// 文件头尺寸，让列表项高度尽量提前就位；未下载的图片直接跳过
/// （不触发任何网络请求），其尺寸仍走图片显示时的原有上报路径。
///
/// # 为什么这里必须「一页一次会话只探一次」
///
/// 调用方（`ComicReadSuccessWidget._onSeamlessChaptersChanged`）在
/// `loadedChapters.length` 每变一次，会把**手上所有章节**重新交给本函数 ——
/// 也就是用户每翻到某一章的最后一页，这里就为全部已加载章节再跑一遍。
/// 单次探测并不便宜：`findCachedPicturePath` 要依次试新下载 / 旧下载 / 新缓存
/// 三组候选，每组都取一次根目录（带 mkdir）并做十几次 `encodePath` 跨桥
/// （Rust 侧是 `#[frb(sync)]`，直接在 UI isolate 上阻塞），再加若干次 stat。
///
/// 旧的跳过判据是「这一页量到过尺寸没有」，于是**磁盘上还没有的那些页**
/// （在线未下载、以及本地压缩包里的每一页）永远不满足条件，
/// 每次边界都要重探「已加载章数 × 页数」这么多页，代价随阅读进度往上走，
/// 而触发的瞬间恰好是「翻到最后一页」—— 这就是用户感到的那一下卡顿。
///
/// 现在用 [ImageSizeCubit.isProbed]：探过就记账（落空也算）。负缓存只挡这条
/// 「提前铺高度」的旁路，图片真正上屏时 `ImageDisplay` 照旧逐页
/// [ImageSizeCubit.updateSize]，不会因此停在占位高度上。
///
/// 命中结果按 [_prefetchFlushBatch] 攒批走 [ImageSizeCubit.updateSizes]，
/// 免得「每页复制一遍整份尺寸表 + 每页通知一次所有监听者」。
Future<void> prefetchChapterImageSizes({
  required ImageSizeCubit imageSizeCubit,
  required List<Doc> docs,
  required String comicId,
  required String from,
  required String chapterId,
  required int chapterOrder,
  required double contentWidth,
  CachedPicturePathResolver? resolveCachedPath,
}) async {
  final resolve = resolveCachedPath ?? findCachedPicturePath;
  final pending = <int, Size>{};

  for (var i = 0; i < docs.length; i++) {
    if (imageSizeCubit.isClosed) return;

    final cacheIndex = resolveStableSizeCacheIndex(
      chapterOrder: chapterOrder,
      localPageIndex: i,
    );
    if (imageSizeCubit.isProbed(cacheIndex)) continue;

    final doc = docs[i];
    final storageChapterId = doc.storageChapterId.trim();
    // 占坑在 IO 之前：同一章可能被并发启动，见 `claimProbe`。
    imageSizeCubit.claimProbe(cacheIndex);

    try {
      final filePath = await resolve(
        from: from,
        path: doc.path,
        cartoonId: comicId,
        chapterId: chapterId,
        storageChapterId: storageChapterId,
      );
      if (filePath.isEmpty) continue;

      final rawSize = await readImageHeaderSize(filePath);
      if (rawSize == null || rawSize.width <= 0 || rawSize.height <= 0) {
        continue;
      }
      if (imageSizeCubit.isClosed) return;

      // 与 ImageDisplay 上报保持一致：存渲染宽度 + 等比高度。
      final displayHeight = contentWidth * (rawSize.height / rawSize.width);
      pending[cacheIndex] = Size(contentWidth, displayHeight);
      if (pending.length >= _prefetchFlushBatch) {
        imageSizeCubit.updateSizes(pending);
        pending.clear();
      }
    } catch (_) {
      // 单张失败不影响其余图片；坑已占，本会话不再重试这一页。
    }
  }

  if (pending.isNotEmpty && !imageSizeCubit.isClosed) {
    imageSizeCubit.updateSizes(pending);
  }
}
