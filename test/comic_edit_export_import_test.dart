import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/bookshelf/method/import_comic.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_service.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/rust_loader.dart';

import 'test_helper.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
    '/x8AAusB9Wl2nXQAAAAASUVORK5CYII=';

Map<String, dynamic> _cover() => <String, dynamic>{
  'id': 'cover1',
  'url': '',
  'name': 'cover.png',
  'path': 'cover.png',
  'extern': <String, dynamic>{'path': 'cover.png'},
};

List<Map<String, dynamic>> _chapters() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 's1',
    'name': '第1话',
    'order': 1,
    'logicalKey': 'ch1',
    'taskChapterId': 'r1',
    'storageChapterId': 's1',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'i1',
        'name': '1.png',
        'path': 'p1',
        'url': 'https://example.com/p1.png',
        'extern': <String, dynamic>{},
      },
      <String, dynamic>{
        'id': 'i2',
        'name': '2.png',
        'path': 'p2',
        'url': 'https://example.com/p2.png',
        'extern': <String, dynamic>{},
      },
    ],
  },
  <String, dynamic>{
    'id': 's2',
    'name': '手动章',
    'order': 2,
    'logicalKey': 'local:manual',
    'taskChapterId': '',
    'storageChapterId': 's2',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'i3',
        'name': '3.png',
        'path': 'p3',
        'url': 'https://example.com/p3.png',
        'extern': <String, dynamic>{},
      },
    ],
  },
  <String, dynamic>{
    'id': 's3',
    'name': '空章',
    'order': 3,
    'logicalKey': 'local:empty',
    'taskChapterId': '',
    'storageChapterId': 's3',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[],
  },
];

Map<String, dynamic> _detail() => <String, dynamic>{
  'comicInfo': <String, dynamic>{
    'id': 'c1',
    'title': 'Original',
    'description': '',
    'cover': _cover(),
  },
  'eps': _chapters()
      .map(
        (chapter) => <String, dynamic>{
          'id': chapter['logicalKey'],
          'name': chapter['name'],
          'order': chapter['order'],
          'requestId': chapter['taskChapterId'],
          'storageChapterId': chapter['storageChapterId'],
          'logicalKey': chapter['logicalKey'],
          'groupTitle': '',
          'extern': <String, dynamic>{},
        },
      )
      .toList(),
  'extern': <String, dynamic>{'downloadChapters': _chapters()},
};

Future<void> _writeAsset({
  required String storageChapterId,
  required String path,
  PictureType pictureType = PictureType.page,
}) async {
  final store = DownloadAssetStore(
    from: 'test',
    path: path,
    cartoonId: 'c1',
    chapterId: '',
    storageChapterId: storageChapterId,
    pictureType: pictureType,
  );
  final target = await store.canonicalDownloadPath();
  final file = File(target);
  await file.create(recursive: true);
  await file.writeAsBytes(base64Decode(_pngBase64));
}

