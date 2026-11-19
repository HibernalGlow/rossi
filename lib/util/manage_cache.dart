import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/util/get_path.dart';

/// 各分类缓存的占用统计
class CacheCategorySizes {
  const CacheCategorySizes({
    required this.totalBytes,
    required this.readerImageProcessingBytes,
    required this.comicPagesBytes,
    required this.mimageCatalogBytes,
    required this.videoPostersBytes,
    required this.otherBytes,
  });

  final int totalBytes;
  final int readerImageProcessingBytes;
  final int comicPagesBytes;
  final int mimageCatalogBytes;
  final int videoPostersBytes;
  final int otherBytes;

  static const empty = CacheCategorySizes(
    totalBytes: 0,
    readerImageProcessingBytes: 0,
    comicPagesBytes: 0,
    mimageCatalogBytes: 0,
    videoPostersBytes: 0,
    otherBytes: 0,
  );
}

/// 自动清理执行结果统计
class CacheCleanResult {
  const CacheCleanResult({this.cleanedFilesCount = 0, this.cleanedBytes = 0});

  final int cleanedFilesCount;
  final int cleanedBytes;
}

/// 计算各类缓存的大小
Future<CacheCategorySizes> calculateCacheCategorySizes({
  String? customCachePath,
  String? customTempPath,
}) async {
  final cachePath = customCachePath ?? await getCachePath();
  final cacheDir = Directory(cachePath);

  int readerImageProcessingBytes = 0;
  int comicPagesBytes = 0;
  int mimageCatalogBytes = 0;
  int otherBytes = 0;

  if (await cacheDir.exists()) {
    try {
      final entries = cacheDir.listSync(recursive: false);
      for (final entity in entries) {
        final name = p.basename(entity.path);
        // 保留 sentry，不计入缓存大小
        if (name == 'sentry') continue;

        if (name == 'reader_image_processing') {
          readerImageProcessingBytes += _safeDirectorySize(entity);
        } else if (name == 'mimage_catalog') {
          mimageCatalogBytes += _safeDirectorySize(entity);
        } else if (entity is Directory) {
          // 插件漫画页面缓存目录
          comicPagesBytes += _safeDirectorySize(entity);
        } else if (entity is File) {
          try {
            otherBytes += entity.lengthSync();
          } on FileSystemException {
            // 忽略读取错误
          }
        }
      }
    } catch (e) {
      logger.e('Error listing cache directory: $e');
    }
  }

  // 视频海报缓存位于临时目录下的 rossi-video-posters
  int videoPostersBytes = 0;
  try {
    final tempPath = customTempPath ?? (await getTemporaryDirectory()).path;
    final posterDir = Directory(p.join(tempPath, 'rossi-video-posters'));
    if (await posterDir.exists()) {
      videoPostersBytes = _safeDirectorySize(posterDir);
    }
  } catch (e) {
    logger.e('Error checking video poster cache: $e');
  }

  final totalBytes =
      readerImageProcessingBytes +
      comicPagesBytes +
      mimageCatalogBytes +
      videoPostersBytes +
      otherBytes;

  return CacheCategorySizes(
    totalBytes: totalBytes,
    readerImageProcessingBytes: readerImageProcessingBytes,
    comicPagesBytes: comicPagesBytes,
    mimageCatalogBytes: mimageCatalogBytes,
    videoPostersBytes: videoPostersBytes,
    otherBytes: otherBytes,
  );
}

int _safeDirectorySize(FileSystemEntity entity) {
  if (entity is! Directory) return 0;
  int size = 0;
  try {
    for (final file in entity.listSync(recursive: true).whereType<File>()) {
      try {
        size += file.lengthSync();
      } on FileSystemException {
        continue;
      }
    }
  } catch (_) {}
  return size;
}

/// 清理图片处理缓存（超分与降噪生成的增强图片，包含 reader_image_processing）
Future<void> clearReaderImageProcessingCache({String? customCachePath}) async {
  final cachePath = customCachePath ?? await getCachePath();
  final target = Directory(p.join(cachePath, 'reader_image_processing'));
  if (await target.exists()) {
    try {
      await target.delete(recursive: true);
      logger.d('reader_image_processing cache cleared successfully.');
    } catch (e) {
      logger.e('Error clearing reader_image_processing cache: $e');
    }
  }
  try {
    await SuperResolutionLog.trimCache();
  } catch (_) {}
}

/// 清理在线漫画页面缓存（排除 sentry、reader_image_processing 与 mimage_catalog）
Future<void> clearComicPagesCache({String? customCachePath}) async {
  final cachePath = customCachePath ?? await getCachePath();
  final directory = Directory(cachePath);
  if (!await directory.exists()) return;

  try {
    final entries = directory.listSync(recursive: false);
    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (name == 'sentry' ||
          name == 'reader_image_processing' ||
          name == 'mimage_catalog') {
        continue;
      }
      if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
    logger.d('Comic pages cache cleared successfully.');
  } catch (e) {
    logger.e('Error clearing comic pages cache: $e');
  }
}

