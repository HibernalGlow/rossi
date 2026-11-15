import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_service.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/rust_loader.dart';

import 'test_helper.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
    '/x8AAusB9Wl2nXQAAAAASUVORK5CYII=';

Map<String, dynamic> _detail() => <String, dynamic>{
  'comicInfo': <String, dynamic>{
    'id': 'c1',
    'title': 'Original',
    'description': 'desc',
    'cover': <String, dynamic>{
      'id': 'cover1',
      'url': 'https://example.com/cover.jpg',
      'name': 'cover.jpg',
      'path': 'cover.jpg',
      'extern': <String, dynamic>{'path': 'cover.jpg'},
    },
  },
  'eps': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'ch1',
      'name': '第1话',
      'order': 1,
      'requestId': 'r1',
      'storageChapterId': 's1',
      'logicalKey': 'ch1',
      'groupTitle': '',
      'extern': <String, dynamic>{},
    },
    <String, dynamic>{
      'id': 'ch2',
      'name': '第2话',
      'order': 2,
      'requestId': 'r2',
      'storageChapterId': 's2',
      'logicalKey': 'ch2',
      'groupTitle': '',
      'extern': <String, dynamic>{},
    },
  ],
  'extern': <String, dynamic>{},
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
        'name': '1.jpg',
        'path': 'p1',
        'url': 'u1',
        'extern': <String, dynamic>{},
      },
      <String, dynamic>{
        'id': 'i2',
        'name': '2.jpg',
        'path': 'p2',
        'url': 'u2',
        'extern': <String, dynamic>{},
      },
    ],
  },
  <String, dynamic>{
    'id': 's2',
    'name': '第2话',
    'order': 2,
    'logicalKey': 'ch2',
    'taskChapterId': 'r2',
    'storageChapterId': 's2',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[],
  },
];

UnifiedComicDownload _insertRecord({Map<String, dynamic>? cover}) {
  final record = createTestDownload('test:c1')
    ..comicId = 'c1'
    ..title = 'Original'
    ..chapters = jsonEncode(_chapters())
    ..detailJson = jsonEncode(_detail());
  if (cover != null) {
    record.cover = jsonEncode(cover);
  }
  objectbox.unifiedDownloadBox.put(record);
  return record;
}

UnifiedComicDownload _readRecord() =>
    objectbox.unifiedDownloadBox.getAll().single;

