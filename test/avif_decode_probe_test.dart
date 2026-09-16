import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 量的是 **`flutter_tester`（单元测试宿主）** 的解码能力。
///
/// # 警告：这不是 App 解码能力的判据
///
/// 曾经拿这里的"全部通过"当作"显示路径可用"的证据，**结论是错的**。
/// App 跑的是 `flutter_windows.dll`，两者**不是同一个解码器**：
/// 同样这批字节，在 App 里 5 个样本 × 3 种调用形态**全部失败**
/// （`Exception: Could not decompress image.`），而同尺寸 JPEG 正常。
/// 引擎 PDB 里没有 `dav1d` / `libavif` / `aom` / `avif` 任何一个符号。
///
/// 要判断"App 能不能显示"，必须看**真机引擎**：
/// `integration_test/avif_decode_probe_test.dart`。
/// 这个文件留着只为记录这处宿主差异本身 —— 它正是一次教训的物证。
///
/// 背景：`E:\1Hub\EH\G44 不会受伤...zip` 里 30 张**全是 `.avif`**，而
/// `rust/local_core` 的 `IMAGE_EXTENSIONS` 不含 avif（它按 `image` crate 的
/// feature 集划线），于是归档被枚举成 **0 页** —— UI 表现为「打开 zip 没反应」。
///
/// 样本由 `.workbuddy/tmp/` 提供（从真实归档里抽出的原始字节，不入库）；
/// 样本不在时静默跳过，不让 CI/别人 clone 后因为缺夹具而红。
void main() {
  test('Skia 解码 AVIF 的能力探针', () async {
    final samples = [1, 2, 3]
        .map((i) => File('.workbuddy/tmp/sample-$i.avif'))
        .where((f) => f.existsSync())
        .toList();

    if (samples.isEmpty) {
      // ignore: avoid_print
      print('[skip] 没有 avif 样本（.workbuddy/tmp/sample-*.avif）');
      return;
    }

    for (final file in samples) {
      final bytes = await file.readAsBytes();
      // ignore: avoid_print
      print('\n=== ${file.path}  ${bytes.length} B ===');

      await _try('A 裸解码 instantiateImageCodec(bytes)', () async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final size = '${frame.image.width}x${frame.image.height}';
        frame.image.dispose();
        codec.dispose();
        return size;
      });

      await _try('B 带 targetWidth（旧签名，≡ResizeImage）', () async {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 600,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        final size = '${frame.image.width}x${frame.image.height}';
        frame.image.dispose();
        codec.dispose();
        return size;
      });

      await _try('C TargetImageSize（新签名，ResizeImage 实际用的）', () async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final codec = await descriptor.instantiateCodec(
          targetWidth: 600,
          targetHeight: 600,
        );
        final frame = await codec.getNextFrame();
        final size = '${frame.image.width}x${frame.image.height}';
        frame.image.dispose();
        codec.dispose();
        return size;
      });

      await _try('D ImageDescriptor 裸描述（先只建描述子）', () async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final size = '${descriptor.width}x${descriptor.height}';
        descriptor.dispose();
        return size;
      });
    }
  });
}

Future<void> _try(String label, Future<String> Function() body) async {
  try {
    final result = await body();
    // ignore: avoid_print
    print('  OK    $label -> $result');
  } catch (e) {
    // ignore: avoid_print
    print('  FAIL  $label -> $e');
  }
}
