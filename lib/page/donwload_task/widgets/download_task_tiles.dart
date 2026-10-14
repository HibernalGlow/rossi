import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/bloc/dowload_task_bloc.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

/// 下载任务行的状态与操作；已离线漫画的视图由书架共用组件负责。
class DownloadTaskRow extends StatelessWidget {
  const DownloadTaskRow({
    super.key,
    required this.task,
    this.onRetry,
    this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return task.isDownloading
        ? _ComfortableDownloadingTile(task: task)
        : _ComfortablePendingTile(
            task: task,
            onRetry: onRetry,
            onDelete: onDelete,
          );
  }
}

/// 下载中：圆环进度 + 状态/进度文字 + 暂停与取消。
class _ComfortableDownloadingTile extends StatelessWidget {
  const _ComfortableDownloadingTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final payload = task.taskInfo;
    final progress = payload == null
        ? null
        : downloadTaskPayloadProgressFraction(payload);
    final progressMessage = payload == null
        ? ''
        : downloadTaskPayloadProgressMessage(payload);
    // 任务状态和 checkpoint 进度是分开写入的。下载中只显示结构化进度，
    // 避免两次 ObjectBox 更新之间蓝色状态文字短暂出现造成闪烁。
    final statusMessage = progressMessage.isEmpty ? task.status : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        title: Text(_chapterTaskTitle(task)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusMessage.isNotEmpty)
              Text(
                statusMessage,
                style: const TextStyle(color: Colors.blue),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (progressMessage.isNotEmpty)
              Text(
                progressMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: t.reader.pauseDownload,
              icon: const GlyphIcon(AppGlyphs.pause, color: Colors.blue),
              onPressed: payload == null
                  ? null
                  : () {
                      DownloadQueueManager.instance.pauseTask(payload.taskKey);
                      showInfoToast(t.reader.downloadStatusPaused);
                    },
            ),
            IconButton(
              icon: const GlyphIcon(AppGlyphs.close, color: Colors.blue),
              onPressed: () => _confirmCancelTask(context, task),
            ),
          ],
        ),
      ),
    );
  }
}

/// 排队 / 暂停 / 失败：按状态给恢复、重试与删除。
class _ComfortablePendingTile extends StatelessWidget {
  const _ComfortablePendingTile({
    required this.task,
    this.onRetry,
    this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final payload = task.taskInfo;
    final progressMessage = payload == null
        ? ''
        : downloadTaskPayloadProgressMessage(payload);
    final statusMessage = task.status == progressMessage ? '' : task.status;
    final failureMessage = payload?.stateCode == 'failed'
        ? payload?.lastErrorMessage.trim() ?? ''
        : '';
    final isPaused = payload?.stateCode == 'paused';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange,
          child: GlyphIcon(
            isPaused ? AppGlyphs.pause : AppGlyphs.hourglass,
            color: Colors.white,
          ),
        ),
        title: Text(_chapterTaskTitle(task)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusMessage.isNotEmpty)
              Text(
                statusMessage,
                style: const TextStyle(color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (progressMessage.isNotEmpty)
              Text(
                progressMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (failureMessage.isNotEmpty)
              InkWell(
                onTap: () =>
                    _showDownloadFailureDetails(context, failureMessage),
                child: Text(
                  failureMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPaused)
              IconButton(
                tooltip: t.reader.resumeDownload,
                icon: const GlyphIcon(AppGlyphs.play),
                onPressed: () {
                  final taskKey = payload?.taskKey;
                  if (taskKey == null) return;
                  DownloadQueueManager.instance.resumeTask(taskKey);
                  showInfoToast(t.reader.downloadStatusDownloading);
                },
              ),
            if (onRetry != null)
              IconButton(
                tooltip: t.common.retry,
                icon: const GlyphIcon(AppGlyphs.refresh),
                onPressed: onRetry,
              ),
            if (onDelete != null)
              IconButton(
                tooltip: t.common.delete,
                icon: const GlyphIcon(AppGlyphs.delete),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

/// 单行取消：确认后才动，取消会连带删掉本章已下载的散图。
void _confirmCancelTask(BuildContext context, DownloadTask task) {
  final bloc = context.read<DowloadTaskBloc>();
  showPopupPanel(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (dialogContext) => PopupPanel(
      title: Text(t.download.cancelTask),
      content: Text(t.download.cancelTaskConfirm(comicName: task.comicName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            t.common.cancel,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: () {
            bloc.add(DowloadTaskEvent.cancelTask(task.id));
            Navigator.of(dialogContext).pop();
          },
          child: Text(t.common.ok, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

/// 任务 payload 里的状态码。读不出来（跨进程残留的坏 JSON 行）返回 null，
/// 让调用方按「未知状态」处理 —— 直接 `task.taskInfo` 会在 build 里抛出去。
String? downloadTaskStateCode(DownloadTask task) {
  try {
    return task.taskInfo?.stateCode;
  } catch (_) {
    return null;
  }
}

/// 单章节任务标题：漫画名 + 章节名（老任务无章节名时只显示漫画名）。
String _chapterTaskTitle(DownloadTask task) {
  String? chapterTitle;
  try {
    chapterTitle = task.taskInfo?.chapterRef.title.trim();
  } catch (_) {
    chapterTitle = null;
  }
  if (chapterTitle == null || chapterTitle.isEmpty) return task.comicName;
  return '${task.comicName} $chapterTitle';
}

void _showDownloadFailureDetails(BuildContext context, String message) {
  showPopupPanel<void>(
    context: context,
    builder: (dialogContext) => PopupPanel(
      title: Text(t.download.notificationFailedTitle),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(child: SelectableText(message)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t.common.ok),
        ),
      ],
    ),
  );
}
