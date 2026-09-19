import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/src/rust/compressed/compressed.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/widgets/toast.dart';

enum ReaderExportAction {
  saveToAlbum,
  exportZip,
  downloadSelected,
}

class ReaderImageExportItem {
  final int index;
  final String title;
  final Doc doc;
  final String from;
  final String comicId;

  const ReaderImageExportItem({
    required this.index,
    required this.title,
    required this.doc,
    required this.from,
    required this.comicId,
  });
}

class ReaderImageExportService {
  static Future<void> exportImages({
    required BuildContext context,
    required List<ReaderImageExportItem> items,
    required ReaderExportAction action,
    required String comicTitle,
    void Function(int current, int total)? onProgress,
  }) async {
    if (items.isEmpty) return;

    final isMobile = Platform.isAndroid || Platform.isIOS;

    String? desktopTargetDir;
    String? targetZipPath;

    if (action == ReaderExportAction.saveToAlbum && !isMobile) {
      desktopTargetDir = await getDirectoryPath(
        confirmButtonText: t.common.confirm,
      );
      if (desktopTargetDir == null) return;
    } else if (action == ReaderExportAction.exportZip) {
      if (!isMobile) {
        final safeName = comicTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final location = await getSaveLocation(
          suggestedName: '${safeName}_selected.zip',
        );
        if (location == null) return;
        targetZipPath = location.path;
      } else {
        final downloadDir = await getDownloadPath();
        final safeName = comicTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        targetZipPath = p.join(
          downloadDir,
          '${safeName}_selected_${DateTime.now().millisecondsSinceEpoch}.zip',
        );
      }
    }

    if (action == ReaderExportAction.saveToAlbum && isMobile) {
      try {
        if (!await Gal.hasAccess()) {
          await Gal.requestAccess();
        }
      } catch (e) {
        showErrorToast(t.reader.saveImagePermissionDenied);
        return;
      }
    }

    final originalImagePaths = <String>[];
    final packImagePaths = <String>[];

    var processed = 0;
    for (final item in items) {
      processed++;
      onProgress?.call(processed, items.length);

      try {
        String imagePath;
        if (action == ReaderExportAction.downloadSelected) {
          final res = await downloadPictureResult(
            from: item.from,
            url: item.doc.fileServer,
            path: item.doc.path,
            cartoonId: item.comicId,
            chapterId: item.doc.id,
            storageChapterId: item.doc.storageChapterId,
            pictureType: PictureType.page,
            retry: true,
            extern: item.doc.extern,
          );
          if (!res.isSuccess) {
            throw StateError('下载失败: ${res.status.name}');
          }
          imagePath = res.path;
        } else {
          imagePath = await getCachePicture(
            from: item.from,
            url: item.doc.fileServer,
            path: item.doc.path,
            cartoonId: item.comicId,
            chapterId: item.doc.id,
            storageChapterId: item.doc.storageChapterId,
            pictureType: PictureType.page,
            extern: item.doc.extern,
            usePlugin: true,
          );
        }

        if (imagePath.isEmpty || imagePath == '404' || !File(imagePath).existsSync()) {
          logger.w('选图提取图片不存在，跳过: index=${item.index}, path=$imagePath');
          continue;
        }

        final file = File(imagePath);
        final ext = await detectImageExtension(file);

        if (action == ReaderExportAction.saveToAlbum) {
          if (isMobile) {
            final tempDir = Directory.systemTemp;
            final fileName =
                'selected_${item.index}_${DateTime.now().millisecondsSinceEpoch}$ext';
            final tempPath = p.join(tempDir.path, fileName);
            final tempFile = await file.copy(tempPath);
            try {
              await Gal.putImage(
                tempFile.path,
                album: Platform.isIOS ? null : appName,
              );
            } finally {
              try {
                await tempFile.delete();
              } catch (_) {}
            }
          } else if (desktopTargetDir != null) {
            final targetName =
                'p${item.index.toString().padLeft(3, '0')}$ext';
            await file.copy(p.join(desktopTargetDir, targetName));
          }
        } else if (action == ReaderExportAction.exportZip) {
          originalImagePaths.add(imagePath);
          packImagePaths.add('p${item.index.toString().padLeft(3, '0')}$ext');
        }
      } catch (e) {
        logger.e('处理选图项目失败: index=${item.index}', error: e);
      }
    }

    if (action == ReaderExportAction.exportZip && targetZipPath != null) {
      if (originalImagePaths.isEmpty) {
        showErrorToast(t.error.operationFailed);
        return;
      }
      final packInfo = PackInfo(
        comicInfoString: '{"title":"$comicTitle"}',
        processedComicInfoString: '{"title":"$comicTitle"}',
        originalImagePaths: originalImagePaths,
        packImagePaths: packImagePaths,
      );
      await packFolderZip(destPath: targetZipPath, packInfo: packInfo);
      showSuccessToast(t.reader.extractSuccess);
    } else if (action == ReaderExportAction.saveToAlbum) {
      if (isMobile) {
        showSuccessToast(t.reader.imageSavedToAlbum);
      } else if (desktopTargetDir != null) {
        showSuccessToast(t.reader.imageSavedTo(path: desktopTargetDir));
      }
    } else if (action == ReaderExportAction.downloadSelected) {
      showSuccessToast(t.reader.extractSuccess);
    }
  }
}
