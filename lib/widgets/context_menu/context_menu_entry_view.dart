/// 把「菜单定义 + 用户偏好」翻译成一份 [CommonPopupMenuItem] 并弹出来。
///
/// 调用点只做两件事：
/// 1. 造 `ContextMenuDefinition`（纯数据，哪些项、能不能点、哪个危险）；
/// 2. 给 `viewOf`（文案 / 图标 / 子菜单 / 内嵌输入框，在**打开那一刻**现算）。
///
/// 顺序、折叠、隐藏、pin、顶部图标条全在这里按解析计划落地，调用点不再判断。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/context_menu/context_menu_customize_dialog.dart';
import 'package:zephyr/widgets/context_menu/context_menu_icon_strip.dart';

/// 一个菜单项**长什么样**。定义层只管语义，这一层才碰 Flutter。
class ContextMenuEntryView {
  const ContextMenuEntryView({
    required this.label,
    this.glyph,
    this.checked,
    this.subItems = const <CommonPopupMenuItem>[],
    this.content,
    this.onPressed,
  });

  final String label;
  final Glyph? glyph;
  final bool? checked;

  /// 子菜单项（如「面板栏：停靠…」）。父行本身不执行动作。
  final List<CommonPopupMenuItem> subItems;

  /// 整段替换中部的标签文本（例如项里嵌输入框），语义同
  /// [CommonPopupMenuItem.content]。
  final Widget? content;

  final VoidCallback? onPressed;
}

/// 在 [position]（全局坐标）处弹出这个菜单。
Future<void> showContextMenu({
  required BuildContext context,
  required Offset position,
  required ContextMenuDefinition definition,
  required ContextMenuEntryView Function(ContextMenuEntryDefinition entry)
  viewOf,
  bool allowCustomizeEntry = true,
}) async {
  final settings = context.read<GlobalSettingCubit>().state.contextMenuSetting;
  final plan = resolveContextMenu(
    definition: definition,
    layout: settings.scopes[definition.scope],
  );

  CommonPopupMenuItem itemOf(ContextMenuPlannedEntry planned) {
    final entry = planned.entry;
    final view = viewOf(entry);
    return CommonPopupMenuItem(
      label: view.label,
      glyph: view.glyph,
      checked: view.checked,
      subItems: view.subItems,
      content: view.content,
      danger: entry.dangerous,
      // null 就是禁用态：项永远在场，只是有的不可点。
      onPressed: entry.enabled ? view.onPressed : null,
    );
  }

  /// 组内不画线、组间画线。pin / 折叠打乱原组序后，分隔线只在同一区段内生效。
  List<CommonPopupMenuItem> withGroupDividers(
    List<ContextMenuPlannedEntry> planned,
  ) {
    final result = <CommonPopupMenuItem>[];
    int? lastGroup;
    for (final entry in planned) {
      if (lastGroup != null && entry.entry.group != lastGroup) {
        result.add(const CommonPopupMenuItem.divider());
      }
      result.add(itemOf(entry));
      lastGroup = entry.entry.group;
    }
    return result;
  }

  final sections = <List<CommonPopupMenuItem>>[];

  if (plan.topRows.isNotEmpty) {
    sections.add(withGroupDividers(plan.topRows));
  }

  // 动态项（`persistent == false`）接在主列表之后，位置由定义决定。
  final mainEntries = <ContextMenuPlannedEntry>[
    ...plan.list,
    ...plan.ephemeral,
  ];
  if (mainEntries.isNotEmpty) {
    sections.add(withGroupDividers(mainEntries));
  }

  if (plan.collapsed.isNotEmpty) {
    sections.add(<CommonPopupMenuItem>[
      CommonPopupMenuItem(
        label: t.contextMenu.more,
        glyph: AppGlyphs.more,
        subItems: withGroupDividers(plan.collapsed),
      ),
    ]);
  }

  if (plan.bottomRows.isNotEmpty) {
    sections.add(withGroupDividers(plan.bottomRows));
  }

  if (allowCustomizeEntry && settings.customizeEntryVisible) {
    sections.add(<CommonPopupMenuItem>[
      CommonPopupMenuItem(
        label: t.contextMenu.customizeThisMenu,
        glyph: AppGlyphs.sliders,
        onPressed: () => unawaited(
          showContextMenuCustomizeDialog(context, definition: definition),
        ),
      ),
    ]);
  }

  final items = <CommonPopupMenuItem>[];
  for (var index = 0; index < sections.length; index++) {
    if (index > 0) items.add(const CommonPopupMenuItem.divider());
    items.addAll(sections[index]);
  }

  Widget? header;
  if (settings.topStripEnabled && plan.topStrip.isNotEmpty) {
    header = CommonPopupMenuIconStrip(
      actions: <ContextMenuIconAction>[
        for (final planned in plan.topStrip) _iconAction(planned, viewOf),
      ],
    );
  }

  await showCommonPopupMenu(
    context: context,
    position: position,
    items: items,
    header: header,
    // 图标条那 6 格决定了下限，否则 4 格时菜单会被 160 夹得过窄。
    minWidth: math.max(160, plan.topStrip.length * (34 + 2) + 16).toDouble(),
  );
}

ContextMenuIconAction _iconAction(
  ContextMenuPlannedEntry planned,
  ContextMenuEntryView Function(ContextMenuEntryDefinition entry) viewOf,
) {
  final entry = planned.entry;
  final view = viewOf(entry);
  return ContextMenuIconAction(
    label: view.label,
    // 没有图标的项不该被允许变成图标（定义层应给 `canIconOnly: false`）；
    // 真漏了也不隐藏它，用「更多」兜底画出来。
    glyph: view.glyph ?? AppGlyphs.more,
    dangerous: entry.dangerous,
    enabled: entry.enabled && view.onPressed != null,
    onPressed: view.onPressed,
  );
}
