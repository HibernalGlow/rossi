/// 所有可自定义菜单的**注册表** —— 设置页与「自定义此菜单…」共用。
///
/// 放在 UI 层（而不是 `lib/model/context_menu/`）是刻意的：每个 scope 的文案
/// 要 `t.*`，而 `lib/model/` 那一层必须保持纯 Dart、能被 `dart run` 直接跑。
///
/// 新增菜单时在这里登记一条：定义（预览用，全部可用）+ 标题 + 单行文案。
/// 预览定义只影响设置页里能看到哪些项，不影响真实菜单的 enabled/danger。
library;

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/page/bookshelf/model/folder_menu_definitions.dart';
import 'package:zephyr/page/comic_info/models/comic_info_link_menu_definition.dart';
import 'package:zephyr/widgets/plat/rossi_plat_tab_menu.dart';
import 'package:zephyr/workspace/model/card_menu_definition.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_definition.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/file_manager_tab_menu_definition.dart';
import 'package:zephyr/workspace/model/lane_menu_definition.dart';
import 'package:zephyr/workspace/model/panel_tab_menu_definition.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_definition.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';

/// 一个菜单在设置界面的呈现。
class ContextMenuScopeDescriptor {
  const ContextMenuScopeDescriptor({
    required this.definition,
    required this.title,
    required this.labelOf,
  });

  /// 预览定义：条目齐全、全部可用，用来摆顺序与显隐。
  final ContextMenuDefinition definition;

  /// 设置页里的标题（「书架条目」）。
  final String title;

  /// 这一项叫什么。真实菜单的文案可能随条目状态变（「继续阅读」/「收藏」），
  /// 设置页用预览输入的措辞即可。
  final String Function(ContextMenuEntryDefinition entry) labelOf;
}

/// 预览用的收藏/历史输入：两条只在历史卡出现的项也摆出来。
const ShelfEntryMenuInput _shelfPreview = ShelfEntryMenuInput(
  kind: ShelfEntryKind.history,
  canOpenInFileManagerTab: true,
);

/// 预览用的文件管理器输入：目录、可写、可粘贴、可收藏 —— 让所有项都可用。
const FileManagerEntryMenuInput _fileManagerPreview = FileManagerEntryMenuInput(
  isDirectory: true,
  canOpen: true,
  canCreateFolder: true,
  canPaste: true,
  canReveal: true,
  canFavorite: true,
);

