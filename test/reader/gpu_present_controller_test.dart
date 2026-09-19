import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

class _Source extends PageSource {
  /// 换书用：路径变了才算是另一份来源（呈现器按路径判断要不要重新 open）。
  String pathOverride = '/test/book.cbz';

  @override
  String get path => pathOverride;

  @override
  int get pageCount => 10;

  @override
  List<PageRef> get pages => [];

  @override
  RasterTargetRef? rasterTargetFor(int index) =>
      RasterTargetRef(path: path, index: index);

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => throw StateError('Cached SR must not reload the source');

  @override
  Future<void> close() async {}
}

class _Bridge extends GpuPresentBridge {
  int? currentIndex;
  bool enhanced = false;
  bool originalPreview = false;
  int injections = 0;
  int checks = 0;
  bool reportsEnhancedTrack = true;
  Completer<void>? injectionGate;
  int showCalls = 0;
  int opens = 0;
  Completer<void>? statsGate;
  final List<String> injectedPaths = [];

  @override
  Future<GpuPresentStatus> tryInit({
    required int width,
    required int height,
  }) async =>
      const GpuPresentStatus(state: GpuPresentState.ready, textureId: 1);

  @override
  Future<int> open(String path) async {
    opens++;
    currentIndex = null;
    enhanced = false;
    return 10;
  }

  @override
  Future<void> show(int index) async {
    showCalls++;
    if (currentIndex != index) {
      // 模拟离开保留集后原生侧淘汰增强图。
      enhanced = false;
    }
    currentIndex = index;
  }

  @override
  Future<bool> setOriginalPreview({required bool active}) async {
    originalPreview = active;
    return true;
  }

  @override
  Future<bool> setEnhancedImage(
    int index,
    String imagePath, {
    int? width,
    int? height,
  }) async {
    injections++;
    injectedPaths.add(imagePath);
    final sourceEpoch = opens;
    await injectionGate?.future;
    if (sourceEpoch != opens) return false;
    enhanced = true;
    return true;
  }

