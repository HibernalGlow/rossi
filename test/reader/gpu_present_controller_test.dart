import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';

class _Source extends PageSource {
  @override
  String get path => '/test/book.cbz';

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

  @override
  Future<GpuPresentStatus> tryInit({
    required int width,
    required int height,
  }) async =>
      const GpuPresentStatus(state: GpuPresentState.ready, textureId: 1);

  @override
  Future<int> open(String path) async => 10;

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
    await injectionGate?.future;
    enhanced = true;
    return true;
  }

  @override
  Future<GpuPresentStats> stats() async {
    checks++;
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
      SharedPreferences.setMockInitialValues({});
      cache = await Directory.systemTemp.createTemp('rossi_sr_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async => cache.path);
      source = _Source();
      final srDir = await Directory('${cache.path}/rossi_sr_cache').create();
      // 解码由假 bridge 接管，这里只模拟已落盘的超分产物。
      await File(
        '${srDir.path}/sr_${source.path.hashCode}_0.png',
      ).writeAsBytes([1]);
      bridge = _Bridge();
      controller = GpuPresentController(bridge);
      await Future<void>.delayed(Duration.zero);
      controller.setUpscaleEnabled(true);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await cache.delete(recursive: true);
    });

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
  }, skip: !GpuPresentBridge.isPlatformSupported);
}
