import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/donwload_task/models/download_task_view_filter.dart';

bool _matches(
  DownloadTaskViewFilter filter, {
  bool isDownloading = false,
  String? stateCode,
}) {
  return downloadTaskMatchesViewFilter(
    filter: filter,
    isDownloading: isDownloading,
    stateCode: stateCode,
  );
}

void main() {
  group('下载任务状态筛选', () {
    test('「全部」放行每一行，包括状态码读不出来的残留行', () {
      expect(_matches(DownloadTaskViewFilter.all), isTrue);
      expect(_matches(DownloadTaskViewFilter.all, stateCode: null), isTrue);
      expect(
        _matches(
          DownloadTaskViewFilter.all,
          isDownloading: true,
          stateCode: 'running',
        ),
        isTrue,
      );
    });

    test('「下载中」只看 isDownloading，不信状态码', () {
      expect(
        _matches(
          DownloadTaskViewFilter.downloading,
          isDownloading: true,
          stateCode: 'running',
        ),
        isTrue,
      );
      // 状态码写了 running 但调度器还没认领 —— 不算正在下。
      expect(
        _matches(DownloadTaskViewFilter.downloading, stateCode: 'running'),
        isFalse,
      );
      expect(
        _matches(
          DownloadTaskViewFilter.downloading,
          isDownloading: true,
          stateCode: 'paused',
        ),
        isTrue,
      );
    });

    test('「等待中」是剩下的那一档：排队与重试中在内，暂停与失败在外', () {
      for (final stateCode in ['queued', 'retrying', null]) {
        expect(
          _matches(DownloadTaskViewFilter.waiting, stateCode: stateCode),
          isTrue,
          reason: 'stateCode=$stateCode 应该算等待中',
        );
      }
      expect(
        _matches(DownloadTaskViewFilter.waiting, stateCode: 'paused'),
        isFalse,
      );
      expect(
        _matches(DownloadTaskViewFilter.waiting, stateCode: 'failed'),
        isFalse,
      );
      expect(
        _matches(
          DownloadTaskViewFilter.waiting,
          isDownloading: true,
          stateCode: 'queued',
        ),
        isFalse,
      );
    });

    test('「已暂停」与「失败」各自只收自己那一档', () {
      expect(
        _matches(DownloadTaskViewFilter.paused, stateCode: 'paused'),
        isTrue,
      );
      expect(
        _matches(DownloadTaskViewFilter.paused, stateCode: 'failed'),
        isFalse,
      );
      expect(
        _matches(DownloadTaskViewFilter.failed, stateCode: 'failed'),
        isTrue,
      );
      expect(
        _matches(DownloadTaskViewFilter.failed, stateCode: 'paused'),
        isFalse,
      );
      // 一条在跑的行不该被筛进「失败」，否则用户会去点「重试失败项」打断它。
      expect(
        _matches(
          DownloadTaskViewFilter.failed,
          isDownloading: true,
          stateCode: 'failed',
        ),
        isFalse,
      );
    });

    test('五档筛选对同一行互斥：非下载中的行只落进一档', () {
      const buckets = [
        DownloadTaskViewFilter.downloading,
        DownloadTaskViewFilter.waiting,
        DownloadTaskViewFilter.paused,
        DownloadTaskViewFilter.failed,
      ];
      for (final stateCode in ['running', 'queued', 'paused', 'failed', null]) {
        for (final isDownloading in [false, true]) {
          final hits = buckets
              .where(
                (f) => _matches(
                  f,
                  isDownloading: isDownloading,
                  stateCode: stateCode,
                ),
              )
              .toList();
          expect(
            hits,
            hasLength(1),
            reason:
                'isDownloading=$isDownloading, stateCode=$stateCode → $hits',
          );
        }
      }
    });
  });
}
