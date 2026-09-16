import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 这一次实验只回答一个问题：**Flutter/Skia 能不能解 AVIF？**
///
/// 背景：`E:\1Hub\EH\G44 不会受伤...zip` 里 30 张**全是 `.avif`**，而
/// `rust/local_core` 的 `IMAGE_EXTENSIONS` 不含 avif（它按 `image` crate 的
/// feature 集划线），于是归档被枚举成 **0 页** —— UI 表现为「打开 zip 没反应」。
///
/// 但**显示路径走的是 Flutter/Skia 的解码器**（Dart 兜底路径，见
/// `docs/v0.1-local-core.md` §9），两者能力并不相同。所以要分开量：
/// 「v0.1 能不能**显示** avif」与「Rust 侧能不能**解出像素**（Phase 1 上屏）」是两件事。
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
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        // ignore: avoid_print
        print('OK   ${file.path}  ${bytes.length} B -> '
            '${frame.image.width}x${frame.image.height}');
        frame.image.dispose();
        codec.dispose();
      } catch (e) {
        // ignore: avoid_print
        print('FAIL ${file.path}  ${bytes.length} B -> $e');
      }
    }
  });
}
