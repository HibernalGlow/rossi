import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_sheet.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 阅读器顶部工具栏下载快捷按钮
///
/// 外形就是主行那颗统一的图标按钮（[ReaderToolbarIconButton]），五种状态只换
/// **图标与角色色**，不再自己画一个 36 见方的框 —— 改造前那一圈与旁边的
/// 40 圆钮、30 面板钮并排，正是主行看起来「一堆不同大小的图标挤在一起」的一处。
/// 下载中时在按钮**底下**垫一圈进度环，不额外占宽度。
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
        Color iconColor;
        String tooltip;
        double? progress;

        // 颜色一律取角色：MD3 的盘里没有「成功绿」这一档，完成与进行中同用
        // `primary`，靠图标区分；暂停用 `tertiary`，失败用 `error`。
        if (isDownloading) {
          iconData = Icons.downloading_rounded;
          iconColor = colorScheme.primary;
          tooltip = t.reader.downloadStatusDownloading;
          if (payload != null) {
            progress = downloadTaskPayloadProgressFraction(payload);
          }
        } else if (isPaused) {
          iconData = Icons.pause_circle_outline_rounded;
          iconColor = colorScheme.tertiary;
          tooltip = t.reader.downloadStatusPaused;
        } else if (isFailed) {
          iconData = Icons.error_outline_rounded;
          iconColor = colorScheme.error;
          tooltip = t.reader.downloadStatusFailed;
        } else if (isCompleted) {
          iconData = Icons.download_done_rounded;
          iconColor = colorScheme.primary;
          tooltip = t.reader.downloadStatusCompleted;
        } else {
          iconData = Icons.download_rounded;
          iconColor = colorScheme.onSurfaceVariant;
          tooltip = t.reader.startDownload;
        }

        final button = ReaderToolbarIconButton(
          icon: iconData,
          tint: iconColor,
          tooltip: tooltip,
          onPressed: () {
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
        );

        if (!isDownloading || progress == null) {
          return button;
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            // 环画在按钮底下：40 的可点区不变，进度只是那一圈附加信息。
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            button,
          ],
        );
      },
    );
  }
}
