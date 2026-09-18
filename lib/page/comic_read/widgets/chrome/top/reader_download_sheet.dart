import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/widgets/toast.dart';

/// 弹出阅读器下载管理面板
Future<void> showReaderDownloadSheet(
  BuildContext context, {
  required String from,
  required String comicId,
  required String comicTitle,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _ReaderDownloadSheet(
        from: from,
        comicId: comicId,
        comicTitle: comicTitle,
        comicInfo: comicInfo,
        chapterRefs: chapterRefs,
      );
    },
  );
}

/// 快速启动整本漫画的下载任务
Future<void> startComicDownload({
  required BuildContext context,
  required String from,
  required String comicId,
  required String comicTitle,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
}) async {
  // 1. 检查点击下载自动收藏
  await autoFavoriteComicOnDownloadIfEnabled(
    from: from,
    comicId: comicId,
    comicInfo: comicInfo,
    context: context,
  );

  // 2. 解析章节列表
  List<UnifiedComicChapterRef> resolved = chapterRefs ?? [];
  if (resolved.isEmpty && comicInfo != null) {
    resolved = resolveUnifiedComicChapters(comicInfo, from);
  }
  if (resolved.isEmpty) {
    try {
      final detail = await getComicDetailByPlugin(comicId, from, pluginId: from);
      resolved = resolveUnifiedComicChapters(detail.source, from);
    } catch (e) {
      logger.e('解析章节列表失败: $e');
    }
  }

  if (resolved.isEmpty) {
    showErrorToast(t.error.operationFailed);
    return;
  }

  const adapter = DownloadChapterAdapter();
  final chapters = resolved.map(adapter.fromChapterRef).toList();

  final task = DownloadTaskJson(
    from: from,
    comicId: comicId,
    comicName: comicTitle,
    chapterRefs: chapters
        .map(
          (chapter) => DownloadChapterTaskRef(
            chapterId: chapter.id,
            requestId: chapter.effectiveRequestId,
            storageChapterId: chapter.effectiveStorageId,
            logicalKey: chapter.id,
            title: chapter.displayName,
            order: chapter.order,
            extern: Map<String, dynamic>.from(chapter.extern),
          ),
        )
        .toList(),
  );

  try {
    await startDownloadTask(task);
    showSuccessToast(t.reader.downloadStartedToast);
  } catch (e) {
    showErrorToast(
      t.download.taskStartFailed(error: normalizeSearchErrorMessage(e)),
    );
  }
}

class _ReaderDownloadSheet extends StatefulWidget {
  final String from;
  final String comicId;
  final String comicTitle;
  final dynamic comicInfo;
  final List<UnifiedComicChapterRef>? chapterRefs;

  const _ReaderDownloadSheet({
    required this.from,
    required this.comicId,
    required this.comicTitle,
    this.comicInfo,
    this.chapterRefs,
  });

  @override
  State<_ReaderDownloadSheet> createState() => _ReaderDownloadSheetState();
}

