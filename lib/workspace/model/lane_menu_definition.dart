// 泳道栏头「更多」菜单的定义（纯 Dart）。
//
// 这一份走的是「薄适配」：项的内容（宽度输入框、面板栏子菜单）仍由
// `lane_more_menu.dart` 手写，统一模型只接管排序 / 显隐 / pin / 折叠。
// 两个子菜单父行标成 structural —— 把它们压成小图标或折叠进「更多」都
// 会让子菜单失去意义。

import 'package:zephyr/model/context_menu/context_menu.dart';

ContextMenuDefinition buildLaneMenuDefinition({required bool hasPanelSide}) =>
    ContextMenuDefinition(
      scope: 'lane',
      entries: <ContextMenuEntryDefinition>[
        ContextMenuEntryDefinition(id: 'lane.panelEditMode'),
        ContextMenuEntryDefinition(id: 'lane.solo'),
        ContextMenuEntryDefinition(id: 'lane.collapse'),
        ContextMenuEntryDefinition(
          id: 'lane.width',
          group: 1,
          capabilities: ContextMenuEntryCapabilities.structural,
        ),
        ContextMenuEntryDefinition(
          id: 'lane.panelBar',
          group: 1,
          available: hasPanelSide,
          capabilities: ContextMenuEntryCapabilities.structural,
        ),
        ContextMenuEntryDefinition(id: 'lane.widthBadge', group: 2),
        ContextMenuEntryDefinition(id: 'lane.topChrome', group: 2),
        ContextMenuEntryDefinition(id: 'lane.exit', group: 2),
      ],
    );
