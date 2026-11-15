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
  final resolved = buildContextMenuItems(
    context: context,
    definition: definition,
    viewOf: viewOf,
    allowCustomizeEntry: allowCustomizeEntry,
  );
  await showCommonPopupMenu(
    context: context,
    position: position,
    items: resolved.items,
    header: resolved.header,
    footer: resolved.footer,
    minWidth: resolved.minWidth,
  );
}

/// 解析好的菜单：可以直接喂给 `showCommonPopupMenu`，也可以放进
/// `CommonPopupBox` 的 `popupBuilder`（泳道栏头那颗 ⋮ 就是后者）。
class ContextMenuBuildResult {
  const ContextMenuBuildResult({
    required this.items,
    this.header,
    this.footer,
    this.minWidth = 160,
  });

  final List<CommonPopupMenuItem> items;
  final Widget? header;
  final Widget? footer;
  final double minWidth;
}

/// 把「定义 + 偏好」翻译成 `CommonPopupMenuItem` 清单。
///
/// 有触发按钮的入口（`CommonPopupBox`）用它，再自己决定在哪儿弹；
/// 右键/长按入口直接用 [showContextMenu]。
ContextMenuBuildResult buildContextMenuItems({
  required BuildContext context,
  required ContextMenuDefinition definition,
  required ContextMenuEntryView Function(ContextMenuEntryDefinition entry)
  viewOf,
  bool allowCustomizeEntry = true,
}) => buildContextMenuItemsWith(
  context: context,
  definition: definition,
  itemOf: (entry) {
    final view = viewOf(entry);
    return CommonPopupMenuItem(
      label: view.label,
      glyph: view.glyph,
      // 视图层优先；定义里的 checked 是「静态勾选」的兜底。
      checked: view.checked ?? entry.checked,
      subItems: view.subItems,
      content: view.content,
      danger: entry.dangerous,
      // null 就是禁用态：项永远在场，只是有的不可点。
      onPressed: entry.enabled ? view.onPressed : null,
    );
  },
  allowCustomizeEntry: allowCustomizeEntry,
  // 从真实菜单进来的编辑入口：预览直接用这一份 viewOf 的文案与图标，
  // 连「继续阅读 / 收藏」这种随状态变的措辞都是真的。
  customizeItemBuilder: (definition) => CommonPopupMenuItem(
    label: t.contextMenu.customizeThisMenu,
    glyph: AppGlyphs.sliders,
    onPressed: () => unawaited(
      showContextMenuCustomizeDialog(
        context,
        definition: definition,
        labelOf: (entry) => viewOf(entry).label,
        glyphOf: (entry) => viewOf(entry).glyph,
      ),
    ),
  ),
);

/// 与 [buildContextMenuItems] 相同，但**项本身由调用方给**。
///
/// 给泳道栏头那种「项里有子菜单 / 输入框，手写比映射更稳」的菜单做薄适配：
/// 内容仍由它自己造，排序 / 显隐 / pin / 折叠走统一模型。
ContextMenuBuildResult buildContextMenuItemsWith({
  required BuildContext context,
  required ContextMenuDefinition definition,
  required CommonPopupMenuItem Function(ContextMenuEntryDefinition entry)
  itemOf,
  bool allowCustomizeEntry = true,
  CommonPopupMenuItem Function(ContextMenuDefinition definition)?
  customizeItemBuilder,
}) {
  final settings = context.read<GlobalSettingCubit>().state.contextMenuSetting;
  final plan = resolveContextMenu(
    definition: definition,
    layout: settings.scopes[definition.scope],
  );

  /// 计划里的一项 → 实际菜单项（内容由调用方给）。
  CommonPopupMenuItem itemFor(ContextMenuPlannedEntry planned) =>
      itemOf(planned.entry);

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
      result.add(itemFor(entry));
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
      customizeItemBuilder?.call(definition) ??
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
        for (final planned in plan.topStrip)
          _iconAction(planned, itemFor(planned)),
      ],
    );
  }

  Widget? footer;
  if (settings.topStripEnabled && plan.bottomStrip.isNotEmpty) {
    footer = CommonPopupMenuIconStrip(
      // 底部那条：分隔线在图标上方。
      dividerAbove: true,
      actions: <ContextMenuIconAction>[
        for (final planned in plan.bottomStrip)
          _iconAction(planned, itemFor(planned)),
      ],
    );
  }

  return ContextMenuBuildResult(
    items: items,
    header: header,
    footer: footer,
    // 图标条那 6 格决定了下限，否则 4 格时菜单会被 160 夹得过窄。
    minWidth: math
        .max(
          160,
          math.max(plan.topStrip.length, plan.bottomStrip.length) * (34 + 2) +
              16,
        )
        .toDouble(),
  );
}

ContextMenuIconAction _iconAction(
  ContextMenuPlannedEntry planned,
  CommonPopupMenuItem item,
) {
  final entry = planned.entry;
  return ContextMenuIconAction(
    label: item.label,
    // 没有图标的项不该被允许变成图标（定义层应给 `canIconOnly: false`）；
    // 真漏了也不隐藏它，用「更多」兜底画出来。
    glyph: item.glyph ?? AppGlyphs.more,
    dangerous: entry.dangerous,
    enabled: entry.enabled && item.onPressed != null,
    onPressed: item.onPressed,
  );
}
