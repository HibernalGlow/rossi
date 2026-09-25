import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/type/enum.dart';

void main() {
  test('原子写入提交后只保留最终文件', () async {
    final root = await Directory.systemTemp.createTemp('breeze_asset_store_');
    addTearDown(() => root.delete(recursive: true));

    final finalPath = '${root.path}${Platform.pathSeparator}image.jpg';
    await DownloadAssetStore.writeBytesAtomically(
      Uint8List.fromList(const [1, 2, 3]),
      finalPath: finalPath,
      taskId: 'task/with:special',
    );

    expect(await File(finalPath).readAsBytes(), [1, 2, 3]);
    final entries = await root.list().toList();
    expect(entries.whereType<File>().map((file) => file.path), [finalPath]);
  });

  test('空数据写入失败且不创建最终文件', () async {
    final root = await Directory.systemTemp.createTemp('breeze_asset_store_');
    addTearDown(() => root.delete(recursive: true));

    final finalPath = '${root.path}${Platform.pathSeparator}empty.jpg';
    await expectLater(
      DownloadAssetStore.writeBytesAtomically(
        Uint8List(0),
        finalPath: finalPath,
        taskId: 'empty',
      ),
      throwsStateError,
    );

    expect(await File(finalPath).exists(), isFalse);
    expect((await root.list().toList()).whereType<File>(), isEmpty);
  });

  test('历史路径越界时不被视为下载根目录内路径', () {
    final root = Directory.systemTemp.path;
    expect(
      DownloadAssetStore.isWithinRoot(
        root,
        '$root${Platform.pathSeparator}downloads${Platform.pathSeparator}comic',
      ),
      isTrue,
    );
    expect(
      DownloadAssetStore.isWithinRoot(
        root,
        '$root${Platform.pathSeparator}..${Platform.pathSeparator}outside',
      ),
      isFalse,
    );
  });

  // 阅读器与下载任务必须把同一页算到同一个目录段上，否则已下载的页会被重新下载。
  group('章节 key 口径', () {
    // 下载任务的构造方式（comic_download_task.dart）：chapterId 用插件返回的
    // epId，storageChapterId 用 effectiveStorageId —— 插件未提供存储 key 时，
    // 它就是宿主对章节 id 做的 hash。
    final downloader = DownloadAssetStore(
      from: 'bika',
      path: 'p/001.jpg',
      cartoonId: 'comic-1',
      chapterId: '1001',
      storageChapterId: 'd3a3c3e5f0b1e2c4a5b6c7d8e9f0a1b2',
      pictureType: PictureType.page,
    );

    // 阅读器的构造方式（read_mode_image_builder.dart → PictureBloc）：chapterId
    // 是章节逻辑 id，与 epId 可以不同；storageChapterId 由 ComicReadRoute 用
    // 同一个 effectiveStorageId 一路透传下来。
    final reader = DownloadAssetStore(
      from: 'bika',
      path: 'p/001.jpg',
      cartoonId: 'comic-1',
      chapterId: 'ep-3',
      storageChapterId: 'd3a3c3e5f0b1e2c4a5b6c7d8e9f0a1b2',
      pictureType: PictureType.page,
    );

    test('章节 id 形态不同不影响写入目录段', () {
      expect(reader.chapterId, isNot(downloader.chapterId));
      expect(reader.effectiveChapterId, downloader.effectiveChapterId);
    });

    test('读取候选的第一项就是写入位置', () {
      expect(reader.chapterKeyCandidates.first, reader.effectiveChapterId);
      expect(
        downloader.chapterKeyCandidates.first,
        downloader.effectiveChapterId,
      );
    });

    test('原始章节 id 留在候选里以兼容历史落盘', () {
      // 修复前阅读器把原始章节 id 当作目录段写过缓存与下载目录。
      expect(reader.chapterKeyCandidates, contains('ep-3'));
      expect(downloader.chapterKeyCandidates, contains('1001'));
    });

    test('插件给出存储 key 时按存储 key 落盘', () {
      final store = DownloadAssetStore(
        from: 'bika',
        path: 'p/001.jpg',
        cartoonId: 'comic-1',
        chapterId: '1001',
        storageChapterId: 'GALLERY-KEY',
        pictureType: PictureType.page,
      );
      expect(store.chapterKeyCandidates, ['GALLERY-KEY', '1001']);
    });

    test('两 key 相同或缺失时候选不重复', () {
      final same = DownloadAssetStore(
        from: 'bika',
        path: 'p/001.jpg',
        cartoonId: 'comic-1',
        chapterId: '1001',
        storageChapterId: '1001',
        pictureType: PictureType.page,
      );
      expect(same.chapterKeyCandidates, ['1001']);

      final noStorageKey = DownloadAssetStore(
        from: 'bika',
        path: 'p/001.jpg',
        cartoonId: 'comic-1',
        chapterId: '1001',
        pictureType: PictureType.page,
      );
      expect(noStorageKey.effectiveChapterId, '1001');
      expect(noStorageKey.chapterKeyCandidates, ['1001']);
    });

    test('章节 id 为空时不产生空串之外的候选', () {
      final cover = DownloadAssetStore(
        from: 'bika',
        path: 'cover.jpg',
        cartoonId: 'comic-1',
        chapterId: '',
        pictureType: PictureType.cover,
      );
      expect(cover.chapterKeyCandidates, ['']);
    });
  });
}
