/// 上下文菜单的**解析器** —— 纯 Dart，不 import Flutter。
///
/// 判据：`dart run test/context_menu/context_menu_resolve_check.dart`
///
/// 输入「菜单定义 + 用户偏好」，输出一份**渲染计划**（顶部图标条 / 列表 /
/// 折叠进「更多」/ 底部固定 / 每次现造）。渲染层只负责把计划翻译成
/// `CommonPopupMenuItem`，不再判断显隐与次序 —— 判断全在这里，可以脱开 UI 断言。
///
/// 兜底口径与 `navigation_entries.dart` 的 `decodeNavigationEntryIds` 一致：
/// 认不出的 id 丢掉、重复的保留第一次、缺失的追加末尾、全坏就回出厂。
library;

import 'package:zephyr/model/context_menu/context_menu_definition.dart';
import 'package:zephyr/model/context_menu/context_menu_model.dart';

/// 顶部图标条最多几格。
///
/// 上限不只是观感：`CommonPopupMenu` 用 `IntrinsicWidth` 量宽，`Wrap` 的 intrinsic
/// 宽度会把菜单撑过 280。6 格 × 34 + 5 × 2 ≈ 214，加两侧内边距仍在 280 以内。
const int kMaxContextMenuStripItems = 6;

/// 菜单里的四个可见区段（外加隐藏池）。
enum ContextMenuBucket { top, list, collapsed, bottom, hidden }

/// 一个已经决定好去处的菜单项。
class ContextMenuPlannedEntry {
  const ContextMenuPlannedEntry({
    required this.entry,
    required this.visibility,
    required this.pin,
    this.iconOnly = false,
  });

  final ContextMenuEntryDefinition entry;
  final ContextMenuVisibility visibility;
  final ContextMenuPin pin;

  /// 顶部图标条里的那一格。只有 `pin == top` 且能力允许时才可能为 true。
  final bool iconOnly;
}

/// 一次解析的结果。
class ContextMenuPlan {
  const ContextMenuPlan({
    this.topStrip = const <ContextMenuPlannedEntry>[],
    this.topRows = const <ContextMenuPlannedEntry>[],
    this.list = const <ContextMenuPlannedEntry>[],
    this.collapsed = const <ContextMenuPlannedEntry>[],
    this.bottomRows = const <ContextMenuPlannedEntry>[],
    this.ephemeral = const <ContextMenuPlannedEntry>[],
  });

  /// 顶部图标条（pin=top 且只画图标）。
  final List<ContextMenuPlannedEntry> topStrip;

  /// 顶部普通行（pin=top 但保留图标 + 文字，或图标格超出上限被降级）。
  final List<ContextMenuPlannedEntry> topRows;

  /// 主列表（normal）。
  final List<ContextMenuPlannedEntry> list;

  /// 折叠进「更多」子菜单。
  final List<ContextMenuPlannedEntry> collapsed;

  /// 固定到底部。
  final List<ContextMenuPlannedEntry> bottomRows;

  /// 每次现造、不受偏好影响的项，渲染在主列表之后。
  final List<ContextMenuPlannedEntry> ephemeral;

  bool get isEmpty =>
      topStrip.isEmpty &&
      topRows.isEmpty &&
      list.isEmpty &&
      collapsed.isEmpty &&
      bottomRows.isEmpty &&
      ephemeral.isEmpty;
}

/// 把存储形状补成完整次序（编辑器与解析共用的第一步）。
///
/// - 只保留 definition 里存在、且参与偏好的 id；
/// - 去重，保留第一次出现的位置；
/// - definition 有、存储没有的追加到末尾（新增项不需要迁移）；
/// - 存储里的未知 override 丢掉，与出厂一致的 override 也丢掉（保持稀疏）。
ContextMenuScopeLayout materializeContextMenuLayout(
  ContextMenuDefinition definition,
  ContextMenuScopeLayout? stored,
) {
  final orderable = definition.orderableEntries.toList();
  final valid = <String>{for (final entry in orderable) entry.id};

  final order = <String>[];
  for (final raw in stored?.order ?? const <String>[]) {
    final id = raw.trim();
    if (!valid.contains(id) || order.contains(id)) continue;
    order.add(id);
  }
  for (final entry in orderable) {
    if (!order.contains(entry.id)) order.add(entry.id);
  }

  final overrides = <String, ContextMenuItemOverride>{};
  for (final raw
      in (stored?.overrides ?? const <String, ContextMenuItemOverride>{})
          .entries) {
    final id = raw.key.trim();
    if (!valid.contains(id) || raw.value.isDefault) continue;
    overrides[id] = raw.value;
  }

  return ContextMenuScopeLayout(order: order, overrides: overrides);
}

