import 'package:pool/pool.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/type/enum.dart';

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/service/download/download_cancel_signal.dart';
import 'package:zephyr/service/download/download_progress_reporter.dart';
import 'package:zephyr/service/download/download_retry.dart';

class DownloadImageJob {
  const DownloadImageJob({
    required this.url,
    required this.path,
    required this.cartoonId,
    required this.chapterId,
    this.storageChapterId = '',
    this.extern = const <String, dynamic>{},
  });

  final String url;
  final String path;
  final String cartoonId;
  final String chapterId;
  final String storageChapterId;
  final Map<String, dynamic> extern;
}

class DownloadImageJobException implements Exception {
  const DownloadImageJobException({required this.job, required this.result});

  final DownloadImageJob job;
  final DownloadPictureResult result;

  @override
  String toString() {
    final processedError = result.error?.toString().trim() ?? 'null';
    final rawError = _formatRawDownloadError(result.error);
    final rawStackTrace = result.errorStackTrace?.toString().trim();
    final stackSuffix = rawStackTrace == null || rawStackTrace.isEmpty
        ? ''
        : '\nrawStackTrace:\n$rawStackTrace';
    return '图片下载失败 path=${job.path} url=${job.url} '
        'status=${result.status.name}\n'
        'processedError=$processedError\n'
        'rawError=$rawError$stackSuffix';
  }
}

String _formatRawDownloadError(Object? error) {
  if (error == null) return 'null';

  final buffer = StringBuffer('${error.runtimeType}: $error');
  if (error is DownloadPictureNotFoundException) {
    final cause = error.cause;
    if (cause != null) {
      buffer.write('\nrawCause=${cause.runtimeType}: $cause');
    }
  }
  return buffer.toString();
}

class DownloadImageJobsResult {
  const DownloadImageJobsResult({
    required this.completed,
    required this.downloaded,
    required this.reused,
    required this.skipped,
    this.failed = 0,
    this.failedJobs = const [],
  });

  final int completed;
  final int downloaded;
  final int reused;

  /// 真 404 / 空数据而跳过的图片数（不计入失败，不阻塞完成）。
  final int skipped;
  final int failed;
  final List<DownloadImageJob> failedJobs;
}

Future<String> downloadCoverAsset({
  required String from,
  required String url,
  required String path,
  required String cartoonId,
  required String qjsName,
  required String qjsTaskGroupKey,
  bool Function()? shouldRetryUntilSuccess,
}) {
  return downloadPicture(
    from: from,
    url: url,
    path: path,
    cartoonId: cartoonId,
    pictureType: PictureType.cover,
    retry: true,
    shouldRetryUntilSuccess: shouldRetryUntilSuccess,
    qjsName: qjsName,
    qjsTaskGroupKey: qjsTaskGroupKey,
  );
}

