import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_frame.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_image_builder.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_transition_style.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

/// 阅读模式渲染轴。
enum ReadModeAxis { column, row }

/// 把单个显示槽位渲染为 Widget，不关心外层滚动容器。
///
/// [singleItem] 与 [doublePageSlot] 有且仅有一个非 null：
/// - 单页模式使用 [singleItem]；
/// - 双页模式使用 [doublePageSlot]。
///
/// [viewportHeight] 是这一帧能占到的**高度**（横翻 = 一整页的高；条漫 = 视口高，
/// 只有 `fit-height` 会用到它）。呈现层没有参与（算不出帧）时整条链路退回
/// 改造前的铺排，第一帧因此与今天一致。
Widget buildReadModeSlot({
  required BuildContext context,
  required int slotIndex,
  required ReadModeSlotItem? singleItem,
  required ReadModeDoublePageSlot? doublePageSlot,
  required ReadModeAxis axis,
  required double containerWidth,
  required double contentWidth,
  required double viewportHeight,
  required ReaderPresentation presentation,
  required Color backgroundColor,
  required bool isRtl,
  required String comicId,
  required String from,
  required ValueChanged<int>? onTransitionAction,
  required ReadModeTransitionStyle transitionStyle,
  bool seamlessDoublePage = false,
}) {
  assert(
    (singleItem == null) != (doublePageSlot == null),
    '必须且只能传入 singleItem 或 doublePageSlot 之一',
  );

  if (singleItem != null) {
    final entry = singleItem.entry;
    if (entry.type == ReadModeEntryType.transition) {
      return buildReadModeTransitionItem(
        entry: entry,
        backgroundColor: backgroundColor,
        onTap: () => onTransitionAction?.call(entry.chapterOrder),
        containerWidth: containerWidth,
        fixedCardSize: transitionStyle.fixedCardSize,
        outerPadding: transitionStyle.outerPadding,
        cardPadding: transitionStyle.cardPadding,
        minHeight: transitionStyle.minHeight,
        lineSpacing: transitionStyle.lineSpacing,
      );
    }

    if (axis == ReadModeAxis.column) {
      return _buildColumnSingleImage(
        context: context,
        item: singleItem,
        containerWidth: containerWidth,
        contentWidth: contentWidth,
        viewportHeight: viewportHeight,
        presentation: presentation,
        backgroundColor: backgroundColor,
        comicId: comicId,
        from: from,
      );
    }

    return _buildRowFrame(
      context: context,
      slotIndex: slotIndex,
      items: [singleItem],
      containerWidth: containerWidth,
      contentWidth: contentWidth,
      viewportHeight: viewportHeight,
      presentation: presentation,
      backgroundColor: backgroundColor,
      isRtl: isRtl,
      comicId: comicId,
      from: from,
      // 条漫以外的一帧只有一张图时，「双页留缝」没有可言。
      seamless: true,
    );
  }

  final slot = doublePageSlot!;
  if (slot.transition != null) {
    final entry = slot.transition!.entry;
    return buildReadModeTransitionItem(
      entry: entry,
      backgroundColor: backgroundColor,
      onTap: () => onTransitionAction?.call(entry.chapterOrder),
      containerWidth: containerWidth,
      fixedCardSize: transitionStyle.fixedCardSize,
      outerPadding: transitionStyle.outerPadding,
      cardPadding: transitionStyle.cardPadding,
      minHeight: transitionStyle.minHeight,
      lineSpacing: transitionStyle.lineSpacing,
    );
  }

  if (axis == ReadModeAxis.column) {
    return _buildColumnDoublePageImage(
      context: context,
      slot: slot,
      slotIndex: slotIndex,
      containerWidth: containerWidth,
      contentWidth: contentWidth,
      backgroundColor: backgroundColor,
      isRtl: isRtl,
      comicId: comicId,
      from: from,
    );
  }

  final items = <ReadModeSlotItem>[
    if (slot.left != null) slot.left!,
    if (slot.right != null) slot.right!,
  ];
  if (items.isEmpty) return const SizedBox.shrink();

  return _buildRowFrame(
    context: context,
    slotIndex: slotIndex,
    items: items,
    containerWidth: containerWidth,
    contentWidth: contentWidth,
    viewportHeight: viewportHeight,
    presentation: presentation,
    backgroundColor: backgroundColor,
    isRtl: isRtl,
    comicId: comicId,
    from: from,
    seamless: seamlessDoublePage,
  );
}

// ── 横翻：呈现层真正生效的那条路 ────────────────────────────────────────────

