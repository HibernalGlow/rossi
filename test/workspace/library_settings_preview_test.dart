import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  for (final (name, size, dark, scale) in [
    ('wide', const Size(1200, 900), false, 1.0),
    ('phone-dark', const Size(390, 844), true, 1.0),
    ('narrow-large-text', const Size(220, 800), false, 1.6),
  ]) {
    testWidgets('展墙设置预览 $name：分组、菜单和动作在可用空间内', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final font = FontLoader('PreviewChinese')
        ..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf'));
      await font.load();
      final canvas = GlobalKey<LibraryEditorialCanvasState>();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff81505c),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            fontFamily: 'PreviewChinese',
          ),
          builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Scaffold(
            appBar: AppBar(
              title: const Text('作品'),
              actions: [LibraryPresentationButton(canvasKey: canvas)],
            ),
            body: LibraryEditorialCanvas(
              key: canvas,
              scope: 'preview-$name',
              standalone: true,
              initialPresentation: const LibraryPresentation(
                hero: false,
                weight: LibraryWeight.order,
                cardWidth: 140,
              ),
              entries: [
                for (var i = 0; i < 9; i++)
                  LibraryEntry(
                    key: '$i',
                    title: '示例作品 ${i + 1}',
                    media:
                        (
                          _, {
                          required width,
                          required height,
                          required radius,
                          required fit,
                        }) => SizedBox(
                          width: width,
                          height: height,
                          child: ColoredBox(
                            color: Color.lerp(
                              const Color(0xffbce3db),
                              const Color(0xffbba9d2),
                              i / 8,
                            )!,
                          ),
                        ),
                  ),
              ],
              onTap: (_) {},
              legacyBuilder: (_) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
      await tester.pumpAndSettle();
      expect(find.text('卡片宽度'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['ROSSI_LIBRARY_PREVIEW_OUTPUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
