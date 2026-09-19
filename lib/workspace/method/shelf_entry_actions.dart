import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/service/favorite_folder_service.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/service/file_manager_tab_bridge.dart';
import 'package:zephyr/widgets/toast.dart';

/// 收藏 / 历史卡片右键菜单里那些动作的**落地实现**。
///
/// 两张卡片各自拿着不同的 ObjectBox 实体（`UnifiedComicFavorite` /
/// `UnifiedComicHistory`），但动作本身是同一批：复制、在新页签打开、收藏、
/// 移除。把「怎么落地」收在这里，卡片那边只剩「选中了哪个动作」的分派 ——
/// 于是两处不会各写一套复制、各弹一种提示。
///
/// 菜单**有哪些项 / 哪一项可用**不在这里：那是纯逻辑，见
/// `lib/workspace/model/shelf_entry_menu_spec.dart`（判据
/// `dart run test/workspace/shelf_entry_menu_check.dart`）。

// ── 复制 ────────────────────────────────────────────────────────────────────

/// 复制标题。历史上「复制」这件事在这个仓里有三四种写法，这里统一成
/// `Clipboard.setData` + 一条成功提示（与 `particulars.dart` 里的一致）。
Future<void> copyShelfEntryTitle(
  BuildContext context, {
  required String title,
}) async {
  if (title.trim().isEmpty) return;
  await Clipboard.setData(ClipboardData(text: title));
  if (!context.mounted) return;
  showSuccessToast(t.shelfMenu.copiedTitle(title: title), context: context);
}