/// 横翻一帧（1 或 2 页）的排布。
///
/// 先按**帧**算（整帧铺进视口，与 neoview 同一口径），再决定怎么**摆**：
/// - [seamless] 开 → 两张图紧挨着（帧本来就是紧挨着算的，直接排）；
/// - [seamless] 关 → 各自居中在自己的半宽格里，窄图旁留出缝（改造前的观感）。
Widget _buildRowFrame({
  required BuildContext context,
  required int slotIndex,
  required List<ReadModeSlotItem> items,
  required double containerWidth,
  required double contentWidth,
  required double viewportHeight,
  required ReaderPresentation presentation,
  required Color backgroundColor,
  required bool isRtl,
  required String comicId,
  required String from,
  required bool seamless,
}) {
  final cacheIndices = items
      .map((item) => _resolveImageCacheIndex(item.entry, item.entryIndex))
      .toList();

  return BlocSelector<
    ImageSizeCubit,
    ImageSizeState,
    List<({Size cached, Size? intrinsic})>
  >(
    selector: (state) => [
      for (final index in cacheIndices)
        (
          cached: state.getSizeValue(index),
          intrinsic: state.getIntrinsic(index),
        ),
    ],
    builder: (context, sizes) {
      final frame = _frameOf(
        sizes: sizes,
        contentWidth: contentWidth,
        viewportHeight: viewportHeight,
        presentation: presentation,
      );
      // 帧里少了一页就意味着「这一帧里谁占哪儿」和条目顺序对不上了 —— 与其错配，
      // 整帧退回改造前的铺排。正常情况下 `getSizeValue` 永远给得出兜底尺寸，
      // 走不到这条。
      if (frame == null || frame.pages.length != items.length) {
        return _legacyRowSlot(
          context: context,
          slotIndex: slotIndex,
          items: items,
          cacheIndices: cacheIndices,
          containerWidth: containerWidth,
          contentWidth: contentWidth,
          backgroundColor: backgroundColor,
          isRtl: isRtl,
          comicId: comicId,
          from: from,
          seamless: seamless,
        );
      }

      // RTL（左开）下两张图左右互换，与改造前同一处理。
      var order = [
        for (var i = 0; i < items.length; i++) i,
      ];
      if (isRtl) order = order.reversed.toList();

      final pages = <Widget>[];
      for (final i in order) {
        final page = _page(
          context: context,
          item: items[i],
          placed: frame.pages[i],
          slotIndex: slotIndex,
          cacheIndex: cacheIndices[i],
          comicId: comicId,
          from: from,
          presentation: presentation,
        );
        pages.add(
          seamless
              ? page
              : SizedBox(
                  width: contentWidth / items.length,
                  child: Center(child: page),
                ),
        );
      }

      return Container(
        color: backgroundColor,
        width: containerWidth,
        height: viewportHeight,
        // 帧可以比视口宽（适应宽度遇上横页、或手动放大之后）—— 这一层必须
        // **先按自身尺寸排开、再被视口裁掉**。直接放在受限的 Row 里会画出
        // 黄黑溢出条纹；`UnconstrainedBox` 给回 neoview 那种「帧按自己大小
        // 摆、容器 overflow: hidden」的行为，`alignment` 同时负责 fit-left/right。
        child: ClipRect(
          child: UnconstrainedBox(
            alignment: presentation.fitMode.alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: pages,
            ),
          ),
        ),
      );
    },
  );
}

/// 用帧模型算这一帧的排布；null = 呈现层不参与。
///
/// ## 尺寸基准
///
/// 优先用**原始像素尺寸**：两张图并排时，各自的宽本来就该按各自的比例来，
/// 统一压成同一个宽度会让「宽度对齐」这一档永远算出 1 倍（无从生效）。
/// 只要有一页还没解出原始尺寸，就退回「每页都按 contentWidth」的近似基准 ——
/// 单页下两种基准铺出来**完全一样**（比例与基准无关：内容放大 k 倍，
/// 算出的 scale 就小 k 倍，落地的框大小不变），双页下只是暂时等宽。
/// `original` 例外：它要的就是绝对像素，没有原始尺寸只能不参与。
ReaderFrame? _frameOf({
  required List<({Size cached, Size? intrinsic})> sizes,
  required double contentWidth,
  required double viewportHeight,
  required ReaderPresentation presentation,
  ReaderFrameAxis axis = ReaderFrameAxis.page,
}) {
  if (sizes.isEmpty || contentWidth <= 0 || viewportHeight <= 0) return null;

  final intrinsics = sizes.map((size) => size.intrinsic).toList();
  final hasAllIntrinsics = intrinsics.every((size) => size != null);

  if (presentation.fitMode == ReaderFitMode.original && !hasAllIntrinsics) {
    return null;
  }

  final basis = <Size>[];
  for (var i = 0; i < sizes.length; i++) {
    if (hasAllIntrinsics) {
      basis.add(intrinsics[i]!);
      continue;
    }
    final cached = sizes[i].cached;
    if (cached.width <= 0 || cached.height <= 0) return null;
    basis.add(Size(contentWidth, contentWidth * cached.height / cached.width));
  }

  return ReaderFrame.of(
    intrinsicPages: basis,
    viewport: Size(contentWidth, viewportHeight),
    presentation: presentation,
    axis: axis,
  );
}

