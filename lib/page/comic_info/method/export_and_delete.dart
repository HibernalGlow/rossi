import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/service/download/download_asset_store.dart'
    show DownloadAssetStore;
import 'package:zephyr/service/download/download_delete_service.dart'
    show deleteWholeComicDownload;
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';

/// 一次「导出 + 可选删除」的结局。删除只在 [deleted] 时发生。
enum ExportDeleteOutcome {
  /// 没勾选删除，只导出。
  notRequested,

  /// 三道门都过了，本地下载已删除。
  deleted,

  /// 有页没进归档，或一页都没进归档。
  incomplete,

  /// 产物没落到磁盘上，或结构不完整。
  artifactInvalid,

  /// 产物就在下载目录里面，删下去会连着把导出结果一起删掉。
  insideDownloadRoot,

  /// 导出与校验都没问题，但删除本身失败了。
  deleteFailed,
}

/// 一次「导出（+ 可选删除）」的结果。
class ExportWithDeleteResult {
  const ExportWithDeleteResult({
    required this.export,
    required this.outcome,
    this.deleteError,
  });

  final ComicExportResult export;
  final ExportDeleteOutcome outcome;

  /// 仅在 [ExportDeleteOutcome.deleteFailed] 时非空。
  final Object? deleteError;

  bool get deleted => outcome == ExportDeleteOutcome.deleted;
}

/// 导出漫画；只有确认导出完整且落盘成功，才删掉本地下载。
///
/// 删除不可逆，而导出侧对取不到的页是静默跳过的，所以「没抛异常」不能当放行条件，
/// 必须同时过三道门（见 [ExportDeleteOutcome]）。任一道不过就保留原文件并回报原因。
Future<ExportWithDeleteResult> exportComicAndMaybeDelete({
  required String comicId,
  required ExportType type,
  required String from,
  String? path,
  required bool deleteAfterExport,
}) async {
  final export = await exportComic(comicId, type, from, path: path);

  if (!deleteAfterExport) {
    return _result(export, ExportDeleteOutcome.notRequested);
  }

  if (!export.complete) {
    return _result(export, ExportDeleteOutcome.incomplete);
  }

  if (!await _artifactLanded(export.path, type)) {
    return _result(export, ExportDeleteOutcome.artifactInvalid);
  }

  if (await _landsInsideDownloadRoot(export.path)) {
    return _result(export, ExportDeleteOutcome.insideDownloadRoot);
  }

  try {
    await deleteWholeComicDownload(from: from, comicId: comicId);
  } catch (e) {
    return ExportWithDeleteResult(
      export: export,
      outcome: ExportDeleteOutcome.deleteFailed,
      deleteError: e,
    );
  }

  return _result(export, ExportDeleteOutcome.deleted);
}

ExportWithDeleteResult _result(
  ComicExportResult export,
  ExportDeleteOutcome outcome,
) {
  return ExportWithDeleteResult(export: export, outcome: outcome);
}

/// 产物是否真的落到了磁盘上。
Future<bool> _artifactLanded(String path, ExportType type) async {
  if (type == ExportType.zip) {
    final file = File(path);
    if (!await file.exists()) return false;
    if (await file.length() <= 0) return false;
    return await hasZipEndOfCentralDirectory(file);
  }

  final dir = Directory(path);
  if (!await dir.exists()) return false;
  for (final name in const [
    'original_comic_info.json',
    'processed_comic_info.json',
  ]) {
    if (!await File(p.join(path, name)).exists()) return false;
  }
  return true;
}

/// 校验 zip 的「中央目录结束记录」（EOCD）确实是收尾的那条记录。
///
/// 只验「文件非空」不够：写盘被打断留下的半截 zip 同样非空，但删掉原下载后就再也打不开了。
/// 光在尾部找 `PK\x05\x06` 签名也不够——签名是这条记录的**头 4 个字节**，
/// 砍掉文件尾反而会把签名留下。所以必须按记录结构对齐：签名位置 + 记录长度
/// + 声明的注释长度，要正好等于文件末尾。
Future<bool> hasZipEndOfCentralDirectory(File file) async {
  const signature = [0x50, 0x4b, 0x05, 0x06];
  const recordLength = 22;
  const maxCommentLength = 65535;

  final length = await file.length();
  if (length < recordLength) return false;

  final readLength = length < recordLength + maxCommentLength
      ? length
      : recordLength + maxCommentLength;
  final raf = await file.open(mode: FileMode.read);
  try {
    await raf.setPosition(length - readLength);
    final tail = await raf.read(readLength);
    for (var i = tail.length - recordLength; i >= 0; i--) {
      if (tail[i] != signature[0] ||
          tail[i + 1] != signature[1] ||
          tail[i + 2] != signature[2] ||
          tail[i + 3] != signature[3]) {
        continue;
      }
      final commentLength = tail[i + 20] | (tail[i + 21] << 8);
      if (i + recordLength + commentLength == tail.length) return true;
    }
    return false;
  } finally {
    await raf.close();
  }
}

/// 导出目标是否就在下载目录里面（跟着一起被删）。
Future<bool> _landsInsideDownloadRoot(String artifactPath) async {
  final artifact = await _canonical(artifactPath);
  final root = await _canonical(await getDownloadPath());
  if (artifact == null || root == null) return false;
  return DownloadAssetStore.isWithinRoot(root, artifact);
}

Future<String?> _canonical(String path) async {
  final file = File(path);
  if (file.existsSync()) {
    return file.resolveSymbolicLinks();
  }
  final dir = Directory(path);
  if (await dir.exists()) {
    return dir.resolveSymbolicLinks();
  }
  return null;
}
