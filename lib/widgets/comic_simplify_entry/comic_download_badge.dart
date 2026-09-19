import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';

/// 列表卡片封面右上角的下载角标。
///
/// 单击语义与详情页「下载」按钮**逐条一致**（共用
/// [resolveComicDownloadVisualState] 与 [startComicDownloadAll]）：
/// 没下过 → 直接下载整本；已有记录/任务 → 打开章节选择页。
///
/// 卡片上只有标题和封面、没有章节数据，所以直接下载这条路会回源问一次插件详情
/// （`startComicDownloadAll(comicInfo: null)` 内部的兜底分支）。
class ComicDownloadBadge extends StatefulWidget {
  const ComicDownloadBadge({
    super.key,
    required this.from,
    required this.comicId,
    this.title = '',
    this.size = 30,
  });

  final String from;
  final String comicId;

  /// 传给下载任务的显示名。
  final String title;
  final double size;

  @override
  State<ComicDownloadBadge> createState() => _ComicDownloadBadgeState();
}

class _ComicDownloadBadgeState extends State<ComicDownloadBadge> {
  String? _taskStreamKey;
  Stream<DownloadTask?>? _taskStream;

  /// 防止连点：拉详情/排队期间再点一次会重复发起。
  bool _busy = false;

  String get _source => widget.from.trim();
  String get _comicId => widget.comicId.trim();

  @override
  void didUpdateWidget(ComicDownloadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.comicId != widget.comicId) {
      _taskStreamKey = null;
    }
  }

  /// 任务流按 key 缓存：build 里每次新建会让 StreamBuilder 反复重订阅。
  Stream<DownloadTask?> get _stream {
    final key = '$_source|$_comicId';
    if (_taskStreamKey != key) {
      _taskStreamKey = key;
      _taskStream = DownloadQueueManager.instance.watchTaskByComic(
        _source,
        _comicId,
      );
    }
    return _taskStream!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadTask?>(
      stream: _stream,
      initialData: DownloadQueueManager.instance.getTaskByComic(
        _source,
        _comicId,
      ),
      builder: (context, snapshot) {
        final task = snapshot.data;
        return _buildBadge(
          context,
          task,
          resolveComicDownloadVisualState(
            isDownloading: task?.isDownloading ?? false,
            isCompleted: task?.isCompleted ?? false,
            stateCode:
                task?.taskInfo?.stateCode ?? (task == null ? 'none' : 'queued'),
            hasRecord: hasComicDownloadRecord(from: _source, comicId: _comicId),
          ),
        );
      },
    );
  }

  Widget _buildBadge(
    BuildContext context,
    DownloadTask? task,
    ComicDownloadVisualState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final payload = task?.taskInfo;

    final (IconData icon, String label, Color background) = switch (state) {
      ComicDownloadVisualState.downloading => (
        Icons.downloading_rounded,
        t.reader.downloadStatusDownloading,
        colorScheme.primary,
      ),
      ComicDownloadVisualState.paused => (
        Icons.pause_rounded,
        t.reader.downloadStatusPaused,
        Colors.orange,
      ),
      ComicDownloadVisualState.failed => (
        Icons.error_outline_rounded,
        t.reader.downloadStatusFailed,
        Colors.red,
      ),
      ComicDownloadVisualState.completed => (
        Icons.download_done_rounded,
        t.reader.downloadManage,
        Colors.green,
      ),
      ComicDownloadVisualState.notDownloaded => (
        Icons.download_rounded,
        t.comicInfo.download,
        Colors.black.withValues(alpha: 0.55),
      ),
    };

    final progress =
        state == ComicDownloadVisualState.downloading && payload != null
        ? downloadTaskPayloadProgressFraction(payload)
        : null;

    return Tooltip(
      message: label,
      // triggerMode 必须是 manual：默认的 longPress 触发会跟卡片的
      // 长按（多选 / 右键菜单）抢同一个手势。桌面悬停提示不受影响。
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.size),
          onTap: () => _onTap(state),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: progress != null
                ? Padding(
                    padding: EdgeInsets.all(widget.size * 0.24),
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  )
                : Icon(icon, size: widget.size * 0.6, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(ComicDownloadVisualState state) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (state) {
        case ComicDownloadVisualState.notDownloaded:
          await startComicDownloadAll(
            context: context,
            from: _source,
            comicId: _comicId,
            comicName: widget.title,
          );
        case ComicDownloadVisualState.downloading:
        case ComicDownloadVisualState.paused:
        case ComicDownloadVisualState.failed:
        case ComicDownloadVisualState.completed:
          await openComicDownloadChapterPicker(
            context,
            from: _source,
            comicId: _comicId,
          );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
