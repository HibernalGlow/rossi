import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/read_entry_placement.dart';
import 'package:zephyr/page/comic_info/widgets/comic_inline_details_surface.dart';
import 'package:zephyr/page/comic_info/widgets/comic_info_action_rail.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/permission.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/service/reader/shelf_book_navigation.dart';
part 'parts/comic_info_rossi_actions_part.dart';
part 'parts/comic_info_chapter_groups_part.dart';
part 'parts/comic_info_content_part.dart';
part 'parts/comic_info_sections_part.dart';
part 'parts/comic_info_inline_part.dart';
part 'parts/embedded_comic_info_part.dart';

enum MenuOption { export, cloudCollect, follow }

@RoutePage()
class ComicInfoPage extends StatelessWidget {
  final String comicId;
  final String from;
  final ComicEntryType type;
  final Map<String, dynamic>? extern;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const ComicInfoPage({
    super.key,
    required this.comicId,
    required this.from,
    required this.type,
    this.extern,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFrom = from.trim();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => GetComicInfoBloc()
            ..add(
              GetComicInfoEvent(
                comicId: comicId,
                from: resolvedFrom,
                type: type,
                extern: extern,
              ),
            ),
        ),
        BlocProvider(create: (_) => StringSelectCubit()),
      ],
      child: _ComicInfo(
        comicId: comicId,
        type: type,
        from: resolvedFrom,
        extern: extern,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      ),
    );
  }
}

