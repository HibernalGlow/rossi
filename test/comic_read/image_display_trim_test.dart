import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/image/image_display.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/margin_fit_cache.dart';
import 'package:zephyr/reader/page_trim_transform.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _MemoryImageSizeCubit extends ImageSizeCubit {
  _MemoryImageSizeCubit(String tag)
    : super(
        count: 1,
        defaultWidth: 100,
        defaultHeight: 100,
        sourceTag: 'trim-test-$tag',
        pageKeys: ['page-$tag'],
        chapterOrder: 0,
        hydrateOnInit: false,
        initialCache: {},
        initialResolved: {},
      );

  @override
  Future<void> flushNow() async {}
}

/// 只改内存状态，不碰 ObjectBox（单测里没有数据库）。
class _MemoryGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateReadSetting(ReadSettingState Function(ReadSettingState) updates) {
    emit(state.copyWith(readSetting: updates(state.readSetting)));
  }
}

/// 白底、中间一块有内容、右侧留 ~6% 空白，模拟截图里的那一页。
Future<void> _writeMarginPage(File file) async {
  const w = 400, h = 560;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  final paint = Paint()..color = Colors.black;
  // 散布的墙块，右侧留白。整页实心色会被检测器判为「不可靠」而不裁。
  for (var y = 20; y < h - 20; y += 40) {
    for (var x = 20; x < w * 0.94 - 20; x += 36) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 20, 22), paint);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  image.dispose();
  picture.dispose();
}

void main() {
  var nativeReady = false;
  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (_) {}
  });

  for (final isColumn in [true, false]) {
    testWidgets('开启自动裁边后，${isColumn ? '条漫' : '翻页'}模式下页面套上裁边变换', (tester) async {
      if (!nativeReady) {
        markTestSkipped('原生库不可用');
        return;
      }
      AutoTrimSettings.resetForTesting();
      MarginFitCache.instance.clear();
      SharedPreferences.setMockInitialValues({});
      final directory = Directory.systemTemp.createTempSync('reader-trim-');
      // 无扩展名，和真实下载文件一样；每个用例用不同文件名，避免命中进程内的检测缓存。
      final file = File('${directory.path}/f_${isColumn ? 1 : 2}');
      final settings = _MemoryGlobalSettingCubit();
      final reader = ReaderCubit();
      final sizes = _MemoryImageSizeCubit(isColumn ? 'column' : 'paged');
      addTearDown(() async {
        await settings.close();
        await reader.close();
        if (!sizes.isClosed) await sizes.close();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        directory.deleteSync(recursive: true);
      });
      settings.updateReadSetting(
        (setting) => setting.copyWith(autoTrimPageMargins: true),
      );
      await tester.runAsync(() => _writeMarginPage(file));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<GlobalSettingCubit>.value(value: settings),
            BlocProvider<ComicReadPreferenceCubit>(
              create: (_) => ComicReadPreferenceCubit(),
            ),
            BlocProvider<ReaderCubit>.value(value: reader),
            BlocProvider<ImageSizeCubit>.value(value: sizes),
          ],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 420,
                child: ImageDisplay(
                  imagePath: file.path,
                  isColumn: isColumn,
                  pageSlotIndex: 0,
                  sizeCacheIndex: 0,
                ),
              ),
            ),
          ),
        ),
      );

      var trimmed = false;
      for (var i = 0; i < 200 && !trimmed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        trimmed = find.byType(PageTrimTransform).evaluate().isNotEmpty;
      }
      expect(trimmed, isTrue, reason: '右侧有 6% 空白的页面应当被检测并套上 PageTrimTransform');
      expect(tester.takeException(), isNull);

      // ImageSizeCubit 的延迟落盘定时器要先走完，否则测试收尾会报 Timer 未结束。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
