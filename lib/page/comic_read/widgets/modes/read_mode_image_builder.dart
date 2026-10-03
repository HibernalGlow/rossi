import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/model/reader_frame.dart';
import 'package:zephyr/page/comic_read/widgets/image/read_image_widget.dart';
import 'package:zephyr/reader/translated_page_overlay.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
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

  // 视频自行管理画面。静态 GPU 图片与普通图片共用真实尺寸算出的缩放/旋转框。
  final isVideo = entry.doc!.extern['isVideo'] == true;
  final effectivePlaced = isVideo ? null : placed;

  final image = ReadImageWidget(
    key: ValueKey((
      entry.chapterId,
      entry.chapterOrder,
      entry.chapterPageIndex,
      entry.doc!.fileServer,
      entry.doc!.path,
    )),
    // 章节 id 与本地存储目录 key 要分开传：下载任务落盘的目录段是后者，
    // 混用会让阅读器把已下载的页当作未下载重新请求。
    pictureInfo: PictureInfo(
      from: from,
      url: entry.doc!.fileServer,
      path: entry.doc!.path,
      cartoonId: comicId,
      chapterId: entry.chapterId!,
      storageChapterId: entry.doc!.storageChapterId,
      pictureType: PictureType.page,
      extern: entry.doc!.extern,
    ),
    index: slotIndex,
    cacheIndex: cacheIndex,
    displayNumber: displayNumber,
    isColumn: isColumn,
    imageAlignment: isVideo ? Alignment.center : imageAlignment,
    paintSize: effectivePlaced?.paintSize,
  );

  if (effectivePlaced == null) return image;

  // 占位盒按**旋转后**的尺寸给，图片本身画在旋转前的尺寸上 —— 两者只差一次宽高交换。
  // 旋转放在这一层而不是 `ImageDisplay` 里，是因为本地 GPU 管线那条分支（`ImageSurface`）
  // 走的是完全不同的绘制路径，放在外层才能让两条路径一起旋转。
  //
  // 叠层就挂在这一层的**里面**（同一个 `RotatedBox` 的孩子）：同一个理由反过来用 ——
  // 放在外层才能让两条渲染路一起被旋转 / 双页 / 页宽适配带着走，
  // 而不必在 Flutter 侧与 Rust 侧各算一遍变换。GPU 那条纹理通路一个字都不改。
  final painted = effectivePlaced.paintSize;
  // 半页也画：图层那份坐标始终是**整页**物理像素，`TranslatedPageOverlay` 按 [slice]
  // 自己裁（与底图那一路同一把尺 `PageSlice.uvRect`）。
  // 之前这里直接不挂叠层，于是横长页拆半读时芯片说「译文页」而画面上一个中文都没有 ——
  // 那是最难发现的一类错：状态是真的（这一页确实翻好了），只是没画。
  final overlay = !ocrSupportedHere
      ? const SizedBox.shrink()
      : TranslatedPageOverlay(
          pageIndex: slotIndex,
          boxSize: painted,
          slice: slice,
        );

  Widget withOverlay(Widget child) => Stack(
    fit: StackFit.passthrough,
    children: [child, Positioned.fill(child: overlay)],
  );

  if (effectivePlaced.quarterTurns == 0) {
    return SizedBox(
      width: effectivePlaced.boxSize.width,
      height: effectivePlaced.boxSize.height,
      child: withOverlay(image),
    );
  }
  return SizedBox(
    width: effectivePlaced.boxSize.width,
    height: effectivePlaced.boxSize.height,
    child: withOverlay(
      RotatedBox(
        quarterTurns: effectivePlaced.quarterTurns,
        child: image,
      ),
    ),
  );
}