/// 复制链接。取值规则（本地给路径、插件给 `来源:漫画id`）在
/// [resolveShelfEntryLink] 里，那条规则有判据。
Future<void> copyShelfEntryLink(
  BuildContext context, {
  required String source,
  required String comicId,
}) async {
  final link = resolveShelfEntryLink(source: source, comicId: comicId);
  if (link.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  showSuccessToast(t.shelfMenu.copiedLink(link: link), context: context);
}

// ── 在文件管理的新页签里打开 ────────────────────────────────────────────────

/// 把这条漫画所在的**目录**交给文件管理面板，让它在**新页签**里打开。
///
/// 三步，顺序不能换：
///
/// 1. 解析目录（[resolveFileManagerTabPath]）—— 插件漫画没有磁盘位置，
///    这里直接提示而不是交给文件管理去撞一个错误；
/// 2. **先把右泳道切到文件管理面板** —— 面板很可能还停在「发现」上，卡片没建过，
///    也就没人接这次请求（`FileManagerTabBridge` 说得更细）。先切过去，卡片才会
///    挂载并建会话；
/// 3. 再请求新页签 —— 桥那边会等一小会儿（会话是异步建的），等不到就回
///    [FileManagerTabOpenOutcome.noSession]。
///
/// 只有第 3 步失败时才提示，且三种结局提示不同：`failed` 时卡片已经弹过**具体**
/// 原因，这里再补一句笼统的失败提示只会把用户从「知道原因」推回「什么都不知道」。
Future<void> openShelfEntryInFileManagerTab(
  BuildContext context, {
  required String comicId,
}) async {
  final path = resolveFileManagerTabPath(comicId);
  if (path == null) {
    showWarningToast(t.shelfMenu.fileManagerTabNoLocalPath, context: context);
    return;
  }

  // 卡片只住在工作台里（两侧注册表是唯一的构造点），所以这个 read 拿得到。
  context.read<WorkspaceCubit>().setActivePanel(
    WorkspacePanelSide.right.laneId,
    WorkspacePanelId.fileManager,
  );

  final outcome = await FileManagerTabBridge.instance.openInNewTab(path);
  if (!context.mounted) return;
  switch (outcome) {
    case FileManagerTabOpenOutcome.opened:
      showSuccessToast(
        path,
        title: t.shelfMenu.fileManagerTabOpened,
        context: context,
      );
    case FileManagerTabOpenOutcome.noSession:
      showErrorToast(t.shelfMenu.fileManagerTabUnavailable, context: context);
    case FileManagerTabOpenOutcome.failed:
      // 文件管理卡片已经弹过具体错误（只有那一层知道异常是什么）。
      break;
  }
}

// ── 破坏性动作的二次确认 ────────────────────────────────────────────────────

/// 「移除」的二次确认。返回 `true` = 用户确认了。
///
/// 收藏卡删的是**收藏记录**，历史卡删的是**阅读记录** —— 两件不同的事，
/// 所以问的也是两句不同的话（`confirmKindFor` 那条判据钉的就是这件事）。
Future<bool> confirmShelfEntryRemoval(
  BuildContext context, {
  required ShelfEntryKind kind,
  required String title,
}) async {
  final isFavorite = kind == ShelfEntryKind.favorite;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        isFavorite
            ? t.shelfMenu.removeFavoriteConfirmTitle
            : t.shelfMenu.removeHistoryConfirmTitle,
      ),
      content: Text(
        isFavorite
            ? t.shelfMenu.removeFavoriteConfirmBody(title: title)
            : t.shelfMenu.removeHistoryConfirmBody(title: title),
      ),
      actions: [
        TextButton(
          onPressed: () => dialogContext.pop(false),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => dialogContext.pop(true),
          child: Text(
            isFavorite ? t.shelfMenu.removeFavorite : t.shelfMenu.removeHistory,
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// ── 库侧读写 ────────────────────────────────────────────────────────────────
//
// 口径照抄既有的两条路径，不另立一套：
// - 移除：`page/bookshelf/widgets/local_shelf_page.dart` 的批量删除
//   （软删 + 摘掉文件夹成员关系 + 清掉跨文件夹链接）；
// - 加收藏：`page/comic_info/models/collect_comic.dart` 的字段映射。

/// 这条目当前在不在收藏里（按库内唯一键 `来源:漫画id`）。
///
/// 菜单打开的那一刻才查 —— 列表里每一条都提前查一遍属于「为一个可能永远不打开的
/// 菜单，把整张列表过一遍数据库」。
bool isShelfEntryFavorite(String uniqueKey) {
  if (uniqueKey.isEmpty) return false;
  final query = objectbox.unifiedFavoriteBox
      .query(UnifiedComicFavorite_.uniqueKey.equals(uniqueKey))
      .build();
  try {
    final found = query.findFirst();
    // 软删过的记录仍在库里，但它不算「已收藏」。
    return found != null && !found.deleted;
  } finally {
    query.close();
  }
}

/// 历史条目 → 收藏。
///
/// 直接把历史里已经存好的那些 JSON 串搬过去：历史记录写库时就已经把
/// `cover` / `creator` / `titleMeta` / `metadata` 存成了**与收藏同形的**字符串
/// （见 `reader_history_service.dart` 的 `_normalizeWorker*String`），所以这里
/// 不需要再去问一次图源 —— 离线也能收藏。
void addHistoryEntryToFavorites(UnifiedComicHistory item) {
  final now = DateTime.now().toUtc();
  final existing = objectbox.unifiedFavoriteBox
      .query(UnifiedComicFavorite_.uniqueKey.equals(item.uniqueKey))
      .build()
      .findFirst();

  objectbox.unifiedFavoriteBox.put(
    UnifiedComicFavorite(
      // 命中软删过的旧记录就复活它，别新建一条同 key 的 —— `uniqueKey` 上有
      // Unique 约束，重复写会抛。
      id: existing?.id ?? 0,
      uniqueKey: item.uniqueKey,
      source: item.source,
      comicId: item.comicId,
      title: item.title,
      description: item.description,
      cover: item.cover,
      creator: item.creator,
      titleMeta: item.titleMeta,
      metadata: item.metadata,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    ),
  );
}

/// 取消收藏：软删 + 摘掉它在所有收藏文件夹里的成员关系 + 清掉跨文件夹链接。
void removeShelfEntryFromFavorites(String uniqueKey) {
  final item = objectbox.unifiedFavoriteBox
      .query(UnifiedComicFavorite_.uniqueKey.equals(uniqueKey))
      .build()
      .findFirst();
  if (item == null) return;
  item.deleted = true;
  item.updatedAt = DateTime.now().toUtc();
  objectbox.unifiedFavoriteBox.put(item);
  FavoriteFolderService.removeMemberFromAllFolders(uniqueKey);
  ComicLinkService.removeComicFromAll(uniqueKey, ComicFolderType.favorite);
}

/// 从阅读历史移除：软删 + 清掉跨文件夹链接。
///
/// **只删记录，不碰源文件** —— 这条在确认对话框里也写明了
/// （见 [confirmShelfEntryRemoval]）。
void removeShelfEntryFromHistory(String uniqueKey) {
  final item = objectbox.unifiedHistoryBox
      .query(UnifiedComicHistory_.uniqueKey.equals(uniqueKey))
      .build()
      .findFirst();
  if (item == null) return;
  item.deleted = true;
  item.updatedAt = DateTime.now().toUtc();
  objectbox.unifiedHistoryBox.put(item);
  ComicLinkService.removeComicFromAll(uniqueKey, ComicFolderType.history);
}
