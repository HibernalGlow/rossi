// 无标题栏工作台卡片右键菜单的定义（纯 Dart）。
//
// 「恢复被收起的卡片」是每次现场生成的（`persistent: false`）：隐藏了哪几张
// 卡片只有运行时知道，它们不该进用户偏好，也不该被排序或再隐藏。
//
// 尺寸预设只有在卡片有网格宿主（`onResize`）时才有意义，面板栏那一档用
// `available: false` 临时不渲染。

import 'package:zephyr/model/context_menu/context_menu.dart';

ContextMenuDefinition buildCardMenuDefinition({
  required bool canEditLayout,
  required bool canFill,
  required bool canResize,
  required bool hasHide,
  required List<String> hiddenCardIds,
}) => ContextMenuDefinition(
  scope: 'card',
  entries: <ContextMenuEntryDefinition>[
    ContextMenuEntryDefinition(id: 'card.toggle'),
    ContextMenuEntryDefinition(id: 'card.editLayout', available: canEditLayout),
    ContextMenuEntryDefinition(id: 'card.fill', group: 1, available: canFill),
    ContextMenuEntryDefinition(
      id: 'card.preset1x1',
      group: 1,
      available: canResize,
    ),
    ContextMenuEntryDefinition(
      id: 'card.preset2x1',
      group: 1,
      available: canResize,
    ),
    ContextMenuEntryDefinition(
      id: 'card.preset2x2',
      group: 1,
      available: canResize,
    ),
    ContextMenuEntryDefinition(
      id: 'card.presetFull',
      group: 1,
      available: canResize,
    ),
    for (final id in hiddenCardIds)
      ContextMenuEntryDefinition(
        id: 'card.restore.$id',
        group: 2,
        persistent: false,
      ),
    ContextMenuEntryDefinition(
      id: 'card.hide',
      group: 3,
      available: hasHide,
      dangerous: true,
    ),
  ],
);