/// 解析优先级（从高到低）：
/// 1. `persistent == false`：不进偏好，永远按出厂位置追加在主列表之后；
/// 2. `hidden`：从所有区段消失；
/// 3. `pin == top`：进顶部（`iconOnly` 且能力允许且未超上限 ⇒ 图标条）；
/// 4. `pin == bottom`：进底部；
/// 5. `collapsed`：进「更多」；
/// 6. 其余：进主列表。
ContextMenuPlan resolveContextMenu({
  required ContextMenuDefinition definition,
  required ContextMenuScopeLayout? layout,
  int maxStripItems = kMaxContextMenuStripItems,
}) {
  final materialized = materializeContextMenuLayout(definition, layout);
  final byId = <String, ContextMenuEntryDefinition>{
    for (final entry in definition.entries) entry.id: entry,
  };

  final top = <ContextMenuPlannedEntry>[];
  final list = <ContextMenuPlannedEntry>[];
  final collapsed = <ContextMenuPlannedEntry>[];
  final bottom = <ContextMenuPlannedEntry>[];

  for (final id in materialized.order) {
    final entry = byId[id];
    if (entry == null) continue;
    final override =
        materialized.overrides[id] ?? const ContextMenuItemOverride();
    final visibility = _effectiveVisibility(entry, override);
    if (visibility == ContextMenuVisibility.hidden) continue;

    final pin = _effectivePin(entry, override);
    final iconOnly =
        override.iconOnly &&
        pin == ContextMenuPin.top &&
        entry.capabilities.canIconOnly;

    final planned = ContextMenuPlannedEntry(
      entry: entry,
      visibility: visibility,
      pin: pin,
      iconOnly: iconOnly,
    );

    switch (pin) {
      case ContextMenuPin.top:
        top.add(planned);
      case ContextMenuPin.bottom:
        bottom.add(planned);
      case ContextMenuPin.none:
        if (visibility == ContextMenuVisibility.collapsed) {
          collapsed.add(planned);
        } else {
          list.add(planned);
        }
    }
  }

  final ephemeral = <ContextMenuPlannedEntry>[
    for (final entry in definition.ephemeralEntries)
      ContextMenuPlannedEntry(
        entry: entry,
        visibility: ContextMenuVisibility.normal,
        pin: ContextMenuPin.none,
      ),
  ];

  final topStrip = <ContextMenuPlannedEntry>[];
  final topRows = <ContextMenuPlannedEntry>[];
  for (final planned in top) {
    final fits =
        definition.supportsTopStrip &&
        planned.iconOnly &&
        topStrip.length < maxStripItems;
    (fits ? topStrip : topRows).add(planned);
  }

  return ContextMenuPlan(
    topStrip: topStrip,
    topRows: topRows,
    list: list,
    collapsed: collapsed,
    bottomRows: bottom,
    ephemeral: ephemeral,
  );
}

/// 设置显隐。能力不允许时原样返回。
ContextMenuScopeLayout setContextMenuVisibility(
  ContextMenuDefinition definition,
  ContextMenuScopeLayout? layout,
  String id,
  ContextMenuVisibility value,
) {
  final entry = definition.entryById(id);
  if (entry == null || !entry.persistent)
    return layout ?? const ContextMenuScopeLayout();
  final current =
      (layout ?? const ContextMenuScopeLayout()).overrides[id] ??
      const ContextMenuItemOverride();
  return _withOverride(layout, id, current.copyWith(visibility: value));
}

/// 设置 pin 位置。切离顶部时顺手清掉 `iconOnly`（免得留着一条无意义的偏好）。
ContextMenuScopeLayout setContextMenuPin(
  ContextMenuDefinition definition,
  ContextMenuScopeLayout? layout,
  String id,
  ContextMenuPin value,
) {
  final entry = definition.entryById(id);
  if (entry == null || !entry.persistent)
    return layout ?? const ContextMenuScopeLayout();
  final current =
      (layout ?? const ContextMenuScopeLayout()).overrides[id] ??
      const ContextMenuItemOverride();
  return _withOverride(
    layout,
    id,
    current.copyWith(
      pin: value,
      iconOnly: value == ContextMenuPin.top ? current.iconOnly : false,
    ),
  );
}

/// 设置顶部图标条里的「只显示图标」。只有 pin 在顶部时才有意义。
ContextMenuScopeLayout setContextMenuIconOnly(
  ContextMenuDefinition definition,
  ContextMenuScopeLayout? layout,
  String id,
  bool value,
) {
  final entry = definition.entryById(id);
  if (entry == null || !entry.persistent)
    return layout ?? const ContextMenuScopeLayout();
  final current =
      (layout ?? const ContextMenuScopeLayout()).overrides[id] ??
      const ContextMenuItemOverride();
  if (current.pin != ContextMenuPin.top) {
    return layout ?? const ContextMenuScopeLayout();
  }
  return _withOverride(layout, id, current.copyWith(iconOnly: value));
}

