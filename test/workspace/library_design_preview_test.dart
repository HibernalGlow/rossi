import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_download_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart'
    show ComicCoverMetadata;
import 'package:zephyr/widgets/comic_simplify_entry/comic_translation_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_artist_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/page/comic_info/widgets/comic_inline_details_surface.dart';
import 'package:zephyr/page/comic_info/widgets/all_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

const _names = [
  '月光旅行者',
  '海边的夏日',
  '夜航日记',
  '森林里的信',
  '漫长的告别',
  '星河之间',
  '山谷与风',
  '昨日的故事',
  '漂流书店',
  '春日列车',
  '远山来信',
  '城市散步',
];
const _inks = [
  Color(0xff8b4148),
  Color(0xff306d72),
  Color(0xff333f65),
  Color(0xff416346),
  Color(0xff996334),
  Color(0xff694e7c),
];

Widget _sampleCover(int i, double width, double height, BorderRadius radius) =>
    SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: i % 3 == 0
                    ? 1.65
                    : i % 3 == 1
                    ? .60
                    : .85,
                child: ColoredBox(
                  color: const Color(0xffefe7d5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: CustomPaint(
                          painter: _CoverArt(_inks[i % _inks.length], i),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${i + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                              color: _inks[i % _inks.length],
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: width < 140 ? 52 : 6,
              right: width < 140 ? 6 : 54,
              child: ComicCoverMetadata(
                children: [
                  if (i % 3 == 0)
                    const FavoriteArtistBadge(artistName: 'RAITA'),
                  FavoriteTagBadge(tagName: i.isEven ? '旅行' : '日常'),
                  ComicTranslationBadge(
                    match: ChineseTranslationMatcher.match(
                      title: '汉化',
                      tags: const [],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: ComicDownloadStatusButton(
                state: i == 1
                    ? ComicDownloadVisualState.downloading
                    : ComicDownloadVisualState.completed,
                progress: i == 1 ? .42 : null,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );

class _CoverArt extends CustomPainter {
  const _CoverArt(this.ink, this.index);
  final Color ink;
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = ink;
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .36),
      size.width * .39,
      fill,
    );
    fill.color = ink.withValues(alpha: .22);
    canvas.drawCircle(
      Offset(size.width * .22, size.height * .76),
      size.width * .45,
      fill,
    );
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var n = 0; n < 5; n++) {
      canvas.drawArc(
        Rect.fromLTWH(
          -size.width * .3,
          size.height * .3 + n * 8,
          size.width * 1.4,
          size.height * .48,
        ),
        -.6,
        2.8,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverArt old) => old.ink != ink || old.index != index;
}

void main() {
  for (final (name, size, dark, expanded) in [
    ('library-light', const Size(1120, 920), false, false),
    ('library-dark-inline', const Size(1120, 920), true, true),
    ('library-phone', const Size(390, 844), false, false),
    ('library-native-shapes', const Size(1120, 920), false, false),
  ]) {
    testWidgets('设计组件预览 $name 无溢出', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loader = FontLoader('PreviewChinese')
        ..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf'));
      await loader.load();
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await iconFont.load();
      SharedPreferences.setMockInitialValues({
        'rossi.library.presentation.preview': jsonEncode(
          LibraryPresentation(
            hero: !expanded && name != 'library-native-shapes',
            sections: true,
            weight: name == 'library-native-shapes'
                ? LibraryWeight.imageShape
                : LibraryWeight.balanced,
          ).toJson(),
        ),
      });
      final boundary = GlobalKey();
      final canvas = GlobalKey<LibraryEditorialCanvasState>();
      final data = List.generate(
        _names.length,
        (i) => LibraryEntry(
          key: '$i',
          mediaAspectRatio: i % 3 == 0
              ? 1.65
              : i % 3 == 1
              ? .60
              : .85,
          title: _names[i],
          tags: i.isEven ? ['旅行', '冒险', '全彩', '汉化'] : ['日常', '剧情', '系列'],
          subtitle: i == 0 ? '第 3 卷 · 第 42 页' : '全 $i 卷 · 本地藏书',
          section: i < 4 ? '正在阅读' : '藏书展墙',
          reading: i < 4,
          timestamp: DateTime(2026, 10, 13).subtract(Duration(days: i)),
          metaText: i < 4 ? '继续阅读' : '未读',
          itemCount: 12 - i,
          onRead: () async {},
          media:
              (
                _, {
                required width,
                required height,
                required radius,
                required fit,
              }) => _sampleCover(i, width, height, radius),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PreviewChinese',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff85505b),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Rossi  /  藏书空间'),
                actions: [
                  LibraryPresentationButton(canvasKey: canvas),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              body: LibraryEditorialCanvas(
                key: canvas,
                scope: 'preview',
                entries: data,
                standalone: true,
                onTap: (_) {},
                legacyBuilder: (_) => const SizedBox(),
                detailBuilder: (_, entry, close) => ComicInlineDetailsSurface(
                  onClose: close,
                  operations: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('下载'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.bookmark_rounded),
                        label: const Text('已收藏'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.favorite_outline_rounded),
                        label: const Text('喜欢 · 128'),
                      ),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none_rounded),
                        label: const Text('追更'),
                      ),
                    ],
                  ),
                  metadata: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('题材 / Tag'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in ['旅行', '日常', '冒险'])
                            AllChipItem(
                              label: tag,
                              expressive: true,
                              onTap: () {},
                              onLongPress: () {},
                            ),
                        ],
                      ),
                    ],
                  ),
                  description: const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('一段关于远行与相遇的故事。在熟悉的藏书空间里，浏览简介、标签和章节，选好下一段旅程。'),
                  ),
                  preview: ComicInlinePreviewGallery(
                    count: 4,
                    itemBuilder: (_, i) => _sampleCover(
                      i + 2,
                      132,
                      184,
                      BorderRadius.circular(12),
                    ),
                  ),
                  chapters: ComicInlineChapterBoard(
                    count: 6,
                    onReverse: () {},
                    itemBuilder: (_, i) => SizedBox(
                      height: 48,
                      child: FilledButton.tonal(
                        onPressed: () {},
                        child: Text('第 ${i + 1} 话'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (expanded) {
        canvas.currentState!.toggleDetails(data.first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final output = Platform.environment['ROSSI_UI_PREVIEW_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
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
