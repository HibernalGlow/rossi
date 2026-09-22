//! 文档校验，以及「条目被删掉之后绑定怎么收口」。

use super::*;

/// 校验：返回**人话**的问题清单（空 = 可用）。
///
/// 不返回错误码是因为这份清单要直接显示在设置页上：「层数越界」不如
/// 「轮盘『默认轮盘』的层数 5 超过 3」看得懂。
pub fn validate(config: &RadialConfig) -> Vec<String> {
    let mut problems = Vec::new();
    if config.menus.is_empty() {
        problems.push("至少需要一个轮盘".into());
    }
    if config.menus.len() > MAX_RADIAL_MENUS {
        problems.push(format!(
            "轮盘数量 {} 超过上限 {MAX_RADIAL_MENUS}",
            config.menus.len()
        ));
    }
    let mut ids: Vec<&str> = config.menus.iter().map(|menu| menu.id.as_str()).collect();
    ids.sort_unstable();
    let unique_len = ids.len();
    ids.dedup();
    if ids.len() != unique_len {
        problems.push("轮盘 id 有重复（绑定会指错轮盘）".into());
    }
    if !config.active_menu_id.is_empty() && config.menu(&config.active_menu_id).is_none() {
        problems.push(format!("生效轮盘 {} 不存在", config.active_menu_id));
    }
    if !(MIN_RADIAL_LAYERS..=MAX_RADIAL_LAYERS).contains(&config.layer_count) {
        problems.push(format!(
            "层数 {} 不在 {MIN_RADIAL_LAYERS}..={MAX_RADIAL_LAYERS}",
            config.layer_count
        ));
    }
    if !(MIN_RADIAL_RADIUS..=MAX_RADIAL_RADIUS).contains(&config.radius) {
        problems.push(format!(
            "半径 {radius} 不在 {MIN_RADIAL_RADIUS}..={MAX_RADIAL_RADIUS}",
            radius = config.radius
        ));
    }
    if !(MIN_RADIAL_INNER_RADIUS..=MAX_RADIAL_INNER_RADIUS).contains(&config.inner_radius)
        || config.inner_radius >= config.radius
    {
        problems.push(format!(
            "内半径 {} 不合法（0..={MAX_RADIAL_INNER_RADIUS} 且要小于半径）",
            config.inner_radius
        ));
    }
    if !(MIN_RADIAL_START_ANGLE..=MAX_RADIAL_START_ANGLE).contains(&config.start_angle) {
        problems.push(format!("起始角 {} 不合法", config.start_angle));
    }
    let sweep = config.sweep_angle.abs();
    if !(MIN_RADIAL_SWEEP_ANGLE..=MAX_RADIAL_SWEEP_ANGLE).contains(&sweep) {
        problems.push(format!("扫过角 {} 不合法", config.sweep_angle));
    }
    for menu in &config.menus {
        if menu.id.is_empty() {
            problems.push("有轮盘的 id 是空的".into());
        }
        if menu.layers.len() > MAX_RADIAL_LAYERS as usize {
            problems.push(format!(
                "轮盘『{}』有 {} 层条目，超过 {MAX_RADIAL_LAYERS}",
                menu.name,
                menu.layers.len()
            ));
        }
        for dup in menu.duplicated_item_ids() {
            problems.push(format!("轮盘『{}』里条目 id {dup} 重复", menu.name));
        }
        for (level, items) in menu.layers.iter().enumerate() {
            if items.len() > MAX_RADIAL_SLOTS {
                problems.push(format!(
                    "轮盘『{}』第 {} 层有 {} 个条目，超过 {MAX_RADIAL_SLOTS}",
                    menu.name,
                    level + 1,
                    items.len()
                ));
            }
            for entry in items {
                if !is_item_id_shape(&entry.id) {
                    problems.push(format!(
                        "轮盘『{}』的条目 id「{}」形状不合法",
                        menu.name, entry.id
                    ));
                }
                if entry.slot_index >= MAX_RADIAL_SLOTS {
                    problems.push(format!(
                        "轮盘『{}』第 {} 层的条目 {} 槽位 {} 越界",
                        menu.name,
                        level + 1,
                        entry.id,
                        entry.slot_index
                    ));
                }
                if let Some(target) = entry.move_to_menu_id.as_deref() {
                    if !target.is_empty() && config.menu(target).is_none() {
                        problems.push(format!(
                            "轮盘『{}』的条目 {} 指向不存在的轮盘 {target}",
                            menu.name, entry.id
                        ));
                    }
                }
            }
        }
    }
    problems
}

/// 这份文档能不能用。
pub fn is_valid(config: &RadialConfig) -> bool {
    validate(config).is_empty()
}

/// 删掉指向**已不存在的条目**的轮盘绑定，返回留下的那些。
///
/// 「形状在文档、动作在绑定表」的收口：删了条目 / 删了轮盘之后，那些 `itemId`
/// 再没有对应的画法了。留着它们的表现是设置页列出一排点不到的槽位。
pub fn prune_bindings(config: &RadialConfig, bindings: &[InputBinding]) -> Vec<InputBinding> {
    bindings
        .iter()
        .filter(|binding| match &binding.input {
            InputDescriptor::Radial { menu_id, item_id } => config
                .menu(menu_id)
                .is_some_and(|menu| menu.item(item_id).is_some()),
            _ => true,
        })
        .cloned()
        .collect()
}
