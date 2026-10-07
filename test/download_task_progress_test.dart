import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/download/download_speed_meter.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

DownloadTaskJson _payload({
  int completed = 0,
  int total = 0,
  int bytesPerSecond = 0,
  String stateCode = 'running',
}) {
  return DownloadTaskJson(
    from: 'plugin-a',
    comicId: 'comic/1',
    comicName: '测试漫画',
    chapterRef: const DownloadChapterTaskRef(
      chapterId: 'chapter-1',
      title: '第 1 话',
      order: 1,
    ),
    stateCode: stateCode,
    completedImages: completed,
    totalImages: total,
    bytesPerSecond: bytesPerSecond,
  );
}

void main() {
  LocaleSettings.setLocale(AppLocale.zhCn);

  test('图片进度换算', () {
    expect(
      downloadTaskProgressFraction(completedImages: 5, totalImages: 10),
      0.5,
    );
    expect(
      downloadTaskProgressFraction(completedImages: 0, totalImages: 10),
      0.0,
    );
    expect(
      downloadTaskProgressFraction(completedImages: 10, totalImages: 10),
      1.0,
    );
  });

  test('进度钳制在 0~1 之间', () {
    expect(
      downloadTaskProgressFraction(completedImages: 12, totalImages: 10),
      1.0,
    );
    expect(
      downloadTaskProgressFraction(completedImages: -2, totalImages: 10),
      0.0,
    );
  });

  test('总数未知时返回 null / 空文案', () {
    expect(
      downloadTaskProgressFraction(completedImages: 0, totalImages: 0),
      isNull,
    );
    expect(downloadTaskPayloadProgressFraction(_payload()), isNull);
    expect(downloadTaskPayloadProgressMessage(_payload()), '');
  });

  test('payload 进度换算', () {
    expect(
      downloadTaskPayloadProgressFraction(_payload(completed: 3, total: 4)),
      0.75,
    );
  });

  test('速度文本按量级换算', () {
    expect(formatDownloadSpeed(512), '512 B/s');
    expect(formatDownloadSpeed(1536), '2 KB/s');
    expect(formatDownloadSpeed(1024 * 1024 * 1.5), '1.5 MB/s');
  });

  test('页数文案：下载中带速度，停下来的状态不带过期速度', () {
    expect(
      downloadTaskPayloadProgressMessage(
        _payload(completed: 12, total: 45, bytesPerSecond: 1536),
      ),
      '已下载 12/45 页 · 2 KB/s',
    );
    expect(
      downloadTaskPayloadProgressMessage(
        _payload(
          completed: 12,
          total: 45,
          bytesPerSecond: 1536,
          stateCode: 'paused',
        ),
      ),
      '已下载 12/45 页',
    );
  });

  test('速度采样窗口内没有样本时归零', () {
    final meter = DownloadSpeedMeter();
    final start = DateTime(2026, 1, 1, 12);
    meter.addBytes(100 * 1024, at: start);
    expect(
      meter.bytesPerSecondAt(start.add(const Duration(seconds: 1))),
      greaterThan(0),
    );
    // 超过窗口后样本被清空，速度归零。
    expect(meter.bytesPerSecondAt(start.add(const Duration(seconds: 10))), 0);
  });
}
