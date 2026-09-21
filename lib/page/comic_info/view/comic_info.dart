import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:zephyr/page/comic_info/widgets/comic_info_action_rail.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
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
import 'package:zephyr/widgets/toast.dart';

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
  final String comicId;
  final ComicEntryType type;
  final String from;
  final Map<String, dynamic>? extern;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const _ComicInfo({
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
  NormalComicAllInfo? _currentInfo;
  bool _isCloudCollected = false;
  bool _cloudFavoriteStateOverridden = false;
  bool _isLocalCollected = false;
  String _localCollectSyncedFor = '';

  @override
  void initState() {
    super.initState();
    _type = type;
    _comicId = widget.comicId;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 开启「优先云端收藏」后，页面收藏按钮与菜单项的本地/云端收藏行为互换
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final cloudFavoritePreferred = globalSetting.cloudFavoritePreferred;
    // 「阅读」入口只落一处：桌面端落进操作行（下载旁边），触摸端落右下角悬浮按钮。
    final readEntryPlacement = resolveComicInfoReadEntryPlacement(
      platform: defaultTargetPlatform,
      inlineReadEntryEnabled: globalSetting.comicInfoInlineReadButton,
    );
    final showInlineReadEntry =
        readEntryPlacement == ComicInfoReadEntryPlacement.inlineCard;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // 住在发现页的标签里时，这颗「返回」关的是**当前这条标签**。
          // context.pop() 走的是根路由：那一下弹掉的是压着详情页的那一页，
          // 在工作台里就是整个工作台。
          onPressed: () =>
              popTabOrClose(context, otherwise: () => context.pop()),
        ),
        actions: [
          const SizedBox(width: 50),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
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
                icon: Icon(
                  isFollowing
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                ),
                tooltip: isFollowing
                    ? t.comicInfo.unfollow
                    : t.comicInfo.follow,
                onPressed: () => _toggleFollow(isFollowing),
              );
            },
          ),
          FluentPopupMenuButton<MenuOption>(
            icon: const Icon(Icons.more_vert),
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
                  leading: Icon(
                    isFollowing
                        ? Icons.notifications_off
                        : Icons.notifications_active,
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
                    leading: const Icon(Icons.save_alt),
                    title: Text(t.comicInfo.exportComic),
                  ),
                );
              }

              menuItems.add(
                FluentPopupMenuItem<MenuOption>(
                  value: MenuOption.cloudCollect,
                  leading: Icon(
                    cloudFavoritePreferred
                        ? (_isLocalCollected ? Icons.star : Icons.star_border)
                        : (_isCloudCollected ? Icons.star : Icons.star_border),
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
        child: BlocBuilder<GetComicInfoBloc, GetComicInfoState>(
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
                        onPressed: () => popTabOrClose(
                          context,
                          otherwise: () => context.pop(),
                        ),
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
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      // 桌面上入口已经贴在操作行里（下载旁边），这里就撤掉 —— 两个入口并存会让人
      // 以为它们是两件事。触摸端（或开关关掉）仍旧是这颗悬浮按钮。
      floatingActionButton: (_loadingComplete && !showInlineReadEntry)
          ? BlocBuilder<StringSelectCubit, String>(
              builder: (context, stringSelectDate) {
                return _ReadActionButton(
                  hasHistory: stringSelectDate.isNotEmpty,
                  onPressed: () => _startReading(widget.type),
                );
              },
            )
          : null,
    );
  }

  /// 进阅读器：悬浮按钮与操作行里的「阅读」卡片共用的**唯一**一处入口。
  ///
  /// 参数口径与那颗悬浮按钮原本的写法（以及封面/「继续阅读」两处点击）一致：
  /// 传 `_comicId`（解析后的 id）。类型上悬浮按钮用 [widget.type]、封面点击用
  /// `_type` —— 两者原本就不同，这里不顺手改口径，只保证「同一类入口同一份参数」。
  void _startReading(ComicEntryType entryType) {
    goToComicRead(context, _comicId, entryType, comicInfoDyn, widget.from);
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
        icon: Icons.arrow_back,
        label: t.comicInfo.back,
        onTap: () => actionBack(context),
      ),
      ComicInfoActionEntry(
        actionId: ComicInfoActionIds.home,
        // 「返回首页」这条文案 reader 段里已有，不为了 rail 再造一个新键
        // （造键要重跑 slang，那是全仓共享的生成物）。
        icon: Icons.home_outlined,
        label: t.reader.backToHome,
        onTap: () => actionHome(context),
      ),
      // 没加载完就没有「这本书」，阅读那颗**不出现**（与那颗悬浮按钮同一口径），
      // 而不是画一颗永远点不动的。
      if (_loadingComplete)
        ComicInfoActionEntry(
          actionId: ComicInfoActionIds.read,
          icon: hasHistory ? Icons.history_rounded : Icons.menu_book_rounded,
          label: hasHistory ? t.comicInfo.continueRead : t.comicInfo.startRead,
          onTap: () => actionRead(context),
        ),
    ];
  }

  @override
  void actionBack(BuildContext context) =>
      // 与左上角那颗箭头**同一条**行为：住在标签里时关的是那条标签。
      popTabOrClose(context, otherwise: () => context.pop());

  @override
  void actionHome(BuildContext context) {
    final tabs = DiscoverTabScope.maybeOf(context);
    if (tabs != null) {
      tabs.goHome();
      return;
    }
    popToRoot(context);
  }

  @override
  void actionRead(BuildContext context) => _startReading(widget.type);

  /// 有指针 ⇒ 正文左右各浮一颗胶囊；触摸端原样返回（底部条是车道 G）。
  ///
  /// 判据用指针而不是视口宽度（口径 4）：带触摸屏的 Windows 笔记本仍然有指针，
  /// 「该不该省鼠标的路」取决于手上是什么，不取决于窗口多宽。
  ///
  /// 用 `Stack` + `Positioned` 而不是 `Row`：第一版用 Row 占了两列 52px，实机截图里
  /// 漫画正文被挤窄 104px、而那一列除了顶上两颗整截是空的。悬浮 = **不占布局宽度**，
  /// 正文该多宽还多宽。
  Widget _withActionRails({required Widget child}) {
    if (!comicInfoPlatformHasPointer(defaultTargetPlatform)) {
      return child;
    }
    final items = comicInfoActionItems();
    List<ComicInfoActionEntry> pick(List<String> ids) => [
      for (final id in ids)
        for (final item in items)
          if (item.actionId == id) item,
    ];

    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          // 垂直居中贴边：手/鼠标停在屏幕边上就能点，且上下都不挡正文标题与封面。
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: ComicInfoActionRail(
              scope: this,
              items: pick(const [
                ComicInfoActionIds.back,
                ComicInfoActionIds.home,
              ]),
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: ComicInfoActionRail(
              scope: this,
              items: pick(const [ComicInfoActionIds.read]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoView(
    NormalComicAllInfo normalComicAllInfo, {
    required bool showInlineReadEntry,
  }) {
    final comicInfo = normalComicAllInfo.comicInfo;
    _title = comicInfo.title;
    final clickCoverToStartReading = context
        .watch<GlobalSettingCubit>()
        .state
        .clickCoverToStartReading;

    if (!_loadingComplete) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _loadingComplete = true),
      );
    }

    var displayEps = List<dynamic>.from(normalComicAllInfo.eps);
    if (_isReversed) {
      displayEps = displayEps.reversed.toList();
    }

    final previewCapability = ComicPreviewCapability.fromInfo(
      normalComicAllInfo,
    );
    final showPreview =
        _type != ComicEntryType.download && previewCapability.enabled;

    return BlocSelector<StringSelectCubit, String, bool>(
      selector: (state) => state.isNotEmpty,
      builder: (context, hasHistory) {
        final refreshable = RefreshIndicator(
          onRefresh: () async {
            _type = ComicEntryType.normal;
            _isReversed = false;

            context.read<GetComicInfoBloc>().add(
              GetComicInfoEvent(
                comicId: _comicId,
                from: widget.from,
                type: _type,
                extern: widget.extern,
              ),
            );
            setState(() {
              _loadingComplete = false;
            });
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: _constrainedSliver(
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ComicParticularsWidget(
                          comicInfo: comicInfo,
                          from: widget.from,
                          type: _type,
                          onCoverTap: clickCoverToStartReading
                              ? () => _startReading(_type)
                              : null,
                          onContinueRead: hasHistory
                              ? () => _startReading(_type)
                              : null,
                        ),
                        _buildDivider(context),
                        ComicOperationWidget(
                          normalInfo: normalComicAllInfo,
                          from: widget.from,
                          collectionTargetId: widget.collectionTargetId,
                          collectionTargetName: widget.collectionTargetName,
                          comicInfo: comicInfoDyn,
                          hasHistory: hasHistory,
                          // 桌面端：贴上「下载」旁边的那张阅读卡片；
                          // 触摸端为空（悬浮按钮才是它的落点）。
                          onRead: showInlineReadEntry
                              ? () => _startReading(widget.type)
                              : null,
                        ),
                        if (comicInfo.metadata.isNotEmpty ||
                            comicInfo.description.trim().isNotEmpty) ...[
                          _buildDivider(context),
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final meta in comicInfo.metadata) ...[
                                  AllChipWidget(
                                    comicId: comicInfo.id,
                                    metadata: meta,
                                    from: widget.from,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (comicInfo.description.trim().isNotEmpty)
                                  _DescriptionCard(
                                    description: comicInfo.description.let(
                                      convertChineseForDisplay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (comicInfo.creator.name.trim().isNotEmpty ||
                            comicInfo.creator.avatar.url.trim().isNotEmpty) ...[
                          _buildDivider(context),
                          _SectionCard(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: CreatorInfoWidget(
                                  creator: comicInfo.creator,
                                  from: widget.from,
                                  imageKey: comicInfo.id,
                                ),
                              ),
                            ),
                          ),
                        ],
                        _buildDivider(context),
                        _SectionCard(
                          title: t.comicInfo.chapterList,
                          trailing: _EpisodeHeaderBadge(
                            label: t.comicInfo.episodeCount(
                              count: normalComicAllInfo.eps.length,
                            ),
                            icon: _isReversed ? Icons.south : Icons.north,
                            onTap: _toggleOrder,
                          ),
                          child: _EpisodeListSection(
                            episodes: displayEps,
                            allInfo: comicInfoDyn,
                            epsLength: normalComicAllInfo.eps.length,
                            type: _type,
                            comicId: _comicId,
                            from: widget.from,
                            isReversed: _isReversed,
                          ),
                        ),
                        if (normalComicAllInfo.recommend.isNotEmpty &&
                            _resolveRecommendItems(
                              normalComicAllInfo.recommend,
                            ).isNotEmpty) ...[
                          _buildDivider(context),
                          _SectionCard(
                            title: t.comicInfo.related,
                            child: RecommendWidget(
                              comicList: _resolveRecommendItems(
                                normalComicAllInfo.recommend,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (showPreview) ...[
                _constrainedSliver(const ComicPreviewSliver()),
              ],
              const SliverPadding(
                padding: EdgeInsets.only(bottom: 180),
                sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          ),
        );

        if (!showPreview) return refreshable;

        return BlocProvider(
          key: ValueKey('preview:${widget.from}:$_comicId'),
          create: (_) => ComicPreviewBloc(
            comicId: _comicId,
            from: widget.from,
            capability: previewCapability,
            extern: widget.extern ?? const <String, dynamic>{},
          )..add(const LoadComicPreview()),
          child: Builder(
            builder: (context) => NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent * 0.9) {
                  context.read<ComicPreviewBloc>().add(
                    const LoadComicPreview(loadMore: true),
                  );
                }
                return false;
              },
              child: refreshable,
            ),
          ),
        );
      },
    );
  }

  Widget _constrainedSliver(Widget sliver) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = ((constraints.crossAxisExtent - 1120) / 2)
            .clamp(20.0, double.infinity)
            .toDouble();
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

  Future<ExportType?> _pickExportType() async {
    if (Platform.isIOS) return ExportType.zip;

    return showDialog<ExportType>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(t.comicInfo.exportTitle),
          content: Text(t.comicInfo.exportSubtitle),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ExportType.folder),
              child: Text(t.comicInfo.folder),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ExportType.zip),
              child: Text(t.comicInfo.zip),
            ),
          ],
        );
      },
    );
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

  void _showExportDirectory(String exportedPath, ExportType exportType) {
    if (!(Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux)) {
      return;
    }

    final exportDirectory = exportType == ExportType.zip
        ? p.dirname(exportedPath)
        : exportedPath;
    final displayPath = Platform.isAndroid
        ? _simplifyAndroidPathForLog(exportDirectory)
        : exportDirectory;
    showInfoToast(
      t.comicInfo.exportDirectory(displayPath: displayPath),
      duration: const Duration(seconds: 5),
    );
  }

  // 导出逻辑
  Future<void> _handleExport() async {
    try {
      if (!mounted) return;

      final exportType = await _pickExportType();
      if (exportType == null) return;

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

      final exportedPath = await exportComic(
        _comicId,
        exportType,
        widget.from,
        path: exportPath,
      );
      _showExportDirectory(exportedPath, exportType);
      _logExportPath(exportedPath);
    } catch (e) {
      final errorMessage = e is StateError
          ? e.message.toString()
          : t.comicInfo.exportFailedWithError(
              error: normalizeSearchErrorMessage(e),
            );
      showErrorToast(errorMessage, duration: const Duration(seconds: 5));
    }
  }

  // 切换章节列表的倒序/正序显示
  void _toggleOrder() => setState(() => _isReversed = !_isReversed);

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    } on FavoriteWorkflowUnsupportedException {
      if (mounted) {
        showInfoToast(t.comicInfo.cloudCollectDisabled);
      }
    } on FavoriteWorkflowIncompleteException catch (error) {
      if (mounted) {
        showInfoToast(error.result.message ?? '云端收藏操作未完成');
      }
    } catch (e) {
      showErrorToast(t.error.operationFailed);
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title, this.trailing});

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: context.theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _EpisodeHeaderBadge extends StatelessWidget {
  const _EpisodeHeaderBadge({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: context.theme.colorScheme.outlineVariant.withValues(
                alpha: 0.3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: context.textColor.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.textColor.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final descriptionStyle = context.theme.textTheme.bodyMedium?.copyWith(
      height: 1.65,
      color: context.textColor.withValues(alpha: 0.9),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.comicInfo.description,
            style: context.theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SelectionArea(
            child: Text(
              widget.description,
              style: descriptionStyle,
              maxLines: _expanded ? null : 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.description.length > 90) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                _expanded ? t.comicInfo.collapse : t.comicInfo.expandFullText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeListSection extends StatelessWidget {
  const _EpisodeListSection({
    required this.episodes,
    required this.allInfo,
    required this.epsLength,
    required this.type,
    required this.comicId,
    required this.from,
    required this.isReversed,
  });

  final List<dynamic> episodes;
  final dynamic allInfo;
  final int epsLength;
  final ComicEntryType type;
  final String comicId;
  final String from;
  final bool isReversed;

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          t.comicInfo.noChapters,
          style: context.theme.textTheme.bodyMedium,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var i = 0; i < episodes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EpButtonWidget(
                    doc: episodes[i] as Ep,
                    allInfo: allInfo,
                    epsLength: epsLength,
                    type: type,
                    comicId: comicId,
                    from: from,
                    index: i,
                    isReversed: isReversed,
                  ),
                ),
            ],
          );
        }

        final isDesktop = constraints.maxWidth >= 960;
        if (isDesktop) {
          return Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < episodes.length; i++)
                  SizedBox(
                    width: 280,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: EpButtonWidget(
                        doc: episodes[i] as Ep,
                        allInfo: allInfo,
                        epsLength: epsLength,
                        type: type,
                        comicId: comicId,
                        from: from,
                        index: i,
                        isReversed: isReversed,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final isWide = constraints.maxWidth >= 720;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 2 : 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: EpButtonWidget.fixedHeight,
          ),
          itemBuilder: (context, index) {
            final e = episodes[index] as Ep;
            return EpButtonWidget(
              doc: e,
              allInfo: allInfo,
              epsLength: epsLength,
              type: type,
              comicId: comicId,
              from: from,
              index: index,
              isReversed: isReversed,
            );
          },
        );
      },
    );
  }
}

class _ReadActionButton extends StatelessWidget {
  const _ReadActionButton({required this.hasHistory, required this.onPressed});

  final bool hasHistory;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: Icon(
        hasHistory ? Icons.history_rounded : Icons.menu_book_rounded,
        size: 18,
      ),
      label: Text(
        hasHistory ? t.comicInfo.continueRead : t.comicInfo.startRead,
      ),
    );
  }
}
