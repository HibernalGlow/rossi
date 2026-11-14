/// 右键菜单的**宿主**：同一张卡在「菜单」与「编辑器」之间原地切换。
///
/// 菜单底部那一条「自定义此菜单…」不再打开弹窗 —— 它把当前这份菜单直接
/// 变成编辑器（同一位置、同一张卡片）。改完点「完成」回到菜单形态，改动是
/// 即时落账的，所以两种形态看到的就是同一份数据。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/context_menu/context_menu_entry_view.dart';
import 'package:zephyr/widgets/context_menu/context_menu_inline_editor.dart';

class ContextMenuHost extends StatefulWidget {
  const ContextMenuHost({
    super.key,
    required this.definition,
    required this.viewOf,
  });

  final ContextMenuDefinition definition;
  final ContextMenuEntryView Function(ContextMenuEntryDefinition entry) viewOf;

  @override
  State<ContextMenuHost> createState() => _ContextMenuHostState();
}

class _ContextMenuHostState extends State<ContextMenuHost> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .watch<GlobalSettingCubit>()
        .state
        .contextMenuSetting;

    if (_editing) {
      return ContextMenuInlineEditor(
        definition: widget.definition,
        labelOf: (entry) => widget.viewOf(entry).label,
        glyphOf: (entry) => widget.viewOf(entry).glyph,
        onDone: () => setState(() => _editing = false),
      );
    }

    final resolved = buildContextMenuItems(
      context: context,
      definition: widget.definition,
      viewOf: widget.viewOf,
      // 自定义入口由这里合成（它要切换成编辑态，而不是弹窗）。
      allowCustomizeEntry: false,
    );

    final items = <CommonPopupMenuItem>[
      ...resolved.items,
      if (settings.customizeEntryVisible) ...[
        if (resolved.items.isNotEmpty) const CommonPopupMenuItem.divider(),
        CommonPopupMenuItem(
          label: t.contextMenu.customizeThisMenu,
          glyph: AppGlyphs.sliders,
          // 不关菜单：点它要把**这张卡**切成编辑器，关掉就什么都没了。
          dismissOnSelect: false,
          onPressed: () => setState(() => _editing = true),
        ),
      ],
    ];

    // 全部隐藏且关掉自定义入口：没有可弹的东西，给一张空卡不如什么都不显示。
    if (items.isEmpty) return const SizedBox.shrink();

    return CommonPopupMenu(
      items: items,
      header: resolved.header,
      footer: resolved.footer,
      minWidth: resolved.minWidth,
    );
  }
}