/// 清理本地漫画缩略图与目录数据库缓存
Future<void> clearMImageCatalogCache({String? customCachePath}) async {
  final cachePath = customCachePath ?? await getCachePath();
  final target = Directory(p.join(cachePath, 'mimage_catalog'));
  if (await target.exists()) {
    try {
      await target.delete(recursive: true);
      logger.d('mimage_catalog cache cleared successfully.');
    } catch (e) {
      logger.e('Error clearing mimage_catalog cache: $e');
    }
  }
}

/// 清理视频封面海报缓存
Future<void> clearVideoPostersCache({String? customTempPath}) async {
  try {
    final tempPath = customTempPath ?? (await getTemporaryDirectory()).path;
    final target = Directory(p.join(tempPath, 'rossi-video-posters'));
    if (await target.exists()) {
      await target.delete(recursive: true);
      logger.d('Video posters cache cleared successfully.');
    }
  } catch (e) {
    logger.e('Error clearing video posters cache: $e');
  }
}

/// 清理全部缓存（保留 sentry 目录）
Future<void> clearCache(String cachePath, {String? customTempPath}) async {
  try {
    final directory = Directory(cachePath);
    if (await directory.exists()) {
      final List<FileSystemEntity> entities = directory.listSync(
        recursive: false,
      );

      for (var entity in entities) {
        final String name = p.basename(entity.path);
        if (name != 'sentry') {
          await entity.delete(recursive: true);
        }
      }
      logger.d('Cache cleared successfully (Sentry folder preserved).');
    }
    await clearVideoPostersCache(customTempPath: customTempPath);
  } catch (e) {
    logger.e('Error clearing cache: $e');
  }
}

