// 收藏 / 历史卡片条目右键菜单的**定义** —— 纯 Dart，不 import Flutter。
//
// 与 `shelf_entry_menu_spec.dart` 的分工：那份回答「有哪些项、哪一项可用、
// 要不要确认」（可用 `dart run` 断言），这份补上「用户能怎么摆它」——
// 稳定 id、分组、危险色、以及哪些项允许 pin / 折叠 / 隐藏 / 变成图标。
//
// id 用 `shelf.<action.name>`：动作枚举名是既有的稳定词表，改它等于改契约。

import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';

/// 由菜单项 id 反查动作。id 的生成规则只有 [buildShelfMenuDefinition] 一处，
/// 这里与它是同一份契约。
ShelfEntryAction shelfEntryActionOfId(String id) {
  for (final action in ShelfEntryAction.values) {
    if ('shelf.${action.name}' == id) return action;
  }
  throw StateError('未知的 shelf 菜单项 id: $id');
}

ContextMenuDefinition buildShelfMenuDefinition(ShelfEntryMenuInput input) {
  final specs = buildShelfEntryMenuItems(input);
  return ContextMenuDefinition(
    scope: 'shelf',
    entries: <ContextMenuEntryDefinition>[
      for (final spec in specs)
        ContextMenuEntryDefinition(
          id: 'shelf.${spec.action.name}',
          // 原菜单的两条分隔线：「打开类 / 复制类 / 破坏性」。
          group: switch (spec.action) {
            ShelfEntryAction.open || ShelfEntryAction.openInFileManagerTab => 0,
            ShelfEntryAction.remove => 2,
            _ => 1,
          },
          enabled: spec.enabled,
          // 这一份的 destructive 同时驱动危险色与二次确认，两个字段同值。
          dangerous: spec.destructive,
          destructive: spec.destructive,
          // 「移除」不许变成小图标：误触代价太大，而且它必须是最后一项。
          capabilities: spec.destructive
              ? const ContextMenuEntryCapabilities(canIconOnly: false)
              : const ContextMenuEntryCapabilities(),
        ),
    ],
  );
}
