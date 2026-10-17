import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_info/models/favorite_workflow.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/page/comic_info/models/comic_magnet.dart';
import 'package:zephyr/page/comic_info/models/comic_source_page_url.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/download/widgets/comic_download_options_sheet.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';

import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/dialog.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

part 'comic_operation_presentation.dart';

class ComicOperationWidget extends StatefulWidget {
  final NormalComicAllInfo normalInfo;
  final String from;
  final String? collectionTargetId;
  final String? collectionTargetName;
  final dynamic comicInfo;

  /// 这本书有没有阅读历史（决定页内阅读入口写着「继续阅读」还是「开始阅读」）。
  final bool hasHistory;

  /// 页内「阅读」入口（桌面端贴在「下载」旁边）。
  ///
  /// **为空即不显示** —— 触摸端走右下角的悬浮按钮，那才是它的落点；
  /// 落点由 [resolveComicInfoReadEntryPlacement] 判定，两个入口不并存。
  final VoidCallback? onRead;

  final bool inline;
  final bool primaryActionsOnly;

  const ComicOperationWidget({
    super.key,
    required this.normalInfo,
    required this.from,
    this.collectionTargetId,
    this.collectionTargetName,
    required this.comicInfo,
    this.hasHistory = false,
    this.onRead,
    this.inline = false,
    this.primaryActionsOnly = false,
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

  /// 这本书在原站的页面地址；空串 = 插件没给过，那颗卡整个不渲染。
  String _sourcePageUrl = '';

  @override
  void initState() {
    super.initState();
    _syncLocalCollectStatus();
    isLiked = normalInfo.isLiked;
    isCloudCollected = normalInfo.isFavourite;
    _resolveSourcePageUrl();
  }

  @override
  void didUpdateWidget(covariant ComicOperationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 下拉刷新会换一份 normalInfo（插件可能这次才给链接），只在这时重算。
    if (oldWidget.normalInfo != widget.normalInfo ||
        oldWidget.from != widget.from) {
      _resolveSourcePageUrl();
    }
  }

  Future<void> _resolveSourcePageUrl() async {
    final url = await resolveComicSourcePageUrl(
      info: widget.normalInfo,
      from: widget.from,
      comicId: _downloadComicId,
    );
    if (!mounted || url == _sourcePageUrl) {
      return;
    }
    setState(() {
      _sourcePageUrl = url;
    });
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
            icon: isCloudCollected ? AppGlyphs.cloudDone : AppGlyphs.cloud,
            text: isCloudCollected
                ? t.comicInfo.collected
                : t.comicInfo.collectToCloud,
            highlighted: isCloudCollected,
            accentColor: const Color(0xFFE6A700),
            enabled: true,
            onTap: _toggleCloudFavorite,
          )
        : _OperationItemData(
            icon: AppGlyphs.star,
            fillsWhenHighlighted: true,
            text: isCollected ? t.comicInfo.collected : t.comicInfo.collect,
            highlighted: isCollected,
            accentColor: const Color(0xFFE6A700),
            enabled: true,
            onTap: _toggleLocalFavorite,
          );
    final magnet = comicMagnetOf(normalInfo);
    final actions = [
      _OperationItemData(
        icon: AppGlyphs.heart,
        fillsWhenHighlighted: true,
        text: t.comicInfo.likes(count: normalInfo.totalLikes),
        highlighted: isLiked,
        accentColor: Colors.red,
        enabled: normalInfo.allowLike,
        onTap: _toggleCloudLike,
      ),
      _OperationItemData(
        icon: AppGlyphs.comment,
        text: t.comicInfo.comments(count: normalInfo.totalComments),
        enabled: normalInfo.allowComments,
        onTap: _openComments,
      ),
      collectItem,
      // 桌面端的阅读入口：和「下载」并排，而不是叠在右下角（见
      // `read_entry_placement.dart`）。触摸端 onRead 为空，这一项不出现。
      if (widget.onRead != null)
        _OperationItemData(
          icon: widget.hasHistory ? AppGlyphs.history : AppGlyphs.book,
          text: widget.hasHistory
              ? t.comicInfo.continueRead
              : t.comicInfo.startRead,
          onTap: widget.onRead,
          primary: true,
        ),
      _OperationItemData(
        kind: _OperationKind.download,
        icon: AppGlyphs.cloudDownload,
        text: normalInfo.allowDownload
            ? t.comicInfo.download
            : t.comicInfo.downloadForbidden,
        enabled: normalInfo.allowDownload,
        onTap: _openDownload,
        onLongPress: (_) => _openDownloadChapterPicker(),
        onLongPressTooltip: t.reader.selectChapter,
      ),
      // 磁力一键复制：只有插件在 comicInfo.extern 里给了 magnet 才出现，
      // 没有磁力的图源这里恒为空、这一项整个不渲染。
      if (magnet.isNotEmpty)
        _OperationItemData(
          icon: AppGlyphs.copy,
          text: t.common.copy,
          enabled: true,
          onTap: _copyMagnet,
        ),
      // 在原站打开。链接只取插件**已经交出来过**的地址（详情的 extern，或早前解析
      // 列表项时记下的那条），插件没给就和磁力那颗一样静默不出现 —— 不去猜站的 URL。
      // 单击走内置 WebView（它右上角本来就有「外部浏览器打开」，且与插件共享 Cookie），
      // 长按给「外部浏览器打开 / 复制链接」。
      if (_sourcePageUrl.isNotEmpty)
        _OperationItemData(
          icon: AppGlyphs.globe,
          text: t.comicInfo.openOnSource,
          onTap: _openSourcePageInWebView,
          onLongPress: _showSourcePageMenu,
          onLongPressTooltip: t.webview.openInExternalBrowser,
        ),
    ];

    if (widget.inline) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item
              in widget.primaryActionsOnly
                  ? actions.where(
                      (item) =>
                          item.kind == _OperationKind.download || item.primary,
                    )
                  : actions)
            item.kind == _OperationKind.download
                ? _DownloadOperationCard(
                    item: item,
                    compact: true,
                    inline: true,
                    from: _downloadSource,
                    comicId: _downloadComicId,
                    taskStream: _downloadTaskStream,
                  )
                : _InlineOperationButton(item: item),
        ],
      );
    }

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

  Future<void> _copyMagnet() async {
    final magnet = comicMagnetOf(normalInfo);
    if (magnet.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: magnet));
    if (!mounted) {
      return;
    }
    showSuccessToast(
      t.comicInfo.copiedToClipboard(name: magnet),
      context: context,
    );
  }

  /// 单击「在原站打开」：走内置 WebView —— 它与插件共享 Cookie，
  /// 在应用里登录过的源不需要在系统浏览器里再登一遍。
  void _openSourcePageInWebView() {
    final url = _sourcePageUrl;
    if (url.isEmpty) {
      return;
    }
    context.pushRoute(WebViewRoute(info: [comicInfoView.title, url]));
  }

  /// 长按「在原站打开」：给外部浏览器和复制链接两个出口。
  Future<void> _showSourcePageMenu(Offset position) async {
    final url = _sourcePageUrl;
    if (url.isEmpty) {
      return;
    }

    // 走 [showCommonPopupMenu]（[CommonPopupRoute] 那份 FlClash 动画）：
    // 托盘从长按那一点长出来，与工作台那排「更多」菜单同一套。
    await showCommonPopupMenu(
      context: context,
      position: position,
      items: [
        CommonPopupMenuItem(
          label: t.webview.openInExternalBrowser,
          onPressed: () => unawaited(_openSourcePageExternally(url)),
        ),
        CommonPopupMenuItem(
          label: t.common.copy,
          onPressed: () => unawaited(_copySourcePageUrl(url)),
        ),
      ],
    );
  }

  /// 长按菜单里的「外部浏览器打开」：系统浏览器没有插件的 Cookie，
  /// 所以它是**出口**而不是默认路径（默认那颗点击进的是内置 WebView）。
  Future<void> _openSourcePageExternally(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        showErrorToast(t.webview.invalidLink);
      }
      return;
    }
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (mounted) {
      showErrorToast(t.webview.cannotOpenLink(uri: url));
    }
  }

  Future<void> _copySourcePageUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    showSuccessToast(
      t.comicInfo.copiedToClipboard(name: url),
      context: context,
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
      final reason = normalInfo.allowCommentsReason.trim();
      commonDialog(
        context,
        t.comicInfo.commentForbiddenTitle,
        reason.isNotEmpty ? reason : t.comicInfo.commentForbidden,
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
  /// 已有下载记录/任务时点击语义是「管理已有下载」，直接进章节选择页；
  /// 全新漫画也不再闷头把整本塞进队列 —— 弹一次三选（整本 / 最近 N 章 / 手动挑），
  /// 因为 100+ 章的本误点一下就是 100 个任务，长按找入口的成本不该由用户付。
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
    final info = resolveUnifiedDownloadInfo(comicInfo, widget.from);
    await promptAndRunComicDownload(
      context,
      from: _downloadSource,
      comicId: _downloadComicId,
      comicName: comicInfoView.title,
      comicInfo: comicInfo,
      chapterCount: info.chapters.length,
      onOpenChapterPicker: () => _pushChapterPicker(info),
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
        legacyAllowCollectedReason: normalInfo.allowCollectedReason,
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
    } on FavoriteWorkflowUnsupportedException catch (error) {
      if (mounted) {
        final reason = error.reason.trim();
        showInfoToast(
          reason.isNotEmpty ? reason : t.comicInfo.cloudCollectDisabled,
        );
      }
    } on FavoriteWorkflowIncompleteException catch (error) {
      if (mounted) {
        showInfoToast(
          error.result.message ?? t.comicInfo.cloudFavoriteIncomplete,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showErrorToast(
        normalizeSearchErrorMessage(error),
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<bool> _showUncollectConfirmDialog() async {
    final result = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) {
        return PopupPanel(
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
      final reason = normalInfo.allowLikeReason.trim();
      showInfoToast(reason.isNotEmpty ? reason : t.comicInfo.likeDisabled);
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
