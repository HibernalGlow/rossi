import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';

/// **真机引擎**上的 GPU 上屏探针（Windows / D3D12 共享纹理）。
///
/// 为什么必须是集成测试而不是单元测试：这条链路的最后一环是**引擎来打开我们给的
/// 共享句柄**，而那只会在真实窗口把 `Texture` 合成出去的时候发生。`flutter test`
/// 跑的是 `flutter_tester`（软件渲染、没有 Windows embedder、连 `TextureRegistrar`
/// 都没有），在那里"通过"什么也证明不了。
///
/// 判据只有一条：`handleOpened > 0`。我们先渲染、再通知引擎取帧（`framesMarked`），
/// 但那只证明我们喊过；引擎真的打开句柄，才证明屏幕上的像素确实来自 Rust 侧
/// 那张纹理 —— 而不是某个默认的空白纹理。
///
/// 跑法：
/// ```
/// flutter test integration_test/gpu_present_probe_test.dart -d windows
/// ```
/// 样本路径可用 `ROSSI_GPU_PRESENT_SAMPLE` 覆盖，默认取 `.workbuddy/tmp` 之外
/// 的固定夹具；样本缺失时**静默跳过**，不让别人 clone 后因为缺夹具而红。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String defaultSample = r'D:\1Dev\tmp\rossi-probe\probe.cbz';

  void log(String message) {
    // ignore: avoid_print
    print('[gpu-present] $message');
  }

  testWidgets('D3D12 共享纹理上屏：引擎真的来取帧', (WidgetTester tester) async {
    if (!GpuPresentBridge.isPlatformSupported) {
      log('[skip] 非 Windows 平台，这条路径不存在');
      return;
    }

    final String path =
        Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ?? defaultSample;
    if (!File(path).existsSync() && !Directory(path).existsSync()) {
      log('[skip] 样本不存在: $path');
      return;
    }
    log('sample = $path');

    const GpuPresentBridge bridge = GpuPresentBridge();

    // 先读一次 native 侧状态：`rossi_gpu_present.dll` 没构建、没拷到 exe 旁边、
    // 或者 C++ 桥注册失败，都会在这里以可读的原因暴露出来。
    final GpuPresentStats before = await bridge.stats();
    log(
      'native ok=${before.ok} adapter=${before.adapter} '
      'luidKnown=${before.luidKnown} error=${before.error}',
    );
    expect(before.ok, isTrue, reason: 'native 侧不可用：${before.error}');

    final int textureId = await bridge.init(width: 800, height: 600);
    log('textureId = $textureId');
    expect(textureId, greaterThanOrEqualTo(0));

    final int pageCount = await bridge.open(path);
    log('pageCount = $pageCount');
    expect(pageCount, greaterThan(0), reason: '本地来源打不开或没有页');

    await bridge.show(0);

    // 把纹理放进真实窗口。**故意不给它套 AspectRatio / BoxFit**：页的等比缩放
    // 与留边是在 Rust 侧着色器里做的，这张纹理本来就已经是"屏幕上的那一幅"。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: Texture(textureId: textureId),
            ),
          ),
        ),
      ),
    );

    // 引擎的 raster 线程取帧是异步的，`pump` 只推进一帧，所以中间要放真实时间。
    GpuPresentStats stats = await bridge.stats();
    for (int i = 0; i < 40 && stats.handleOpened == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stats = await bridge.stats();
    }

    log(
      'framesMarked=${stats.framesMarked} handleOpened=${stats.handleOpened} '
      'resizes=${stats.resizes} size=${stats.width}x${stats.height}',
    );
    log('probe = ${stats.probeRaw}');

    expect(
      stats.framesMarked,
      greaterThan(0),
      reason: '我们从未通知过引擎来取帧 —— SurfaceCallback 没被调用',
    );
    expect(
      stats.handleOpened,
      greaterThan(0),
      reason: '引擎没有打开共享句柄 —— 屏幕上的画面不是来自这张纹理',
    );

    // 解码与上传的分段耗时由 Rust 侧上报；有了它，"像素过桥"这件事才有个刻度。
    log(
      'decode=${stats.probeDouble('decodeMs').toStringAsFixed(1)}ms '
      'upload=${stats.probeDouble('uploadMs').toStringAsFixed(1)}ms '
      'submit=${stats.probeDouble('submitMs').toStringAsFixed(1)}ms '
      'decoded=${stats.probeInt('decodedWidth')}x${stats.probeInt('decodedHeight')} '
      'source=${stats.probeInt('sourceWidth')}x${stats.probeInt('sourceHeight')}',
    );
  });
}
