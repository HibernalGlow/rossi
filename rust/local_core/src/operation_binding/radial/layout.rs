//! 轮盘的几何：一层的槽位数、每格的内外半径与角度、指针落点命中哪一格。
//!
//! 常量与文档模型都在父 `radial.rs`。兄弟模块之间引用不到彼此的私有项，所以
//! **被调用的一侧留在父模块**。

use super::*;

/// 一层的槽位数：至少 [`MIN_RADIAL_SLOTS`] 格，条目排到第几格就至少有几格。
pub fn layer_slot_count(items: &[RadialMenuItem]) -> usize {
    let needed = items
        .iter()
        .map(|item| item.slot_index + 1)
        .max()
        .unwrap_or(0);
    needed.max(MIN_RADIAL_SLOTS).min(MAX_RADIAL_SLOTS)
}

/// 一个槽的**画法与命中区**（同一个结构体服务两件事，见模块头）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RadialSlotLayout {
    pub menu_id: String,
    /// 第几环（1 起）与这一环里的第几格（0 起）。
    pub level: usize,
    pub index: usize,
    /// 这一格上的条目（空槽为 `None`）。
    pub item_id: Option<String>,
    pub label: Option<String>,
    /// 遗留直连动作（绑定派发不到时回落）。
    pub legacy_action: Option<String>,
    /// 「跳转轮盘」型条目的目标轮盘。
    pub move_to_menu_id: Option<String>,
    pub disabled: bool,
    /// 这一格能不能被选中：空槽与 `disabled` 的条目都不行。
    pub selectable: bool,
    pub inner_radius: f32,
    pub outer_radius: f32,
    pub start_deg: f32,
    pub end_deg: f32,
    pub mid_deg: f32,
}

/// 落点选中的槽（命中结果，外壳只拿它去问绑定表）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RadialSlotHit {
    pub menu_id: String,
    pub level: usize,
    pub index: usize,
    pub item_id: Option<String>,
    pub legacy_action: Option<String>,
    pub move_to_menu_id: Option<String>,
}

/// 算出一个轮盘显示出来的全部槽位（含空格，按环、再按格排序）。
pub fn slot_layout(config: &RadialConfig, menu: &RadialMenuDefinition) -> Vec<RadialSlotLayout> {
    let sweep = config.sweep_angle.abs();
    let mut out = Vec::new();
    for level in 1..=config.layers() {
        let items = menu.layer(level);
        let slots = layer_slot_count(items);
        let step = sweep / slots as f32;
        let (inner_radius, outer_radius) = config.band(level);
        for index in 0..slots {
            let item = items.iter().find(|entry| entry.slot_index == index);
            let mid_deg = config.start_angle + index as f32 * step;
            out.push(RadialSlotLayout {
                menu_id: menu.id.clone(),
                level,
                index,
                item_id: item.map(|entry| entry.id.clone()),
                label: item.map(|entry| entry.label.clone()),
                legacy_action: item.and_then(|entry| entry.action.clone()),
                move_to_menu_id: item.and_then(|entry| entry.move_to_menu_id.clone()),
                disabled: item.is_none_or(|entry| entry.disabled),
                selectable: item.is_some_and(|entry| !entry.disabled),
                inner_radius,
                outer_radius,
                start_deg: mid_deg - step / 2.0,
                end_deg: mid_deg + step / 2.0,
                mid_deg,
            });
        }
    }
    out
}

/// 落点 → 槽（`dx` / `dy` 是相对圆心的偏移，屏幕坐标系：x 右、y 下）。
///
/// 算法逐行照 neoview `_getSlotAtPoint`：先按半径定第几环（**第一层命中即止**），
/// 再按角度定第几格；落在空洞里、环带缝隙里、或超出 `sweepAngle` 之外都算没选中。
pub fn slot_at(
    config: &RadialConfig,
    menu: &RadialMenuDefinition,
    dx: f32,
    dy: f32,
) -> Option<RadialSlotHit> {
    let distance = (dx * dx + dy * dy).sqrt();
    let layers = config.layers();
    let mut level = 0usize;
    for candidate in 1..=layers {
        let (inner, outer) = config.band(candidate);
        if distance >= inner && distance <= outer {
            level = candidate;
            break;
        }
    }
    if level == 0 {
        return None;
    }
    let angle = dy.atan2(dx).to_degrees();
    let sweep = config.sweep_angle.abs();
    // 角度换算**刻意不照抄 neoview 的 `normalizeAngle`**：它把偏移折到 `[-180, 180)`，
    // 于是从起始角逆时针那一半的偏移是负数，`floor` 之后被夹回第 0 格 —— 表现为
    // 「顺时针半圈能用、另外半圈全选中第 0 格」。这里按 `[0, 360)` 算，整圈都能命中；
    // 「超出扫过角就不算选中」那一条与 neoview 同语义。
    let offset = RadialConfig::offset_from(config.start_angle, angle);
    if offset > sweep {
        return None;
    }
    let items = menu.layer(level);
    let slots = layer_slot_count(items);
    let index = ((offset / (sweep / slots as f32)).floor() as usize).clamp(0, slots - 1);
    let item = items.iter().find(|entry| entry.slot_index == index);
    // 空格与 `disabled` 的条目都不算选中（neoview 的 `selectable:false` 同一语义）。
    if item.is_none_or(|entry| entry.disabled) {
        return None;
    }
    let entry = item?;
    Some(RadialSlotHit {
        menu_id: menu.id.clone(),
        level,
        index,
        item_id: Some(entry.id.clone()),
        legacy_action: entry.action.clone(),
        move_to_menu_id: entry.move_to_menu_id.clone(),
    })
}
