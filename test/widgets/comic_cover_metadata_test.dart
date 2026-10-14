import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_download_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_translation_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_artist_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';

void main() {
  for (final width in [68.0, 100.0, 160.0, 260.0]) {
    testWidgets('多类角标及长名称在 $width 宽度有界且无溢出', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ComicCoverMetadata(
                  children: [
                    const FavoriteArtistBadge(artistName: '一位名字很长的关注画师'),
                    const FavoriteTagBadge(tagName: '一个非常长的收藏标签'),
                    ComicTranslationBadge(
                      match: ChineseTranslationMatcher.match(
                        title: '汉化',
                        tags: const [],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(ComicCoverMetadata));
      for (final type in [
        FavoriteArtistBadge,
        FavoriteTagBadge,
        ComicTranslationBadge,
      ]) {
        final badge = tester.getRect(find.byType(type));
        expect(badge.left, greaterThanOrEqualTo(box.left));
        expect(badge.right, lessThanOrEqualTo(box.right + .1));
      }
    });
  }
  for (final state in ComicDownloadVisualState.values) {
    testWidgets('下载状态 $state 保留 48dp 操作入口和状态语义', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComicDownloadStatusButton(
              state: state,
              progress: state == ComicDownloadVisualState.downloading
                  ? .42
                  : null,
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(InkWell)), const Size(48, 48));
      await tester.tap(find.byType(InkWell));
      expect(pressed, 1);
      if (state == ComicDownloadVisualState.downloading) {
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .value,
          .42,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
