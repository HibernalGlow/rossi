// 本地书架（文件夹 / 文件夹内漫画）右键菜单的定义。
//
// id 是持久化契约，改名等于丢用户偏好。这里不标 dangerous：迁移前这两个
// 删除项就是普通色，确认框在动作里（`_confirmDeleteSingleFolder` /
// `_confirmRemoveComic`）—— 统一模型不该顺带改观感。

import 'package:zephyr/model/context_menu/context_menu.dart';

const ContextMenuDefinition folderMenuDefinition = ContextMenuDefinition(
  scope: 'folder',
  entries: <ContextMenuEntryDefinition>[
    ContextMenuEntryDefinition(id: 'folder.rename'),
    ContextMenuEntryDefinition(id: 'folder.moveTo'),
    ContextMenuEntryDefinition(id: 'folder.delete'),
  ],
);

const ContextMenuDefinition folderComicMenuDefinition = ContextMenuDefinition(
  scope: 'folderComic',
  entries: <ContextMenuEntryDefinition>[
    ContextMenuEntryDefinition(id: 'folderComic.multiSelect'),
    ContextMenuEntryDefinition(id: 'folderComic.delete'),
  ],
);