void main() {
  late Directory downloadRoot;

  setUpAll(() async {
    await initRustLib(silent: true);
    await TestObjectBoxHelper.setUpTestObjectBox();
    downloadRoot = await Directory.systemTemp.createTemp(
      'breeze_edit_downloads_',
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

  setUp(() {
    objectbox.unifiedDownloadBox.removeAll();
    objectbox.downloadTaskBox.removeAll();
    objectbox.unifiedHistoryBox.removeAll();
    objectbox.unifiedFavoriteBox.removeAll();
  });

  test('updateTitle 同时写生效值与 override', () async {
    _insertRecord();

    const service = ComicEditService();
    await service.updateTitle(from: 'test', comicId: 'c1', title: '  New  ');

    final record = _readRecord();
    expect(record.title, 'New');
    expect(record.titleOverride, 'New');
    final detail = jsonDecode(record.detailJson) as Map;
    expect((detail['comicInfo'] as Map)['title'], 'New');
  });

  test('renameChapter 同步 chapters / eps / 镜像', () async {
    _insertRecord();

    const service = ComicEditService();
    await service.renameChapter(
      from: 'test',
      comicId: 'c1',
      chapterId: 'ch1',
      name: 'Renamed',
    );

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    expect((chapters[0] as Map)['name'], 'Renamed');
    final detail = jsonDecode(record.detailJson) as Map;
    expect(((detail['eps'] as List)[0] as Map)['name'], 'Renamed');
    final mirror = (detail['extern'] as Map)['downloadChapters'] as List;
    expect((mirror[0] as Map)['name'], 'Renamed');
  });

  test('addChapter 追加本地空章节', () async {
    _insertRecord();

    const service = ComicEditService();
    await service.addChapter(from: 'test', comicId: 'c1', name: 'New');

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    expect(chapters.length, 3);
    final added = chapters.last as Map;
    expect(added['id'], startsWith('local:'));
    expect(added['order'], 3);
    expect(added['images'], isEmpty);
    final detail = jsonDecode(record.detailJson) as Map;
    expect((detail['eps'] as List).length, 3);
  });

  test('reorderImages 只改元数据顺序', () async {
    _insertRecord();

    const service = ComicEditService();
    await service.reorderImages(
      from: 'test',
      comicId: 'c1',
      chapterId: 'ch1',
      orderedPaths: <String>['p2', 'p1'],
    );

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    final images = (chapters[0] as Map)['images'] as List;
    expect(images.map((image) => (image as Map)['path']).toList(), <String>[
      'p2',
      'p1',
    ]);
  });

  test('reorderChapters 重编号并同步 eps', () async {
    _insertRecord();

    const service = ComicEditService();
    await service.reorderChapters(
      from: 'test',
      comicId: 'c1',
      orderedChapterIds: <String>['ch2', 'ch1'],
    );

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    expect((chapters[0] as Map)['logicalKey'], 'ch2');
    expect((chapters[0] as Map)['order'], 1);
    expect((chapters[1] as Map)['order'], 2);
    final detail = jsonDecode(record.detailJson) as Map;
    final eps = detail['eps'] as List;
    expect((eps[0] as Map)['logicalKey'], 'ch2');
    expect((eps[0] as Map)['order'], 1);
  });

  test('deleteImages 删除元数据与文件', () async {
    _insertRecord();
    final store = DownloadAssetStore(
      from: 'test',
      path: 'p1',
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: 's1',
      pictureType: PictureType.page,
    );
    final path = await store.canonicalDownloadPath();
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(base64Decode(_pngBase64));

    const service = ComicEditService();
    await service.deleteImages(
      from: 'test',
      comicId: 'c1',
      chapterId: 'ch1',
      imagePaths: <String>['p1'],
    );

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    final images = (chapters[0] as Map)['images'] as List;
    expect(images.length, 1);
    expect((images[0] as Map)['path'], 'p2');
    expect(await File(path).exists(), isFalse);
  });

  test('标题/封面同步到历史与本地收藏', () async {
    _insertRecord();
    final history = createTestHistory('test:c1')
      ..title = 'Old'
      ..cover = 'old';
    final favorite = createTestFavorite('test:c1')
      ..title = 'Old'
      ..cover = 'old';
    objectbox.unifiedHistoryBox.put(history);
    objectbox.unifiedFavoriteBox.put(favorite);

    final source = File('${downloadRoot.path}/cover_source.png');
    await source.writeAsBytes(base64Decode(_pngBase64));

    const service = ComicEditService();
    await service.updateTitle(from: 'test', comicId: 'c1', title: 'New');
    await service.updateCover(from: 'test', comicId: 'c1', source: source);

    final record = _readRecord();
    final updatedHistory = objectbox.unifiedHistoryBox.getAll().single;
    final updatedFavorite = objectbox.unifiedFavoriteBox.getAll().single;
    expect(updatedHistory.title, 'New');
    expect(updatedHistory.cover, record.cover);
    expect(updatedFavorite.title, 'New');
    expect(updatedFavorite.cover, record.cover);
  });

  test('updateCoverFromImage 复制章节图片为封面', () async {
    _insertRecord();
    final imageStore = DownloadAssetStore(
      from: 'test',
      path: 'p1',
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: 's1',
      pictureType: PictureType.page,
    );
    final imagePath = await imageStore.canonicalDownloadPath();
    await File(imagePath).create(recursive: true);
    await File(imagePath).writeAsBytes(base64Decode(_pngBase64));

    const service = ComicEditService();
    await service.updateCoverFromImage(
      from: 'test',
      comicId: 'c1',
      chapterId: 'ch1',
      imagePath: 'p1',
    );

    final record = _readRecord();
    final cover = jsonDecode(record.cover) as Map;
    expect(cover['path'], startsWith('cover_'));
    final coverStore = DownloadAssetStore(
      from: 'test',
      path: cover['path'] as String,
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: '',
      pictureType: PictureType.cover,
    );
    expect(await coverStore.findCanonicalDownload(), isNotNull);
    expect(await File(imagePath).exists(), isTrue);
  });

  test('有未完成章节任务时禁止编辑', () async {
    _insertRecord();
    final task = DownloadTask()
      ..comicId = 'c1'
      ..comicName = 'Test'
      ..isCompleted = false
      ..isDownloading = false
      ..status = 'queued';
    task.taskInfo = DownloadTaskJson(
      from: 'test',
      comicId: 'c1',
      comicName: 'Test',
      chapterRef: const DownloadChapterTaskRef(
        chapterId: 'ch1',
        logicalKey: 'ch1',
        title: '第1话',
        order: 1,
      ),
    );
    objectbox.downloadTaskBox.put(task);

    const service = ComicEditService();
    expect(service.hasIncompleteDownload('test', 'c1'), isTrue);
    expect(
      () => service.updateTitle(from: 'test', comicId: 'c1', title: 'X'),
      throwsA(isA<ComicEditLockedException>()),
    );
  });

  test('updateCover 写本地封面并保留 override', () async {
    _insertRecord(
      cover: <String, dynamic>{
        'id': 'cover1',
        'url': 'https://example.com/cover.jpg',
        'name': 'cover.jpg',
        'path': 'cover.jpg',
        'extern': <String, dynamic>{'path': 'cover.jpg'},
      },
    );
    final source = File('${downloadRoot.path}/source.png');
    await source.writeAsBytes(base64Decode(_pngBase64));

    const service = ComicEditService();
    await service.updateCover(from: 'test', comicId: 'c1', source: source);

    final record = _readRecord();
    final cover = jsonDecode(record.cover) as Map;
    expect(cover['path'], startsWith('cover_'));
    expect(cover['url'], '');
    expect(record.coverOverride, isNotNull);
    final detail = jsonDecode(record.detailJson) as Map;
    expect(
      ((detail['comicInfo'] as Map)['cover'] as Map)['path'],
      cover['path'],
    );

    final store = DownloadAssetStore(
      from: 'test',
      path: cover['path'] as String,
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: '',
      pictureType: PictureType.cover,
    );
    expect(await store.findCanonicalDownload(), isNotNull);
  });

  test('moveImages 搬文件并更新两章元数据', () async {
    _insertRecord();
    final sourceStore = DownloadAssetStore(
      from: 'test',
      path: 'p1',
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: 's1',
      pictureType: PictureType.page,
    );
    final sourcePath = await sourceStore.canonicalDownloadPath();
    await File(sourcePath).create(recursive: true);
    await File(sourcePath).writeAsBytes(base64Decode(_pngBase64));

    const service = ComicEditService();
    await service.moveImages(
      from: 'test',
      comicId: 'c1',
      sourceChapterId: 'ch1',
      targetChapterId: 'ch2',
      imagePaths: <String>['p1'],
    );

    final record = _readRecord();
    final chapters = jsonDecode(record.chapters) as List;
    expect(((chapters[0] as Map)['images'] as List).length, 1);
    expect(((chapters[1] as Map)['images'] as List).length, 1);
    expect((((chapters[1] as Map)['images'] as List)[0] as Map)['path'], 'p1');

    expect(await File(sourcePath).exists(), isFalse);
    final targetStore = DownloadAssetStore(
      from: 'test',
      path: 'p1',
      cartoonId: 'c1',
      chapterId: '',
      storageChapterId: 's2',
      pictureType: PictureType.page,
    );
    final targetPath = await targetStore.canonicalDownloadPath();
    expect(await File(targetPath).exists(), isTrue);
  });
}
