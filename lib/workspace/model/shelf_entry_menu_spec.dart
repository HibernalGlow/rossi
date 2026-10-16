// 书签（收藏）/ 阅读历史卡片条目的**右键菜单规格** —— 纯 Dart，不 import Flutter。
//
// 判据：`dart run test/workspace/shelf_entry_menu_check.dart`
//
// 为什么抽出来：这份判断决定「右键点出来有哪些项、哪一项是灰的」，
// 而它错的方式**全是静默的** —— 少一项、把不能用的项画成可用、破坏性动作
// 混在普通动作里。界面上不报错，只是「点了没反应」或者「一下子删掉了」。
// 本机的 `flutter test` 要拖起整棵工作台（objectbox 基线红），所以把
// 「有哪些项 / 哪一项可用 / 这条漫画在文件管理里该开哪个目录」收成纯函数，
// 用 `dart run` 直接断言。
//
// 对照 neoview：`features/panels/cards/bookmark/BookmarkContextActions.tsx` 与
// `features/panels/cards/history/HistoryContextActions.tsx` 里的
// `build*ContextMenuItems`。差别只有一处：neo 的条目是**文件系统上的路径**，
// 所以「在新标签页打开」= 在资源管理器里开那个文件夹；rossi 的条目是**漫画**，
// 于是它落在「文件管理面板新开一个页签、指到这条漫画所在的目录」（本地漫画），
// 插件漫画没有本地目录 ⇒ 那一项置灰而不是隐藏（隐藏会让人以为没这功能）。
//
// ignore_for_file: avoid_print

export 'package:zephyr/workspace/model/file_manager_tab_target.dart';

/// 右键菜单作用的条目类型。
///
/// 两者的菜单**不是同一份**：收藏卡上的「移除」就是取消收藏，「收藏」那一项
/// 只该出现在历史卡上（在收藏卡上给自己收藏是本末倒置）。
enum ShelfEntryKind {
  /// 收藏（书签）卡片。
  favorite,

  /// 阅读历史卡片。
  history,
}

/// 菜单里的一个动作。UI 层负责把它翻译成图标 + 文案。
enum ShelfEntryAction {
  /// 打开：本地漫画直进阅读器，插件漫画进详情页（分岔在 `openComicItem`）。
  open,

  /// 在文件管理面板的**新页签**里打开这条漫画所在的目录。
  openInFileManagerTab,

  copyTitle,
  copyLink,

  /// 收藏 / 取消收藏。只出现在历史卡上（见 [ShelfEntryKind]）。
  toggleFavorite,

  /// 从这张卡里移除：收藏卡 = 取消收藏，历史卡 = 从历史记录移除。
  remove,
}

/// 一个菜单项**规格**：只说「是哪个动作、能不能点、是不是破坏性的」。
///
/// 不含图标与文案 —— 那两样要 Flutter 的 `Glyph` 与 slang 的 `t`，
/// 放进来这份文件就不能被 `dart run` 直接跑了。
class ShelfEntryMenuItemSpec {
  final ShelfEntryAction action;

  /// 不可用（画成灰的、点了不响应）。
  final bool enabled;

  /// 破坏性动作：UI 要画危险色**并且**先弹二次确认。
  ///
  /// 这两件事必须由同一个布尔驱动：只上色不确认等于没保护，
  /// 只确认不上色则用户点下去才知道是删。
  final bool destructive;

  const ShelfEntryMenuItemSpec({
    required this.action,
    this.enabled = true,
    this.destructive = false,
  });

  @override
  String toString() =>
      '${action.name}(enabled=$enabled, destructive=$destructive)';
}

/// 造菜单需要的全部输入 —— **没有一件是从 widget 里现推的**，
/// 调用方必须自己把答案查好了再传进来（尤其是 [isFavorite] 要查库）。
class ShelfEntryMenuInput {
  final ShelfEntryKind kind;

  /// 这条目的打开链路可用吗。目前恒为 `true`（本地与插件都有打开方式），
  /// 留成字段是为了让「以后某天这条条目打不开」时有一个**唯一**的置灰入口，
  /// 而不是在各处 `if` 里长出第二套判断。
  final bool canOpen;

  /// 能在文件管理里新开页签吗。
  ///
  /// 判据只有一条：[resolveFileManagerTabPath] 解得出一条本地目录（插件漫画
  /// 没有磁盘位置）。**不**把「文件管理面板当前活着」也并进来：面板没开过是
  /// 可以现场补的（动作会先把右泳道切过去、再等卡片建会话），把它算进可用性
  /// 只会让「第一次点这一项永远是灰的」。
  final bool canOpenInFileManagerTab;

  /// 这条目当前是否已在收藏里（历史卡用它决定显示「收藏」还是「已在收藏中」）。
  final bool isFavorite;

  const ShelfEntryMenuInput({
    required this.kind,
    this.canOpen = true,
    this.canOpenInFileManagerTab = false,
    this.isFavorite = false,
  });
}

/// 按条目类型造出完整菜单。次序与 neoview 对齐：**动作 → 复制 → 破坏性**，
/// 破坏性那一条永远在最后（避免手指/指针滑一下就点到）。
List<ShelfEntryMenuItemSpec> buildShelfEntryMenuItems(
  ShelfEntryMenuInput input,
) {
  return <ShelfEntryMenuItemSpec>[
    ShelfEntryMenuItemSpec(
      action: ShelfEntryAction.open,
      enabled: input.canOpen,
    ),
    ShelfEntryMenuItemSpec(
      action: ShelfEntryAction.openInFileManagerTab,
      enabled: input.canOpenInFileManagerTab,
    ),
    const ShelfEntryMenuItemSpec(action: ShelfEntryAction.copyTitle),
    const ShelfEntryMenuItemSpec(action: ShelfEntryAction.copyLink),
    if (input.kind == ShelfEntryKind.history)
      // 已经在收藏里就不再提供「收藏」—— 重复点它只会反复写同一个 key。
      ShelfEntryMenuItemSpec(
        action: ShelfEntryAction.toggleFavorite,
        enabled: !input.isFavorite,
      ),
    const ShelfEntryMenuItemSpec(
      action: ShelfEntryAction.remove,
      destructive: true,
    ),
  ];
}

/// 破坏性动作的**二次确认文案**该问哪一句。
///
/// 收藏卡的「移除」与历史卡的「移除」删的是**两件不同的东西**，问同一句话会
/// 让人以为要么都会被删、要么都不会。返回 `null` 表示这个动作不需要确认。
ShelfEntryKind? confirmKindFor(ShelfEntryAction action, ShelfEntryKind kind) {
  if (action != ShelfEntryAction.remove) return null;
  return kind;
}

// ── 路径解析 ────────────────────────────────────────────────────────────────

/// 「复制链接」复制出去的那一串。
///
/// 本地漫画就是它的磁盘路径（对用户直接可用）；插件漫画没有公开 URL，
/// 给**库内唯一标识** `来源:漫画id` —— 与 `UnifiedComicFavorite.uniqueKey`
/// 同形，粘回来能在库里定位到同一条。
String resolveShelfEntryLink({
  required String source,
  required String comicId,
}) {
  final from = source.trim();
  final id = comicId.trim();
  if (from.isEmpty) return id;
  if (from == 'local' || from == 'local_source') return id;
  return '$from:$id';
}
