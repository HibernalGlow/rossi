import 'package:zephyr/i18n/strings.g.dart';

/// 下载任务页的状态筛选。
enum DownloadTaskViewFilter {
  all,
  downloading,
  waiting,
  paused,
  failed;

  String get label => switch (this) {
    DownloadTaskViewFilter.all => t.download.filterAll,
    DownloadTaskViewFilter.downloading => t.download.downloading,
    DownloadTaskViewFilter.waiting => t.download.statusWaiting,
    DownloadTaskViewFilter.paused => t.download.paused,
    DownloadTaskViewFilter.failed => t.download.failed,
  };
}

/// 这一行是否属于当前筛选。
///
/// `isDownloading` 与状态码由调用方读好传进来：判据本身是纯函数，
/// 页面上「筛完什么都不剩」和「筛错类别」这两种红才有办法分开测。
/// 「等待中」是剩下的那一档（非下载中、非暂停、非失败），因为队列里
/// 排队与重试中的写法不止一种，逐值列举容易漏。
bool downloadTaskMatchesViewFilter({
  required DownloadTaskViewFilter filter,
  required bool isDownloading,
  required String? stateCode,
}) {
  return switch (filter) {
    DownloadTaskViewFilter.all => true,
    DownloadTaskViewFilter.downloading => isDownloading,
    DownloadTaskViewFilter.waiting =>
      !isDownloading && stateCode != 'paused' && stateCode != 'failed',
    DownloadTaskViewFilter.paused => !isDownloading && stateCode == 'paused',
    DownloadTaskViewFilter.failed => !isDownloading && stateCode == 'failed',
  };
}
