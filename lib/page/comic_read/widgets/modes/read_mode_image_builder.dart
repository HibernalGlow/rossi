import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/model/reader_frame.dart';
import 'package:zephyr/page/comic_read/widgets/image/read_image_widget.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

/// 构造列/行模式共用的图片 widget。
///
/// - [slotIndex] 会作为 [ReadImageWidget] 的 `pageSlotIndex`。
/// - [cacheIndex] 会作为 [ReadImageWidget] 的 `sizeCacheIndex`。
/// - [displayNumber] 用于行模式等需要显式页号的场景；为 null 时使用 [slotIndex] + 1。
/// - [placed] 是顶栏缩放/旋转面板对**这一页**的排布结果；为 null 时按老逻辑铺满宽度。
Widget buildReadModeImage({
  required BuildContext context,
  required ReadModeEntry entry,
  required String comicId,
  required String from,
  required int slotIndex,
  required int cacheIndex,
  required bool isColumn,
  int? displayNumber,
  Alignment imageAlignment = Alignment.center,
  ReaderPlacedPage? placed,
}) {
  if (entry.type != ReadModeEntryType.image ||
      entry.doc == null ||
      entry.chapterId == null) {
    return const SizedBox.shrink();
  }

  final resolvedChapterId = entry.doc!.storageChapterId.trim().isNotEmpty
      ? entry.doc!.storageChapterId
      : entry.chapterId!;

  final image = ReadImageWidget(
    key: ValueKey((
      entry.chapterId,
      entry.chapterOrder,
      entry.chapterPageIndex,
      entry.doc!.fileServer,
      entry.doc!.path,
    )),
    pictureInfo: PictureInfo(
      from: from,
      url: entry.doc!.fileServer,
      path: entry.doc!.path,
      cartoonId: comicId,
      chapterId: resolvedChapterId,
      pictureType: PictureType.page,
      extern: entry.doc!.extern,
    ),
    index: slotIndex,
    cacheIndex: cacheIndex,
    displayNumber: displayNumber,
    isColumn: isColumn,
    imageAlignment: imageAlignment,
    paintSize: placed?.paintSize,
  );

  if (placed == null) return image;

  // 占位盒按**旋转后**的尺寸给，图片本身画在旋转前的尺寸上 —— 两者只差一次宽高交换。
  // 旋转放在这一层而不是 `ImageDisplay` 里，是因为本地 GPU 管线那条分支（`ImageSurface`）
  // 走的是完全不同的绘制路径，只有包在这一层才能一起转起来。
  return SizedBox(
    width: placed.boxSize.width,
    height: placed.boxSize.height,
    child: placed.quarterTurns == 0
        ? image
        : RotatedBox(quarterTurns: placed.quarterTurns, child: image),
  );
}
