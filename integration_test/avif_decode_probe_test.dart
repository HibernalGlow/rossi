import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// **真机引擎**上的 AVIF 解码探针。
///
/// 为什么必须单开一个：`flutter test`（单元测试）跑的是 `flutter_tester`，
/// 那是个**软件渲染、无 Impeller** 的宿主；而 App 跑的是 `flutter_windows.dll`
/// + Impeller。同一个文件在 `test/avif_decode_probe_test.dart` 里四种形态全过，
/// 在 App 里却是 `Exception: Could not decompress image.` —— 两者的解码器
/// **不是同一个**，所以必须在真机上复测才能定论。
///
/// Rust 侧已由 `local_probe` 证明字节逐条正确（长度与头部都对得上），
/// 这里只回答「这台机器上的这个引擎，能不能解这堆字节」。
///
/// 跑法：`flutter test integration_test/avif_decode_probe_test.dart -d windows`
/// 样本缺失时静默跳过，不让别人 clone 后因为缺夹具而红。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真机引擎解码 AVIF 的能力探针', (tester) async {
    // ignore: avoid_print
    print('[probe] cwd = ${Directory.current.path}');

    // 扫目录而不是写死文件名：这样「真实样本」与「ffmpeg 造的对照」能一起测。
    // 对照的意义在于把变量降到只剩一个 —— c420 与 c444 尺寸相同、位深相同，
    // 只有色度采样（AV1 profile 0 / 1）不同。
    final dir = Directory('.workbuddy/tmp');
    final samples = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) {
              final p = f.path.toLowerCase();
              // jpg 是对照组：排除「大图本身解不动」这个变量。
              return p.endsWith('.avif') || p.endsWith('.jpg');
            }).toList()
              ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];

    if (samples.isEmpty) {
      // ignore: avoid_print
      print('[skip] 没有样本（.workbuddy/tmp/*.avif 或 *.jpg）');
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

      await _try('C TargetImageSize（ResizeImage 实际走的）', () async {
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

      await _try('D ImageDescriptor 裸描述', () async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final size = '${descriptor.width}x${descriptor.height}';
        descriptor.dispose();
        return size;
      });
    }

    // 对照：同一引擎解一张 PNG，排除「整条解码头都不通」。
    await _try('E 对照 PNG（1x1）', () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final size = '${frame.image.width}x${frame.image.height}';
      frame.image.dispose();
      codec.dispose();
      return size;
    });
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