/// 执行自动清理逻辑：按各分类的保留时间与容量上限清理过期或多余的缓存文件
Future<CacheCleanResult> autoCleanExpiredAndExcessCaches(
  CacheSettingState setting, {
  String? customCachePath,
  String? customTempPath,
  DateTime? now,
}) async {
  final currentTime = now ?? DateTime.now();
  final cachePath = customCachePath ?? await getCachePath();
  int cleanedFiles = 0;
  int cleanedBytes = 0;

  // 1. 自动清理图片处理缓存 (reader_image_processing)
  if (setting.autoCleanReaderImageProcessing) {
    final ripDir = Directory(p.join(cachePath, 'reader_image_processing'));
    if (await ripDir.exists()) {
      try {
        final files = ripDir
            .listSync(recursive: true)
            .whereType<File>()
            .toList();
        final remainingFiles = <(File, int, DateTime)>[];

        for (final file in files) {
          try {
            final stat = file.statSync();
            final size = file.lengthSync();
            final isExpired =
                setting.readerImageProcessingMaxAgeDays > 0 &&
                currentTime.difference(stat.modified).inDays >=
                    setting.readerImageProcessingMaxAgeDays;

            if (isExpired) {
              file.deleteSync();
              cleanedFiles++;
              cleanedBytes += size;
            } else {
              remainingFiles.add((file, size, stat.modified));
            }
          } on FileSystemException {
            continue;
          }
        }

        // 检查容量上限：如果剩余产物超出容量上限，按修改时间从最旧的开始删
        if (setting.readerImageProcessingSizeLimit > 0) {
          int currentRipSize = remainingFiles.fold(0, (sum, f) => sum + f.$2);
          if (currentRipSize > setting.readerImageProcessingSizeLimit) {
            remainingFiles.sort((a, b) => a.$3.compareTo(b.$3));
            for (final (file, size, _) in remainingFiles) {
              if (currentRipSize <= setting.readerImageProcessingSizeLimit) {
                break;
              }
              try {
                file.deleteSync();
                cleanedFiles++;
                cleanedBytes += size;
                currentRipSize -= size;
              } on FileSystemException {
                continue;
              }
            }
          }
        }
      } catch (e) {
        logger.e('Error auto-cleaning reader_image_processing: $e');
      }
    }

    try {
      await SuperResolutionLog.trimCache();
    } catch (_) {}
  }

  // 2. 自动清理在线漫画页面缓存
  if (setting.autoCleanComicPages && setting.comicPagesMaxAgeDays > 0) {
    final baseDir = Directory(cachePath);
    if (await baseDir.exists()) {
      try {
        final entries = baseDir.listSync(recursive: false);
        for (final entity in entries) {
          final name = p.basename(entity.path);
          if (name == 'sentry' ||
              name == 'reader_image_processing' ||
              name == 'mimage_catalog') {
            continue;
          }
          if (entity is Directory) {
            for (final file
                in entity.listSync(recursive: true).whereType<File>()) {
              try {
                final stat = file.statSync();
                if (currentTime.difference(stat.modified).inDays >=
                    setting.comicPagesMaxAgeDays) {
                  final size = file.lengthSync();
                  file.deleteSync();
                  cleanedFiles++;
                  cleanedBytes += size;
                }
              } on FileSystemException {
                continue;
              }
            }
          }
        }
      } catch (e) {
        logger.e('Error auto-cleaning comic pages: $e');
      }
    }
  }

  // 3. 自动清理视频海报缓存（7天未用即清理）
  if (setting.autoCleanVideoPosters) {
    try {
      final tempPath = customTempPath ?? (await getTemporaryDirectory()).path;
      final posterDir = Directory(p.join(tempPath, 'rossi-video-posters'));
      if (await posterDir.exists()) {
        for (final file
            in posterDir.listSync(recursive: true).whereType<File>()) {
          try {
            final stat = file.statSync();
            if (currentTime.difference(stat.modified).inDays >= 7) {
              final size = file.lengthSync();
              file.deleteSync();
              cleanedFiles++;
              cleanedBytes += size;
            }
          } on FileSystemException {
            continue;
          }
        }
      }
    } catch (_) {}
  }

  // 4. 自动清理本地缩略图与目录（30天未用即清理）
  if (setting.autoCleanThumbnails) {
    final catalogDir = Directory(p.join(cachePath, 'mimage_catalog'));
    if (await catalogDir.exists()) {
      try {
        for (final file
            in catalogDir.listSync(recursive: true).whereType<File>()) {
          try {
            final stat = file.statSync();
            if (currentTime.difference(stat.modified).inDays >= 30) {
              final size = file.lengthSync();
              file.deleteSync();
              cleanedFiles++;
              cleanedBytes += size;
            }
          } on FileSystemException {
            continue;
          }
        }
      } catch (_) {}
    }
  }

  // 5. 全局容量上限治理：若总缓存仍超过 cacheSizeLimit，按最旧文件开始逐级清理
  if (setting.autoCleanCache && setting.cacheSizeLimit > 0) {
    try {
      final sizes = await calculateCacheCategorySizes(
        customCachePath: cachePath,
        customTempPath: customTempPath,
      );
      if (sizes.totalBytes > setting.cacheSizeLimit) {
        final cacheDir = Directory(cachePath);
        if (await cacheDir.exists()) {
          final allFiles = <(File, int, DateTime)>[];
          for (final file
              in cacheDir.listSync(recursive: true).whereType<File>()) {
            if (file.path.split(Platform.pathSeparator).contains('sentry')) {
              continue;
            }
            try {
              allFiles.add((file, file.lengthSync(), file.statSync().modified));
            } on FileSystemException {
              continue;
            }
          }

          allFiles.sort((a, b) => a.$3.compareTo(b.$3));
          int currentTotal = sizes.totalBytes;
          for (final (file, size, _) in allFiles) {
            if (currentTotal <= setting.cacheSizeLimit) break;
            try {
              file.deleteSync();
              cleanedFiles++;
              cleanedBytes += size;
              currentTotal -= size;
            } on FileSystemException {
              continue;
            }
          }
        }
      }
    } catch (e) {
      logger.e('Error enforcing global cache limit: $e');
    }
  }

  logger.d(
    'Auto clean finished: removed $cleanedFiles files, freed ${(cleanedBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  );

  return CacheCleanResult(
    cleanedFilesCount: cleanedFiles,
    cleanedBytes: cleanedBytes,
  );
}

/// 检查并执行缓存管理
Future<void> manageCacheSize(BuildContext context) async {
  if (!context.mounted) return;
  final settinCubit = context.read<GlobalSettingCubit>();
  final currentState = settinCubit.state;

  if (!currentState.cacheSetting.autoCleanCache &&
      !currentState.cacheSetting.autoCleanReaderImageProcessing &&
      !currentState.cacheSetting.autoCleanComicPages) {
    logger.d('Auto clean cache disabled, skipping.');
    return;
  }

  try {
    await autoCleanExpiredAndExcessCaches(currentState.cacheSetting);
  } catch (e) {
    logger.e('Error during auto clean: $e');
  }

  if (!context.mounted) return;

  final sizes = await calculateCacheCategorySizes();
  final maxSize = currentState.cacheSetting.cacheSizeLimit;

  if (sizes.totalBytes >= maxSize && currentState.cacheSetting.autoCleanCache) {
    logger.d(
      'Cache size still exceeded ${maxSize / (1024 * 1024)} MB after auto-clean, marking needCleanCache.',
    );
    settinCubit.updateState(
      (current) => current.copyWith(needCleanCache: true),
    );
  } else {
    settinCubit.updateState(
      (current) => current.copyWith(needCleanCache: false),
    );
  }
}
