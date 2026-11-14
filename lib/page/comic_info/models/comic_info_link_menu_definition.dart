// 详情页「在原站打开」长按菜单的定义（纯 Dart）。
//
// id 是持久化契约，改名等于丢用户偏好。

import 'package:zephyr/model/context_menu/context_menu.dart';

const ContextMenuDefinition comicInfoLinkMenuDefinition = ContextMenuDefinition(
  scope: 'comicInfoLink',
  entries: <ContextMenuEntryDefinition>[
    ContextMenuEntryDefinition(id: 'comicInfoLink.openExternal'),
    ContextMenuEntryDefinition(id: 'comicInfoLink.copy'),
  ],
);
