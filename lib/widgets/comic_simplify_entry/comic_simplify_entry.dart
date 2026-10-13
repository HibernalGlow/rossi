import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart';

export 'package:zephyr/widgets/comic_simplify_entry/favorite_artist_badge.dart';
export 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart'
    show kComicCardBorderRadius;

class ComicFixedSizeHorizontalList extends StatelessWidget {
  final List<ComicSimplifyEntryInfo> entries;
  final double spacing; // 卡片之间的横向间距
  final double itemWidth; // 卡片固定宽度
  final bool roundedCorner; // 是否有圆角
  final bool useRandomImageKey;

  /// 封面左上角是否显示语言 / 汉化角标。默认开。
  ///
  /// 这是**页面级**开关；用户的**总开关**在「设置 → 书架 → 卡片角标」，
  /// 两者是「与」的关系（见 [ComicCardBadgePolicy]）。
  final bool showTranslationBadge;

  /// 封面右上角是否显示下载角标。默认开。语义同 [showTranslationBadge]。
  final bool showDownloadAction;

  /// 封面正中是否显示「直接阅读」按钮。默认开。语义同 [showTranslationBadge]。
  final bool showReadAction;

  const ComicFixedSizeHorizontalList({
    super.key,
    required this.entries,
    this.spacing = 10.0, // 默认间距设为 10
    this.itemWidth = 200, // 固定宽度，不随窗口宽高比变化
    this.roundedCorner = true,
    this.useRandomImageKey = false,
    this.showTranslationBadge = true,
    this.showDownloadAction = true,
    this.showReadAction = true,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    // 使用固定的宽高，避免在 Windows 桌面端拖动窗口时因
    // MediaQuery.orientation 随宽高比切换而导致高度跳变
    final double itemHeight = itemWidth / 0.75;

    // 最外层需要限制高度，否则横向 ListView 会报错
    return SizedBox(
      height: itemHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final info = entries[index];

          // 过滤无数据的情况
          if (info.title == "无数据") {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: EdgeInsets.only(right: spacing),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _navigateToComicInfo(context, info),
              child: SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _buildCoverWithTitle(
                  context,
                  info,
                  itemWidth,
                  itemHeight,
                  useRandomImageKey
                      ? ValueKey('cover-${const Uuid().v4()}')
                      : ValueKey('cover-${info.from}:${info.id}:${info.path}'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCoverWithTitle(
    BuildContext context,
    ComicSimplifyEntryInfo info,
    double width,
    double height,
    Key coverKey,
  ) => ComicCoverSurface(
    info: info,
    width: width,
    height: height,
    roundedCorner: roundedCorner,
    showDownloadAction: showDownloadAction,
    showTranslationBadge: showTranslationBadge,
    showReadAction: showReadAction,
    coverKey: coverKey,
  );

  // 点击跳转逻辑 (需要把当前的 info 传进来)
  void _navigateToComicInfo(BuildContext context, ComicSimplifyEntryInfo info) {
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    if (pluginId.isEmpty) return;
    if (isLocalComicSource(pluginId, info.id)) {
      context.pushRoute(
        ComicReadRoute(
          comicId: info.id,
          order: 0,
          from: 'local',
          epsNumber: 1,
          type: ComicEntryType.history,
          comicInfo: info.id,
          stringSelectCubit: StringSelectCubit(),
        ),
      );
      return;
    }
    // 发现页的标签体系里：详情开成**一条标签**，而不是压住标签条的一页。
    // 其余场合（书架、收藏、历史……）`maybeOf` 返回 null，行为逐字不变。
    final tabs = DiscoverTabScope.maybeOf(context);
    if (tabs != null) {
      tabs.openComicInfo(comicId: info.id, from: pluginId, title: info.title);
      return;
    }
    context.pushRoute(
      ComicInfoRoute(
        comicId: info.id,
        type: ComicEntryType.normal,
        from: pluginId,
      ),
    );
  }
}

class ComicSimplifyEntry extends StatelessWidget {
  final ComicSimplifyEntryInfo info;
  final ComicEntryType type;
  final VoidCallback? refresh;
  final ValueChanged<String>? onDeleteSuccess;
  final ValueChanged<ComicSimplifyEntryInfo>? onTapOverride;
  final void Function(
    ComicSimplifyEntryInfo info,
    LongPressStartDetails details,
  )?
  onLongPressOverride;
  final void Function(ComicSimplifyEntryInfo info, TapDownDetails details)?
  onSecondaryTapDown;
  final bool isSelected;
  final bool selectionMode;
  final bool topPadding;
  final bool roundedCorner;

  /// 封面右上角是否显示下载角标。默认开：看到喜欢的可以直接下载，
  /// 不用先点进详情页。本地漫画与多选模式会自动隐藏（见 `_buildCoverWithTitle`）。
  final bool showDownloadAction;

  /// 封面左上角是否显示语言 / 汉化角标。默认开。
  ///
  /// 判定只吃插件给的标签与标题（`ComicSimplifyEntryInfo.tags`），
  /// 所以插件没给语言线索时**本来就不会显示**（不是坏了）。
  final bool showTranslationBadge;

  /// 封面正中是否显示「直接阅读」按钮。默认开：下载过 / 本地有的书，
  /// 点封面进详情页只是多一步。多选模式下自动隐藏（同 [showDownloadAction] 的让位规矩）。
  final bool showReadAction;

  /// 这本书是否「已下载但还没读过」，决定封面右上角那颗未读圆点。
  ///
  /// 由调用方批量算好再传进来（见 `FolderShelfState.unreadComicKeys`）：
  /// 卡片自己查库的话，一屏几十张卡就是几十次查询。
  final bool unread;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const ComicSimplifyEntry({
    super.key,
    required this.info,
    required this.type,
    this.refresh,
    this.onDeleteSuccess,
    this.onTapOverride,
    this.onLongPressOverride,
    this.onSecondaryTapDown,
    this.isSelected = false,
    this.selectionMode = false,
    this.topPadding = true,
    this.roundedCorner = true,
    this.showDownloadAction = true,
    this.showTranslationBadge = true,
    this.showReadAction = true,
    this.unread = false,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  /// 展墙等呈现层复用原卡片的来源判断、发现页签与合集目标导航。
  void openDetails(BuildContext context) => _navigateToComicInfo(context);

  @override
  Widget build(BuildContext context) {
    if (info.title == "无数据") {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width / 0.75;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final onTapHandler = onTapOverride;
            if (onTapHandler != null) {
              onTapHandler(info);
              return;
            }
            _navigateToComicInfo(context);
          },
          onLongPressStart: (details) {
            final onLongPressHandler = onLongPressOverride;
            if (onLongPressHandler != null) {
              onLongPressHandler(info, details);
              return;
            }
            if (type != ComicEntryType.normal) {
              _showDeleteDialog(context);
            }
          },
          onSecondaryTapDown: (details) {
            onSecondaryTapDown?.call(info, details);
          },
          child: SizedBox(
            width: width,
            height: height,
            child: _buildCoverWithTitle(context, width, height),
          ),
        );
      },
    );
  }

  Widget _buildCoverWithTitle(
    BuildContext context,
    double width,
    double height,
  ) => ComicCoverSurface(
    info: info,
    width: width,
    height: height,
    roundedCorner: roundedCorner,
    showDownloadAction: showDownloadAction,
    showTranslationBadge: showTranslationBadge,
    showReadAction: showReadAction,
    isSelected: isSelected,
    selectionMode: selectionMode,
    unread: unread,
  );

  void _navigateToComicInfo(BuildContext context) {
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    if (pluginId.isEmpty) return;

    // 本地来源必须绕开详情页 —— 与上方 [ComicFixedSizeHorizontalList] 的同名方法、
    // 以及 [ComicEntryWidget] 的分支保持一致。
    //
    // 本地漫画的 `source` 是 `local`、`id` 是文件路径，它**没有插件**。送进
    // [ComicInfoRoute] 会被详情页当成「插件 id = local」去问 qjs 运行时，
    // 得到 `plugin_not_found:local`；这在界面上只会显示成一句「加载失败，请重试。」
    // （历史上还会被错误处理改写成一句类型转换错误）。本地漫画直接进阅读器。
    if (isLocalComicSource(pluginId, info.id)) {
      context.pushRoute(
        ComicReadRoute(
          comicId: info.id,
          order: 0,
          from: 'local',
          epsNumber: 1,
          type: type == ComicEntryType.normal
              ? ComicEntryType.normal
              : ComicEntryType.history,
          comicInfo: info.id,
          stringSelectCubit: StringSelectCubit(),
        ),
      );
      return;
    }

    // 发现页的标签体系里：详情开成**一条标签**（收藏目标一并带过去，
    // 详情页那颗「收进合集」的按钮才不会失联）。
    final tabs = DiscoverTabScope.maybeOf(context);
    if (tabs != null) {
      tabs.openComicInfo(
        comicId: info.id,
        from: pluginId,
        title: info.title,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      );
      return;
    }

    context.pushRoute(
      ComicInfoRoute(
        comicId: info.id,
        type: type,
        from: pluginId,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final (title, content) = _getDialogContent();

    return showPopupPanel(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (context) => PopupPanel(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () {
              context.router.pop();
              _handleDeleteAction(context);
            },
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
  }

  (String, String) _getDialogContent() {
    logger.d(type);
    switch (type) {
      case ComicEntryType.favorite:
        return (
          t.comicEntry.deleteFavorite,
          t.comicEntry.deleteFavoriteConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      case ComicEntryType.history:
        return (
          t.comicEntry.deleteHistory,
          t.comicEntry.deleteHistoryConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      case ComicEntryType.download:
        return (
          t.comicEntry.deleteDownload,
          t.comicEntry.deleteDownloadConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      default:
        return ("", "");
    }
  }

  Future<void> _handleDeleteAction(BuildContext context) async {
    try {
      if (type == ComicEntryType.history) {
        await _deleteHistory();
      } else if (type == ComicEntryType.download) {
        await _deleteDownload();
      } else if (type == ComicEntryType.favorite) {
        await _deleteFavorite();
      }
      final deletedKey = '${info.from.trim()}:${info.id}';
      if (onDeleteSuccess != null) {
        onDeleteSuccess!(deletedKey);
      } else {
        refresh?.call();
      }
    } catch (e, s) {
      logger.e('删除失败', error: e, stackTrace: s);
      showErrorToast(t.comicEntry.deleteFailed);
    }
  }

  Future<void> _deleteHistory() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
    final temp = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      temp.deleted = true;
      temp.updatedAt = DateTime.now().toUtc();
      objectbox.unifiedHistoryBox.put(temp);
    }
  }

  Future<void> _deleteDownload() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
    final temp = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      objectbox.unifiedDownloadBox.remove(temp.id);
      await _deleteDownloadDirectory(info.id);
    }
  }

  Future<void> _deleteFavorite() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
    final temp = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      temp.deleted = true;
      temp.updatedAt = DateTime.now().toUtc();
      objectbox.unifiedFavoriteBox.put(temp);
    }
  }

  Future<void> _deleteDownloadDirectory(String id) async {
    try {
      await deleteComicDownloadDirectory(info.from, id);
      logger.d('目录已成功删除: $id');
    } catch (e) {
      logger.e('删除目录时发生错误: $e');
      throw Exception('删除目录失败');
    }
  }
}