void main() {
  late Directory downloadRoot;

  setUpAll(() async {
    await initRustLib(silent: true);
    await TestObjectBoxHelper.setUpTestObjectBox();
    downloadRoot = await Directory.systemTemp.createTemp(
      'breeze_edit_roundtrip_',
    );
    debugDownloadRootPath = downloadRoot.path;
  });

  tearDownAll(() async {
    debugDownloadRootPath = null;
    if (await downloadRoot.exists()) {
      await downloadRoot.delete(recursive: true);
    }
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });

  setUp(() async {
    objectbox.unifiedDownloadBox.removeAll();
    objectbox.downloadTaskBox.removeAll();
    final record = createTestDownload('test:c1')
      ..comicId = 'c1'
      ..title = 'Original'
      ..cover = jsonEncode(_cover())
      ..chapters = jsonEncode(_chapters())
      ..detailJson = jsonEncode(_detail());
    objectbox.unifiedDownloadBox.put(record);

    await _writeAsset(
      storageChapterId: '',
      path: 'cover.png',
      pictureType: PictureType.cover,
    );
    await _writeAsset(storageChapterId: 's1', path: 'p1');
    await _writeAsset(storageChapterId: 's1', path: 'p2');
    await _writeAsset(storageChapterId: 's2', path: 'p3');
  });

  test('编辑后的标题/封面/章节/图片顺序经导出导入保持', () async {
    final exportRoot = await Directory.systemTemp.createTemp(
      'breeze_edit_export_',
    );
    try {
      const service = ComicEditService();
      await service.reorderChapters(
        from: 'test',
        comicId: 'c1',
        orderedChapterIds: <String>['local:empty', 'ch1', 'local:manual'],
      );

      final exportedDir = await exportComic(
        'c1',
        ExportType.folder,
        'test',
        path: exportRoot.path,
      );
      expect(await Directory(exportedDir).exists(), isTrue);

      objectbox.unifiedDownloadBox.removeAll();
      final result = await importComicFromDirectory(exportedDir);
      expect(result.comicId, 'c1');

      final record = objectbox.unifiedDownloadBox.getAll().single;
      expect(record.title, 'Original');

      final chapters = jsonDecode(record.chapters) as List;
      expect(chapters.length, 3);
      expect((chapters[0] as Map)['name'], '空章');
      expect((chapters[1] as Map)['name'], '第1话');
      expect((chapters[2] as Map)['name'], '手动章');

      expect((chapters[0] as Map)['images'], isEmpty);
      final ch1Images = (chapters[1] as Map)['images'] as List;
      expect(
        ch1Images.map((image) => (image as Map)['path']).toList(),
        <String>['p1', 'p2'],
      );
      expect(
        (((chapters[2] as Map)['images'] as List)[0] as Map)['path'],
        'p3',
      );

      final cover = jsonDecode(record.cover) as Map;
      final coverStore = DownloadAssetStore(
        from: 'test',
        path: cover['path'] as String,
        cartoonId: 'c1',
        chapterId: '',
        storageChapterId: '',
        pictureType: PictureType.cover,
      );
      expect(await coverStore.findCanonicalDownload(), isNotNull);
    } finally {
      if (await exportRoot.exists()) {
        await exportRoot.delete(recursive: true);
      }
    }
  });

  test('导入到空下载目录时会补建封面与章节目录', () async {
    final exportRoot = await Directory.systemTemp.createTemp(
      'breeze_clean_import_',
    );
    try {
      final exportedDir = await exportComic(
        'c1',
        ExportType.folder,
        'test',
        path: exportRoot.path,
      );

      // 模拟从其他设备导入：本地下载目录里没有任何已有文件。
      if (await downloadRoot.exists()) {
        await downloadRoot.delete(recursive: true);
      }
      objectbox.unifiedDownloadBox.removeAll();

      await importComicFromDirectory(exportedDir);

      final record = objectbox.unifiedDownloadBox.getAll().single;
      final cover = jsonDecode(record.cover) as Map;
      final coverStore = DownloadAssetStore(
        from: 'test',
        path: cover['path'] as String,
        cartoonId: 'c1',
        chapterId: '',
        storageChapterId: '',
        pictureType: PictureType.cover,
      );
      final coverFile = File(await coverStore.canonicalDownloadPath());
      expect(await coverFile.exists(), isTrue);
      expect(await coverFile.length(), greaterThan(0));

      final imageStore = DownloadAssetStore(
        from: 'test',
        path: 'p1',
        cartoonId: 'c1',
        chapterId: '',
        storageChapterId: 's1',
        pictureType: PictureType.page,
      );
      final imageFile = File(await imageStore.canonicalDownloadPath());
      expect(await imageFile.exists(), isTrue);
    } finally {
      if (await exportRoot.exists()) {
        await exportRoot.delete(recursive: true);
      }
    }
  });
}
