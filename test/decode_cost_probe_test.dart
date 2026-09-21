import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 解码成本量具：**为什么判据 C 不可能由「CPU/Dart 全尺寸解码」达成**。
///
/// 用法（样本不在时整组跳过，所以 CI 上不会失败）：
///
/// ```bash
/// # 从任意 CBZ 里抽一页出来当样本
/// python -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1]);\
///   n=[i.filename for i in z.infolist() if i.filename.lower().endswith('.jpg')][1];\
///   open('build/local-samples/one-page.jpg','wb').write(z.read(n))" <你的.cbz>
///
/// flutter test test/decode_cost_probe_test.dart
/// ```
///
/// 为什么要有这个文件：调试页上的「解码 500 ms」是在完整 App 里量的，读数里混着
/// 纹理上传与首帧调度。这里把解码单独拎到 `flutter_tester` 里量，只回答一个问题 ——
/// **同一张图，解码到全尺寸 vs 解码到显示尺寸，差多少？**
///
/// `targetWidth` 走的是 `ui.instantiateImageCodec(targetWidth:)`，对应 Skia 的
/// `SkCodec` 缩放解码路径：JPEG 可以按 1/2、1/4、1/8 做 DCT 缩放，**不是**先解全尺寸
/// 再缩放。这正是 `ResizeImage` / `cacheWidth` 省下成本的机制。
///
/// 参照实测（`E:\1Hub\EH\G44不会受伤 八奈见杏菜（泳装）.cbz`，JPEG 5464×8192 = 44.8 MPix）：
/// 全尺寸解码约 500 ms、RGBA 位图 179 MB；按显示宽度（约 800–1400 px）解码后
/// 像素量降一到两个数量级。判据 C 要求 p95 ≤ 16.7 ms —— 连场景不明的解码都放不下，
/// 所以目标形态只能是 Rust 侧按需解码 + 直接进 GPU（Phase 1 `texture-bridge`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sample = File('build/local-samples/one-page.jpg');

  Future<({int ms, int width, int height})> decode(
    Uint8List bytes,
    int? targetWidth,
  ) async {
    final sw = Stopwatch()..start();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );
    final frame = await codec.getNextFrame();
    sw.stop();
    final result = (
      ms: sw.elapsedMilliseconds,
      width: frame.image.width,
      height: frame.image.height,
    );
    frame.image.dispose();
    codec.dispose();
    return result;
  }

  test('解码成本随目标宽度下降（量具，非断言）', () async {
    final bytes = await sample.readAsBytes();
    // 预热一次，避免把首次的引擎初始化算进来。
    await decode(bytes, 800);

    final full = <({int ms, int width, int height})>[];
    final scaled = <({int ms, int width, int height})>[];
    for (var i = 0; i < 3; i++) {
      full.add(await decode(bytes, null));
      scaled.add(await decode(bytes, 800));
    }
    // 再测一档更宽的目标，看缩放档位（DCT 1/2、1/4、1/8）落在哪里。
    final mid = <({int ms, int width, int height})>[];
    for (var i = 0; i < 3; i++) {
      mid.add(await decode(bytes, 1600));
    }

    int best(List<int> xs) => xs.reduce((a, b) => a < b ? a : b);

    final fullMs = best(full.map((r) => r.ms).toList());
    final midMs = best(mid.map((r) => r.ms).toList());
    final scaledMs = best(scaled.map((r) => r.ms).toList());

    // ignore: avoid_print
    print('''
=== 解码成本量具（样本 ${sample.path}，${(bytes.length / 1e6).toStringAsFixed(2)} MB）===
  全尺寸          : ${fullMs.toString().padLeft(4)} ms  ${full.first.width}x${full.first.height}  ${(full.first.width * full.first.height / 1e6).toStringAsFixed(1)} MPix  RGBA ${(full.first.width * full.first.height * 4 / 1e6).toStringAsFixed(1)} MB
  目标宽 1600     : ${midMs.toString().padLeft(4)} ms  ${mid.first.width}x${mid.first.height}  ${(mid.first.width * mid.first.height / 1e6).toStringAsFixed(1)} MPix  RGBA ${(mid.first.width * mid.first.height * 4 / 1e6).toStringAsFixed(1)} MB
  目标宽  800     : ${scaledMs.toString().padLeft(4)} ms  ${scaled.first.width}x${scaled.first.height}  ${(scaled.first.width * scaled.first.height / 1e6).toStringAsFixed(1)} MPix  RGBA ${(scaled.first.width * scaled.first.height * 4 / 1e6).toStringAsFixed(1)} MB
  → 全尺寸/800px = ${(fullMs / (scaledMs == 0 ? 1 : scaledMs)).toStringAsFixed(1)}×
  判据 C 预算     : 16.7 ms（p95）''');

    expect(full.first.width, greaterThan(0));
    expect(scaled.first.width, lessThanOrEqualTo(800));
  }, skip: !sample.existsSync() ? '样本不存在：${sample.path}' : null);
}
