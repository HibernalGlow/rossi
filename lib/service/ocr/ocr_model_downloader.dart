import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

/// OCR 权重的首下。沿用 RealSR 那套写法（`real_sr_super_resolution.dart` 的 `downloadModel`）：
/// 先下到 `.download_<uuid>` 再改名 —— 中断不会留下一个「看起来存在但其实是半截」的模型，
/// 而那正是 `OcrModels._valid` 的体积下限要挡的东西。
class OcrModelDownloader {
  OcrModelDownloader._();

  /// 下载缺失的权重（已就绪的跳过）。
  ///
  /// [withInpaint] 为 false 时只下识别链路（约 460 MB）；成品页还要 LaMa（再 206 MB）。
  /// [onProgress] 报**总进度**：`(已传字节, 总字节, 当前文件名)`，总字节在开始前按已知体积估。
  /// [download] 是网络那一跳的缝：默认走 `WindHttp`，测试要能喂「下到一半就断」这种剧本 ——
  /// 这条路径的产物是 660 MB 权重，真下载不该是单测的前提。
  static Future<void> ensure({
    bool withInpaint = true,
    bool force = false,
    void Function(int received, int total, String file)? onProgress,
    Future<void> Function(String url, String path, OcrModelProgress)? download,
  }) async {
    final pull = download ?? _windDownload;
    final dir = await OcrModels.directory();
    await dir.create(recursive: true);

    final wanted = <String, String>{
      OcrModels.detFile: OcrModels.detUrl,
      OcrModels.encoderFile: OcrModels.encoderUrl,
      OcrModels.decoderFile: OcrModels.decoderUrl,
      OcrModels.vocabFile: OcrModels.vocabUrl,
      if (withInpaint) OcrModels.inpaintFile: OcrModels.inpaintUrl,
    };

    // 总量按**已知体积**估，用来把「5 个文件各自的进度」合成一条总进度。
    const totals = <String, int>{
      OcrModels.detFile: 4745517,
      OcrModels.encoderFile: 343454249,
      OcrModels.decoderFile: 117480262,
      OcrModels.vocabFile: 30216,
      OcrModels.inpaintFile: 206291843,
    };
    final grandTotal = wanted.keys
        .map((f) => totals[f] ?? 0)
        .fold<int>(0, (a, b) => a + b);

    var doneBytes = 0;
    for (final entry in wanted.entries) {
      final file = entry.key;
      final url = entry.value;
      final destination = File(p.join(dir.path, file));
      if (!force && await _looksValid(destination, file)) {
        doneBytes += totals[file] ?? 0;
        onProgress?.call(doneBytes, grandTotal, file);
        continue;
      }

      final pending = File('${destination.path}.download_${const Uuid().v4()}');
      try {
        await pull(url, pending.path, (received, total) {
          onProgress?.call(doneBytes + received, grandTotal, file);
        });
        if (!await _looksValid(pending, file)) {
          throw StateError('下载的 $file 体积不对（可能是 HTML 错误页或 LFS 指针）');
        }
        await pending.rename(destination.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
      doneBytes += await destination.length();
      onProgress?.call(doneBytes, grandTotal, file);
    }
  }

  static Future<bool> _looksValid(File f, String name) async {
    if (!await f.exists()) return false;
    const minBytes = <String, int>{
      OcrModels.detFile: 4 * 1000 * 1000,
      OcrModels.encoderFile: 300 * 1000 * 1000,
      OcrModels.decoderFile: 100 * 1000 * 1000,
      OcrModels.vocabFile: 20 * 1000,
      OcrModels.inpaintFile: 180 * 1000 * 1000,
    };
    return await f.length() >= (minBytes[name] ?? 1024);
  }
}

/// 单文件的下载进度回调。
typedef OcrModelProgress = void Function(int received, int total);

Future<void> _windDownload(
  String url,
  String path,
  OcrModelProgress onReceiveProgress,
) => WindHttp().download(url, path, onReceiveProgress: onReceiveProgress);