Widget _page({
  required BuildContext context,
  required ReadModeSlotItem item,
  required ReaderPlacedPage placed,
  required int slotIndex,
  required int cacheIndex,
  required String comicId,
  required String from,
  required ReaderPresentation presentation,
}) {
  return buildReadModeImage(
    context: context,
    entry: item.entry,
    comicId: comicId,
    from: from,
    slotIndex: slotIndex,
    cacheIndex: cacheIndex,
    displayNumber: (item.entry.chapterPageIndex ?? 0) + 1,
    isColumn: false,
    imageAlignment: presentation.fitMode.alignment,
    placed: placed,
  );
}

/// 呈现层不参与时的行模式铺排 —— 与改造前逐字一致。
Widget _legacyRowSlot({
  required BuildContext context,
  required int slotIndex,
  required List<ReadModeSlotItem> items,
  required List<int> cacheIndices,
  required double containerWidth,
  required double contentWidth,
  required Color backgroundColor,
  required bool isRtl,
  required String comicId,
  required String from,
  required bool seamless,
}) {
  final panelWidth = (contentWidth / math.max(1, items.length)).clamp(
    1.0,
    contentWidth,
  );
  // 无缝模式把两张图贴向中间边缘，避免各自居中后在接缝处留白。
  final leftAlignment = !seamless
      ? Alignment.center
      : (isRtl ? Alignment.centerLeft : Alignment.centerRight);
  final rightAlignment = !seamless
      ? Alignment.center
      : (isRtl ? Alignment.centerRight : Alignment.centerLeft);

  final children = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    final alignment = items.length == 1
        ? Alignment.center
        : (i == 0
              ? (isRtl ? rightAlignment : leftAlignment)
              : (isRtl ? leftAlignment : rightAlignment));
    children.add(
      SizedBox(
        width: panelWidth,
        child: buildReadModeImage(
          context: context,
          entry: items[i].entry,
          comicId: comicId,
          from: from,
          slotIndex: slotIndex,
          cacheIndex: cacheIndices[i],
          displayNumber: (items[i].entry.chapterPageIndex ?? 0) + 1,
          isColumn: false,
          imageAlignment: alignment,
        ),
      ),
    );
  }

  final ordered = isRtl ? children.reversed.toList() : children;

  // 「顶部对齐」只属于双页无缝那一格：两张图要贴着顶边拼。
  // 单页（以及改造前的每一格）都是垂直居中，这里不能跟着一起改。
  final topAligned = seamless && items.length > 1;

  return Container(
    color: backgroundColor,
    width: containerWidth,
    alignment: topAligned ? Alignment.topCenter : Alignment.center,
    child: SizedBox(
      width: contentWidth,
      child: Row(
        crossAxisAlignment: topAligned
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: ordered,
      ),
    ),
  );
}

// ── 条漫 ──────────────────────────────────────────────────────────────────

Widget _buildColumnSingleImage({
  required BuildContext context,
  required ReadModeSlotItem item,
  required double containerWidth,
  required double contentWidth,
  required double viewportHeight,
  required ReaderPresentation presentation,
  required Color backgroundColor,
  required String comicId,
  required String from,
}) {
  final entry = item.entry;
  final cacheIndex = _resolveImageCacheIndex(entry, item.entryIndex);

  return BlocSelector<ImageSizeCubit, ImageSizeState, (Size, Size?)>(
    selector: (state) => (
      state.getSizeValue(cacheIndex),
      state.getIntrinsic(cacheIndex),
    ),
    builder: (context, sizes) {
      final frame = _frameOf(
        sizes: [
          (cached: sizes.$1, intrinsic: sizes.$2),
        ],
        contentWidth: contentWidth,
        viewportHeight: viewportHeight,
        presentation: presentation,
        axis: ReaderFrameAxis.strip,
      );
      final placed = frame?.pages.first;

      // 长条滚动下「列表项多高」必须等于「这一节画多高」，否则节与节重叠。
      // 呈现层没参与时退回改造前那套按宽高比推的高度。
      final finalHeight = placed?.boxSize.height ??
          _resolveDisplayHeight(
            cachedSize: sizes.$1,
            targetWidth: contentWidth,
          );

      final image = buildReadModeImage(
        context: context,
        entry: entry,
        comicId: comicId,
        from: from,
        slotIndex: entry.chapterPageIndex ?? item.entryIndex,
        cacheIndex: cacheIndex,
        isColumn: true,
        placed: placed,
      );

      return Container(
        color: backgroundColor,
        height: finalHeight,
        width: containerWidth,
        alignment: presentation.fitMode.alignment,
        child: placed == null
            ? SizedBox(width: contentWidth, height: finalHeight, child: image)
            : image,
      );
    },
  );
}

