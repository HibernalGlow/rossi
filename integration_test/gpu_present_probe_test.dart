import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/util/rust_loader.dart';

/// **真机引擎**上的 GPU 上屏探针（Windows / D3D12 共享纹理）。
///
/// 为什么必须是集成测试而不是单元测试：这条链路的最后一环是**引擎来打开我们给的
/// 共享句柄**，而那只会在真实窗口把 `Texture` 合成出去的时候发生。`flutter test`
/// 跑的是 `flutter_tester`（软件渲染、没有 Windows embedder、连 `TextureRegistrar`
/// 都没有），在那里"通过"什么也证明不了。
///
/// # 它验四件事
///
/// 1. **呈现器是异步建的**：`create` 在 `FlutterWindow::OnCreate` 里被调，它必须
///    立刻返回、不压在第一帧之前。所以启动后第一次问 `status` 很可能还是
///    `loading` —— 那不是失败，是这条路径该有的样子。
/// 2. **上屏本身**：`handleOpened > 0`。我们先渲染、再通知引擎取帧
///    （`framesMarked`），但那只证明我们喊过；引擎真的打开句柄，才证明屏幕上的
///    像素确实来自 Rust 侧那张纹理 —— 而不是某个默认的空白纹理。
/// 3. **收敛后的页来源两侧一致**：页面用的 `LocalPageSource`（`local_core` 会话）
///    与呈现器自己数出来的页数必须相等。这是「先收敛页来源」那句话能不能
///    兑现的**唯一**硬证据 —— 两侧不一致时 GPU 路会静默地画错页。
/// 4. **显示节点自己会把两条路接对**：就绪前落在 CPU 兜底（出现 `RawImage`），
///    就绪后落在 GPU（出现 `Texture`），且不需要外面替它排序。
///
/// 跑法：
/// ```
/// flutter test integration_test/gpu_present_probe_test.dart -d windows
/// ```
/// 样本路径可用 `ROSSI_GPU_PRESENT_SAMPLE` 覆盖，默认取固定夹具；
/// 样本缺失时**静默跳过**，不让别人 clone 后因为缺夹具而红。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 默认夹具落在临时目录下的 rossi-probe/，盘符由 win-baseline-env.sh 的
  // TMP/TEMP（= $ROSSI_WIN_ROOT/tmp）决定，不在此处写死。
  final String defaultSample =
      p.join(Directory.systemTemp.path, 'rossi-probe', 'probe.cbz');

  void log(String message) {
    // ignore: avoid_print
    print('[gpu-present] $message');
  }

  /// 解析样本路径；不存在就返回 null（调用方据此跳过）。
  String? samplePath() {
    final String path =
        Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ?? defaultSample;
    if (!File(path).existsSync() && !Directory(path).existsSync()) {
      log('[skip] 样本不存在: $path');
      return null;
    }
    log('sample = $path');
    return path;
  }

  /// integration_test 的入口**不是** `lib/main.dart`（测试文件自己就是入口），
  /// 所以 FRB 从没被初始化过 —— 不显式来一次，`openLocalSource` 会抛
  /// `flutter_rust_bridge has not been initialized`。
  /// 注意它**不可重复调用**（第二次 `RustLib.init()` 会抛），所以放在 `setUpAll`。
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('呈现器异步创建：启动期不被它压住，且最终就绪', (WidgetTester tester) async {
    if (!GpuPresentBridge.isPlatformSupported) {
      log('[skip] 非 Windows 平台，这条路径不存在');
      return;
    }

    const GpuPresentBridge bridge = GpuPresentBridge();

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

    final GpuPresentStats stats = await bridge.stats();
    // 呈现器那 ~1 s 花在哪：device 那一段与管线那一段的可优化性完全不同，
    // 所以它们必须分开报，否则以后不知道该往哪使劲。
    log(
      'init=${stats.probeDouble('initMs').toStringAsFixed(0)}ms '
      '= device ${stats.probeDouble('initDeviceMs').toStringAsFixed(0)}'
      ' + 管线 ${stats.probeDouble('initPipelineMs').toStringAsFixed(0)}'
      ' + 其余 ${stats.probeDouble('initRestMs').toStringAsFixed(0)}',
    );
  });

  testWidgets('收敛后的页来源：页面一份、呈现器一份，页数必须相等',
      (WidgetTester tester) async {
    if (!GpuPresentBridge.isPlatformSupported) {
      return;
    }
    final String? path = samplePath();
    if (path == null) {
      return;
    }

    final PageSourceOpen opened = await LocalPageSource.open(path);
    expect(
      opened,
      isA<PageSourceOpened>(),
      reason: '打不开来源：${opened is PageSourceRejected ? opened.message : ''}',
    );
    final PageSource source = (opened as PageSourceOpened).source;
    log('页面来源：${source.pageCount} 页，kind 由 local_core 判定');

    expect(source.pageCount, greaterThan(0), reason: '来源里没有可显示的页');
    expect(source.rasterTargetFor(0), isNotNull);
    // 越界要给 null 而不是抛：显示节点在切页时可能拿着上一份来源的下标。
    expect(source.rasterTargetFor(-1), isNull);
    expect(source.rasterTargetFor(source.pageCount), isNull);

    // ── 收敛的核心断言 ──
    //
    // 呈现器**自己**也打开同一份文件（像素不过桥的代价）。两侧能对同一页达成一致，
    // 靠的是它们跑同一份枚举代码（`rossi_gpu_present` 依赖 `rossi_local_core`），
    // 而不是靠任何同步动作。所以这条断言不是"顺带检查"，它就是那个前提本身。
    const GpuPresentBridge bridge = GpuPresentBridge();
    final int nativeCount = await bridge.open(path);
    log('页数：页面来源 ${source.pageCount} / 呈现器 $nativeCount');
    expect(
      nativeCount,
      source.pageCount,
      reason: '两侧页数不一致 —— 前提（同一份枚举代码）失效了，GPU 路会画错页',
    );

    // ── 兜底路要能出图，且降采样必须真的生效 ──
    //
    // 不给宽度的代价是量过的：44.8 MPix 的一页解出 170.8 MB 位图、这一段 1526 ms
    // （其中解码只占 17%）。这条断言是「兜底不会比 GPU 路还慢」的依据。
    final PageLoadOutcome outcome = await source.load(0, targetWidth: 800);
    expect(
      outcome,
      isA<PageLoaded>(),
      reason: '兜底路解不出第 1 页：'
          '${outcome is PageLoadFailed ? outcome.message : outcome}',
    );
    final PageContent content = (outcome as PageLoaded).content;
    expect(content, isA<RasterPageContent>());
    final RasterPageContent raster = content as RasterPageContent;
    expect(
      raster.width,
      lessThanOrEqualTo(800),
      reason: 'targetWidth=800 没生效，解出了 ${raster.width} 宽',
    );
    log(
      '兜底路：${raster.width}x${raster.height}'
      '（原图 ${raster.sourceWidth}x${raster.sourceHeight}）'
      'rgba=${raster.rgba.lengthInBytes} 字节',
    );

    // ── 会话纪律：关闭必须幂等，且计数要回落 ──
    final int before = localOpenSessionCount();
    await source.close();
    final int after = localOpenSessionCount();
    await source.close(); // 幂等：重复关闭不该报错、也不该误关别人
    final int afterTwice = localOpenSessionCount();
    log('会话数：开之前 $before → 关之后 $after → 重复关闭后 $afterTwice');
    expect(after, before - 1, reason: 'close() 没有释放会话（判据 D 的探针会单调上升）');
    expect(afterTwice, after, reason: 'close() 不幂等，重复调用又减了一次');
  });

  testWidgets('显示节点：就绪前落 CPU 兜底（RawImage），就绪后落 GPU（Texture）',
      (WidgetTester tester) async {
    if (!GpuPresentBridge.isPlatformSupported) {
      return;
    }
    final String? path = samplePath();
    if (path == null) {
      return;
    }

    final PageSourceOpen opened = await LocalPageSource.open(path);
    expect(opened, isA<PageSourceOpened>());
    final PageSource source = (opened as PageSourceOpened).source;

    // ── 1) 未 start 的控制器 = 永远还没就绪 ──
    //
    // 这样构造出的 `loading` 是**确定性的**，不靠抢时间窗口。它验证的正是
    // 「就绪前走兜底」这条契约：节点该自己落到 CPU 路，而不是留一块黑。
    final GpuPresentController idle = GpuPresentController();
    final List<ImageSurfacePath> idlePaths = <ImageSurfacePath>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ImageSurface(
              source: source,
              index: 0,
              presenter: idle,
              onPathChanged: idlePaths.add,
            ),
          ),
        ),
      ),
    );

    // 解码 + decodeImageFromPixels 是异步的，给它几帧真实时间。
    for (int i = 0; i < 40 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    log('未就绪时通路 = ${idlePaths.isEmpty ? '（无）' : idlePaths.first.name}');
    expect(
      idlePaths,
      contains(ImageSurfacePath.cpu),
      reason: '呈现器未就绪时节点应当落 CPU 兜底',
    );
    expect(
      find.byType(RawImage),
      findsOneWidget,
      reason: '兜底位图没出来 —— 就绪前用户看到的就是这块，它不能是空的',
    );
    expect(find.byType(Texture), findsNothing);

    // 先拆树、再 disposal 控制器：反过来会让 `ImageSurface.dispose` 对着
    // 一个已析构的 notifier 调 removeListener。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    idle.dispose();

    // ── 2) 真控制器：节点应当自己切到 GPU 并上屏 ──
    final GpuPresentController presenter = GpuPresentController();
    final List<ImageSurfacePath> paths = <ImageSurfacePath>[];
    presenter.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ImageSurface(
              source: source,
              index: 0,
              presenter: presenter,
              onPathChanged: paths.add,
            ),
          ),
        ),
      ),
    );

    // 节点要自己完成：等就绪 → 建目标 → 让 native 侧打开同一份来源 → 校验页数 → 呈现。
    const GpuPresentBridge bridge = GpuPresentBridge();
    GpuPresentStats stats = await bridge.stats();
    for (int i = 0; i < 120 && stats.handleOpened == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stats = await bridge.stats();
    }

    log(
      '通路 = ${paths.map((ImageSurfacePath p) => p.name).join('→')} '
      'handleOpened=${stats.handleOpened} framesMarked=${stats.framesMarked} '
      'resizes=${stats.resizes} size=${stats.width}x${stats.height}',
    );
    log('probe = ${stats.probeRaw}');
    log(
      'decode=${stats.probeDouble('decodeMs').toStringAsFixed(1)}ms '
      'upload=${stats.probeDouble('uploadMs').toStringAsFixed(1)}ms '
      'submit=${stats.probeDouble('submitMs').toStringAsFixed(1)}ms '
      'decoded=${stats.probeInt('decodedWidth')}x${stats.probeInt('decodedHeight')} '
      'source=${stats.probeInt('sourceWidth')}x${stats.probeInt('sourceHeight')}',
    );

    expect(
      presenter.mismatchFor(source),
      isNull,
      reason: '节点报出了两侧页数不一致：${presenter.mismatchFor(source)}',
    );
    expect(
      paths,
      contains(ImageSurfacePath.gpu),
      reason: '节点始终没有切到 GPU 路',
    );
    expect(
      find.byType(Texture),
      findsOneWidget,
      reason: '节点走 GPU 路却没有把 Texture 挂上去',
    );
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    presenter.dispose();
    await source.close();
  });
}