  @override
  Future<GpuPresentStats> stats() async {
    checks++;
    await statsGate?.future;
    return GpuPresentStats.fromMap({
      'ok': true,
      'state': 'ready',
      'probe': jsonEncode({
        'currentIndex': currentIndex,
        if (reportsEnhancedTrack)
          'usedEnhanced': enhanced && !originalPreview ? 1 : 0,
      }),
    });
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the enhancement pipeline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GPU enhancement replacement', () {
    late Directory cache;
    late _Source source;
    late _Bridge bridge;
    late GpuPresentController controller;
    const viewport = Size(800, 600);
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'realsr_prefetch_forward': 0,
        'realsr_prefetch_back': 0,
      });
      cache = await Directory.systemTemp.createTemp('rossi_sr_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async => cache.path);
      source = _Source();
      final srDir = await Directory('${cache.path}/rossi_sr_cache').create();
      // 解码由假 bridge 接管，这里只模拟已落盘的超分产物。
      await File(
        '${srDir.path}/sr_${source.path.hashCode}_0_${await RealSrSettings.loadCacheKey()}.png',
      ).writeAsBytes([1]);
      bridge = _Bridge();
      controller = GpuPresentController(bridge);
      await Future<void>.delayed(Duration.zero);
      controller.setUpscaleEnabled(true);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      controller.dispose();
      await controller.enhancementsIdle;
      await SuperResolutionLog.flush();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await cache.delete(recursive: true);
    });

    test(
      'cached prefetch never changes the current frame and remains reusable',
      () async {
        final key = await RealSrSettings.loadCacheKey();
        for (final index in [1, 2]) {
          await File(
            '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_${index}_$key.png',
          ).writeAsBytes([2]);
        }
        await RealSrSettings.savePrefetch(forward: 1, back: 1);
        for (var pass = 0; pass < 4; pass++) {
          await controller.present(
            source: source,
            index: 0,
            physicalSize: viewport,
          );
          await controller.enhancementsIdle;
          expect(bridge.currentIndex, 0);
          expect(bridge.enhanced, isTrue);
          expect(bridge.injectedPaths.last, contains('_0_$key'));
          await controller.present(
            source: source,
            index: 1,
            physicalSize: viewport,
          );
          await controller.enhancementsIdle;
          expect(bridge.currentIndex, 1);
          expect(bridge.enhanced, isTrue);
          expect(bridge.injectedPaths.last, contains('_1_$key'));
        }
        expect(bridge.injections, 8);
        expect(bridge.opens, 1, reason: '预超分设置不得重新打开来源');
      },
    );

    test(
      'enhanced frame notifies listeners after injection and redraw',
      () async {
        bridge.injectionGate = Completer<void>();
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        await _until(() => bridge.injections == 1);
        final before = controller.presentCount;
        final frames = <int>[];
        controller.addListener(() => frames.add(controller.presentCount));

        bridge.injectionGate!.complete();
        await _until(() => bridge.checks >= 2);

        expect(bridge.enhanced, isTrue);
        expect(controller.presentCount, before + 1);
        expect(frames, contains(before + 1));
      },
    );

    test('returning after eviction reinjects the cached SR file', () async {
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(() => bridge.checks >= 2);
      expect(bridge.injections, 1);

      // 中间页不增强，确保最后一次确认仍指向第 0 页。
      controller.setUpscaleEnabled(false);
      await Future<void>.delayed(Duration.zero);
      await controller.present(
        source: source,
        index: 9,
        physicalSize: viewport,
      );
      expect(bridge.enhanced, isFalse);
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      controller.setUpscaleEnabled(true);
      await _until(() => bridge.injections == 2 && bridge.enhanced);

      expect(bridge.currentIndex, 0);
      expect(bridge.originalPreview, isFalse);
    });

    test('restoring automatic SR also restores enhanced preview', () async {
      controller.dispose();
      SharedPreferences.setMockInitialValues({'realsr_auto_upscale': true});
      bridge = _Bridge()..originalPreview = true;
      controller = GpuPresentController(bridge);

      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(() => bridge.injections == 1 && bridge.enhanced);

      expect(controller.isUpscaleEnabled, isTrue);
      expect(bridge.originalPreview, isFalse);
    });

    test(
      'leaving original preview redraws the current page immediately',
      () async {
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        await _until(() => bridge.injections == 1 && bridge.enhanced);

        await controller.setOriginalPreview(true);
        expect(bridge.originalPreview, isTrue);
        final callsBeforeRestore = bridge.showCalls;

        await controller.setOriginalPreview(false);

        expect(bridge.originalPreview, isFalse);
        expect(bridge.showCalls, callsBeforeRestore + 1);
        expect(controller.isOriginalPreview, isFalse);
      },
    );

    test('original preview does not start enhancement work', () async {
      await controller.setOriginalPreview(true);
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bridge.injections, 0);
      expect(bridge.originalPreview, isTrue);
    });

    test(
      'missing native diagnostics do not cause repeated injection',
      () async {
        bridge.reportsEnhancedTrack = false;
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        await _until(() => bridge.checks == 1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bridge.injections, 0);
      },
    );

    test(
      'switching model clears native track and uses that model cache',
      () async {
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        await _until(() => bridge.checks >= 2);
        final oldPath = bridge.injectedPaths.single;
        const newKey = 'mimage_onnx_realesr_general_v3_0';
        await File(
          '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_0_$newKey.png',
        ).writeAsBytes([2]);
        await RealSrSettings.saveMImageModel(MImageOnnxModel.general);
        await _until(() => bridge.opens == 2);
        await _until(
          () => bridge.injectedPaths.any((path) => path.contains(newKey)),
        );
        expect(bridge.injectedPaths.last, isNot(oldPath));
        expect(bridge.enhanced, isTrue);
        final opens = bridge.opens;
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        expect(bridge.opens, opens, reason: '普通重建不得重新打开来源');
      },
      skip: !Platform.isMacOS,
    );

    test(
      'switching engines replaces the track in both directions without mixing caches',
      () async {
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
        await _until(() => bridge.checks >= 2);
        final onnxPath = bridge.injectedPaths.last;
        const nativeKey =
            'breeze_coreml_waifu2x_photo_noise0_scale2x.mlmodel_2x';
        await File(
          '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_0_$nativeKey.png',
        ).writeAsBytes([3]);
        await RealSrSettings.saveAppleEngine(
          AppleSuperResolutionEngine.breezeCoreML,
        );
        await _until(() => bridge.injectedPaths.last.contains(nativeKey));
        expect(bridge.opens, 2);
        expect(bridge.enhanced, isTrue);
        await RealSrSettings.saveAppleEngine(
          AppleSuperResolutionEngine.mimageOnnx,
        );
        await _until(() => bridge.injectedPaths.last == onnxPath);
        expect(bridge.opens, 3);
        expect(bridge.enhanced, isTrue);
      },
      skip: !Platform.isMacOS,
    );

    test('switching models discards work waiting on old diagnostics', () async {
      bridge.statsGate = Completer<void>();
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(() => bridge.checks == 1);
      await controller.setUpscaleEnabled(false);
      await RealSrSettings.saveMImageModel(MImageOnnxModel.general);
      await _until(() => bridge.opens == 2);
      bridge.statsGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bridge.injections, 0);
      expect(bridge.enhanced, isFalse);
    }, skip: !Platform.isMacOS);

    test('unchanged page does not repeatedly query or inject', () async {
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(() => bridge.checks >= 2);
      final checks = bridge.checks;
      for (var i = 0; i < 5; i++) {
        await controller.present(
          source: source,
          index: 0,
          physicalSize: viewport,
        );
      }
      expect(bridge.checks, checks);
      expect(bridge.injections, 1);
    });

    // ── 顶栏那枚芯片读的三样东西 ──
    //
    // 这几条守的不是「值算得对不对」（那是纯函数的判据），而是**打点打在了真的
    // 那一步上**：状态必须由呈现器的证据推出来，不能由「我调过那个方法」推出来。
    // 从前那条老路（日志说成功、画面还是原图）就是这么来的。

    test('呈现器确认替换后，当前页状态是「已超分」', () async {
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(() => bridge.enhanced);

      final status = controller.currentPageUpscaleStatus;
      expect(status.phase, SuperResolutionPagePhase.applied);
      expect(status.index, 0);
      expect(status.pageNumber, 1);
    });

    test('翻到预超分过的邻页时，状态也落在「已超分」上', () async {
      final key = await RealSrSettings.loadCacheKey();
      await File(
        '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_1_$key.png',
      ).writeAsBytes(image.encodePng(image.Image(width: 3, height: 5)));
      await RealSrSettings.savePrefetch(forward: 1, back: 0);

      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      // 第 1 页在后台被预超分（注入进呈现器，但没上屏）。
      await _until(
        () =>
            controller.upscaleStatusForPage(1).phase ==
            SuperResolutionPagePhase.ready,
      );

      await controller.present(
        source: source,
        index: 1,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.applied,
      );

      final status = controller.currentPageUpscaleStatus;
      expect(status.phase, SuperResolutionPagePhase.applied);
      expect(status.enhancedSize, const Size(3, 5));
    });

    test('关掉开关后不再声称「已超分」', () async {
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.applied,
      );

      controller.setUpscaleEnabled(false);
      await Future<void>.delayed(Duration.zero);

      // 盘上的产物还在，但画面已经旁路回原图 —— 这时说「已超分」就是撒谎。
      expect(
        controller.currentPageUpscaleStatus.phase,
        SuperResolutionPagePhase.disabled,
      );
    });

    test('对比原图时状态是「原图对比」，且保留超分分辨率', () async {
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.applied,
      );

      await controller.setOriginalPreview(true);
      expect(
        controller.currentPageUpscaleStatus.phase,
        SuperResolutionPagePhase.originalPreview,
      );

      await controller.setOriginalPreview(false);
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.applied,
      );
      expect(
        controller.currentPageUpscaleStatus.phase,
        SuperResolutionPagePhase.applied,
      );
    });

    test('超分产物的分辨率按产物的字节量出来（不是猜的 2×）', () async {
      // 换一份**真的** PNG 当产物：分辨率是量出来的，所以这里必须给真文件。
      final key = await RealSrSettings.loadCacheKey();
      final outFile = File(
        '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_0_$key.png',
      );
      await outFile.writeAsBytes(
        image.encodePng(image.Image(width: 6, height: 9)),
      );

      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.applied,
      );

      final status = controller.currentPageUpscaleStatus;
      expect(status.enhancedSize, const Size(6, 9));
      // 归档来源拿不到页文件路径，量不到原图尺寸 —— 那就**没有**原图尺寸，
      // 不许编一个出来（界面上「不知道」与「0×0」是两件事）。
      expect(status.sourceSize, isNull);
    });

    test('拿不到超分输入时，当前页状态落到「超分失败」', () async {
      // 删掉 setUp 预置的产物，逼流水线去走推理那一段；而这份来源既没有页文件
      // 路径、也不给原始字节，于是必然失败。
      final key = await RealSrSettings.loadCacheKey();
      final outFile = File(
        '${cache.path}/rossi_sr_cache/sr_${source.path.hashCode}_0_$key.png',
      );
      if (await outFile.exists()) await outFile.delete();

      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.currentPageUpscaleStatus.phase ==
            SuperResolutionPagePhase.failed,
      );

      expect(
        controller.currentPageUpscaleStatus.phase,
        SuperResolutionPagePhase.failed,
      );
      // 失败时画面仍是原图：不能因为「试过了」就说已超分。
      expect(
        superResolutionPhaseHasEnhancedResult(
          controller.currentPageUpscaleStatus.phase,
        ),
        isFalse,
      );
    });

    test('换书后记账整体作废，不把上一本的结论搬到新书上', () async {
      // 让第 1 页也进流水线，并且**必然失败**（这份来源拿不到超分输入）。
      await RealSrSettings.savePrefetch(forward: 1, back: 0);
      await controller.present(
        source: source,
        index: 0,
        physicalSize: viewport,
      );
      await _until(
        () =>
            controller.upscaleStatusForPage(1).phase ==
            SuperResolutionPagePhase.failed,
      );

      // 换书之前把预取窗口收回到「只做当前页」：这样新书的第 1 页根本不会进队列，
      // 于是它的状态只可能来自「记账有没有作废」这一件事 ——
      // 旧记录还在，它就是上一本书留下的「超分失败」。
      await RealSrSettings.savePrefetch(forward: 0, back: 0);
      final other = _Source()..pathOverride = '/test/other.cbz';
      await controller.present(
        source: other,
        index: 0,
        physicalSize: viewport,
      );
      await controller.enhancementsIdle;

      expect(
        controller.upscaleStatusForPage(1).phase,
        SuperResolutionPagePhase.idle,
        reason: '第 1 页在新书里没有任务，它的状态必须是「无记录」而不是上一本的残留',
      );
    });
  }, skip: !GpuPresentBridge.isPlatformSupported);
}
