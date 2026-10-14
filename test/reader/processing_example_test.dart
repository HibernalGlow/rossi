import 'dart:ui' as ui;
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/page_trim_layout.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_example.dart';

void main() {
  testWidgets(
    'bundled before and after images decode at their intended sizes',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'trim_before': const Size(480, 600),
          'trim_after': const Size(358, 448),
          'denoise_before': const Size(128, 128),
          'denoise_after': const Size(128, 128),
        }.entries) {
          final data = await rootBundle.load(
            'asset/image/processing_examples/${entry.key}.png',
          );
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final image = (await codec.getNextFrame()).image;
          expect(
            Size(image.width.toDouble(), image.height.toDouble()),
            entry.value,
          );
          image.dispose();
          codec.dispose();
        }
      });
    },
  );

  for (final disableAnimations in [false, true]) {
    for (final kind in ProcessingExampleKind.values) {
      testWidgets(
        '${kind.name} preview is collapsed by default (disableAnimations=$disableAnimations)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(useMaterial3: true),
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(1.8),
                  disableAnimations: disableAnimations,
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: ProcessingExample(kind: kind),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final title = kind == ProcessingExampleKind.autoTrim
              ? '裁边预览'
              : '降噪预览';
          // 默认折叠：不加载任何图片，节省内存
          expect(find.byType(Image), findsNothing);
          expect(find.text(title), findsOneWidget);
          expect(find.text('默认收起，展开后才会加载图片'), findsOneWidget);

          // 主动点击展开：没有当前阅读页时才展示内置示例图
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
          expect(find.byType(Image), findsNWidgets(2));
          expect(find.textContaining('没有正在阅读的页面'), findsOneWidget);

          // 点击示例可查看大图对话框
          await tester.tap(find.textContaining('没有正在阅读的页面'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭示例'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);

          // 再次点击收起折叠：释放并移除图片
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
          expect(find.byType(Image), findsNothing);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  testWidgets(
    'current page preview reads applied state and refreshes when detection completes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AutoTrimSettings.resetForTesting();
      await AutoTrimSettings.load();
      final store = CurrentPageImageInfo.instance;
      final owner = Object();
      final directory = Directory.systemTemp.createTempSync('live-crop-');
      final file = File('${directory.path}/page.png');
      file.writeAsBytesSync(img.encodePng(img.Image(width: 120, height: 180)));
      final layout = PageTrimLayout();
      addTearDown(() {
        store.clear(owner);
        layout.dispose();
        directory.deleteSync(recursive: true);
      });
      store.reportFile(
        owner,
        file.path,
        trimLayout: layout,
        trimIndex: 0,
        trimEnabled: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessingExample(kind: ProcessingExampleKind.autoTrim),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      await tester.tap(find.text('裁边预览'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.textContaining('尚未完成裁边检测'), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: '已有当前页时不得退回示例');
      layout.report(
        0,
        AutoTrimSettings.options.value.cacheKey,
        const Rect.fromLTRB(.1, 0, .9, 1),
      );
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.textContaining('已应用显示裁边'), findsOneWidget);
      expect(find.text('裁剪后'), findsOneWidget);
      await tester.tap(find.text('裁边预览'));
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
