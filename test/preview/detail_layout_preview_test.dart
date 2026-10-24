// web 风详情行（detailLayout，默认关）的预览截图，供「是否接线到更多页面」的
// 人工评审用。运行 `flutter test test/preview/detail_layout_preview_test.dart
// --update-goldens` 后查看 `test/preview/` 下的 PNG。
// 说明：测试环境没有 Rust 桥，封面走 PictureBloc 失败分支（占位），行结构、
// 文本层级与元信息胶囊是真实渲染。

import 'dart:io';

import 'package:flutter/services.dart' show ByteData, FontLoader;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_item.dart';
import '../test_helper.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

ComicSimplifyEntryInfo _info(
  String title, {
  String author = '',
  List<String> metadata = const [],
}) => ComicSimplifyEntryInfo(
  title: title,
  id: title,
  fileServer: 'https://example.com',
  path: '/mock/$title.jpg',
  pictureType: PictureType.cover,
  from: 'jm',
  author: author,
  metadata: metadata,
);

ComicFolder _folder(String name, String syncId) => ComicFolder(
  syncId: syncId,
  uniqueKey: '|$name|favorite',
  name: name,
  typeData: ComicFolderType.favorite.name,
  versionVectorJson: '{}',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  // convertChineseForDisplay 经 globalSetting 读 ObjectBox，预览前先起测试库。
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  // golden 渲染不加载 FontManifest，中文会变豆腐块；显式注册仓库自带的
  // 霞鹜文楷（与生产 TranslatedPageRenderer 同一条 FontLoader 路径）。
  const kPreviewFont = 'LXGWPreview';
  setUpAll(() async {
    final bytes = File('asset/fonts/LXGWWenKaiLite-Regular.ttf').readAsBytesSync();
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final loader = FontLoader(kPreviewFont)..addFont(Future.value(data));
    await loader.load();
  });

  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: Brightness.light,
  );

  testWidgets('web 风详情行预览（漫画行 + 文件夹行）', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: kPreviewFont),
          home: Scaffold(
            backgroundColor: scheme.surface,
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  '「详情布局」开启后的书架 / 插件首页列表（横排详情行）',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 8),
                FolderShelfItem(
                  folder: _folder('连载追更', 'f1'),
                  detailed: true,
                  comicCount: 42,
                ),
                FolderShelfItem(
                  folder: _folder('短篇合集', 'f2'),
                  detailed: true,
                  comicCount: 7,
                ),
                const SizedBox(height: 12),
                ComicSimplifyEntry(
                  info: _info(
                    '在异世界获得超强能力的我',
                    author: '某作者',
                    metadata: ['恋爱', '奇幻', '连载中', '汉化'],
                  ),
                  type: ComicEntryType.normal,
                  detailed: true,
                ),
                ComicSimplifyEntry(
                  info: _info(
                    '深夜食堂 · 完全版',
                    author: '安倍夜郎',
                    metadata: ['治愈', '全12卷', '中译'],
                  ),
                  type: ComicEntryType.normal,
                  detailed: true,
                ),
                ComicSimplifyEntry(
                  info: _info(
                    'Everyday Manga With A Very Long English Title That Should Ellipsize Gracefully',
                    author: 'Some Author Name',
                    metadata: ['English', 'Ongoing', 'Chapter 128'],
                  ),
                  type: ComicEntryType.normal,
                  detailed: true,
                ),
                ComicSimplifyEntry(
                  info: _info('没有作者与元信息的条目'),
                  type: ComicEntryType.normal,
                  detailed: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('detail_layout_preview.png'),
    );
  });
}
