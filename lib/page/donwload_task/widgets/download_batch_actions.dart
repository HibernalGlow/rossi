import 'package:material_ui/material_ui.dart' hide Page;
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/widgets/download_task_tiles.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 下载任务页标题栏的批量操作：全部开始 / 全部暂停 / 全部取消。
///
/// 可点状态从当前任务列表算：列表由 ObjectBox 监听刷新，点完之后按钮自己会
/// 变灰或亮起，所以不再补「操作成功」的 toast。
class DownloadBatchActions extends StatelessWidget {
  const DownloadBatchActions({super.key, required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    // payload 读不出来的旧行不在暂停/恢复的可达范围内，别让按钮假装能管它们。
    final stateCodes = tasks.map(downloadTaskStateCode).nonNulls.toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: t.download.startAll,
          visualDensity: VisualDensity.compact,
          icon: const GlyphIcon(AppGlyphs.play),
          onPressed: stateCodes.contains('paused')
              ? DownloadQueueManager.instance.resumeAllTasks
              : null,
        ),
        IconButton(
          tooltip: t.download.pauseAll,
          visualDensity: VisualDensity.compact,
          icon: const GlyphIcon(AppGlyphs.pause),
          onPressed: stateCodes.any((code) => code != 'paused')
              ? DownloadQueueManager.instance.pauseAllTasks
              : null,
        ),
        IconButton(
          tooltip: t.download.cancelAll,
          visualDensity: VisualDensity.compact,
          icon: GlyphIcon(
            AppGlyphs.stopCircle,
            color: Theme.of(context).colorScheme.error,
          ),
          onPressed: tasks.isEmpty
              ? null
              : () => _confirmCancelAll(context, tasks.length),
        ),
      ],
    );
  }

  /// 取消会连带删掉本章已下载的散图，因此保留与单行「取消任务」一样的确认弹窗。
  void _confirmCancelAll(BuildContext context, int count) {
    showPopupPanel<void>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) => PopupPanel(
        title: Text(t.download.cancelAll),
        content: Text(t.download.cancelAllConfirm(count: count)),
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
              DownloadQueueManager.instance.cancelAllTasks();
              Navigator.of(dialogContext).pop();
            },
            child: Text(t.common.ok, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