List<ContextMenuScopeDescriptor> contextMenuScopeCatalog() {
  final shelfDefinition = buildShelfMenuDefinition(_shelfPreview);
  final fileManagerDefinition = buildFileManagerMenuDefinition(
    _fileManagerPreview,
  );

  return <ContextMenuScopeDescriptor>[
    ContextMenuScopeDescriptor(
      definition: shelfDefinition,
      title: t.contextMenu.scopeShelf,
      labelOf: (entry) => shelfEntryActionLabel(
        shelfEntryActionOfId(entry.id),
        kind: _shelfPreview.kind,
        isFavorite: _shelfPreview.isFavorite,
      ),
    ),
    ContextMenuScopeDescriptor(
      definition: fileManagerDefinition,
      title: t.contextMenu.scopeFileManager,
      labelOf: (entry) => fileManagerEntryActionLabel(
        fileManagerActionOfId(entry.id),
        input: _fileManagerPreview,
      ),
    ),
    ContextMenuScopeDescriptor(
      definition: folderMenuDefinition,
      title: t.contextMenu.scopeFolder,
      labelOf: (entry) => switch (entry.id) {
        'folder.rename' => t.common.rename,
        'folder.moveTo' => t.bookshelf.moveTo,
        _ => t.common.delete,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: folderComicMenuDefinition,
      title: t.contextMenu.scopeFolderComic,
      labelOf: (entry) => switch (entry.id) {
        'folderComic.multiSelect' => t.bookshelf.multiSelect,
        _ => t.common.delete,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: comicInfoLinkMenuDefinition,
      title: t.contextMenu.scopeComicInfoLink,
      labelOf: (entry) => switch (entry.id) {
        'comicInfoLink.openExternal' => t.webview.openInExternalBrowser,
        _ => t.common.copy,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: buildPlatTabMenuDefinition(rail: false, hasClose: true),
      title: t.contextMenu.scopePlatTab,
      labelOf: (entry) => switch (entry.id) {
        'platTab.above' => rossiPlatMenuLabel(RossiPlatMenuLabel.above),
        'platTab.below' => rossiPlatMenuLabel(RossiPlatMenuLabel.below),
        'platTab.leftOf' => rossiPlatMenuLabel(RossiPlatMenuLabel.leftOf),
        'platTab.rightOf' => rossiPlatMenuLabel(RossiPlatMenuLabel.rightOf),
        _ => t.plat.closeTab,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: fileManagerTabMenuDefinition,
      title: t.contextMenu.scopeFileManagerTab,
      labelOf: (entry) => switch (entry.id) {
        'fileManagerTab.pin' => t.workspace.pinTab,
        'fileManagerTab.newTab' => t.workspace.newFromThisTab,
        'fileManagerTab.duplicate' => t.workspace.duplicateTab,
        'fileManagerTab.close' => t.workspace.closeTab,
        'fileManagerTab.closeOthers' => t.workspace.closeOtherTabs,
        'fileManagerTab.closeLeft' => t.workspace.closeTabsLeft,
        _ => t.workspace.closeTabsRight,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: panelTabMenuDefinition,
      title: t.contextMenu.scopePanelTab,
      labelOf: (entry) => switch (entry.id) {
        'panelTab.pin' => t.workspace.pinHere,
        'panelTab.constrain' => t.workspace.confineToThisLane,
        'panelTab.sortMode' => t.workspace.sortMode,
        'panelTab.dockLeft' => t.workspace.dockToLabel(
          label: t.contextMenu.dockLeft,
        ),
        'panelTab.dockRight' => t.workspace.dockToLabel(
          label: t.contextMenu.dockRight,
        ),
        'panelTab.dockTop' => t.workspace.dockToLabel(
          label: t.contextMenu.dockTop,
        ),
        _ => t.workspace.dockToLabel(label: t.contextMenu.dockBottom),
      },
    ),
    ContextMenuScopeDescriptor(
      definition: buildLaneMenuDefinition(hasPanelSide: true),
      title: t.contextMenu.scopeLane,
      labelOf: (entry) => switch (entry.id) {
        'lane.panelEditMode' => t.workspace.editLayout,
        'lane.solo' => t.workspace.soloThisLane,
        'lane.collapse' => t.workspace.collapseToBar,
        'lane.width' => t.workspace.regularWidth,
        'lane.panelBar' => t.workspace.panelBarHint,
        'lane.widthBadge' => t.contextMenu.widthBadge,
        'lane.topChrome' => t.workspace.showWorkspaceTopBar,
        _ => t.workspace.exitWorkspace,
      },
    ),
    ContextMenuScopeDescriptor(
      definition: buildCardMenuDefinition(
        canEditLayout: true,
        canFill: true,
        canResize: true,
        hasHide: true,
        hiddenCardIds: const <String>[],
      ),
      title: t.contextMenu.scopeCard,
      labelOf: (entry) => switch (entry.id) {
        'card.toggle' => t.contextMenu.toggleCard,
        'card.editLayout' => t.workspace.editLayout,
        'card.fill' => t.workspace.fullWidthFullHeight,
        'card.preset1x1' => '1×1',
        'card.preset2x1' => '2×1',
        'card.preset2x2' => '2×2',
        'card.presetFull' => t.workspace.fullWidth,
        _ => t.workspace.collapseFromPanel,
      },
    ),
  ];
}

/// 按 scope 找一条登记；找不到返回 null（调用方决定回退到哪里）。
ContextMenuScopeDescriptor? contextMenuScopeOf(String scope) {
  for (final descriptor in contextMenuScopeCatalog()) {
    if (descriptor.definition.scope == scope) return descriptor;
  }
  return null;
}
