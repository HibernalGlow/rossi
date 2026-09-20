import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_sheet.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 阅读器顶部工具栏下载快捷按钮
class ReaderDownloadButton extends StatelessWidget {
  final String from;
  final String comicId;
  final String comicTitle;
  final dynamic comicInfo;
  final List<UnifiedComicChapterRef>? chapterRefs;

  const ReaderDownloadButton({
    super.key,
    required this.from,
    required this.comicId,
    required this.comicTitle,
    this.comicInfo,
    this.chapterRefs,
  });

  String get taskKey => buildDownloadTaskKey(from, comicId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<DownloadTask?>(
      stream: DownloadQueueManager.instance.watchTaskByComic(from, comicId),
      initialData: DownloadQueueManager.instance.getTaskByComic(from, comicId),
      builder: (context, snapshot) {
        final dbTask = snapshot.data;
        final payload = dbTask?.taskInfo;
        final isDownloading = dbTask?.isDownloading ?? false;
        final stateCode =
            payload?.stateCode ?? (dbTask == null ? 'none' : 'queued');
        final isPaused = stateCode == 'paused';
        final isFailed = stateCode == 'failed';
        final isDownloaded =
            objectbox.unifiedDownloadBox
                .query(UnifiedComicDownload_.uniqueKey.equals(taskKey))
                .build()
                .findFirst() !=
            null;
        final isCompleted = (dbTask?.isCompleted ?? false) || isDownloaded;

        IconData iconData;
        Color? iconColor;
        String tooltip;
        double? progress;

        if (isDownloading) {
          iconData = Icons.downloading_rounded;
          iconColor = colorScheme.primary;
          tooltip = t.reader.downloadStatusDownloading;
          if (payload != null) {
            progress = downloadTaskPayloadProgressFraction(payload);
          }
        } else if (isPaused) {
          iconData = Icons.pause_circle_outline_rounded;
          iconColor = Colors.orange;
          tooltip = t.reader.downloadStatusPaused;
        } else if (isFailed) {
          iconData = Icons.error_outline_rounded;
          iconColor = Colors.red;
          tooltip = t.reader.downloadStatusFailed;
        } else if (isCompleted) {
          iconData = Icons.download_done_rounded;
          iconColor = Colors.green;
          tooltip = t.reader.downloadStatusCompleted;
        } else {
          iconData = Icons.download_rounded;
          iconColor = colorScheme.onSurfaceVariant;
          tooltip = t.reader.startDownload;
        }

        return Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (!isDownloading && !isPaused && !isFailed && !isCompleted) {
                // 1. 未开始下载：单击直接开始下载整本
                startComicDownload(
                  context: context,
                  from: from,
                  comicId: comicId,
                  comicTitle: comicTitle,
                  comicInfo: comicInfo,
                  chapterRefs: chapterRefs,
                );
              } else {
                // 2. 正在下载/暂停/失败/已完成：呼出下载管理面板
                showReaderDownloadSheet(
                  context,
                  from: from,
                  comicId: comicId,
                  comicTitle: comicTitle,
                  comicInfo: comicInfo,
                  chapterRefs: chapterRefs,
                );
              }
            },
            onLongPress: () {
              showReaderDownloadSheet(
                context,
                from: from,
                comicId: comicId,
                comicTitle: comicTitle,
                comicInfo: comicInfo,
                chapterRefs: chapterRefs,
              );
            },
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDownloading
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isDownloading && progress != null)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                      ),
                    ),
                  Icon(iconData, size: 20, color: iconColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
