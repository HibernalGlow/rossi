import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/icons/icons.dart';

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
    final payload = task?.taskInfo;
    return ComicDownloadStatusButton(
      state: state,
      progress: state == ComicDownloadVisualState.downloading && payload != null
          ? downloadTaskPayloadProgressFraction(payload)
          : null,
      busy: _busy,
      size: widget.size,
      onPressed: () => _onTap(state),
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

/// 下载状态的纯展示表面，任务订阅与排队仍由 ComicDownloadBadge 管理。
class ComicDownloadStatusButton extends StatelessWidget {
  const ComicDownloadStatusButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.progress,
    this.busy = false,
    this.size = 32,
  });
  final ComicDownloadVisualState state;
  final VoidCallback? onPressed;
  final double? progress;
  final bool busy;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (Glyph icon, String label) = switch (state) {
      ComicDownloadVisualState.downloading => (
        AppGlyphs.downloading,
        t.reader.downloadStatusDownloading,
      ),
      ComicDownloadVisualState.paused => (
        AppGlyphs.pause,
        t.reader.downloadStatusPaused,
      ),
      ComicDownloadVisualState.failed => (
        AppGlyphs.error,
        t.reader.downloadStatusFailed,
      ),
      ComicDownloadVisualState.completed => (
        AppGlyphs.downloadDone,
        t.reader.downloadManage,
      ),
      ComicDownloadVisualState.notDownloaded => (
        AppGlyphs.download,
        t.comicInfo.download,
      ),
    };
    final background = state == ComicDownloadVisualState.failed
        ? colorScheme.errorContainer
        : colorScheme.surfaceContainerHigh;
    final foreground = state == ComicDownloadVisualState.failed
        ? colorScheme.onErrorContainer
        : state == ComicDownloadVisualState.notDownloaded
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;

    return Semantics(
      label: label,
      button: true,
      value: progress == null ? null : '${(progress! * 100).round()}%',
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.manual,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : onPressed,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GlyphIcon(icon, size: size * .52, color: foreground),
                      if (busy || progress != null)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: CircularProgressIndicator(
                              value: busy ? null : progress,
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