Future<DownloadImageJobsResult> downloadImageJobs({
  required String from,
  required List<DownloadImageJob> jobs,
  int? concurrency,
  Duration? requestDelay,
  required String qjsRuntimeName,
  required String qjsTaskGroupKey,
  required Future<void> Function() ensureTaskRunning,
  bool Function()? shouldRetryUntilSuccess,
  required DownloadProgressReporter reporter,
  Future<void> Function(Object error, DownloadImageJob job)? onError,
  Future<void> Function(
    int completed,
    int downloaded,
    int reused,
    DownloadImageJob completedJob,
    bool jobSkipped,
  )?
  onProgress,
}) async {
  void updateProgress(String message) {
    reporter.updateMessage(message);
  }

  if (jobs.isEmpty) {
    if (onProgress == null) {
      updateProgress(t.download.statusDownloadProgressComplete);
    }
    return const DownloadImageJobsResult(
      completed: 0,
      downloaded: 0,
      reused: 0,
      skipped: 0,
    );
  }

  final workerCount = concurrency ?? 3;
  final pool = Pool(workerCount);
  var progress = 0;
  var downloaded = 0;
  var reused = 0;
  var skipped = 0;
  var lastReportedPercent = 0;
  var nextIndex = 0;
  final failedJobs = <DownloadImageJob>[];
  Object? firstFatalError;
  StackTrace? firstFatalStackTrace;

  // 单图失败先记账，等并行阶段结束后统一补重试；firstFatalError 只留第一个错误，
  // 补重试仍失败时用它向上抛，让上层知道这一章失败的原因。
  void recordFailedJob(
    DownloadImageJob job, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    failedJobs.add(job);
    if (error != null) {
      firstFatalError ??= error;
      firstFatalStackTrace ??= stackTrace;
    }
  }

  Future<void> runWorker() async {
    while (firstFatalError == null) {
      await ensureTaskRunning();
      DownloadImageJob? job;
      await pool.withResource(() async {
        if (nextIndex >= jobs.length) {
          return;
        }
        job = jobs[nextIndex];
        nextIndex += 1;
      });
      final currentJob = job;
      if (currentJob == null) {
        return;
      }
      var jobSkipped = false;
      var jobDone = false;
      try {
        final result = await _downloadSingleJob(
          from: from,
          job: currentJob,
          qjsRuntimeName: qjsRuntimeName,
          qjsTaskGroupKey: qjsTaskGroupKey,
          ensureTaskRunning: ensureTaskRunning,
          shouldRetryUntilSuccess: shouldRetryUntilSuccess,
          onError: onError,
          pictureType: PictureType.page,
        );
        progress++;
        if (result.status == DownloadPictureResultStatus.existing) {
          reused++;
        } else {
          downloaded++;
          // 风控节流：网络下载完成后执行设定的等待间隔
          if (requestDelay != null && requestDelay > Duration.zero) {
            await Future.delayed(requestDelay);
          }
        }
        jobDone = true;
      } on DownloadImageJobException catch (e) {
        // 真 404 / 空数据：记跳过，不失败整章。
        if (e.result.status == DownloadPictureResultStatus.notFound ||
            e.result.status == DownloadPictureResultStatus.emptyData) {
          progress++;
          skipped++;
          jobSkipped = true;
          jobDone = true;
        } else {
          recordFailedJob(currentJob, e);
        }
      } catch (error, stackTrace) {
        // 任务取消立即中断；普通单图失败只记账，不打断并行的其它图片
        final errorStr = error.toString();
        if (errorStr.contains(downloadTaskCancelledMessage) ||
            errorStr.contains('__QJS_RUNTIME_CANCELLED__')) {
          firstFatalError ??= error;
          firstFatalStackTrace ??= stackTrace;
          return;
        }
        recordFailedJob(currentJob, error, stackTrace);
      }
      if (!jobDone) {
        // 这张图没落地：不推进度，也不要把它的路径记进 imagePaths，
        // 后面的补全重试会再给它一次机会。
        await ensureTaskRunning();
        continue;
      }
      if (onProgress != null) {
        await onProgress(progress, downloaded, reused, currentJob, jobSkipped);
      }
      final currentPercent = (progress / jobs.length * 100).floor();
      if (onProgress == null && currentPercent > lastReportedPercent) {
        lastReportedPercent = currentPercent;
        updateProgress(
          t.download.statusDownloadProgress(percent: currentPercent),
        );
      }
      await ensureTaskRunning();
    }
  }

  final tasks = List.generate(workerCount, (_) => runWorker());
  await Future.wait(tasks);

  // 如果遇到主动取消，立即抛出
  if (firstFatalError != null &&
      (firstFatalError.toString().contains(downloadTaskCancelledMessage) ||
          firstFatalError.toString().contains('__QJS_RUNTIME_CANCELLED__'))) {
    Error.throwWithStackTrace(firstFatalError!, firstFatalStackTrace!);
  }

  // 章节中若有失败项，针对性发起第二次补全重试（带 1 秒退避，串行重试避免风控加剧）
  final stillFailedJobs = <DownloadImageJob>[];
  if (failedJobs.isNotEmpty) {
    logger.w('本章共有 ${failedJobs.length} 张图片初次下载失败，正在启动针对性补全重试...');
    for (final job in failedJobs) {
      await ensureTaskRunning();
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final result = await _downloadSingleJob(
          from: from,
          job: job,
          qjsRuntimeName: qjsRuntimeName,
          qjsTaskGroupKey: qjsTaskGroupKey,
          ensureTaskRunning: ensureTaskRunning,
          shouldRetryUntilSuccess: shouldRetryUntilSuccess,
          onError: onError,
          pictureType: PictureType.page,
        );
        progress++;
        if (result.status == DownloadPictureResultStatus.existing) {
          reused++;
        } else {
          downloaded++;
          if (requestDelay != null && requestDelay > Duration.zero) {
            await Future.delayed(requestDelay);
          }
        }
        if (onProgress != null) {
          await onProgress(progress, downloaded, reused, job, false);
        }
      } on DownloadImageJobException catch (e) {
        // 补重试时才暴露出真 404 / 空数据的图，同样记跳过而不是算失败。
        if (e.result.status == DownloadPictureResultStatus.notFound ||
            e.result.status == DownloadPictureResultStatus.emptyData) {
          progress++;
          skipped++;
          if (onProgress != null) {
            await onProgress(progress, downloaded, reused, job, true);
          }
        } else {
          stillFailedJobs.add(job);
        }
      } catch (e) {
        stillFailedJobs.add(job);
      }
    }
  }

  if (stillFailedJobs.isNotEmpty) {
    logger.e('章节补全重试后仍有 ${stillFailedJobs.length} 张图片下载失败');
    if (firstFatalError != null) {
      Error.throwWithStackTrace(firstFatalError!, firstFatalStackTrace!);
    }
  }

  return DownloadImageJobsResult(
    completed: progress,
    downloaded: downloaded,
    reused: reused,
    failed: stillFailedJobs.length,
    failedJobs: stillFailedJobs,
    skipped: skipped,
  );
}

