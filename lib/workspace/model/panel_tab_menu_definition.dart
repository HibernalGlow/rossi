// 面板栏把手右键菜单的定义（纯 Dart）。
//
// 勾选态（是否钉住 / 是否限制泳道 / 排序模式 / 当前停靠边）随局面变，由调用点
// 在 `viewOf` 里给 `checked`，定义只描述「有哪些项、怎么分组」。

import 'package:zephyr/model/context_menu/context_menu.dart';

const ContextMenuDefinition panelTabMenuDefinition = ContextMenuDefinition(
  scope: 'panelTab',
  entries: <ContextMenuEntryDefinition>[
    ContextMenuEntryDefinition(id: 'panelTab.pin'),
    ContextMenuEntryDefinition(id: 'panelTab.constrain'),
    ContextMenuEntryDefinition(id: 'panelTab.sortMode', group: 1),
    ContextMenuEntryDefinition(id: 'panelTab.dockLeft', group: 2),
    ContextMenuEntryDefinition(id: 'panelTab.dockRight', group: 2),
    ContextMenuEntryDefinition(id: 'panelTab.dockTop', group: 2),
    ContextMenuEntryDefinition(id: 'panelTab.dockBottom', group: 2),
  ],
);
