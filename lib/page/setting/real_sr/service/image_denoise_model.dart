import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:zephyr/main.dart' show logger;
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/page/setting/real_sr/service/denoise_model_download.dart';
import 'package:zephyr/page/setting/real_sr/service/download_retry.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/src/rust/api/mimage_onnx.dart';
import 'package:zephyr/util/get_path.dart';

abstract final class ImageDenoiseModel {
  // 与 vendor/mimageviewer 的已审计权重一致；更新上游时显式更新版本和摘要。
  static const revision = 'bb6ca0c665544da10b1acb061b590512acd0a4a4';
  static const expectedBytes = 29620809;
  static const digest =
      '70832d4536202d7e83603debb7b3e47a798553f0b534e708a498a23939c905b2';
  static const url =
      'https://media.githubusercontent.com/media/MikageSawatari/mimageviewer/$revision/models/${MImageOnnxModelConfig.denoiseFileName}';
  static const fallbackUrl =
      'https://github.com/MikageSawatari/mimageviewer/raw/$revision/models/${MImageOnnxModelConfig.denoiseFileName}';
  static Future<File> get file async => File(
    p.join(
      await getFilePath(),
      'super_resolution',
      'mimage_onnx',
      MImageOnnxModelConfig.denoiseFileName,
    ),
  );

  static final downloads = DenoiseModelDownload(
    inspect: installedSize,
    transfer: (progress, verifying) => _download(progress, verifying),
    remove: _remove,
  );
  static (String, int, DateTime)? _verified;

  static Future<int> installedSize() async {
    final model = await file;
    if (!await model.exists()) return 0;
    final stat = await model.stat();
    if (stat.size != expectedBytes) return 0;
    final identity = (model.path, stat.size, stat.modified);
    if (_verified != identity) {
      if ((await sha256.bind(model.openRead()).first).toString() != digest) {
        return 0;
      }
      _verified = identity;
    }
    return stat.size;
  }

  static Future<void> _download(
    void Function(int, int) progress,
    void Function() verifying,
  ) async {
    final destination = await file;
    await destination.parent.create(recursive: true);
    final pending = File('${destination.path}.download_${const Uuid().v4()}');
    final backup = File('${destination.path}.previous_${const Uuid().v4()}');
    var installed = false;
    try {
      // 29 MB 的单文件，连接中途被掐时从头再来比让用户手动重试更省事；最多 3 次。
      final candidateUrls = [url, fallbackUrl];
      await retryTransfer(
        (attempt) {
          final targetUrl = candidateUrls[(attempt - 1) % candidateUrls.length];
          return WindHttp(
            receiveTimeout: const Duration(seconds: 60),
            // 权重已经是二进制，显式关闭 HTTP 内容压缩，避免代理/CDN 的压缩流额外出错。
            headers: {'User-Agent': 'Breeze', 'Accept-Encoding': 'identity'},
          ).download(targetUrl, pending.path, onReceiveProgress: progress);
        },
        onRetry: (attempt, error) =>
            logger.w('降噪模型下载第 $attempt 次失败，准备重试：$error'),
      );
      verifying();
      if (await pending.length() != expectedBytes ||
          (await sha256.bind(pending.openRead()).first).toString() != digest) {
        throw StateError('模型大小或 SHA-256 不匹配，请重试下载');
      }
      // Windows rename 不覆盖现有文件；失败恢复原来已安装的模型。
      await mimageOnnxReleaseSessions();
      if (await destination.exists()) await destination.rename(backup.path);
      try {
        await pending.rename(destination.path);
        installed = true;
      } catch (_) {
        if (await backup.exists()) await backup.rename(destination.path);
        rethrow;
      }
      _verified = null;
      await ImageDenoiseSettings.modelChanged();
    } finally {
      if (await pending.exists()) await pending.delete();
      if (installed && await backup.exists()) await backup.delete();
    }
  }

  static Future<void> _remove() async {
    await mimageOnnxReleaseSessions();
    final model = await file;
    if (await model.exists()) await model.delete();
    _verified = null;
    await ImageDenoiseSettings.modelChanged();
  }
}
