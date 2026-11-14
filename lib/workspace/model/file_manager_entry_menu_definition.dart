// 文件管理器条目右键菜单的**定义** —— 纯 Dart，不 import Flutter。
//
// 与 `file_manager_entry_menu_spec.dart` 的分工：那份回答「有哪些项、哪一项
// 可用、要不要确认」（可用 `dart run` 断言），这份补上「用户能怎么摆它」。
//
// 分组沿用原菜单的**唯一一条**分隔线：十项普通动作一组，回收站 / 永久删除
// 单独一组。不再按「打开 / 剪贴板 / 编辑」细分 —— 现状就没有那些线。

import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';

/// 由菜单项 id 反查动作。
FileManagerEntryAction fileManagerActionOfId(String id) {
  for (final action in FileManagerEntryAction.values) {
    if ('fileManager.${action.name}' == id) return action;
  }
  throw StateError('未知的 fileManager 菜单项 id: $id');
}

ContextMenuDefinition buildFileManagerMenuDefinition(
  FileManagerEntryMenuInput input,
) {
  final specs = buildFileManagerEntryMenuItems(input);
  return ContextMenuDefinition(
    scope: 'fileManager',
    entries: <ContextMenuEntryDefinition>[
      for (final spec in specs)
        ContextMenuEntryDefinition(
          id: 'fileManager.${spec.action.name}',
          group: spec.dangerous ? 1 : 0,
          enabled: spec.enabled,
          dangerous: spec.dangerous,
          destructive: spec.destructive,
          // 破坏性动作也可以只显示图标：两个删除用不同图标区分
          // （回收站 = 归档箱、永久删除 = 垃圾桶），图标条上仍分得清。
          capabilities: const ContextMenuEntryCapabilities(),
        ),
    ],
  );
}
