import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/page/setting/real_sr/service/processing_preview_loader.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/page_trim_layout.dart';

void main() {
  late Directory directory;
  late File original;
  late File enhanced;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'image_denoise_enabled': true});
    AutoTrimSettings.resetForTesting();
    await AutoTrimSettings.load();
    directory = Directory.systemTemp.createTempSync('processing-preview-');
    original = File('${directory.path}/original.png');
    enhanced = File('${directory.path}/enhanced.png');
    original.writeAsBytesSync(
      img.encodePng(img.Image(width: 40, height: 1600)),
    );
    enhanced.writeAsBytesSync(
      img.encodePng(img.Image(width: 80, height: 3200)),
    );
  });
  tearDown(() => directory.deleteSync(recursive: true));

  testWidgets('preview uses the applied display crop and bounds long images', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layout = PageTrimLayout();
      layout.report(
        0,
        AutoTrimSettings.options.value.cacheKey,
        const Rect.fromLTRB(.1, 0, .8, 1),
      );
      final ref = CurrentPageImageRef.file(
        Object(),
        original.path,
        trimLayout: layout,
        trimIndex: 0,
        trimEnabled: true,
      );
      final preview = (await ProcessingPreviewLoader.trim(ref))!;
      expect(preview.trimRect, const Rect.fromLTRB(.1, 0, .8, 1));
      expect(preview.status, contains('已应用显示裁边'));
      expect(preview.before!.height, 720);
      expect(preview.before!.width, lessThanOrEqualTo(720));
      await preview.before!.toByteData();
      preview.dispose();
      layout.dispose();
    });
  });

  testWidgets('disabled or half pages do not claim an applied crop', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layout = PageTrimLayout();
      layout.report(
        0,
        AutoTrimSettings.options.value.cacheKey,
        const Rect.fromLTRB(.1, .1, .8, .8),
      );
      for (final enabled in [false, true]) {
        final ref = CurrentPageImageRef.file(
          Object(),
          original.path,
          trimLayout: layout,
          trimIndex: 0,
          trimEnabled: enabled,
          halfPage: enabled,
        );
        final preview = (await ProcessingPreviewLoader.trim(ref))!;
        expect(preview.trimRect, isNull);
        expect(preview.status, contains('未被裁剪'));
        preview.dispose();
      }
      layout.dispose();
    });
  });

  testWidgets('pending detection and a no-crop result remain distinguishable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layout = PageTrimLayout();
      final ref = CurrentPageImageRef.file(
        Object(),
        original.path,
        trimLayout: layout,
        trimIndex: 0,
        trimEnabled: true,
      );
      final pending = (await ProcessingPreviewLoader.trim(ref))!;
      expect(pending.status, contains('尚未完成'));
      pending.dispose();
      layout.report(0, AutoTrimSettings.options.value.cacheKey, null);
      final done = (await ProcessingPreviewLoader.trim(ref))!;
      expect(done.status, contains('无需裁边'));
      done.dispose();
      layout.dispose();
    });
  });

  testWidgets(
    'denoise inspection reuses the displayed file without loading an AI backend',
    (tester) async {
      await tester.runAsync(() async {
        final ref = CurrentPageImageRef.file(
          Object(),
          enhanced.path,
          originalPath: original.path,
        );
        final result = (await ProcessingPreviewLoader.denoise(
          ref,
          cancelled: () => false,
        ))!;
        expect(result.status, contains('已应用降噪处理'));
        expect(result.before!.height, 720);
        expect(result.after!.height, 720);
        await result.before!.toByteData();
        await result.after!.toByteData();
        result.dispose();
      });
    },
  );

  testWidgets(
    'original display does not infer denoise or trigger model inference',
    (tester) async {
      await tester.runAsync(() async {
        final ref = CurrentPageImageRef.file(
          Object(),
          original.path,
          originalPath: original.path,
        );
        final result = (await ProcessingPreviewLoader.denoise(
          ref,
          cancelled: () => false,
        ))!;
        expect(result.status, contains('未应用降噪'));
        expect(result.after, isNull);
        await result.before!.toByteData();
        result.dispose();
      });
    },
  );

  testWidgets('cancelled inspection returns no images', (tester) async {
    await tester.runAsync(() async {
      final ref = CurrentPageImageRef.file(Object(), original.path);
      expect(
        await ProcessingPreviewLoader.denoise(ref, cancelled: () => true),
        isNull,
      );
    });
  });
}
