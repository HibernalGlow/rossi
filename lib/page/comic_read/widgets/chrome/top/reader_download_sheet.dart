import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:zephyr/util/theme/status_accent.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/service/download/download_delete_service.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/icons/icons.dart';

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

/// 快速启动整本漫画的下载任务。
///
/// 实现已收敛到 [startComicDownloadAll]（详情页「下载」按钮单击走同一份），
/// 这里只保留阅读器侧的参数命名。
Future<void> startComicDownload({
  required BuildContext context,
  required String from,
  required String comicId,
  required String comicTitle,
  dynamic comicInfo,
  List<UnifiedComicChapterRef>? chapterRefs,
}) async {
  await startComicDownloadAll(
    context: context,
    from: from,
    comicId: comicId,
    comicName: comicTitle,
    comicInfo: comicInfo,
    chapterRefs: chapterRefs,
  );
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
  /// 整本下载记录的 key（漫画粒度，与章节任务 key 不同）。
  String get recordKey => buildDownloadTaskKey(widget.from, widget.comicId);

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760, maxHeight: maxHeight),
            child: M3ETheme(
              data: M3EThemeData.fromMaterial(theme),
              child: Material(
                color: colorScheme.surfaceContainerLow,
                surfaceTintColor: colorScheme.surfaceTint,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
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
                    final isDownloaded =
                        objectbox.unifiedDownloadBox
                            .query(
                              UnifiedComicDownload_.uniqueKey.equals(recordKey),
                            )
                            .build()
                            .findFirst() !=
                        null;

                    return CustomScrollView(
                      shrinkWrap: true,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 4,
                              margin: const EdgeInsets.only(top: 12, bottom: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
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
                                _buildSettingsSwitches(context, colorScheme),
                                const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: M3EShapeContainer(
              kind: M3EShapeKind.cookie4Sided,
              color: colorScheme.primaryContainer,
              child: Center(
                child: GlyphIcon(
                  AppGlyphs.download,
                  color: colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.reader.downloadManage,
                  style: context.theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
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
          ElasticPress(
            child: IconButton(
              icon: const GlyphIcon(AppGlyphs.close),
              tooltip: t.common.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
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
    final stateCode =
        payload?.stateCode ?? (dbTask == null ? 'none' : 'queued');
    final isPaused = stateCode == 'paused';
    final isFailed = stateCode == 'failed';
    final isCompleted = dbTask?.isCompleted == true || isDownloaded;

    String statusText;
    Color badgeContainerColor;
    Color badgeTextColor;
    Glyph statusIcon;

    if (isDownloading) {
      statusText = t.reader.downloadStatusDownloading;
      badgeContainerColor = colorScheme.primaryContainer;
      badgeTextColor = colorScheme.onPrimaryContainer;
      statusIcon = AppGlyphs.downloading;
    } else if (isPaused) {
      statusText = t.reader.downloadStatusPaused;
      final warn = statusAccent(context, StatusHue.warning);
      badgeContainerColor = warn.withValues(alpha: 0.16);
      badgeTextColor = warn;
      statusIcon = AppGlyphs.pauseCircle;
    } else if (isFailed) {
      statusText = t.reader.downloadStatusFailed;
      badgeContainerColor = colorScheme.errorContainer;
      badgeTextColor = colorScheme.onErrorContainer;
      statusIcon = AppGlyphs.error;
    } else if (isCompleted) {
      statusText = t.reader.downloadStatusCompleted;
      final succ = statusAccent(context, StatusHue.success);
      badgeContainerColor = succ.withValues(alpha: 0.16);
      badgeTextColor = succ;
      statusIcon = AppGlyphs.checkCircle;
    } else if (dbTask != null) {
      statusText = t.reader.downloadStatusQueued;
      badgeContainerColor = colorScheme.secondaryContainer;
      badgeTextColor = colorScheme.onSecondaryContainer;
      statusIcon = AppGlyphs.clock;
    } else {
      statusText = t.reader.notDownloaded;
      badgeContainerColor = colorScheme.surfaceContainerHighest;
      badgeTextColor = colorScheme.onSurfaceVariant;
      statusIcon = AppGlyphs.cloudDownload;
    }

    final fraction = payload == null
        ? (isCompleted ? 1.0 : null)
        : downloadTaskPayloadProgressFraction(payload);
    final progressMsg = payload == null
        ? ''
        : downloadTaskPayloadProgressMessage(payload);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: badgeContainerColor,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlyphIcon(statusIcon, color: badgeTextColor, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (fraction != null)
                Text(
                  '${(fraction * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
          ],
          if (progressMsg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              progressMsg,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (isFailed && (payload?.lastErrorMessage.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  GlyphIcon(
                    AppGlyphs.error,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      payload!.lastErrorMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
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
    final stateCode =
        payload?.stateCode ?? (dbTask == null ? 'none' : 'queued');
    final isPaused = stateCode == 'paused';
    final isFailed = stateCode == 'failed';
    final hasTask = dbTask != null;
    // 暂停 / 恢复作用于当前展示的那个章节任务。
    final chapterTaskKey = payload?.taskKey;

    final stadiumStyle = FilledButton.styleFrom(
      shape: const StadiumBorder(),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      shape: const StadiumBorder(),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1. 开始 / 继续 / 暂停 按钮
        if (!hasTask && !isDownloaded)
          ElasticPress(
            child: FilledButton.icon(
              style: stadiumStyle,
              icon: const GlyphIcon(AppGlyphs.download),
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
          ),
        if (isDownloading)
          ElasticPress(
            child: FilledButton.tonalIcon(
              style: stadiumStyle,
              icon: const GlyphIcon(AppGlyphs.pause),
              label: Text(t.reader.pauseDownload),
              onPressed: chapterTaskKey == null
                  ? null
                  : () {
                      DownloadQueueManager.instance.pauseTask(chapterTaskKey);
                      showInfoToast(t.reader.downloadStatusPaused);
                    },
            ),
          ),
        if (isPaused)
          ElasticPress(
            child: FilledButton.icon(
              style: stadiumStyle,
              icon: const GlyphIcon(AppGlyphs.play),
              label: Text(t.reader.resumeDownload),
              onPressed: chapterTaskKey == null
                  ? null
                  : () {
                      DownloadQueueManager.instance.resumeTask(chapterTaskKey);
                      showInfoToast(t.reader.downloadStatusDownloading);
                    },
            ),
          ),
        if (isFailed)
          ElasticPress(
            child: FilledButton.icon(
              style: stadiumStyle,
              icon: const GlyphIcon(AppGlyphs.refresh),
              label: Text(t.common.retry),
              onPressed: () {
                if (dbTask != null) {
                  DownloadQueueManager.instance.retryTask(dbTask.id);
                }
              },
            ),
          ),

        // 2. 重新下载按钮
        if (hasTask || isDownloaded)
          ElasticPress(
            child: OutlinedButton.icon(
              style: outlinedStyle,
              icon: const GlyphIcon(AppGlyphs.reset),
              label: Text(t.reader.restartDownload),
              onPressed: () => _confirmRestartDownload(context),
            ),
          ),

        // 3. 删除下载按钮
        if (hasTask || isDownloaded)
          ElasticPress(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.4),
                ),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: GlyphIcon(AppGlyphs.delete, color: colorScheme.error),
              label: Text(
                t.reader.deleteDownload,
                style: TextStyle(color: colorScheme.error),
              ),
              onPressed: () => _confirmDeleteDownload(context),
            ),
          ),

        // 4. 查看全部下载任务
        ElasticPress(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: const GlyphIcon(AppGlyphs.layoutList),
            label: Text(t.reader.viewAllTasks),
            onPressed: () {
              Navigator.of(context).pop();
              context.pushRoute(const DownloadTaskRoute());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSwitches(BuildContext context, ColorScheme colorScheme) {
    final globalState = context.watch<GlobalSettingCubit>().state;
    final cubit = context.read<GlobalSettingCubit>();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t.reader.downloadPreference,
              style: context.theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SettingGroup.switchTile(
            contentPadding: EdgeInsets.zero,
            leading: const GlyphIcon(AppGlyphs.sync),
            title: Text(t.reader.readWhileDownloading),
            subtitle: Text(t.reader.readWhileDownloadingSubtitle),
            value: globalState.readSetting.readWhileDownloading,
            onChanged: (val) {
              cubit.updateReadSetting(
                (s) => s.copyWith(readWhileDownloading: val),
              );
            },
          ),
          SettingGroup.switchTile(
            contentPadding: EdgeInsets.zero,
            leading: const GlyphIcon(AppGlyphs.bookmark),
            title: Text(t.settings.autoFavoriteOnDownload),
            subtitle: Text(t.settings.autoFavoriteOnDownloadSubtitle),
            value: globalState.autoFavoriteOnDownload,
            onChanged: (val) {
              cubit.updateState((s) => s.copyWith(autoFavoriteOnDownload: val));
            },
          ),
          SettingGroup.switchTile(
            contentPadding: EdgeInsets.zero,
            leading: const GlyphIcon(AppGlyphs.download),
            title: Text(t.settings.promptDownloadOptions),
            subtitle: Text(t.settings.promptDownloadOptionsSubtitle),
            value: globalState.promptDownloadOptions,
            onChanged: (val) {
              cubit.updateState((s) => s.copyWith(promptDownloadOptions: val));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRestartDownload(BuildContext context) async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (ctx) => PopupPanel(
        title: Text(t.reader.restartDownload),
        content: Text(t.reader.confirmResetAndRedownload),
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
      await DownloadQueueManager.instance.retryComicTasks(
        from: widget.from,
        comicId: widget.comicId,
      );
      showInfoToast(t.reader.requeuedToDownload);
    }
  }

  Future<void> _confirmDeleteDownload(BuildContext context) async {
    final colorScheme = context.theme.colorScheme;
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (ctx) => PopupPanel(
        title: Text(t.reader.confirmDeleteDownloadTitle),
        content: Text(t.reader.confirmDeleteDownload),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await deleteWholeComicDownload(
        from: widget.from,
        comicId: widget.comicId,
      );
      if (mounted) {
        showSuccessToast(t.download.taskDeleted);
      }
    }
  }
}
