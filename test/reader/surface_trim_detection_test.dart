import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/surface_trim_detection.dart';

class _Source implements PageSource {
  final widths = <int?>[];
  Completer<PageLoadOutcome>? gate;
  @override
  String get path => '/tmp/book.cbz';
  @override
  int get pageCount => 2;
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
  }) async {
    widths.add(targetWidth);
    return gate != null
        ? await gate!.future
        : PageLoaded(
            RasterPageContent(
              rgba: Uint8List(16),
              width: 2,
              height: 2,
              sourceWidth: 200,
              sourceHeight: 20000,
            ),
          );
  }

  @override
  Future<void> close() async {}
  @override
  Future<String?> getPageFilePath(int index) async => null;
  @override
  Future<Uint8List?> getPageBytes(int index) async => null;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AutoTrimSettings.resetForTesting();
    await AutoTrimSettings.load();
  });
  test(
    'long strips sample by the longest edge and completed requests stay deduplicated',
    () async {
      final detector = SurfaceTrimDetection();
      final source = _Source();
      var calls = 0;
      Future<void> run() => detector.fromSource(
        source: source,
        index: 0,
        sizeOf: () async => const Size(200, 20000),
        isCurrent: () => true,
        detector: (_, _, _, _, _) async {
          calls++;
          return null;
        },
        resolved: (_, size) => expect(size, const Size(200, 20000)),
      );
      await run();
      await run();
      expect(source.widths, [10]);
      expect(calls, 1);
    },
  );
  test('CPU and GPU requests in flight share one claim', () async {
    final detector = SurfaceTrimDetection();
    final source = _Source()..gate = Completer<PageLoadOutcome>();
    var calls = 0;
    Future<Rect?> detect(
      PageSource s,
      int i,
      Uint8List rgba,
      int w,
      int h,
    ) async {
      calls++;
      return null;
    }

    final pending = detector.fromSource(
      source: source,
      index: 0,
      sizeOf: () async => const Size(200, 20000),
      isCurrent: () => true,
      detector: detect,
      resolved: (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    await detector.fromPixels(
      source: source,
      index: 0,
      rgba: Uint8List(16),
      width: 2,
      height: 2,
      detector: detect,
      isCurrent: () => true,
      resolved: (_, _) {},
    );
    source.gate!.complete(
      PageLoaded(
        RasterPageContent(
          rgba: Uint8List(16),
          width: 2,
          height: 2,
          sourceWidth: 200,
          sourceHeight: 20000,
        ),
      ),
    );
    await pending;
    expect(calls, 1);
    expect(source.widths, hasLength(1));
  });
  test('closing or switching pages drops a late result', () async {
    final detector = SurfaceTrimDetection();
    final source = _Source();
    final gate = Completer<Rect?>();
    var resolved = false;
    final pending = detector.fromPixels(
      source: source,
      index: 0,
      rgba: Uint8List(16),
      width: 2,
      height: 2,
      detector: (_, _, _, _, _) => gate.future,
      isCurrent: () => true,
      resolved: (_, _) => resolved = true,
    );
    detector.reset();
    gate.complete(const Rect.fromLTRB(.1, .1, .9, .9));
    await pending;
    expect(resolved, isFalse);
  });
  test('failed analysis releases its claim for a later retry', () async {
    final detector = SurfaceTrimDetection();
    final source = _Source();
    var attempts = 0;
    var resolved = false;
    Future<void> run() => detector.fromPixels(
      source: source,
      index: 0,
      rgba: Uint8List(16),
      width: 2,
      height: 2,
      detector: (_, _, _, _, _) async {
        if (++attempts == 1) throw StateError('decode');
        return null;
      },
      isCurrent: () => true,
      resolved: (_, _) => resolved = true,
    );
    await run();
    await run();
    expect(attempts, 2);
    expect(resolved, isTrue);
  });
}
