import 'dart:ui' as ui;

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

  for (final kind in ProcessingExampleKind.values) {
    testWidgets(
      '${kind.name} example opens without model or reader dependencies',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.8),
                disableAnimations: true,
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
        final title = kind == ProcessingExampleKind.autoTrim ? '裁边示例' : '降噪示例';
        expect(find.byType(Image), findsNWidgets(2));
        expect(find.bySemanticsLabel(RegExp('$title.*点击查看大图')), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text(title), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭示例'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