class _ComicInfo extends StatefulWidget {
  final VoidCallback? onClose;
  final String comicId;
  final ComicEntryType type;
  final String from;
  final Map<String, dynamic>? extern;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const _ComicInfo({
    this.onClose,
    required this.comicId,
    required this.type,
    required this.from,
    this.extern,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  @override
  _ComicInfoState createState() => _ComicInfoState();
}

class _ComicInfoState extends State<_ComicInfo>
    with AutomaticKeepAliveClientMixin
    implements ComicInfoActionScope {
  ComicEntryType get type => widget.type;

  @override
  bool get wantKeepAlive => true;

  dynamic comicInfoDyn;
  late ComicEntryType _type;
  late String _comicId;
  bool _loadingComplete = false;
  bool _isReversed = false;
  String _title = "";
  late final EpisodeDownloadController _dlController =
      EpisodeDownloadController();

  /// 章节阅读标记（与下载控制器共用一份选中态）。
  late final EpisodeReadMarkController _readController =
      EpisodeReadMarkController();
  // 已折叠的章节组（存组标题 key）。默认全展开；漫画切换时清空。
  final Set<String> _collapsedGroups = {};
  String _collapsedForComic = '';
  NormalComicAllInfo? _currentInfo;
  bool _isCloudCollected = false;
  bool _cloudFavoriteStateOverridden = false;
  bool _isLocalCollected = false;
  String _localCollectSyncedFor = '';

  // 章节显示顺序缓存：raw 列表实例不变且倒序开关不变时直接复用，
  // 避免每次 build 都 sort + reversed.toList()。
  // 非倒序时 display 与 sorted 同引用，零拷贝。
  List<dynamic>? _epsRawRef;
  List<dynamic> _sortedEps = const [];
  List<dynamic> _displayEps = const [];
  bool _displayEpsReversed = false;
  bool _displayEpsValid = false;

  List<dynamic> _resolveDisplayEps(List<dynamic> rawEps) {
    if (!identical(rawEps, _epsRawRef)) {
      _epsRawRef = rawEps;
      _sortedEps = sortChaptersByOrder(
        List<dynamic>.from(rawEps),
        (e) => (e as Ep).order,
      );
      _displayEpsValid = false;
    }
    if (!_displayEpsValid || _displayEpsReversed != _isReversed) {
      _displayEps = _isReversed ? _sortedEps.reversed.toList() : _sortedEps;
      _displayEpsReversed = _isReversed;
      _displayEpsValid = true;
    }
    return _displayEps;
  }

  @override
  void initState() {
    super.initState();
    _type = type;
    _comicId = widget.comicId;
  }

  @override
  void dispose() {
    _dlController.dispose();
    _readController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.onClose != null) return _buildInlineDetails();
    // 开启「优先云端收藏」后，页面收藏按钮与菜单项的本地/云端收藏行为互换
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final cloudFavoritePreferred = globalSetting.cloudFavoritePreferred;
    // 「阅读」入口只落一处：桌面端落进操作行（下载旁边），触摸端落右下角悬浮按钮。
    final readEntryPlacement = resolveComicInfoReadEntryPlacement(
      platform: defaultTargetPlatform,
      inlineReadEntryEnabled: globalSetting.comicInfoInlineReadButton,
    );
    final showInlineReadEntry =
        widget.onClose != null ||
        readEntryPlacement == ComicInfoReadEntryPlacement.inlineCard;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const GlyphIcon(AppGlyphs.arrowBack),
          // 住在发现页的标签里时，这颗「返回」关的是**当前这条标签**。
          // context.pop() 走的是根路由：那一下弹掉的是压着详情页的那一页，
          // 在工作台里就是整个工作台。
          onPressed: () => actionBack(context),
        ),
        actions: [
          const SizedBox(width: 50),
          IconButton(
            icon: const GlyphIcon(AppGlyphs.home),
            onPressed: () {
              if (widget.onClose != null) {
                widget.onClose!();
                return;
              }
              final tabs = DiscoverTabScope.maybeOf(context);
              if (tabs != null) {
                tabs.goHome();
                return;
              }
              popToRoot(context);
            },
          ),
          Expanded(child: Container()),
          BlocSelector<ComicFollowCubit, ComicFollowState, bool>(
            selector: (state) => state.isFollowing(widget.from, _comicId),
            builder: (context, isFollowing) {
              return IconButton(
                icon: AnimatedGlyph(glyph: AppGlyphs.bell, filled: isFollowing),
                tooltip: isFollowing
                    ? t.comicInfo.unfollow
                    : t.comicInfo.follow,
                onPressed: () => _toggleFollow(isFollowing),
              );
            },
          ),
          FluentPopupMenuButton<MenuOption>(
            icon: const GlyphIcon(AppGlyphs.more),
            onSelected: (MenuOption item) {
              switch (item) {
                case MenuOption.export:
                  _handleExport();
                  break;
                case MenuOption.cloudCollect:
                  if (cloudFavoritePreferred) {
                    _toggleLocalCollectFromMenu();
                  } else {
                    _toggleCloudCollectFromMenu();
                  }
                  break;
                case MenuOption.follow:
                  _toggleFollowFromMenu();
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              final isFollowing = context.read<ComicFollowCubit>().isFollowing(
                widget.from,
                _comicId,
              );
              final menuItems = <FluentPopupMenuItem<MenuOption>>[
                FluentPopupMenuItem<MenuOption>(
                  value: MenuOption.follow,
                  leading: GlyphIcon(
                    isFollowing ? AppGlyphs.bellOff : AppGlyphs.bell,
                  ),
                  title: Text(
                    isFollowing ? t.comicInfo.unfollow : t.comicInfo.follow,
                  ),
                ),
              ];

              if (_type == ComicEntryType.download) {
                menuItems.add(
                  FluentPopupMenuItem<MenuOption>(
                    value: MenuOption.export,
                    leading: const GlyphIcon(AppGlyphs.download),
                    title: Text(t.comicInfo.exportComic),
                  ),
                );
              }

              menuItems.add(
                FluentPopupMenuItem<MenuOption>(
                  value: MenuOption.cloudCollect,
                  leading: GlyphIcon(
                    AppGlyphs.star,
                    fill:
                        (cloudFavoritePreferred
                            ? _isLocalCollected
                            : _isCloudCollected)
                        ? 1
                        : 0,
                  ),
                  title: Text(
                    cloudFavoritePreferred
                        ? (_isLocalCollected
                              ? t.comicInfo.removeLocalCollection
                              : t.comicInfo.collectToLocal)
                        : (_isCloudCollected
                              ? t.comicInfo.removeCloudCollection
                              : t.comicInfo.collectToCloud),
                  ),
                ),
              );

              return menuItems;
            },
          ),
        ],
      ),
      body: _withActionRails(
        child: Stack(
          children: [
            BlocConsumer<GetComicInfoBloc, GetComicInfoState>(
              listener: (context, state) {
                if (state.status == GetComicInfoStatus.success) {
                  final cover = state.allInfo?.comicInfo.cover;
                  if (cover != null && cover.url.isNotEmpty) {
                    DiscoverTabScope.maybeOf(context)?.reportFirstCover(
                      url: cover.url,
                      path: cover.path,
                      from: widget.from,
                      cartoonId: widget.comicId,
                    );
                  }
                }
              },
              builder: (context, state) {
                switch (state.status) {
                  case GetComicInfoStatus.initial:
                    _cloudFavoriteStateOverridden = false;
                    return Center(child: CircularProgressIndicator());
                  case GetComicInfoStatus.failure:
                    if (state.result.contains("under review") &&
                        state.result.contains("1014")) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.comicInfo.discontinued,
                              style: const TextStyle(fontSize: 20),
                            ),
                            SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => actionBack(context),
                              child: Text(t.comicInfo.back),
                            ),
                          ],
                        ),
                      );
                    }
                    return ErrorView(
                      errorMessage: t.comicInfo.loadFailedWithError(
                        error: state.result.toString(),
                      ),
                      onRetry: () {
                        context.read<GetComicInfoBloc>().add(
                          GetComicInfoEvent(
                            comicId: _comicId,
                            from: widget.from,
                            type: _type,
                            extern: widget.extern,
                          ),
                        );
                      },
                    );
                  case GetComicInfoStatus.success:
                    comicInfoDyn = state.comicInfo;
                    _currentInfo = state.allInfo;
                    _comicId = state.comicId ?? _comicId;
                    if (!_cloudFavoriteStateOverridden) {
                      _isCloudCollected = state.allInfo?.isFavourite ?? false;
                    }
                    _syncLocalCollectStatus(state.allInfo!);
                    initHistory(
                      context,
                      _comicId,
                      widget.from,
                      chapters: state.allInfo!.eps,
                    );
                    return _infoView(
                      state.allInfo!,
                      showInlineReadEntry: showInlineReadEntry,
                    );
                }
              },
            ),
            // 章节多选时浮出的操作条（上游把下载管理搬进了详情页）。
            // 控制器已不再是 Listenable，改订阅上游拆出来的这两个 cubit。
            BlocBuilder<EpisodeDownloadStatusCubit, EpisodeDownloadStatusState>(
              bloc: _dlController.statusCubit,
              builder: (context, _) => BlocBuilder<EpisodeSelectionCubit, int>(
                bloc: _dlController.selectionCubit,
                builder: (context, _) => EpisodeSelectionActionBar(
                  controller: _dlController,
                  readController: _readController,
                  isDownloadType: _type == ComicEntryType.download,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      // 桌面上入口已经贴在操作行里（下载旁边），这里就撤掉 —— 两个入口并存会让人
      // 以为它们是两件事。触摸端（或开关关掉）仍旧是这颗悬浮按钮。
      floatingActionButton: BlocBuilder<EpisodeSelectionCubit, int>(
        bloc: _dlController.selectionCubit,
        builder: (context, _) {
          if (_dlController.selectionMode) {
            return const SizedBox.shrink();
          }
          return (_loadingComplete && !showInlineReadEntry)
              ? BlocBuilder<StringSelectCubit, String>(
                  builder: (context, stringSelectDate) {
                    return _ReadActionButton(
                      hasHistory: stringSelectDate.isNotEmpty,
                      onPressed: () => _startReading(widget.type),
                    );
                  },
                )
              : const SizedBox.shrink();
        },
      ),
    );
  }

  // ── 详情页操作栏（车道 C-1 / E / F，见 `docs/comic-info-action-rail.md`）──────
  //
  // 这一屏的「有哪些动作」只在这份清单里写一次；rail 按 id 挑自己那几条。
  // 带状态的 6 条（收藏 / 点赞 / 评论 / 下载 / 挑章节 / 磁力）还没进来 —— 它们的状态
  // 挂在 `ComicOperationWidget` 自己的 `setState` 上，等 C-2 把状态提出来之后再并入，
  // 那时操作行改成读这份清单，才真正做到「一份清单、三处渲染」。

  @override
  List<ComicInfoActionEntry> comicInfoActionItems() {
    final hasHistory = context.watch<StringSelectCubit>().state.isNotEmpty;
    return [
      ComicInfoActionEntry(
        actionId: ComicInfoActionIds.back,
        icon: AppGlyphs.arrowBack,
        label: t.comicInfo.back,
        onTap: () => actionBack(context),
      ),
      ComicInfoActionEntry(
        actionId: ComicInfoActionIds.home,
        // 「返回首页」这条文案 reader 段里已有，不为了 rail 再造一个新键
        // （造键要重跑 slang，那是全仓共享的生成物）。
        icon: AppGlyphs.home,
        label: t.reader.backToHome,
        onTap: () => actionHome(context),
      ),
      // 没加载完就没有「这本书」，阅读那颗**不出现**（与那颗悬浮按钮同一口径），
      // 而不是画一颗永远点不动的。
      if (_loadingComplete)
        ComicInfoActionEntry(
          actionId: ComicInfoActionIds.read,
          icon: hasHistory ? AppGlyphs.history : AppGlyphs.book,
          label: hasHistory ? t.comicInfo.continueRead : t.comicInfo.startRead,
          onTap: () => actionRead(context),
        ),
    ];
  }

  @override
  void actionBack(BuildContext context) =>
      // 与左上角那颗箭头**同一条**行为：住在标签里时关的是那条标签。
      widget.onClose != null
      ? widget.onClose!()
      : popTabOrClose(context, otherwise: () => context.pop());

  @override
  void actionHome(BuildContext context) {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    final tabs = DiscoverTabScope.maybeOf(context);
    if (tabs != null) {
      tabs.goHome();
      return;
    }
    popToRoot(context);
  }

  @override
  void actionRead(BuildContext context) => _startReading(widget.type);

  Widget _constrainedSliver(Widget sliver) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = _constrainedHorizontalPadding(
          constraints.crossAxisExtent,
        );
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: sliver,
        );
      },
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: context.theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }

  String _buildZipFileName() {
    final rawName = _title.trim().isEmpty ? _comicId : _title.trim();
    final safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_');
    return '$safeName.zip';
  }

  Future<String?> _pickExportDirectory() async => getDirectoryPath();

  Future<String?> _resolveExportDirectory() async {
    // iOS 无目录选择器，导出到缓存后通过系统分享面板保存
    if (Platform.isIOS) {
      return getCachePath();
    }
    final customPath = globalSetting.customExportPath.trim();
    if (customPath.isNotEmpty) {
      return customPath;
    }
    if (Platform.isAndroid) {
      final granted = await requestExportPermission();
      if (!granted) {
        throw StateError(t.comicInfo.exportPermissionDenied);
      }
      return createDownloadDir();
    }
    return _pickExportDirectory();
  }

  void _logExportPath(String path) {
    if (!(Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux)) {
      return;
    }

    final displayPath = Platform.isAndroid
        ? _simplifyAndroidPathForLog(path)
        : path;
    logger.d('Exported comic path: $displayPath');
  }

  String _simplifyAndroidPathForLog(String path) {
    final normalized = path.replaceAll('\\', '/');
    final downloadIndex = normalized.indexOf('/Download/');
    if (downloadIndex >= 0) {
      return normalized.substring(downloadIndex + 1);
    }
    return normalized;
  }

  String? _formatExportDirectory(String exportedPath, ExportType exportType) {
    if (!(Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux)) {
      return null;
    }

    final exportDirectory = exportType == ExportType.zip
        ? p.dirname(exportedPath)
        : exportedPath;
    final displayPath = Platform.isAndroid
        ? _simplifyAndroidPathForLog(exportDirectory)
        : exportDirectory;
    return t.comicInfo.exportDirectory(displayPath: displayPath);
  }

  // 导出逻辑
  Future<void> _handleExport() async {
    try {
      if (!mounted) return;

      // iOS 不提供「导出后删除」：分享面板返回时文件是否已存下来并不可知。
      final choice = Platform.isIOS
          ? const ExportChoice(type: ExportType.zip, deleteAfterExport: false)
          : await showExportChoiceDialog(
              context,
              title: t.comicInfo.exportTitle,
              subtitle: t.comicInfo.exportSubtitle,
            );
      if (choice == null) return;
      final exportType = choice.type;

      final exportDir = await _resolveExportDirectory();
      if (exportDir == null) return;

      final zipFileName = _buildZipFileName();
      final targetZipPath = p.join(exportDir, zipFileName);

      if (Platform.isIOS) {
        // 不写入 cacheZipPath：open_file 在分享面板弹出后即返回，
        // finally 里删除会导致用户还没保存文件就被删掉。
        final iosZipPath = targetZipPath;
        final iosZipFile = File(iosZipPath);
        if (await iosZipFile.exists()) {
          await iosZipFile.delete();
        }

        await exportComic(
          _comicId,
          ExportType.zip,
          widget.from,
          path: iosZipPath,
        );

        // 弹出系统分享面板，用户可「存储到文件」
        await OpenFile.open(iosZipPath);
        showSuccessToast(t.comicInfo.exportSuccess);
        _logExportPath(iosZipPath);
        return;
      }

      final exportPath = exportType == ExportType.zip
          ? targetZipPath
          : exportDir;

      final result = await exportComicAndMaybeDelete(
        comicId: _comicId,
        type: exportType,
        from: widget.from,
        path: exportPath,
        deleteAfterExport: choice.deleteAfterExport,
      );
      _logExportPath(result.export.path);
      _showExportOutcome(result, exportType: exportType);
      if (result.deleted && _type == ComicEntryType.download && mounted) {
        actionBack(context);
      }
    } catch (e) {
      final errorMessage = e is StateError
          ? e.message.toString()
          : t.comicInfo.exportFailedWithError(
              error: normalizeSearchErrorMessage(e),
            );
      showErrorToast(errorMessage, duration: const Duration(seconds: 5));
    }
  }

  /// 一条 toast 说完「导到哪了」和「删了没、为什么没删」。
  ///
  /// 提示条同屏有上限（超出挤掉最旧的），而网关对「同事项 + 同标题 + 同正文」
  /// 在窗口内只放行一条 —— 所以这里必须合起来发一次，分两条发会有可能看不见第二条。
  void _showExportOutcome(
    ExportWithDeleteResult result, {
    required ExportType exportType,
  }) {
    final outcome = _deleteOutcomeLine(result);
    final pathLine = _formatExportDirectory(result.export.path, exportType);
    final lines = <String>[?pathLine, ?outcome];
    if (lines.isEmpty) return;

    final message = lines.join('\n');
    if (result.outcome != ExportDeleteOutcome.notRequested && !result.deleted) {
      showErrorToast(message, duration: const Duration(seconds: 6));
    } else {
      showInfoToast(message, duration: const Duration(seconds: 6));
    }
  }

  /// 勾选了「导出后删除」时的结论；没勾选则返回 null。
  String? _deleteOutcomeLine(ExportWithDeleteResult result) {
    switch (result.outcome) {
      case ExportDeleteOutcome.notRequested:
        return null;
      case ExportDeleteOutcome.deleted:
        return t.comicInfo.exportedAndDeleted(title: result.export.title);
      case ExportDeleteOutcome.incomplete:
        if (result.export.exportedPages == 0) {
          return t.comicInfo.exportDeleteSkippedEmpty;
        }
        return t.comicInfo.exportDeleteSkippedIncomplete(
          count: result.export.missingPages,
          chapters: result.export.missingChapters.join(', '),
        );
      case ExportDeleteOutcome.artifactInvalid:
        return t.comicInfo.exportDeleteSkippedArtifact;
      case ExportDeleteOutcome.insideDownloadRoot:
        return t.comicInfo.exportDeleteSkippedInsideRoot;
      case ExportDeleteOutcome.deleteFailed:
        return t.comicInfo.exportDeleteFailed(
          error: result.deleteError?.toString() ?? '',
        );
    }
  }

  // 切换章节列表的倒序/正序显示
  void _toggleOrder() => setState(() => _isReversed = !_isReversed);

  /// 章节计数文案：只显示总数 `N 话`。各组明细已在组头上（`组名 · N 话`），
  /// 头部 badge 不再重复，窄屏下省位置。
  String _chapterCountLabel(List<dynamic> displayEps) {
    return t.comicInfo.episodeCount(count: displayEps.length);
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    final info = _currentInfo;
    if (info == null) {
      showErrorToast(t.comicInfo.detailsNotLoaded);
      return;
    }

    if (isFollowing) {
      await _confirmAndRemoveFollow(info.comicInfo.title);
      return;
    }

    await context.read<ComicFollowCubit>().addOrUpdateFollow(
      source: widget.from,
      comicId: _comicId,
      info: info,
      lastChapterCount: info.eps.length,
    );
    if (mounted) {
      showSuccessToast(t.comicInfo.followed);
    }
  }

  Future<void> _toggleFollowFromMenu() async {
    final info = _currentInfo;
    if (info == null) {
      showErrorToast(t.comicInfo.detailsNotLoaded);
      return;
    }
    final isFollowing = context.read<ComicFollowCubit>().isFollowing(
      widget.from,
      _comicId,
    );
    await _toggleFollow(isFollowing);
  }

  Future<void> _autoFollowIfEnabled() async {
    if (!context.read<GlobalSettingCubit>().state.autoFollowOnCollect) {
      return;
    }
    final info = _currentInfo;
    if (info == null) {
      return;
    }
    final followCubit = context.read<ComicFollowCubit>();
    if (followCubit.isFollowing(widget.from, _comicId)) {
      return;
    }
    await followCubit.addOrUpdateFollow(
      source: widget.from,
      comicId: _comicId,
      info: info,
      lastChapterCount: info.eps.length,
    );
  }

  Future<void> _confirmAndRemoveFollow(String title) async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) => PopupPanel(
        title: Text(t.comicInfo.confirmUnfollowTitle),
        content: Text(t.comicInfo.confirmUnfollowContent(title: title)),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(true),
            child: Text(t.common.ok),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await context.read<ComicFollowCubit>().removeFollow(widget.from, _comicId);
    if (mounted) {
      showSuccessToast(t.comicInfo.unfollowed);
    }
  }

  List<UnifiedComicListItem> _resolveRecommendItems(List<Recommend> recommend) {
    return recommend
        .map((item) {
          // 优先使用 extern 中的 unifiedItem
          final unifiedJson = asJsonMap(item.extern)['unifiedItem'];
          if (unifiedJson != null) return asJsonMap(unifiedJson);

          // 否则从 Recommend 对象构造 JSON
          return item.toJson();
        })
        .where((json) => json.isNotEmpty)
        .map(UnifiedComicListItem.fromJson)
        .toList();
  }

  Future<void> _syncLocalCollectStatus(NormalComicAllInfo info) async {
    // 同一部漫画只同步一次本地收藏状态，避免每次重建都查询数据库
    final comicId = info.comicInfo.id;
    if (_localCollectSyncedFor == comicId) {
      return;
    }
    _localCollectSyncedFor = comicId;
    final collected = await isLocalComicCollected(
      from: widget.from,
      comicId: comicId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isLocalCollected = collected;
    });
  }

  Future<void> _toggleLocalCollectFromMenu() async {
    final info = _currentInfo;
    if (info == null) {
      showErrorToast(t.comicInfo.detailsNotLoaded);
      return;
    }
    try {
      // 取消收藏需要确认，因为会删除所有文件夹中的记录
      if (_isLocalCollected) {
        final confirmed = await _showLocalUncollectConfirmDialog();
        if (!confirmed) {
          return;
        }
      }

      final next = await toggleLocalComicFavorite(
        from: widget.from,
        normalInfo: info,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLocalCollected = next;
      });
      if (next) {
        await _autoFollowIfEnabled();
      }
      showSuccessToast(
        next
            ? t.comicInfo.addedToCollection
            : t.comicInfo.removedFromCollection,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showErrorToast(
        t.comicInfo.localCollectFailed(error: normalizeSearchErrorMessage(e)),
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<bool> _showLocalUncollectConfirmDialog() async {
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

  Future<void> _toggleCloudCollectFromMenu() async {
    final info = _currentInfo;
    if (info == null) {
      showErrorToast(t.comicInfo.detailsNotLoaded);
      return;
    }
    try {
      showInfoToast(
        _isCloudCollected
            ? t.comicInfo.removingCloudCollection
            : t.comicInfo.collectingToCloud,
      );
      final next = await toggleCloudComicFavorite(
        context: context,
        from: widget.from,
        comicId: info.comicInfo.id,
        currentStatus: _isCloudCollected,
        legacyAllowCollected: info.allowCollected,
        legacyAllowCollectedReason: info.allowCollectedReason,
        collectionTargetId: widget.collectionTargetId,
        collectionTargetName: widget.collectionTargetName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isCloudCollected = next;
        _cloudFavoriteStateOverridden = true;
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
    } catch (e) {
      showErrorToast(
        normalizeSearchErrorMessage(e),
        duration: const Duration(seconds: 5),
      );
    }
  }

  void _updateChapterGroups(VoidCallback update) => setState(update);
}
