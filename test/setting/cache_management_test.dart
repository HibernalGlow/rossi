import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/manage_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory mockCacheDir;
  late Directory mockTempDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('cache_manage_test_');
    mockCacheDir = Directory(p.join(tempRoot.path, 'cache'));
    await mockCacheDir.create(recursive: true);
    mockTempDir = Directory(p.join(tempRoot.path, 'temp'));
    await mockTempDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  File createMockFile(String relativePath, int bytes, {DateTime? mtime}) {
    final file = File(p.join(mockCacheDir.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0x42));
    if (mtime != null) {
      file.setLastModifiedSync(mtime);
    }
    return file;
  }

  File createMockTempFile(String relativePath, int bytes, {DateTime? mtime}) {
    final file = File(p.join(mockTempDir.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0x42));
    if (mtime != null) {
      file.setLastModifiedSync(mtime);
    }
    return file;
  }

  group('CacheCategorySizes & calculateCacheCategorySizes', () {
    test('准确分类统计各缓存目录大小并排除 sentry', () async {
      // 1. reader_image_processing: 200KB
      createMockFile('reader_image_processing/img1.png', 100 * 1024);
      createMockFile('reader_image_processing/img2.png', 100 * 1024);

      // 2. 漫画页面缓存 (插件目录): 300KB
      createMockFile('bika/comic_1/chap_1/p1.jpg', 150 * 1024);
      createMockFile('jm/comic_2/chap_1/p1.webp', 150 * 1024);

      // 3. mimage_catalog: 50KB
      createMockFile('mimage_catalog/catalog.db', 50 * 1024);

      // 4. sentry: 500KB (不计入缓存)
      createMockFile('sentry/envelope.json', 500 * 1024);

      // 5. 根目录其他零散文件: 10KB
      createMockFile('other.tmp', 10 * 1024);

      // 6. 视频海报缓存: 80KB
      createMockTempFile('rossi-video-posters/poster1.jpg', 80 * 1024);

      final sizes = await calculateCacheCategorySizes(
        customCachePath: mockCacheDir.path,
        customTempPath: mockTempDir.path,
      );

      expect(sizes.readerImageProcessingBytes, 200 * 1024);
      expect(sizes.comicPagesBytes, 300 * 1024);
      expect(sizes.mimageCatalogBytes, 50 * 1024);
      expect(sizes.videoPostersBytes, 80 * 1024);
      expect(sizes.otherBytes, 10 * 1024);
      expect(sizes.totalBytes, (200 + 300 + 50 + 80 + 10) * 1024);
    });
  });

  group('分类清理函数独立性测试', () {
    test('clearReaderImageProcessingCache 只清空 reader_image_processing', () async {
      final f1 = createMockFile('reader_image_processing/img.png', 100);
      final f2 = createMockFile('bika/comic/p.jpg', 100);
      final f3 = createMockFile('mimage_catalog/cat.db', 100);

      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isTrue);
      expect(f3.existsSync(), isTrue);

      await clearReaderImageProcessingCache(customCachePath: mockCacheDir.path);

      expect(f1.existsSync(), isFalse);
      expect(f2.existsSync(), isTrue);
      expect(f3.existsSync(), isTrue);
    });

    test('clearComicPagesCache 只清理漫画页面目录，保留 sentry/reader_image/catalog', () async {
      final f1 = createMockFile('reader_image_processing/img.png', 100);
      final f2 = createMockFile('bika/comic/p.jpg', 100);
      final f3 = createMockFile('mimage_catalog/cat.db', 100);
      final f4 = createMockFile('sentry/event.json', 100);

      await clearComicPagesCache(customCachePath: mockCacheDir.path);

      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isFalse);
      expect(f3.existsSync(), isTrue);
      expect(f4.existsSync(), isTrue);
    });

    test('clearMImageCatalogCache 只清理 mimage_catalog', () async {
      final f1 = createMockFile('reader_image_processing/img.png', 100);
      final f2 = createMockFile('mimage_catalog/cat.db', 100);

      await clearMImageCatalogCache(customCachePath: mockCacheDir.path);

      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isFalse);
    });

    test('clearVideoPostersCache 只清理 rossi-video-posters', () async {
      final f1 = createMockTempFile('rossi-video-posters/poster.jpg', 100);
      final f2 = createMockTempFile('other_temp.bin', 100);

      await clearVideoPostersCache(customTempPath: mockTempDir.path);

      expect(f1.existsSync(), isFalse);
      expect(f2.existsSync(), isTrue);
    });

    test('clearCache 清理除 sentry 之外的所有缓存和海报', () async {
      final f1 = createMockFile('reader_image_processing/img.png', 100);
      final f2 = createMockFile('bika/p.jpg', 100);
      final f3 = createMockFile('mimage_catalog/cat.db', 100);
      final f4 = createMockFile('sentry/keep.json', 100);
      final f5 = createMockTempFile('rossi-video-posters/poster.jpg', 100);

      await clearCache(mockCacheDir.path, customTempPath: mockTempDir.path);

      expect(f1.existsSync(), isFalse);
      expect(f2.existsSync(), isFalse);
      expect(f3.existsSync(), isFalse);
      expect(f4.existsSync(), isTrue);
      expect(f5.existsSync(), isFalse);
    });
  });

  group('autoCleanExpiredAndExcessCaches 自动清理规则测试', () {
    test('reader_image_processing 按保留天数清理过期文件', () async {
      final now = DateTime(2026, 11, 19, 12, 0);

      // 10 天前的文件（已过期）
      final oldFile = createMockFile(
        'reader_image_processing/old.png',
        1000,
        mtime: now.subtract(const Duration(days: 10)),
      );
      // 2 天前的文件（未过期）
      final newFile = createMockFile(
        'reader_image_processing/new.png',
        2000,
        mtime: now.subtract(const Duration(days: 2)),
      );

      const setting = CacheSettingState(
        autoCleanReaderImageProcessing: true,
        readerImageProcessingMaxAgeDays: 7, // 7 天保留期
        readerImageProcessingSizeLimit: 0, // 不限制容量
        autoCleanComicPages: false,
        autoCleanCache: false,
      );

      final result = await autoCleanExpiredAndExcessCaches(
        setting,
        customCachePath: mockCacheDir.path,
        customTempPath: mockTempDir.path,
        now: now,
      );

      expect(result.cleanedFilesCount, 1);
      expect(result.cleanedBytes, 1000);
      expect(oldFile.existsSync(), isFalse);
      expect(newFile.existsSync(), isTrue);
    });

    test('reader_image_processing 按容量上限按修改时间从最旧的开始删', () async {
      final now = DateTime(2026, 11, 19, 12, 0);

      // 三个文件，每个 1MB (1024*1024)，总共 3MB
      final fOld = createMockFile(
        'reader_image_processing/f_old.png',
        1024 * 1024,
        mtime: now.subtract(const Duration(hours: 3)),
      );
      final fMid = createMockFile(
        'reader_image_processing/f_mid.png',
        1024 * 1024,
        mtime: now.subtract(const Duration(hours: 2)),
      );
      final fNew = createMockFile(
        'reader_image_processing/f_new.png',
        1024 * 1024,
        mtime: now.subtract(const Duration(hours: 1)),
      );

      // 设置容量上限 2MB (2 * 1024 * 1024)，保留天数设为 0 (不限时间)
      const setting = CacheSettingState(
        autoCleanReaderImageProcessing: true,
        readerImageProcessingMaxAgeDays: 0,
        readerImageProcessingSizeLimit: 2 * 1024 * 1024,
        autoCleanComicPages: false,
        autoCleanCache: false,
      );

      final result = await autoCleanExpiredAndExcessCaches(
        setting,
        customCachePath: mockCacheDir.path,
        customTempPath: mockTempDir.path,
        now: now,
      );

      expect(result.cleanedFilesCount, 1);
      expect(result.cleanedBytes, 1024 * 1024);
      expect(fOld.existsSync(), isFalse);
      expect(fMid.existsSync(), isTrue);
      expect(fNew.existsSync(), isTrue);
    });

    test('comicPages 按保留天数自动清理过期页面', () async {
      final now = DateTime(2026, 11, 19, 12, 0);

      final oldComicPage = createMockFile(
        'plugin_x/comic_1/chap_1/p1.jpg',
        5000,
        mtime: now.subtract(const Duration(days: 40)),
      );
      final newComicPage = createMockFile(
        'plugin_x/comic_1/chap_2/p1.jpg',
        6000,
        mtime: now.subtract(const Duration(days: 5)),
      );

      const setting = CacheSettingState(
        autoCleanReaderImageProcessing: false,
        autoCleanComicPages: true,
        comicPagesMaxAgeDays: 30, // 30 天保留
        autoCleanCache: false,
      );

      final result = await autoCleanExpiredAndExcessCaches(
        setting,
        customCachePath: mockCacheDir.path,
        customTempPath: mockTempDir.path,
        now: now,
      );

      expect(result.cleanedFilesCount, 1);
      expect(result.cleanedBytes, 5000);
      expect(oldComicPage.existsSync(), isFalse);
      expect(newComicPage.existsSync(), isTrue);
    });

    test('全局容量上限超过时按 LRU 清理多余缓存并保护 sentry', () async {
      final now = DateTime(2026, 11, 19, 12, 0);

      // 4 个文件，每个 500KB，共 2MB
      final f1 = createMockFile(
        'reader_image_processing/p1.png',
        500 * 1024,
        mtime: now.subtract(const Duration(hours: 4)),
      );
      final f2 = createMockFile(
        'plugin_a/p2.jpg',
        500 * 1024,
        mtime: now.subtract(const Duration(hours: 3)),
      );
      final f3 = createMockFile(
        'plugin_b/p3.jpg',
        500 * 1024,
        mtime: now.subtract(const Duration(hours: 2)),
      );
      final f4 = createMockFile(
        'plugin_c/p4.jpg',
        500 * 1024,
        mtime: now.subtract(const Duration(hours: 1)),
      );
      final sentry = createMockFile(
        'sentry/event.json',
        500 * 1024,
        mtime: now.subtract(const Duration(days: 100)),
      );

      // 全局限制 1MB (1024 * 1024)
      const setting = CacheSettingState(
        autoCleanCache: true,
        cacheSizeLimit: 1024 * 1024,
        autoCleanReaderImageProcessing: false,
        autoCleanComicPages: false,
      );

      await autoCleanExpiredAndExcessCaches(
        setting,
        customCachePath: mockCacheDir.path,
        customTempPath: mockTempDir.path,
        now: now,
      );

      // 最旧的 f1 和 f2 被删，剩余 f3 和 f4 (各 500KB <= 1MB)
      expect(f1.existsSync(), isFalse);
      expect(f2.existsSync(), isFalse);
      expect(f3.existsSync(), isTrue);
      expect(f4.existsSync(), isTrue);
      // sentry 文件必须被完好保留
      expect(sentry.existsSync(), isTrue);
    });
  });

  group('CacheSettingState 默认值与序列化', () {
    test('具备正确的默认值', () {
      const state = CacheSettingState();
      expect(state.autoCleanCache, isTrue);
      expect(state.cacheSizeLimit, 1073741824); // 1GB
      expect(state.autoCleanOnStartup, isTrue);
      expect(state.autoCleanReaderImageProcessing, isTrue);
      expect(state.readerImageProcessingMaxAgeDays, 7);
      expect(state.readerImageProcessingSizeLimit, 2147483648); // 2GB
      expect(state.autoCleanComicPages, isTrue);
      expect(state.comicPagesMaxAgeDays, 30);
      expect(state.autoCleanThumbnails, isFalse);
      expect(state.autoCleanVideoPosters, isTrue);
    });

    test('从旧版 JSON 反序列化时自动补全默认值', () {
      final legacyJson = {
        'autoCleanCache': false,
        'cacheSizeLimit': 536870912,
      };

      final state = CacheSettingState.fromJson(legacyJson);
      expect(state.autoCleanCache, isFalse);
      expect(state.cacheSizeLimit, 536870912);
      expect(state.autoCleanOnStartup, isTrue);
      expect(state.autoCleanReaderImageProcessing, isTrue);
      expect(state.readerImageProcessingMaxAgeDays, 7);
      expect(state.readerImageProcessingSizeLimit, 2147483648);
    });

    test('完整的 JSON 序列化与反序列化往返', () {
      const original = CacheSettingState(
        autoCleanCache: true,
        cacheSizeLimit: 4294967296,
        autoCleanOnStartup: false,
        autoCleanReaderImageProcessing: true,
        readerImageProcessingMaxAgeDays: 14,
        readerImageProcessingSizeLimit: 1073741824,
        autoCleanComicPages: false,
        comicPagesMaxAgeDays: 7,
        autoCleanThumbnails: true,
        autoCleanVideoPosters: false,
      );

      final json = original.toJson();
      final restored = CacheSettingState.fromJson(json);

      expect(restored, equals(original));
    });
  });
}
