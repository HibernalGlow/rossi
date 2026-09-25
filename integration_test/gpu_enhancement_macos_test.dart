import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/page_source.dart';

Future<void> _writeImage(File file, Color color, int size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  image.dispose();
  picture.dispose();
}

class _FolderSource extends PageSource {
  _FolderSource(this.path, this.pageCount);
  @override
  final String path;
  @override
  final int pageCount;
  @override
  List<PageRef> get pages => [];
  @override
  RasterTargetRef? rasterTargetFor(int index) =>
      RasterTargetRef(path: path, index: index);
  @override
  Future<String?> getPageFilePath(int index) async => '$path/$index.png';
  @override
  Future<Uint8List?> getPageBytes(int index) =>
      File('$path/$index.png').readAsBytes();
  @override
  Future<void> close() async {}
  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) async {
    final codec = await ui.instantiateImageCodec(
      await File('$path/$index.png').readAsBytes(),
    );
    final image = (await codec.getNextFrame()).image;
    final bytes = await image.toByteData();
    final result = PageLoaded(
      RasterPageContent(
        width: image.width,
        height: image.height,
        sourceWidth: image.width,
        sourceHeight: image.height,
        rgba: bytes!.buffer.asUint8List(),
      ),
    );
    image.dispose();
    codec.dispose();
    return result;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bundled GPU library replaces pixels without duplicate slow frames',
    (tester) async {
      if (!Platform.isMacOS) return;
      const bridge = GpuPresentBridge();
      final directory = await Directory.systemTemp.createTemp(
        'gpu-sr-integration-',
      );
      final source = await Directory('${directory.path}/pages').create();
      final enhanced = File('${directory.path}/enhanced.png');
      try {
        await tester.runAsync(() async {
          await _writeImage(
            File('${source.path}/0.png'),
            const Color(0xFFFF0000),
            256,
          );
          await _writeImage(
            File('${source.path}/1.png'),
            const Color(0xFF00FF00),
            256,
          );
          await _writeImage(enhanced, const Color(0xFF0000FF), 512);
        });
        late GpuPresentStatus status;
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 100; attempt++) {
            status = await bridge.tryInit(width: 2560, height: 1600);
            if (status.isReady) return;
            if (status.state == GpuPresentState.failed) fail(status.error);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail('GPU presenter did not become ready');
        });
        await tester.pumpWidget(
          MaterialApp(home: Texture(textureId: status.textureId)),
        );
        await tester.runAsync(() async {
          expect(await bridge.open(source.path), 2);
          await bridge.show(0);
          Future<List<int>?> pixel() =>
              GpuPresentBridge.channel.invokeListMethod<int>('debugFramePixel');
          expect(await pixel(), [0, 0, 255, 255]);
          final before = await bridge.stats();
          expect(
            before.probe.containsKey('usedEnhanced'),
            isTrue,
            reason: 'The application loaded an outdated GPU library',
          );

          expect(await bridge.setEnhancedImage(0, enhanced.path), isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            (await bridge.stats()).framesMarked,
            before.framesMarked,
            reason: 'Injection must not enqueue a duplicate show',
          );
          expect(await pixel(), [0, 0, 255, 255]);

          await bridge.show(0);
          expect(await pixel(), [255, 0, 0, 255]);
          expect((await bridge.stats()).probeInt('usedEnhanced'), 1);

          await bridge.show(1);
          expect(await pixel(), [0, 255, 0, 255]);
          await bridge.show(0);
          expect(await pixel(), [255, 0, 0, 255]);

          final timings = <double>[];
          for (var i = 0; i < 6; i++) {
            final watch = Stopwatch()..start();
            await bridge.show(i % 2);
            timings.add(watch.elapsedMicroseconds / 1000);
          }
          // 包含 CVPixelBuffer 填充、Rust 呈现、跨语言返回的完整耗时。
          // ignore: avoid_print
          print('[gpu-sr-integration] cached 2560x1600 show ms: $timings');
          expect(
            timings.every((ms) => ms < 200),
            isTrue,
            reason: 'Cached page turns must not regress to the reported 800 ms',
          );
        });
        await tester.pump();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await directory.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'reader controller replaces cached SR and restores after navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const bridge = GpuPresentBridge();
      final dir = await Directory.systemTemp.createTemp(
        'reader-sr-controller-',
      );
      final source = _FolderSource(dir.path, 12);
      final controller = GpuPresentController();
      final srDir = await SuperResolutionLog.cacheDirectory();
      final srFile = File('${srDir.path}/sr_${source.path.hashCode}_0.png');
      Future<List<int>?> pixel() =>
          GpuPresentBridge.channel.invokeListMethod<int>('debugFramePixel');
      Future<void> waitForPixel(List<int> expected) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final actual = await pixel();
          if (actual.toString() == expected.toString()) return;
        }
        fail(
          'Pixel ${await pixel()}, expected $expected; native: ${(await bridge.stats()).probeRaw}',
        );
      }

      Future<void> mount(int index) => tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ImageSurface(
              source: source,
              index: index,
              presenter: controller,
            ),
          ),
        ),
      );
      try {
        await tester.runAsync(() async {
          for (var i = 0; i < source.pageCount; i++) {
            await _writeImage(
              File('${dir.path}/$i.png'),
              const Color(0xFFFF0000),
              256,
            );
          }
          await _writeImage(srFile, const Color(0xFF0000FF), 512);
        });
        controller.start();
        await mount(0);
        await waitForPixel([0, 0, 255, 255]);
        await controller.setUpscaleEnabled(true);
        await waitForPixel([255, 0, 0, 255]);
        expect((await bridge.stats()).probeInt('usedEnhanced'), 1);
        await controller.setOriginalPreview(true);
        await waitForPixel([0, 0, 255, 255]);
        await controller.setOriginalPreview(false);
        await waitForPixel([255, 0, 0, 255]);
        await controller.setUpscaleEnabled(false);
        await mount(9);
        await waitForPixel([0, 0, 255, 255]);
        await mount(0);
        await controller.setUpscaleEnabled(true);
        await waitForPixel([255, 0, 0, 255]);
        print(
          '[reader-sr] cached controller replacement + original comparison + return: PASS',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await dir.delete(recursive: true);
        if (await srFile.exists()) await srFile.delete();
      }
    },
  );
}
