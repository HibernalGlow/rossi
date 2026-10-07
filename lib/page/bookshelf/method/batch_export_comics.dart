import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/method/export_and_delete.dart';
import 'package:zephyr/page/comic_info/widgets/export_choice_dialog.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/permission.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

/// 一次批量导出的结果。
class BatchExportResult {
  const BatchExportResult({
    required this.success,
    required this.deleted,
    required this.keptForMissingPages,
  });

  /// 成功导出的本数。
  final int success;

  /// 其中已按勾选删掉本地下载的本数。
  final int deleted;

  /// 勾了删除、但因为有页没进归档而被保留下来的本数。
  final int keptForMissingPages;
}

/// 批量导出选中的已下载漫画。
///
/// 返回成功导出的数量。导出失败的项目会被跳过，不会中断后续导出。
/// 只有 [ExportChoice.deleteAfterExport] 为真且该本导出完整时才会删本地下载。
Future<BatchExportResult> batchExportComics({
  required List<ComicSimplifyEntryInfo> comics,
  required ExportChoice choice,
}) async {
  if (comics.isEmpty) {
    return const BatchExportResult(
      success: 0,
      deleted: 0,
      keptForMissingPages: 0,
    );
  }

  final exportType = choice.type;
  final exportRoot = await _resolveBatchExportDirectory();
  if (exportRoot == null || exportRoot.trim().isEmpty) {
    return const BatchExportResult(
      success: 0,
      deleted: 0,
      keptForMissingPages: 0,
    );
  }

  var success = 0;
  var deleted = 0;
  var keptForMissingPages = 0;
  for (final comic in comics) {
    final from = comic.from.trim();
    if (from.isEmpty) continue;

    String? exportPath;
    if (exportType == ExportType.folder) {
      exportPath = exportRoot;
    } else {
      final safeTitle = _sanitizeFileName(
        comic.title.trim().isEmpty ? comic.id : comic.title,
      );
      exportPath = p.join(exportRoot, '$safeTitle.zip');
    }

    try {
      final result = await exportComicAndMaybeDelete(
        comicId: comic.id,
        type: exportType,
        from: from,
        path: exportPath,
        deleteAfterExport: choice.deleteAfterExport,
      );
      success++;
      if (result.deleted) {
        deleted++;
      } else if (result.outcome == ExportDeleteOutcome.incomplete) {
        keptForMissingPages++;
      }
    } catch (_) {
      // 继续导出下一本，避免单本失败导致整批中断。
    }
  }

  return BatchExportResult(
    success: success,
    deleted: deleted,
    keptForMissingPages: keptForMissingPages,
  );
}

/// 弹出批量导出的格式与删除选择；iOS 直接返回 zip 且不删。
Future<ExportChoice?> pickBatchExportChoice(BuildContext context) async {
  if (Platform.isIOS) {
    return const ExportChoice(type: ExportType.zip, deleteAfterExport: false);
  }
  return showExportChoiceDialog(
    context,
    title: t.bookshelf.batchExportTitle,
    subtitle: t.bookshelf.batchExportSubtitle,
  );
}

Future<String?> _resolveBatchExportDirectory() async {
  // iOS 无目录选择器，导出到应用 Documents（可在「文件」App 中访问）
  if (Platform.isIOS) {
    return createDownloadDir();
  }
  final customPath = globalSetting.customExportPath.trim();
  if (customPath.isNotEmpty) {
    return customPath;
  }
  if (Platform.isAndroid) {
    final granted = await requestExportPermission();
    if (!granted) {
      throw StateError(t.comicInfo.exportPermissionDenied);
    }
    return createDownloadDir();
  }
  return getDirectoryPath();
}

String _sanitizeFileName(String input) {
  final safe = input
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'comic' : safe;
}