Future<DownloadPictureResult> _downloadSingleJob({
  required String from,
  required DownloadImageJob job,
  required String qjsRuntimeName,
  required String qjsTaskGroupKey,
  required Future<void> Function() ensureTaskRunning,
  bool Function()? shouldRetryUntilSuccess,
  Future<void> Function(Object error, DownloadImageJob job)? onError,
  PictureType pictureType = PictureType.comic,
}) async {
  try {
    final result = await retryDownloadOperation<DownloadPictureResult>(
      operation: '下载图片 ${job.path}',
      ensureTaskRunning: ensureTaskRunning,
      shouldRetryUntilSuccess: shouldRetryUntilSuccess,
      shouldRetry: (error) {
        if (error is! DownloadImageJobException) return true;
        return error.result.status != DownloadPictureResultStatus.notFound &&
            error.result.status != DownloadPictureResultStatus.emptyData;
      },
      action: () async {
        final result = await downloadPictureResult(
          from: from,
          url: job.url,
          path: job.path,
          cartoonId: job.cartoonId,
          chapterId: job.chapterId,
          storageChapterId: job.storageChapterId,
          pictureType: pictureType,
          // 外层负责整张图片的重试，避免网络层 10 次重试后才进入
          // 保存/解码失败的重试流程。
          retry: false,
          qjsName: qjsRuntimeName,
          qjsTaskGroupKey: qjsTaskGroupKey,
          extern: job.extern,
        );
        if (!result.isSuccess) {
          throw DownloadImageJobException(job: job, result: result);
        }
        return result;
      },
    );
    return result;
  } catch (error, stackTrace) {
    if (onError != null) {
      await onError(error, job);
      return DownloadPictureResult(
        status: DownloadPictureResultStatus.failed,
        error: error,
        errorStackTrace: stackTrace,
      );
    }
    rethrow;
  }
}
