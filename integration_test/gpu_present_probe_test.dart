import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/util/rust_loader.dart';

/// **真机引擎**上的 GPU 上屏探针（Windows / D3D12 共享纹理）。
///
/// 为什么必须是集成测试而不是单元测试：这条链路的最后一环是**引擎来打开我们给的
/// 共享句柄**，而那只会在真实窗口把 `Texture` 合成出去的时候发生。`flutter test`
/// 跑的是 `flutter_tester`（软件渲染、没有 Windows embedder、连 `TextureRegistrar`
/// 都没有），在那里"通过"什么也证明不了。
///
/// # 它验三件事
///
/// 1. **呈现器是异步建的**：`create` 在 `FlutterWindow::OnCreate` 里被调，它必须
///    立刻返回、不压在第一帧之前。所以启动后第一次问 `status` 很可能还是
///    `loading` —— 那不是失败，是这条路径该有的样子。
/// 2. **上屏本身**：`handleOpened > 0`。我们先渲染、再通知引擎取帧
///    （`framesMarked`），但那只证明我们喊过；引擎真的打开句柄，才证明屏幕上的
///    像素确实来自 Rust 侧那张纹理 —— 而不是某个默认的空白纹理。
/// 3. **兜底路径真的能用**：就绪前那一套（`local_core` + `decodeImageFromPixels`）
///    走的是完全不同的接口。不单独验一次，"就绪前走兜底"就只是一句话。
///
/// 跑法：
/// ```
/// flutter test integration_test/gpu_present_probe_test.dart -d windows
/// ```
/// 样本路径可用 `ROSSI_GPU_PRESENT_SAMPLE` 覆盖，默认取固定夹具；
/// 样本缺失时**静默跳过**，不让别人 clone 后因为缺夹具而红。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String defaultSample = r'D:\1Dev\tmp\rossi-probe\probe.cbz';

  void log(String message) {
    // ignore: avoid_print
    print('[gpu-present] $message');
  }

  testWidgets('D3D12 共享纹理上屏：异步创建 + 兜底路径 + 引擎真的来取帧',
      (WidgetTester tester) async {
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

    // ── 1. 异步创建 ──
    //
    // 先读一次 native 侧状态：`rossi_gpu_present.dll` 没构建、没拷到 exe 旁边、
    // 或者 C++ 桥注册失败，都会在这里以可读的原因暴露出来。
    final GpuPresentStats before = await bridge.stats();
    log(
      'native ok=${before.ok} state=${before.state.name} adapter=${before.adapter} '
      'luidKnown=${before.luidKnown} error=${before.error}',
    );
    expect(before.ok, isTrue, reason: 'native 侧不可用：${before.error}');
    expect(
      before.error,
      isNot(contains('缺少必要的导出符号')),
      reason: 'DLL 与桥的版本不匹配 —— 重新构建 rossi_gpu_present',
    );

    final GpuPresentStatus first = await bridge.status();
    log('启动后首次 status = ${first.state.name}');
    if (first.state == GpuPresentState.loading) {
      log('→ 呈现器仍在后台创建，说明 create 确实没有阻塞启动（这正是要的效果）');
    }

    GpuPresentStatus status = first;
    final Stopwatch waited = Stopwatch()..start();
    while (status.state == GpuPresentState.loading &&
        waited.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      status = await bridge.status();
    }
    waited.stop();
    log('等呈现器就绪：${waited.elapsedMilliseconds} ms → ${status.state.name}');
    expect(
      status.state,
      GpuPresentState.ready,
      reason: '呈现器没能在 30 s 内就绪：${status.error}',
    );

    // ── 2. 建目标并上屏 ──
    final GpuPresentStatus initialized = await bridge.tryInit(width: 800, height: 600);
    expect(
      initialized.isReady,
      isTrue,
      reason: '就绪之后 tryInit 仍不是 ready：${initialized.error}',
    );
    final int textureId = initialized.textureId;
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
    // 呈现器那 ~1 s 花在哪：device 那一段与管线那一段的可优化性完全不同，
    // 所以它们必须分开报，否则以后不知道该往哪使劲。
    log(
      'init=${stats.probeDouble('initMs').toStringAsFixed(0)}ms '
      '= device ${stats.probeDouble('initDeviceMs').toStringAsFixed(0)}'
      ' + 管线 ${stats.probeDouble('initPipelineMs').toStringAsFixed(0)}'
      ' + 其余 ${stats.probeDouble('initRestMs').toStringAsFixed(0)}',
    );

    // ── 3. 兜底路径 ──
    //
    // 它走 `local_core` 的 FRB 接口，与本桥毫无关系 —— 所以必须单独验。
    // 就绪之前用户看到的就是这条路，它要是不工作，那"降级"降到的就是黑屏。
    // 兜底路径走 `local_core` 的 FRB 接口，而 integration_test 的入口**不是**
    // `lib/main.dart`（测试文件自己就是入口），所以 FRB 从没被初始化过 ——
    // 不显式来一次，`openLocalSource` 会抛
    // "flutter_rust_bridge has not been initialized"。
    //
    // 上面那三段（status / tryInit / open / show）全都不需要它：GPU 路径走的是
    // 自己的 MethodChannel。这本身也说明两条路确实是独立的。
    await initRustLib();

    final LocalSourceOpenResult opened = await openLocalSource(path: path);
    expect(
      opened.source,
      isNotNull,
      reason: '兜底路径打不开来源：${opened.rejection?.message}',
    );
    final List<LocalPageInfo> pages = await localSourcePages(id: opened.source!.id);
    expect(pages, isNotEmpty, reason: '兜底路径看到 0 页');

    final LocalPageDecodeResult decoded = await localPagePixels(
      id: opened.source!.id,
      index: 0,
      // 兜底路径必须给宽度，否则 44.8 MPix 的一页会解出 170 MB 位图、
      // 整段涨到 1.5 s —— 那条路径本来就是在"等 GPU"，不该比 GPU 还慢。
      targetWidth: 800,
      priority: LocalPageLoadPriority.high,
      contract: LocalPageLoadContract.sequential,
    );
    final LocalPagePixels? pixels = decoded.pixels;
    expect(pixels, isNotNull, reason: '兜底路径解不出第 1 页：${decoded.failure?.message}');
    // 降采样必须真的生效 —— 这条断言是"兜底不会比 GPU 路还慢"的依据。
    expect(
      pixels!.width,
      lessThanOrEqualTo(800),
      reason: 'targetWidth=800 没生效，解出了 ${pixels.width} 宽',
    );
    log(
      '兜底路径：${pixels.width}x${pixels.height} '
      'rgba=${pixels.rgba.lengthInBytes} 字节（targetWidth 已生效）',
    );
  });
}