/// 恢复一个菜单的出厂状态。
ContextMenuScopeLayout resetContextMenuScope() =>
    const ContextMenuScopeLayout();

/// 区段内拖拽重排。
///
/// [newIndex] 用 Flutter 3.41+ `onReorderItem` 的口径：**框架已经替「先摘后插」
/// 修正过**，直接当最终插入位置用，不要再 `-1`（旧的 `onReorder` 才需要）。
///
/// 重排结果写回**一整条全局 order**：`[顶部, 主列表, 更多, 底部, 隐藏]`。
/// 区段归属由 override 决定，order 只决定同一区段内的先后，所以这样重建是
/// 等价的，也让「取消 pin 之后项落在哪」有确定答案。
ContextMenuScopeLayout reorderContextMenuBucket({
  required ContextMenuDefinition definition,
  required ContextMenuScopeLayout? layout,
  required ContextMenuBucket bucket,
  required int oldIndex,
  required int newIndex,
}) {
  final materialized = materializeContextMenuLayout(definition, layout);
  final plan = resolveContextMenu(definition: definition, layout: materialized);

  List<String> idsOf(ContextMenuBucket value) => switch (value) {
    ContextMenuBucket.top => <String>[
      for (final entry in <ContextMenuPlannedEntry>[
        ...plan.topStrip,
        ...plan.topRows,
      ])
        entry.entry.id,
    ],
    ContextMenuBucket.list => <String>[
      for (final entry in plan.list) entry.entry.id,
    ],
    ContextMenuBucket.collapsed => <String>[
      for (final entry in plan.collapsed) entry.entry.id,
    ],
    ContextMenuBucket.bottom => <String>[
      for (final entry in plan.bottomRows) entry.entry.id,
    ],
    ContextMenuBucket.hidden => <String>[],
  };

  if (bucket == ContextMenuBucket.hidden) return materialized;

  final members = idsOf(bucket);
  if (oldIndex < 0 || oldIndex >= members.length) return materialized;

  var target = newIndex;
  if (target < 0) target = 0;
  if (target >= members.length) target = members.length - 1;
  if (target == oldIndex) return materialized;

  final moved = members.removeAt(oldIndex);
  members.insert(target, moved);

  final top = bucket == ContextMenuBucket.top
      ? members
      : idsOf(ContextMenuBucket.top);
  final list = bucket == ContextMenuBucket.list
      ? members
      : idsOf(ContextMenuBucket.list);
  final collapsed = bucket == ContextMenuBucket.collapsed
      ? members
      : idsOf(ContextMenuBucket.collapsed);
  final bottom = bucket == ContextMenuBucket.bottom
      ? members
      : idsOf(ContextMenuBucket.bottom);

  final placed = <String>{...top, ...list, ...collapsed, ...bottom};
  final hidden = <String>[
    for (final id in materialized.order)
      if (!placed.contains(id)) id,
  ];

  return materialized.copyWith(
    order: <String>[...top, ...list, ...collapsed, ...bottom, ...hidden],
  );
}

ContextMenuVisibility _effectiveVisibility(
  ContextMenuEntryDefinition entry,
  ContextMenuItemOverride override,
) {
  switch (override.visibility) {
    case ContextMenuVisibility.hidden:
      return entry.capabilities.canHide
          ? ContextMenuVisibility.hidden
          : ContextMenuVisibility.normal;
    case ContextMenuVisibility.collapsed:
      return entry.capabilities.canCollapse
          ? ContextMenuVisibility.collapsed
          : ContextMenuVisibility.normal;
    case ContextMenuVisibility.normal:
      return ContextMenuVisibility.normal;
  }
}

ContextMenuPin _effectivePin(
  ContextMenuEntryDefinition entry,
  ContextMenuItemOverride override,
) => entry.capabilities.canPin ? override.pin : ContextMenuPin.none;

ContextMenuScopeLayout _withOverride(
  ContextMenuScopeLayout? layout,
  String id,
  ContextMenuItemOverride override,
) {
  final base = layout ?? const ContextMenuScopeLayout();
  final overrides = Map<String, ContextMenuItemOverride>.of(base.overrides);
  if (override.isDefault) {
    overrides.remove(id);
  } else {
    overrides[id] = override;
  }
  return base.copyWith(overrides: overrides);
}
