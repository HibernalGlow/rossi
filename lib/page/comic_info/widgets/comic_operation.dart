import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_info/models/favorite_workflow.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';

import 'package:zephyr/widgets/dialog.dart';
import 'package:zephyr/widgets/toast.dart';

class ComicOperationWidget extends StatefulWidget {
  final NormalComicAllInfo normalInfo;
  final String from;
  final String? collectionTargetId;
  final String? collectionTargetName;
  final dynamic comicInfo;

  const ComicOperationWidget({
    super.key,
    required this.normalInfo,
    required this.from,
    this.collectionTargetId,
    this.collectionTargetName,
    required this.comicInfo,
  });

  @override
  State<ComicOperationWidget> createState() => _ComicOperationWidgetState();
}

class _ComicOperationWidgetState extends State<ComicOperationWidget> {
  dynamic get comicInfo => widget.comicInfo;
  NormalComicAllInfo get normalInfo => widget.normalInfo;
  ComicInfo get comicInfoView => normalInfo.comicInfo;
  bool isCollected = false;
  bool isLiked = false;
  bool isCloudCollected = false;

  String? _taskStreamKey;
  Stream<DownloadTask?>? _taskStream;

  @override
  void initState() {
    super.initState();
    _syncLocalCollectStatus();
    isLiked = normalInfo.isLiked;
    isCloudCollected = normalInfo.isFavourite;
  }