/// 条漫下的双页：仍走改造前的半宽格铺排。
///
/// 呈现层这一版**刻意不接**这条：条漫里一帧两页要同时满足「横向配对」与
/// 「纵向拼接」两个轴，`fit-height` 之类的语义在这里没有唯一正确的解释，
/// 硬造一个不如留空。横翻那条路（阅读时占绝大多数的一路）是全量支持的。
Widget _buildColumnDoublePageImage({
  required BuildContext context,
  required ReadModeDoublePageSlot slot,
  required int slotIndex,
  required double containerWidth,
  required double contentWidth,
  required Color backgroundColor,
  required bool isRtl,
  required String comicId,
  required String from,
}) {
  final left = slot.left;
  final right = slot.right;
  if (left == null && right == null) return const SizedBox.shrink();

  final panelWidth = (contentWidth / 2).clamp(1.0, contentWidth);

  return BlocSelector<ImageSizeCubit, ImageSizeState, (Size, Size)>(
    selector: (state) => (
      left != null
          ? state.getSizeValue(
              _resolveImageCacheIndex(left.entry, left.entryIndex),
            )
          : const Size(0, 0),
      right != null
          ? state.getSizeValue(
              _resolveImageCacheIndex(right.entry, right.entryIndex),
            )
          : const Size(0, 0),
    ),
    builder: (context, pairSize) {
      final leftHeight = left != null
          ? _resolveDisplayHeight(
              cachedSize: pairSize.$1,
              targetWidth: panelWidth,
            )
          : 0.0;
      final rightHeight = right != null
          ? _resolveDisplayHeight(
              cachedSize: pairSize.$2,
              targetWidth: panelWidth,
            )
          : 0.0;
      final rowHeight = math
          .max(leftHeight, rightHeight)
          .clamp(1.0, double.infinity);

      final leftChild = SizedBox(
        width: panelWidth,
        height: rowHeight,
        child: left != null
            ? buildReadModeImage(
                context: context,
                entry: left.entry,
                comicId: comicId,
                from: from,
                slotIndex: left.entry.chapterPageIndex ?? left.entryIndex,
                cacheIndex: _resolveImageCacheIndex(
                  left.entry,
                  left.entryIndex,
                ),
                isColumn: true,
              )
            : const SizedBox.shrink(),
      );
      final rightChild = SizedBox(
        width: panelWidth,
        height: rowHeight,
        child: right != null
            ? buildReadModeImage(
                context: context,
                entry: right.entry,
                comicId: comicId,
                from: from,
                slotIndex: right.entry.chapterPageIndex ?? right.entryIndex,
                cacheIndex: _resolveImageCacheIndex(
                  right.entry,
                  right.entryIndex,
                ),
                isColumn: true,
              )
            : const SizedBox.shrink(),
      );

      final children = isRtl
          ? [rightChild, leftChild]
          : [leftChild, rightChild];

      return Container(
        color: backgroundColor,
        width: containerWidth,
        height: rowHeight,
        alignment: Alignment.center,
        child: SizedBox(
          width: contentWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
    },
  );
}

int _resolveImageCacheIndex(ReadModeEntry entry, int fallbackIndex) {
  final localPageIndex = entry.chapterPageIndex;
  if (entry.type != ReadModeEntryType.image || localPageIndex == null) {
    return fallbackIndex;
  }
  return resolveStableSizeCacheIndex(
    chapterOrder: entry.chapterOrder,
    localPageIndex: localPageIndex,
  );
}

double _resolveDisplayHeight({
  required Size cachedSize,
  required double targetWidth,
}) {
  if (cachedSize.width <= 0 || cachedSize.height <= 0) {
    return 1;
  }

  if ((cachedSize.width - targetWidth).abs() < 0.1) {
    return cachedSize.height;
  }

  final aspectRatio = cachedSize.height / cachedSize.width;
  return (targetWidth * aspectRatio).clamp(1.0, double.infinity);
}
