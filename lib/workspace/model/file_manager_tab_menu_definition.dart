// 文件管理器页签右键菜单的定义（纯 Dart）。
//
// 可用性由调用点的 `tab.canClose*` / `snapshot.canCreateTab` 在 `viewOf` 里给
// `onPressed: null` 表达 —— 与迁移前逐项置灰的做法一致，所以定义里全是
// `enabled: true`。分组沿用原菜单：操作类一组，关闭类一组。

import 'package:zephyr/model/context_menu/context_menu.dart';

const ContextMenuDefinition fileManagerTabMenuDefinition =
    ContextMenuDefinition(
      scope: 'fileManagerTab',
      entries: <ContextMenuEntryDefinition>[
        ContextMenuEntryDefinition(id: 'fileManagerTab.pin'),
        ContextMenuEntryDefinition(id: 'fileManagerTab.newTab'),
        ContextMenuEntryDefinition(id: 'fileManagerTab.duplicate'),
        ContextMenuEntryDefinition(id: 'fileManagerTab.close', group: 1),
        ContextMenuEntryDefinition(id: 'fileManagerTab.closeOthers', group: 1),
        ContextMenuEntryDefinition(id: 'fileManagerTab.closeLeft', group: 1),
        ContextMenuEntryDefinition(id: 'fileManagerTab.closeRight', group: 1),
      ],
    );