class _ReaderDownloadSheetState extends State<_ReaderDownloadSheet> {
  String get taskKey => buildDownloadTaskKey(widget.from, widget.comicId);

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: maxHeight,
            ),
            child: Material(
              color: colorScheme.surface,
              surfaceTintColor: colorScheme.surfaceTint,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<DownloadTask?>(
                stream: DownloadQueueManager.instance.watchTaskByComic(
                  widget.from,
                  widget.comicId,
                ),
                initialData: DownloadQueueManager.instance.getTaskByComic(
                  widget.from,
                  widget.comicId,
                ),
                builder: (context, snapshot) {
                  final dbTask = snapshot.data;
                  final payload = dbTask?.taskInfo;

                  // 检查本地已下载记录
                  final isDownloaded = objectbox.unifiedDownloadBox
                          .query(UnifiedComicDownload_.uniqueKey.equals(taskKey))
                          .build()
                          .findFirst() !=
                      null;

                  return CustomScrollView(
                    shrinkWrap: true,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeader(context, colorScheme),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatusCard(
                                context,
                                colorScheme,
                                dbTask,
                                payload,
                                isDownloaded,
                              ),
                              const SizedBox(height: 16),
                              _buildActions(
                                context,
                                colorScheme,
                                dbTask,
                                payload,
                                isDownloaded,
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              _buildSettingsSwitches(context),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Icon(Icons.download_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.reader.downloadManage,
                  style: context.theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.comicTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ColorScheme colorScheme,
    DownloadTask? dbTask,
    DownloadTaskJson? payload,
    bool isDownloaded,
  ) {
    final isDownloading = dbTask?.isDownloading ?? false;
    final stateCode = payload?.stateCode ?? (dbTask == null ? 'none' : 'queued');
    final isPaused = stateCode == 'paused';
    final isFailed = stateCode == 'failed';
    final isCompleted = dbTask?.isCompleted == true || isDownloaded;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isDownloading) {
      statusText = t.reader.downloadStatusDownloading;
      statusColor = Colors.blue;
      statusIcon = Icons.downloading_rounded;
    } else if (isPaused) {
      statusText = t.reader.downloadStatusPaused;
      statusColor = Colors.orange;
      statusIcon = Icons.pause_circle_outline_rounded;
    } else if (isFailed) {
      statusText = t.reader.downloadStatusFailed;
      statusColor = Colors.red;
      statusIcon = Icons.error_outline_rounded;
    } else if (isCompleted) {
      statusText = t.reader.downloadStatusCompleted;
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (dbTask != null) {
      statusText = t.reader.downloadStatusQueued;
      statusColor = Colors.teal;
      statusIcon = Icons.schedule_rounded;
    } else {
      statusText = '未下载';
      statusColor = colorScheme.onSurfaceVariant;
      statusIcon = Icons.cloud_download_outlined;
    }

    final fraction = payload == null
        ? (isCompleted ? 1.0 : null)
        : downloadTaskPayloadProgressFraction(payload);
    final progressMsg = payload == null ? '' : downloadTaskPayloadProgressMessage(payload);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (fraction != null)
                Text(
                  '${(fraction * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
              ),
            ),
          ],
          if (progressMsg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              progressMsg,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (isFailed && (payload?.lastErrorMessage.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              payload!.lastErrorMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ColorScheme colorScheme,
    DownloadTask? dbTask,
    DownloadTaskJson? payload,
    bool isDownloaded,
  ) {
    final isDownloading = dbTask?.isDownloading ?? false;
    final stateCode = payload?.stateCode ?? (dbTask == null ? 'none' : 'queued');
    final isPaused = stateCode == 'paused';
    final isFailed = stateCode == 'failed';
    final hasTask = dbTask != null;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        // 1. 开始 / 继续 / 暂停 按钮
        if (!hasTask && !isDownloaded)
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text(t.reader.startDownload),
            onPressed: () {
              startComicDownload(
                context: context,
                from: widget.from,
                comicId: widget.comicId,
                comicTitle: widget.comicTitle,
                comicInfo: widget.comicInfo,
                chapterRefs: widget.chapterRefs,
              );
            },
          ),
        if (isDownloading)
          FilledButton.tonalIcon(
            icon: const Icon(Icons.pause_rounded),
            label: Text(t.reader.pauseDownload),
            onPressed: () {
              DownloadQueueManager.instance.pauseTask(taskKey);
              showInfoToast(t.reader.downloadStatusPaused);
            },
          ),
        if (isPaused)
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(t.reader.resumeDownload),
            onPressed: () {
              DownloadQueueManager.instance.resumeTask(taskKey);
              showInfoToast(t.reader.downloadStatusDownloading);
            },
          ),
        if (isFailed)
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t.common.retry),
            onPressed: () {
              if (dbTask != null) {
                DownloadQueueManager.instance.retryTask(dbTask.id);
              }
            },
          ),

        // 2. 重新下载按钮
        if (hasTask || isDownloaded)
          OutlinedButton.icon(
            icon: const Icon(Icons.replay_rounded),
            label: Text(t.reader.restartDownload),
            onPressed: () => _confirmRestartDownload(context),
          ),

        // 3. 删除下载按钮
        if (hasTask || isDownloaded)
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            label: Text(
              t.reader.deleteDownload,
              style: const TextStyle(color: Colors.red),
            ),
            onPressed: () => _confirmDeleteDownload(context),
          ),

        // 4. 查看全部下载任务
        TextButton.icon(
          icon: const Icon(Icons.list_alt_rounded),
          label: Text(t.reader.viewAllTasks),
          onPressed: () {
            Navigator.of(context).pop();
            context.pushRoute(const DownloadTaskRoute());
          },
        ),
      ],
    );
  }

  Widget _buildSettingsSwitches(BuildContext context) {
    final globalState = context.watch<GlobalSettingCubit>().state;
    final cubit = context.read<GlobalSettingCubit>();

    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.sync_rounded),
          title: Text(t.reader.readWhileDownloading),
          subtitle: Text(t.reader.readWhileDownloadingSubtitle),
          value: globalState.readSetting.readWhileDownloading,
          onChanged: (val) {
            cubit.updateReadSetting((s) => s.copyWith(readWhileDownloading: val));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.bookmark_add_outlined),
          title: Text(t.settings.autoFavoriteOnDownload),
          subtitle: Text(t.settings.autoFavoriteOnDownloadSubtitle),
          value: globalState.autoFavoriteOnDownload,
          onChanged: (val) {
            cubit.updateState((s) => s.copyWith(autoFavoriteOnDownload: val));
          },
        ),
      ],
    );
  }

  Future<void> _confirmRestartDownload(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reader.restartDownload),
        content: Text('确认要重置进度并重新下载本漫画吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      DownloadQueueManager.instance.restartTask(taskKey);
      showInfoToast('已重新加入下载队列');
    }
  }

  Future<void> _confirmDeleteDownload(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reader.confirmDeleteDownloadTitle),
        content: Text(t.reader.confirmDeleteDownload),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await DownloadQueueManager.instance.deleteComicDownload(
        widget.from,
        widget.comicId,
        deleteFiles: true,
      );
      if (mounted) {
        showSuccessToast(t.download.taskDeleted);
      }
    }
  }
}
