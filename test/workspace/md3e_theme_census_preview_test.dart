// 配色与配色风格维度的 MD3 Expressive 出图：预设种子色 → 派生色板，
// 加上明暗档选择器本体。给 Xaihi 改版留一份"换色不换造型"的对照。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     ROSSI_UI_PREVIEW_DIR=<目录> \
//     flutter test --no-pub -j1 test/workspace/md3e_theme_census_preview_test.dart
//
// ignore_for_file: avoid_print, deprecated_member_use
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/page/setting/global/widgets/appearance_theme_picker.dart';

const _cjkFamily = 'PreviewCJK';

Future<void> _loadCjk() async {
  final bytes = File(
    'asset/fonts/LXGWWenKaiLite-Regular.ttf',
  ).readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: _cjkFamily);
}

Future<void> _write(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final output = Platform.environment['ROSSI_UI_PREVIEW_DIR'];
  if (output == null) return;
  final context = boundary.currentContext;
  if (context == null) return;
  await tester.runAsync(() async {
    final image = await (context.findRenderObject()! as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// 一颗种子色派生出来的六格色板。
Widget _palette(ColorThemeInfo info, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: info.color,
    brightness: brightness,
  );
  final cells = <String, Color>{
    'primary': scheme.primary,
    'onPrimary': scheme.onPrimary,
    'primaryContainer': scheme.primaryContainer,
    'secondaryContainer': scheme.secondaryContainer,
    'surface': scheme.surface,
    'surfaceContainer': scheme.surfaceContainer,
    'onSurface': scheme.onSurface,
  };
  return Container(
    width: 300,
    margin: const EdgeInsets.only(right: 14, bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: scheme.surface,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: info.color,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              info.label,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
            const SizedBox(width: 6),
            Text(
              '#${info.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final e in cells.entries)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: e.key,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: e.value,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Size size,
  required Brightness brightness,
  required Widget child,
}) async {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff8b4148),
    brightness: brightness,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          fontFamily: _cjkFamily,
        ),
        home: Scaffold(
          backgroundColor: scheme.surfaceDim,
          body: MaterialUiCompatibilityBridge(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Align(alignment: Alignment.topLeft, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _title(String s, ColorScheme scheme) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(
    s,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: scheme.primary,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadCjk);

  final boundary = GlobalKey();

  testWidgets('出图：预设种子色 → 派生色板（暗 / 亮）', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff8b4148),
        brightness: brightness,
      );
      await _pump(
        tester,
        boundary: boundary,
        size: Size(680, 300.0 + 100.0 * (colorThemeList.length / 2).ceil()),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              'colorThemeList 全部 ${colorThemeList.length} 档预设种子色 · '
              '每格依次 primary / onPrimary / primaryContainer / '
              'secondaryContainer / surface / surfaceContainer / onSurface',
              scheme,
            ),
            Wrap(
              children: [
                for (final info in colorThemeList) _palette(info, brightness),
              ],
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'color-theme-list-${brightness == Brightness.dark ? 'dark' : 'light'}',
      );
    }
  });

  testWidgets('出图：AppearanceThemePicker（明暗三档选择器本体）', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff8b4148),
        brightness: brightness,
      );
      await _pump(
        tester,
        boundary: boundary,
        size: const Size(680, 320),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('AppearanceThemePicker · 三档（浅色 / 深色 / 跟随系统）', scheme),
            SizedBox(
              width: 620,
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppearanceThemePicker(
                        value: mode,
                        seedColor: scheme.primary,
                        onChanged: (_) {},
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'appearance-theme-picker-${brightness == Brightness.dark ? 'dark' : 'light'}',
      );
    }
  });
}
