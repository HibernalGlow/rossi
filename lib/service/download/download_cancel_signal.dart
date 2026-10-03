import 'dart:async';

const downloadTaskCancelledMessage = '__DOWNLOAD_TASK_CANCELLED__';

class DownloadTaskCancelledException implements Exception {
  const DownloadTaskCancelledException();

  @override
  String toString() => downloadTaskCancelledMessage;
}

/// 中断下载的原因：决定 worker 收尾时是否清理已落盘的散图。
enum DownloadStopReason {
  /// 用户取消：删掉本章散图，队列随后移除任务记录。
  cancelled,

  /// 用户暂停：保留散图，恢复时按 existing 复用。
  paused,
}

final Map<String, Completer<void>> _downloadCancelSignals = {};
final Map<String, DownloadStopReason> _downloadStopReasons = {};

void prepareDownloadCancelSignal(String taskKey) {
  _downloadCancelSignals.remove(taskKey);
  _downloadStopReasons.remove(taskKey);
}

void triggerDownloadCancelSignal(
  String taskKey, {
  DownloadStopReason reason = DownloadStopReason.cancelled,
}) {
  // 原因必须在触发点同步记下：worker 只能从信号里看出被中断，看不出为什么。
  _downloadStopReasons[taskKey] = reason;
  final completer = _downloadCancelSignals.putIfAbsent(
    taskKey,
    () => Completer<void>(),
  );
  if (!completer.isCompleted) {
    completer.complete();
  }
}

void clearDownloadCancelSignal(String taskKey) {
  _downloadCancelSignals.remove(taskKey);
  _downloadStopReasons.remove(taskKey);
}

/// 触发本次中断的原因；从未触发或已清理时为 null（按取消处理）。
DownloadStopReason? downloadStopReason(String taskKey) {
  return _downloadStopReasons[taskKey];
}

bool isDownloadCancelSignaled(String taskKey) {
  final completer = _downloadCancelSignals[taskKey];
  return completer?.isCompleted ?? false;
}

Future<T> raceWithDownloadCancel<T>(String taskKey, Future<T> future) async {
  if (isDownloadCancelSignaled(taskKey)) {
    throw const DownloadTaskCancelledException();
  }

  final completer = _downloadCancelSignals.putIfAbsent(
    taskKey,
    () => Completer<void>(),
  );
  return Future.any([
    future,
    completer.future.then<T>(
      (_) => throw const DownloadTaskCancelledException(),
    ),
  ]);
}
