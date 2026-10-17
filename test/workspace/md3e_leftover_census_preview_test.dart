// 补漏的一批：worker 那份普查没覆盖到的控件 —— 卡片角标族、手势解锁面板、
// 标签页芯片、搜索历史、多选对话框。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     ROSSI_UI_PREVIEW_DIR=<目录> \
//     flutter test --no-pub -j1 test/workspace/md3e_leftover_census_preview_test.dart
//
// ignore_for_file: avoid_print, deprecated_member_use
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_download_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_unread_indicator.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_artist_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';
import 'package:zephyr/widgets/gesture_lock.dart';
import 'package:zephyr/widgets/plat/rossi_plat_tab_chip.dart';
import 'package:zephyr/widgets/search/search_history_panel.dart';

const _seed = Color(0xff8b4148);
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

Future<void> _pump(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Size size,
  required Brightness brightness,
  required Widget child,
}) async {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
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
          backgroundColor: scheme.surface,
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
  padding: const EdgeInsets.only(top: 18, bottom: 10),
  child: Text(
    s,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.primary,
    ),
  ),
);

/// 一块假封面，用来把角标摆在它该在的位置上。
Widget _cover(ColorScheme scheme, {List<Widget> overlays = const []}) => Stack(
  children: [
    Container(
      width: 132,
      height: 186,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    for (final o in overlays) o,
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadCjk();
  });

  final boundary = GlobalKey();

  testWidgets('出图：封面角标族（未读三档 / 画师 / Tag / 阅读键 / 下载态）', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );
      await _pump(
        tester,
        boundary: boundary,
        size: const Size(900, 620),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('ComicUnreadIndicator 三档（dot / disc / label）叠在封面左上', scheme),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final style in ComicUnreadIndicatorStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _cover(
                      scheme,
                      overlays: [
                        Positioned(
                          left: 6,
                          top: 6,
                          child: ComicUnreadIndicator(style: style),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _title(
              'FavoriteArtistBadge（画师·心形·次要色调）与 FavoriteTagBadge（Tag·中性·#）',
              scheme,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                FavoriteArtistBadge(artistName: '示例画师'),
                FavoriteArtistBadge(artistName: null),
                FavoriteTagBadge(tagName: '汉化'),
                FavoriteTagBadge(tagName: null),
              ],
            ),
            _title(
              'ComicReadButton（封面正中的阅读键）与 ComicDownloadStatusButton 各状态',
              scheme,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: ComicReadButton(onTap: () async {}),
                ),
                const SizedBox(width: 24),
                for (final state in ComicDownloadVisualState.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ComicDownloadStatusButton(
                      state: state,
                      progress: .42,
                      onPressed: () {},
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'card-chrome-badges-${brightness == Brightness.dark ? 'dark' : 'light'}',
      );
    }
  });

  testWidgets('出图：RossiPlatTabChip 三态与 SearchHistoryPanel', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    await _pump(
      tester,
      boundary: boundary,
      size: const Size(900, 620),
      brightness: Brightness.dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'RossiPlatTabChip（vendored plat 标签页的芯片：常态 / hover / 选中）',
            scheme,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final states in [
                const <WidgetState>{},
                const <WidgetState>{WidgetState.hovered},
                const <WidgetState>{WidgetState.selected, WidgetState.hovered},
              ])
                RossiPlatTabChip(
                  label: const Text('标签页'),
                  trailing: const Icon(Icons.close, size: 14),
                  states: states,
                ),
            ],
          ),
          _title('SearchHistoryPanel（搜索历史：可点选、可清空）', scheme),
          SizedBox(
            width: 420,
            child: SearchHistoryPanel(
              queries: const ['#汉化 全集', '东方', 'author:示例', '月光旅行者'],
              onSelected: (_) {},
              onClear: () {},
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'tab-chip-and-search-history-dark');
  });

  testWidgets('出图：AppGesturePatternBoard（九宫手势锁）', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    await _pump(
      tester,
      boundary: boundary,
      size: const Size(900, 420),
      brightness: Brightness.dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('AppGesturePatternBoard（手势解锁面板，静态未拖动态）', scheme),
          SizedBox(
            width: 300,
            height: 300,
            child: AppGesturePatternBoard(onCompleted: (_) {}),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'gesture-pattern-board-dark');
  });
}