  Future<void> _syncLocalCollectStatus() async {
    final localCollected = await isLocalComicCollected(
      from: widget.from,
      comicId: comicInfoView.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      isCollected = localCollected;
    });
  }

  Future<void> _autoFollowIfEnabled() async {
    if (!context.read<GlobalSettingCubit>().state.autoFollowOnCollect) {
      return;
    }
    final followCubit = context.read<ComicFollowCubit>();
    final comicId = comicInfoView.id;
    if (followCubit.isFollowing(widget.from, comicId)) {
      return;
    }
    await followCubit.addOrUpdateFollow(
      source: widget.from,
      comicId: comicId,
      info: normalInfo,
      lastChapterCount: normalInfo.eps.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 开启「优先云端收藏」后，收藏按钮执行云端收藏，原逻辑与菜单项互换
    final cloudFavoritePreferred = context
        .watch<GlobalSettingCubit>()
        .state
        .cloudFavoritePreferred;
    final collectItem = cloudFavoritePreferred
        ? _OperationItemData(
            icon: isCloudCollected
                ? Icons.cloud_done_outlined
                : Icons.cloud_outlined,
            text: isCloudCollected
                ? t.comicInfo.collected
                : t.comicInfo.collectToCloud,
            highlighted: isCloudCollected,
            accentColor: const Color(0xFFE6A700),
            enabled: true,
            onTap: _toggleCloudFavorite,
          )
        : _OperationItemData(
            icon: isCollected ? Icons.star : Icons.star_border,
            text: isCollected ? t.comicInfo.collected : t.comicInfo.collect,
            highlighted: isCollected,
            accentColor: const Color(0xFFE6A700),
            enabled: true,
            onTap: _toggleLocalFavorite,
          );
    final actions = [
      _OperationItemData(
        icon: isLiked ? Icons.favorite : Icons.favorite_border,
        text: t.comicInfo.likes(count: normalInfo.totalLikes),
        highlighted: isLiked,
        accentColor: Colors.red,
        enabled: normalInfo.allowLike,
        onTap: _toggleCloudLike,
      ),
      _OperationItemData(
        icon: Icons.mode_comment_outlined,
        text: t.comicInfo.comments(count: normalInfo.totalComments),
        enabled: normalInfo.allowComments,
        onTap: _openComments,
      ),
      collectItem,
      _OperationItemData(
        kind: _OperationKind.download,
        icon: Icons.cloud_download_outlined,
        text: normalInfo.allowDownload
            ? t.comicInfo.download
            : t.comicInfo.downloadForbidden,
        enabled: normalInfo.allowDownload,
        onTap: _openDownload,
        onLongPress: _openDownloadChapterPicker,
        onLongPressTooltip: t.reader.selectChapter,
      ),
    ];

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final itemWidth = switch (constraints.maxWidth) {
            < 420 => (constraints.maxWidth - 10) / 2,
            < 720 => (constraints.maxWidth - 20) / 3,
            < 900 => (constraints.maxWidth - 30) / 4,
            _ => 136.0,
          };

          return Center(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: actions
                  .map(
                    (item) => SizedBox(
                      width: itemWidth,
                      // 下载卡片要跟着下载状态走（未下载 / 下载中 / 已下载），
                      // 其余卡片是纯静态项。
                      child: item.kind == _OperationKind.download
                          ? _DownloadOperationCard(
                              item: item,
                              compact: isDesktop,
                              from: _downloadSource,
                              comicId: _downloadComicId,
                              taskStream: _downloadTaskStream,
                            )
                          : _OperationCard(item: item, compact: isDesktop),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }

  /// 与下载任务/下载记录一致的 source key。
  String get _downloadSource => widget.from.trim();

  /// 与下载任务/下载记录一致的 comic key。
  String get _downloadComicId => comicInfoView.id.toString().trim();

  /// 下载任务状态流按 key 缓存：`build` 里每次新建会让 StreamBuilder 反复重订阅。
  Stream<DownloadTask?> get _downloadTaskStream {
    final key = '$_downloadSource|$_downloadComicId';
    if (_taskStreamKey != key) {
      _taskStreamKey = key;
      _taskStream = DownloadQueueManager.instance.watchTaskByComic(
        _downloadSource,
        _downloadComicId,
      );
    }
    return _taskStream!;
  }

  void _openComments() {
    if (!normalInfo.allowComments) {
      commonDialog(
        context,
        t.comicInfo.commentForbiddenTitle,
        t.comicInfo.commentForbidden,
      );
      return;
    }

    context.pushRoute(
      PluginCommentsScaffoldRoute(
        from: widget.from,
        comicId: comicInfoView.id.toString(),
        comicTitle: comicInfoView.title,
      ),
    );
  }

  /// 单击「下载」。
  ///
  /// 默认直接下载整本；只有这本漫画已有下载记录/任务时才进章节选择页
  /// （此时点击语义是「管理已有下载」）。想主动挑章节请长按。
  Future<void> _openDownload() async {
    if (!normalInfo.allowDownload) return;

    final action = resolveComicDownloadEntryAction(
      hasDownloadRecord: hasComicDownloadRecord(
        from: _downloadSource,
        comicId: _downloadComicId,
      ),
      hasDownloadTask: hasComicDownloadTask(
        from: _downloadSource,
        comicId: _downloadComicId,
      ),
    );
    if (action == ComicDownloadEntryAction.openChapterPicker) {
      _openDownloadChapterPicker();
      return;
    }

    if (!mounted) return;
    await startComicDownloadAll(
      context: context,
      from: _downloadSource,
      comicId: _downloadComicId,
      comicName: comicInfoView.title,
      comicInfo: comicInfo,
    );
  }

  /// 长按「下载」：显式进入章节选择页。
  void _openDownloadChapterPicker() {
    if (!normalInfo.allowDownload) return;
    _pushChapterPicker(resolveUnifiedDownloadInfo(comicInfo, widget.from));
  }

  void _pushChapterPicker(UnifiedComicDownloadInfo info) {
    context.pushRoute(DownloadRoute(downloadInfo: info));
  }

  Future<void> _toggleLocalFavorite() async {
    try {
      // 取消收藏需要确认，因为会删除所有文件夹中的记录
      if (isCollected) {
        final confirmed = await _showUncollectConfirmDialog();
        if (!confirmed) {
          return;
        }
      }

      final next = await toggleLocalComicFavorite(
        from: widget.from,
        normalInfo: normalInfo,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isCollected = next;
      });
      if (next) {
        await _autoFollowIfEnabled();
      }
      if (next) {
        showSuccessToast(t.comicInfo.addedToCollection);
      } else {
        showSuccessToast(t.comicInfo.removedFromCollection);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showErrorToast(
        t.comicInfo.localCollectFailed(
          error: normalizeSearchErrorMessage(error),
        ),
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _toggleCloudFavorite() async {
    try {
      showInfoToast(
        isCloudCollected
            ? t.comicInfo.removingCloudCollection
            : t.comicInfo.collectingToCloud,
      );
      final next = await toggleCloudComicFavorite(
        context: context,
        from: widget.from,
        comicId: comicInfoView.id,
        currentStatus: isCloudCollected,
        legacyAllowCollected: normalInfo.allowCollected,
        collectionTargetId: widget.collectionTargetId,
        collectionTargetName: widget.collectionTargetName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isCloudCollected = next;
      });
      if (next) {
        await _autoFollowIfEnabled();
      }
      showSuccessToast(
        next
            ? t.comicInfo.cloudCollectSuccess
            : t.comicInfo.cloudUncollectSuccess,
      );
    } on FavoriteWorkflowUnsupportedException {
      if (mounted) {
        showInfoToast(t.comicInfo.cloudCollectDisabled);
      }
    } on FavoriteWorkflowIncompleteException catch (error) {
      if (mounted) {
        showInfoToast(error.result.message ?? '云端收藏操作未完成');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showErrorToast(t.error.operationFailed);
    }
  }

  Future<bool> _showUncollectConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.comicInfo.confirmUncollectTitle),
          content: Text(t.comicInfo.confirmUncollectContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.common.confirm),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _toggleCloudLike() async {
    if (!normalInfo.allowLike) {
      return;
    }
    try {
      showInfoToast(isLiked ? t.comicInfo.unliking : t.comicInfo.liking);
      final next = await toggleCloudComicLike(
        from: widget.from,
        comicId: comicInfoView.id,
        currentStatus: isLiked,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isLiked = next;
      });
      showSuccessToast(
        next ? t.comicInfo.likeSuccess : t.comicInfo.unlikeSuccess,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showErrorToast(
        t.comicInfo.likeFailed(error: normalizeSearchErrorMessage(error)),
        duration: const Duration(seconds: 5),
      );
    }
  }
}

enum _OperationKind { generic, download }

class _OperationItemData {
  const _OperationItemData({
    required this.icon,
    required this.text,
    this.kind = _OperationKind.generic,
    this.onTap,
    this.onLongPress,
    this.onLongPressTooltip,
    this.enabled = true,
    this.highlighted = false,
    this.accentColor,
    this.iconColor,
  });

  final IconData icon;
  final String text;

  /// 下载项要额外接下载状态流，单独渲染。
  final _OperationKind kind;
  final VoidCallback? onTap;

  /// 长按回调；为空时该卡片不响应长按。
  final VoidCallback? onLongPress;

  /// 长按的悬停提示（桌面端可发现性）。
  final String? onLongPressTooltip;
  final bool enabled;
  final bool highlighted;
  final Color? accentColor;

  /// 覆盖图标颜色（用于下载状态的语义色）。
  final Color? iconColor;
}

/// 下载卡片：跟着下载任务/下载记录切图标与文案，让「点一下会发生什么」可预期。
class _DownloadOperationCard extends StatelessWidget {
  const _DownloadOperationCard({
    required this.item,
    required this.compact,
    required this.from,
    required this.comicId,
    required this.taskStream,
  });

  final _OperationItemData item;
  final bool compact;
  final String from;
  final String comicId;
  final Stream<DownloadTask?> taskStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadTask?>(
      stream: taskStream,
      initialData: DownloadQueueManager.instance.getTaskByComic(from, comicId),
      builder: (context, snapshot) {
        return _OperationCard(
          item: _decorate(context, snapshot.data),
          compact: compact,
        );
      },
    );
  }

  _OperationItemData _decorate(BuildContext context, DownloadTask? task) {
    // 不允许下载时保持原样（「禁止下载」）。
    if (!item.enabled) {
      return item;
    }

    final colorScheme = context.theme.colorScheme;
    final state = resolveComicDownloadVisualState(
      isDownloading: task?.isDownloading ?? false,
      isCompleted: task?.isCompleted ?? false,
      stateCode:
          task?.taskInfo?.stateCode ?? (task == null ? 'none' : 'queued'),
      hasRecord: hasComicDownloadRecord(from: from, comicId: comicId),
    );

    final (IconData icon, String text, Color? iconColor) = switch (state) {
      ComicDownloadVisualState.downloading => (
        Icons.downloading_rounded,
        t.reader.downloadStatusDownloading,
        colorScheme.primary,
      ),
      ComicDownloadVisualState.paused => (
        Icons.pause_circle_outline_rounded,
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
        Icons.cloud_download_outlined,
        t.comicInfo.download,
        null,
      ),
    };

    return _OperationItemData(
      kind: item.kind,
      icon: icon,
      text: text,
      onTap: item.onTap,
      onLongPress: item.onLongPress,
      onLongPressTooltip: item.onLongPressTooltip,
      enabled: item.enabled,
      iconColor: iconColor,
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.item, this.compact = false});

  final _OperationItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = item.accentColor ?? context.theme.colorScheme.primary;
    final background = item.highlighted
        ? accent.withValues(alpha: 0.14)
        : context.theme.colorScheme.surfaceContainerLowest;
    final foreground = !item.enabled
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : item.highlighted
        ? accent
        : context.textColor;

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        onLongPress: item.onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 10 : 11,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: compact ? 18 : 20,
                color: item.iconColor ?? foreground,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final tooltip = item.onLongPressTooltip;
    if (tooltip == null || item.onLongPress == null) {
      return card;
    }
    // triggerMode 必须是 manual：默认的 longPress 触发会在触摸设备上与
    // 卡片自身的 onLongPress 抢同一个手势，导致长按变成「弹提示」。
    // 桌面端悬停提示不依赖 triggerMode，仍然正常显示。
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.manual,
      child: card,
    );
  }
}
