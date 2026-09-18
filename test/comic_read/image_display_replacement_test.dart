import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/image/image_display.dart';
import 'package:zephyr/page/setting/real_sr/service/upscaled_image_cache.dart';

class _MemoryImageSizeCubit extends ImageSizeCubit {
  _MemoryImageSizeCubit()
    : super(
        count: 1,
        defaultWidth: 100,
        defaultHeight: 100,
        sourceTag: 'replacement-test',
        pageKeys: const ['page'],
        chapterOrder: 0,
        hydrateOnInit: false,
        initialCache: {},
        initialResolved: {},
      );

  @override
  Future<void> flushNow() async {}
}

Future<void> _writeImage(File file, int size, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  image.dispose();
  picture.dispose();
}

Future<ui.Image> _waitForImage(WidgetTester tester, int size) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final rawImages = tester.widgetList<RawImage>(find.byType(RawImage));
    for (final raw in rawImages) {
      if (raw.image?.width == size) return raw.image!;
    }
  }
  throw TestFailure('没有显示预期的 $size x $size 图片');
}

void main() {
  for (final isMounted in [true, false]) {
    testWidgets(isMounted ? '同路径超分完成后，当前页面立即显示新像素' : '同路径超分完成后，重新进入页面不复用旧图缓存', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('reader-sr-');
      final file = File('${directory.path}/page.png');
      final settings = GlobalSettingCubit();
      final reader = ReaderCubit();
      final sizes = _MemoryImageSizeCubit();
      addTearDown(() async {
        await settings.close();
        await reader.close();
        if (!sizes.isClosed) await sizes.close();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        directory.deleteSync(recursive: true);
      });

      Widget host() => MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: settings),
          BlocProvider<ReaderCubit>.value(value: reader),
          BlocProvider<ImageSizeCubit>.value(value: sizes),
        ],
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              child: ImageDisplay(
                imagePath: file.path,
                isColumn: true,
                pageSlotIndex: 0,
                sizeCacheIndex: 0,
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() => _writeImage(file, 2, Colors.red));
      await tester.pumpWidget(host());
      final original = await _waitForImage(tester, 2);

      UpscaledImageCache.notifyReplaced('${directory.path}/other.png');
      await tester.pump();
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(original),
      );

      if (!isMounted) await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => _writeImage(file, 4, const Color(0xFF0000FF)),
      );
      UpscaledImageCache.notifyReplaced(file.path);
      if (!isMounted) await tester.pumpWidget(host());

      final enhanced = await _waitForImage(tester, 4);
      final pixels = await tester.runAsync(() => enhanced.toByteData());
      expect(pixels!.buffer.asUint8List().take(4), [0, 0, 255, 255]);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      UpscaledImageCache.notifyReplaced(file.path);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await sizes.close();
    });
  }
}
