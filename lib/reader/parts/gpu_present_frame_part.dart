part of '../gpu_present_controller.dart';
// 呈现帧数据类



/// 一次完成呈现的身份与画布尺寸；共享纹理 id 本身不能证明里面是哪一页。
@immutable
class GpuPresentedFrame {
  const GpuPresentedFrame({
    required this.source,
    required this.index,
    required this.physicalSize,
    required this.textureId,
  });

  final PageSource source;
  final int index;
  final Size physicalSize;
  final int textureId;

  bool matches(PageSource source, int index, Size physicalSize) =>
      identical(this.source, source) &&
      this.index == index &&
      this.physicalSize.width.round() == physicalSize.width.round() &&
      this.physicalSize.height.round() == physicalSize.height.round();
}
