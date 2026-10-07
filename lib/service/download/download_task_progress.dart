import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

/// 单章节任务的图片下载进度（0.0 ~ 1.0）。
///
/// 总数未知时返回 null，调用方回退显示任务 status 文字。
double? downloadTaskProgressFraction({
  required int completedImages,
  required int totalImages,
}) {
  if (totalImages <= 0) return null;
  return (completedImages.clamp(0, totalImages).toDouble() / totalImages)
      .clamp(0.0, 1.0)
      .toDouble();
}

double? downloadTaskPayloadProgressFraction(DownloadTaskJson payload) {
  return downloadTaskProgressFraction(
    completedImages: payload.completedImages,
    totalImages: payload.totalImages,
  );
}

/// 速度文本（B/s、KB/s、MB/s）。
String formatDownloadSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).round()} KB/s';
  }
  return '${bytesPerSecond.round()} B/s';
}

/// 页数进度文案：`已下载 12/45 页`（速度未知或为 0 时不带速度）。
///
/// 章节图片总数未知（totalImages <= 0）时返回空字符串，让调用方回退到
/// 任务 status 文字。
String downloadPagesProgressText({
  required int completedImages,
  required int totalImages,
  double bytesPerSecond = 0,
}) {
  if (totalImages <= 0) return '';
  final completed = completedImages.clamp(0, totalImages);
  if (bytesPerSecond > 0) {
    return t.download.progressPagesWithSpeed(
      completed: completed,
      total: totalImages,
      speed: formatDownloadSpeed(bytesPerSecond),
    );
  }
  return t.download.progressPages(completed: completed, total: totalImages);
}

/// payload 的进度文案。
///
/// 速度只在 running 状态展示：暂停/失败/完成后 payload 里的速度值已经过期，
/// 但页数仍要显示，用户才能看出暂停时停在哪一页。
String downloadTaskPayloadProgressMessage(DownloadTaskJson payload) {
  final speed = payload.stateCode == 'running' ? payload.bytesPerSecond : 0;
  return downloadPagesProgressText(
    completedImages: payload.completedImages,
    totalImages: payload.totalImages,
    bytesPerSecond: speed.toDouble(),
  );
}
