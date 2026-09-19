//! 轮盘（radial menu）的**文档模型 + 几何** —— 照抄 neoview
//! `packages/nodes/neoview/src/application/config/ReaderRadialMenuConfig.ts`
//! 与 `vendor/ray-menu/wc/neoview-ray-menu.ts` 的 `_getSlotAtPoint`。
//!
//! ## 一个槽「干什么」不在这份文档里
//!
//! neoview 的条目（`ReaderRadialMenuItem`）带一个 `action` 字段，但它自己的编辑器
//! 会把这个「遗留的直连动作」剥掉（`stripLegacyActions`），改成物化一条
//! `input: {device:"radial", menuId, itemId}` 的**绑定行**；运行时也是先派发绑定、
//! 派发不到才回落到遗留动作（`ReaderAppView.tsx` 的
//! `if (!inputRouter.dispatch(...) && legacyAction) executeInputAction(legacyAction)`）。
//! 这里同一套：**槽位身份 = (menuId, itemId)**，动作在绑定表里。于是轮盘与键盘、
//! 点击共用同一个解析器、同一套冲突判定，`followUpActions` 自动可用。
//! 遗留的 [`RadialMenuItem::action`] 仍然解析并随布局带回去，作为回落。
//!
//! ## 为什么几何归核心
//!
//! 画一格与判定「指针落在哪一格」必须是同一份算术。两处各算一遍时，只要起始角差 1°
//! 或环带差一个像素，就会**高亮的槽与执行的槽不是同一个**，而屏幕上看着没错。
//! 所以 [`slot_layout`] 一次算出每个槽的内外半径与角度，[`slot_at`] 也从同一组数字读。
//!
//! ## 环带不是「半径除以层数」
//!
//! neoview 的第 1 环就是 `内半径 → 半径` 那一整圈，**多出来的每一层往外长
//! [`SUBMENU_RADIUS_STEP`] 像素**（`_getBand`）。把 `(radius-inner)/layers` 当环宽
//! 是最自然的猜法，也是错的：那样 r120 三层时每环只有 26.7px，字放不下，
//! 而且预览与运行时的尺寸感会和 neoview 完全不同。

use serde::{Deserialize, Serialize};

use super::model::{InputBinding, InputDescriptor};
use super::vocabulary::{InputContext, action};

/// 一份文档最多几个轮盘（neoview `MAX_MENUS = 16`）。
pub const MAX_RADIAL_MENUS: usize = 16;
/// 层数（同心环）上下限（neoview `layerCount: 1|2|3`）。
pub const MIN_RADIAL_LAYERS: u8 = 1;
pub const MAX_RADIAL_LAYERS: u8 = 3;
/// 一层的槽位数下限：少于 8 格时外面仍然是 8 格，只是空着（neoview `MIN_SLOT_COUNT`）。
pub const MIN_RADIAL_SLOTS: usize = 8;
/// 一层的槽位数上限，也是 `slotIndex` 的上界（neoview `MAX_SLOT_COUNT = 64`）。
pub const MAX_RADIAL_SLOTS: usize = 64;
/// 每多一层，往外长多少像素（neoview `SUBMENU_RADIUS_STEP`）。
pub const SUBMENU_RADIUS_STEP: f32 = 60.0;

/// 半径档（neoview 的 `radius` 输入框范围 60..=300）。
pub const MIN_RADIAL_RADIUS: f32 = 60.0;
pub const MAX_RADIAL_RADIUS: f32 = 300.0;
/// 中心空洞半径档（0..=100，且必须小于 `radius`）。
pub const MIN_RADIAL_INNER_RADIUS: f32 = 0.0;
pub const MAX_RADIAL_INNER_RADIUS: f32 = 100.0;
/// 起始角档（度，`-90` 是正上方）。
pub const MIN_RADIAL_START_ANGLE: f32 = -180.0;
pub const MAX_RADIAL_START_ANGLE: f32 = 180.0;
/// 扫过角档（度）：`360` 是整圈，小于 360 时是一个扇形轮盘。
pub const MIN_RADIAL_SWEEP_ANGLE: f32 = 90.0;
pub const MAX_RADIAL_SWEEP_ANGLE: f32 = 360.0;

pub const DEFAULT_RADIAL_RADIUS: f32 = 120.0;
pub const DEFAULT_RADIAL_INNER_RADIUS: f32 = 40.0;
pub const DEFAULT_RADIAL_START_ANGLE: f32 = -90.0;
pub const DEFAULT_RADIAL_SWEEP_ANGLE: f32 = 360.0;
/// 出厂文档的层数。
///
/// neoview 的 parser 缺省是 3，而它随包的默认文档写的是 2 —— 两处不一致。
/// 这里取 **3**：截图那一屏就是「3 层」，且 parser 的缺省才是新文档的落点。
pub const DEFAULT_RADIAL_LAYERS: u8 = MAX_RADIAL_LAYERS;

/// 出厂轮盘的 id。
pub const DEFAULT_RADIAL_MENU_ID: &str = "default";
/// 预设槽位绑定的 id 前缀：「重置」只重写这一批（与 `preset.rs` 的 `preset-tap-` 同法）。
pub const RADIAL_PRESET_ID_PREFIX: &str = "preset-radial-";

/// 画法（neoview `variant`：`slice` = 扇区、`bubble` = 气泡）。
///
/// 注意 neoview 运行时**只把 `slice` 接进了 ray-menu**（`observedAttributes` 里没有
/// variant），气泡只在另一份 vendored 实现里。这里照它的数据形状收下这个值，
/// 但两种画法在 Rossi 的运行时里暂时同一套弧线 —— 存下来是为了导出/导入不丢。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RadialMenuVariant {
    #[default]
    Slice,
    Bubble,
}

impl RadialMenuVariant {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Slice => "slice",
            Self::Bubble => "bubble",
        }
    }
}

/// 轮盘里的一个条目（neoview `ReaderRadialMenuItem`）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialMenuItem {
    /// 稳定标识 = 绑定包里的 `itemId`。用户数据会引用它，**只能追加不能重排**。
    pub id: String,
    /// 显示文字。neoview 在绑动作时让它自动跟随动作名，之后可手改。
    pub label: String,
    /// 这一层里的第几格（0..63）。空槽不落进文档，由几何推出（见 [`layer_slot_count`]）。
    pub slot_index: usize,
    /// 遗留的直连动作：新条目一律走绑定，这里只为读得懂老包而保留。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    /// 「跳转轮盘」型条目：松手不执行动作，而是换到另一个轮盘（neoview `moveToMenuId`）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub move_to_menu_id: Option<String>,
    #[serde(default)]
    pub disabled: bool,
}

impl Default for RadialMenuItem {
    fn default() -> Self {
        Self {
            id: String::new(),
            label: String::new(),
            slot_index: 0,
            action: None,
            move_to_menu_id: None,
            disabled: false,
        }
    }
}

impl RadialMenuItem {
    pub fn is_move_to(&self) -> bool {
        self.move_to_menu_id
            .as_deref()
            .is_some_and(|id| !id.is_empty())
    }
}

/// 一个轮盘（neoview `ReaderRadialMenuDefinition`：`layers` 是「每层一组条目」）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialMenuDefinition {
    pub id: String,
    pub name: String,
    /// 下标 0 = 第 1 环（最里面那一圈）。
    pub layers: Vec<Vec<RadialMenuItem>>,
}

impl Default for RadialMenuDefinition {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            layers: vec![Vec::new(), Vec::new(), Vec::new()],
        }
    }
}

impl RadialMenuDefinition {
    /// 第 `level` 环（1 起）的条目。
    pub fn layer(&self, level: usize) -> &[RadialMenuItem] {
        self.layers.get(level - 1).map(Vec::as_slice).unwrap_or(&[])
    }

    pub fn slot_count(&self, level: usize) -> usize {
        layer_slot_count(self.layer(level))
    }

    /// 这一格里有没有条目（按 `slotIndex`）。
    pub fn item_at(&self, level: usize, index: usize) -> Option<&RadialMenuItem> {
        self.layer(level)
            .iter()
            .find(|item| item.slot_index == index)
    }

    pub fn item(&self, item_id: &str) -> Option<&RadialMenuItem> {
        self.layers.iter().flatten().find(|item| item.id == item_id)
    }

    /// 轮盘内所有条目 id 不许重复：绑定按 `(menuId, itemId)` 认，重复就是绑不上。
    pub fn duplicated_item_ids(&self) -> Vec<String> {
        let mut seen: Vec<&str> = Vec::new();
        let mut dup: Vec<String> = Vec::new();
        for entry in self.layers.iter().flatten() {
            if seen.contains(&entry.id.as_str()) && !dup.contains(&entry.id.clone()) {
                dup.push(entry.id.clone());
            }
            seen.push(entry.id.as_str());
        }
        dup
    }
}

/// 一份轮盘文档（持久化单位；槽位的动作不在这里，在绑定表里）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialConfig {
    /// 轮盘总开关。新增的「启用类」字段一律默认开：否则导入旧配置会把用户
    /// 没碰过的通道关掉。
    pub enabled: bool,
    /// 显示几层（同心环数）。
    pub layer_count: u8,
    pub active_menu_id: String,
    pub menus: Vec<RadialMenuDefinition>,
    /// 第 1 环的外半径；每多一层往外长 [`SUBMENU_RADIUS_STEP`]。
    pub radius: f32,
    pub inner_radius: f32,
    pub variant: RadialMenuVariant,
    pub start_angle: f32,
    pub sweep_angle: f32,
}

impl Default for RadialConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            layer_count: DEFAULT_RADIAL_LAYERS,
            active_menu_id: DEFAULT_RADIAL_MENU_ID.into(),
            menus: vec![default_menu()],
            radius: DEFAULT_RADIAL_RADIUS,
            inner_radius: DEFAULT_RADIAL_INNER_RADIUS,
            variant: RadialMenuVariant::default(),
            start_angle: DEFAULT_RADIAL_START_ANGLE,
            sweep_angle: DEFAULT_RADIAL_SWEEP_ANGLE,
        }
    }
}

impl RadialConfig {
    pub fn menu(&self, id: &str) -> Option<&RadialMenuDefinition> {
        self.menus.iter().find(|menu| menu.id == id)
    }

    /// 生效轮盘：`activeMenuId` 优先，指不到时退回第一个 —— 运行时不该因为
    /// 一次「删了又没改选中项」而整个轮盘打不开。
    pub fn active_menu(&self) -> Option<&RadialMenuDefinition> {
        self.menu(&self.active_menu_id)
            .or_else(|| self.menus.first())
    }

    /// 显示出来的层数（夹进合法档）。
    pub fn layers(&self) -> usize {
        (self.layer_count as usize).clamp(MIN_RADIAL_LAYERS as usize, MAX_RADIAL_LAYERS as usize)
    }

    /// 第 `level` 环（1 起）的内外半径 —— 逐条照 neoview `_getBand`。
    pub fn band(&self, level: usize) -> (f32, f32) {
        match level {
            0 | 1 => (self.inner_radius, self.radius),
            2 => (self.radius, self.radius + SUBMENU_RADIUS_STEP),
            _ => (
                self.radius + (level as f32 - 2.0) * SUBMENU_RADIUS_STEP,
                self.radius + (level as f32 - 1.0) * SUBMENU_RADIUS_STEP,
            ),
        }
    }

    /// 整个轮盘的外缘（用来算浮层要占多大、贴边时往哪儿挪）。
    pub fn outer_radius(&self) -> f32 {
        self.band(self.layers()).1
    }

    /// 归一化到 `[0, 360)`（落点相对起始角转过了多少）。
    fn offset_from(start_angle: f32, angle: f32) -> f32 {
        (angle - start_angle).rem_euclid(360.0)
    }
}

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

/// 一条轮盘输入 → 引擎认识的 descriptor（外壳只负责报「哪个轮盘的哪个条目」）。
pub fn radial_input(menu_id: &str, item_id: &str) -> InputDescriptor {
    InputDescriptor::Radial {
        menu_id: menu_id.into(),
        item_id: item_id.into(),
    }
}

/// 条目 id 的形状（neoview 的校验：`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$`）。
///
/// 它是落进用户绑定包的 `itemId`：形状不合法的那条，老版本读不懂、也永远匹配不上，
/// 而设置页看着一切正常 —— 所以「合不合法」必须在核心判，不能只当外壳的提示。
pub fn is_item_id_shape(raw: &str) -> bool {
    let bytes: Vec<char> = raw.chars().collect();
    if bytes.is_empty() || bytes.len() > 80 {
        return false;
    }
    bytes[0].is_ascii_alphanumeric()
        && bytes[1..]
            .iter()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
}

/// 一个条目 id（neoview `uniqueId("item", …)` → `item-3`）。
pub fn new_item_id(count: usize) -> String {
    format!("item-{}", count + 1)
}

/// 一个轮盘的 id（neoview `uniqueId("menu", …)` → `menu-2`）。
pub fn new_menu_id(count: usize) -> String {
    format!("menu-{}", count + 1)
}

fn item(item_id: &str, label: &str, slot_index: usize) -> RadialMenuItem {
    RadialMenuItem {
        id: item_id.into(),
        label: label.into(),
        slot_index,
        ..Default::default()
    }
}

/// 出厂轮盘：3 层、每层 4 个条目（占 0/2/4/6 格，其余留空 ⇒ 一圈 8 格里空一半，
/// 与截图那种「有 `+` 的空槽」一致）。
pub fn default_menu() -> RadialMenuDefinition {
    RadialMenuDefinition {
        id: DEFAULT_RADIAL_MENU_ID.into(),
        name: "默认轮盘".into(),
        layers: vec![
            vec![
                item("radial-next-page", "下一页", 0),
                item("radial-previous-page", "上一页", 2),
                item("radial-toggle-controls", "唤出/收起上下栏", 4),
                item("radial-fullscreen", "全屏", 6),
            ],
            vec![
                item("radial-first-page", "第一页", 0),
                item("radial-page-right", "向右翻页", 2),
                item("radial-last-page", "最后一页", 4),
                item("radial-page-left", "向左翻页", 6),
            ],
            vec![
                item("radial-book-mode", "书籍模式", 0),
                item("radial-toggle-direction", "阅读方向切换", 2),
                item("radial-reset-view", "重置视图", 4),
                item("radial-open-settings", "打开设置", 6),
            ],
        ],
    }
}

/// 新建一个轮盘（设置页的「新轮盘」）：三层全空。
pub fn new_menu(count: usize) -> RadialMenuDefinition {
    RadialMenuDefinition {
        id: new_menu_id(count),
        name: format!("轮盘 {}", count + 1),
        layers: vec![Vec::new(), Vec::new(), Vec::new()],
    }
}

/// 出厂文档。
pub fn default_config() -> RadialConfig {
    RadialConfig::default()
}

/// 出厂槽位绑定（默认轮盘那 12 格 → 注册表里的动作）。
///
/// 条目在文档里、动作在这里 —— 这正是「轮盘里的每个操作都是系统里的 action」。
/// 只给默认轮盘生成：用户新建的轮盘是空的，不该被塞一份别人的默认值。
pub fn preset_bindings(menu_id: &str) -> Vec<InputBinding> {
    if menu_id != DEFAULT_RADIAL_MENU_ID {
        return Vec::new();
    }
    // (条目 id, 动作 id)
    const PAIRS: [(&str, &str); 12] = [
        ("radial-next-page", action::NEXT_PAGE),
        ("radial-previous-page", action::PREVIOUS_PAGE),
        ("radial-toggle-controls", action::TOGGLE_CONTROLS),
        ("radial-fullscreen", action::FULLSCREEN),
        ("radial-first-page", action::FIRST_PAGE),
        ("radial-page-right", action::PAGE_RIGHT),
        ("radial-last-page", action::LAST_PAGE),
        ("radial-page-left", action::PAGE_LEFT),
        ("radial-book-mode", action::TOGGLE_BOOK_MODE),
        ("radial-toggle-direction", action::TOGGLE_READING_DIRECTION),
        ("radial-reset-view", action::RESET_VIEW),
        ("radial-open-settings", action::OPEN_SETTINGS),
    ];
    PAIRS
        .iter()
        .map(|(item_id, action_id)| InputBinding {
            id: format!("{RADIAL_PRESET_ID_PREFIX}{DEFAULT_RADIAL_MENU_ID}-{item_id}"),
            action: (*action_id).into(),
            follow_up_actions: Vec::new(),
            context: InputContext::Reader,
            enabled: true,
            ignore_repeat: false,
            input: radial_input(DEFAULT_RADIAL_MENU_ID, item_id),
        })
        .collect()
}

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::model::PointerAction;
    use crate::operation_binding::preset::{TapPreset, tap_preset_bindings};
    use crate::operation_binding::resolve::{conflicts, resolve};
    use crate::operation_binding::vocabulary::{ReaderViewArea, action_definition};

    fn item_ids(menu: &RadialMenuDefinition) -> Vec<String> {
        menu.layers
            .iter()
            .flatten()
            .map(|entry| entry.id.clone())
            .collect()
    }

    /// 一个槽的正中间那一点（画法给的角平分线 × 环带正中）。
    fn point_of(entry: &RadialSlotLayout) -> (f32, f32) {
        let radius = (entry.inner_radius + entry.outer_radius) / 2.0;
        let angle = entry.mid_deg.to_radians();
        (angle.cos() * radius, angle.sin() * radius)
    }

    #[test]
    fn default_wheel_matches_neoview_numbers() {
        let config = default_config();
        assert_eq!(config.radius, 120.0);
        assert_eq!(config.inner_radius, 40.0);
        assert_eq!(config.start_angle, -90.0);
        assert_eq!(config.sweep_angle, 360.0);
        assert_eq!(config.layer_count, 3);
        assert!(is_valid(&config), "{:?}", validate(&config));
        let menu = config.active_menu().unwrap();
        assert_eq!(menu.layers.len(), 3);
        assert_eq!(menu.layers[0].len(), 4);
        assert_eq!(item_ids(menu).len(), 12);
    }

    #[test]
    fn bands_grow_outward_by_the_submenu_step() {
        let config = default_config();
        // 第 1 环 = 空洞→r120；之后每一层往外 60（neoview `_getBand`）。
        assert_eq!(config.band(1), (40.0, 120.0));
        assert_eq!(config.band(2), (120.0, 180.0));
        assert_eq!(config.band(3), (180.0, 240.0));
        assert_eq!(config.outer_radius(), 240.0);
        // 只留一层时外缘就是 r120 —— 层数改小，轮盘整体缩回去。
        let one = RadialConfig {
            layer_count: 1,
            ..default_config()
        };
        assert_eq!(one.outer_radius(), 120.0);
    }

    #[test]
    fn empty_slots_are_implied_by_geometry_not_stored() {
        let config = default_config();
        let menu = config.active_menu().unwrap();
        // 4 个条目排在 0/2/4/6 格 ⇒ 这一层仍是 8 格（MIN_SLOT_COUNT），空着。
        assert_eq!(menu.slot_count(1), 8);
        let layout = slot_layout(&config, menu);
        assert_eq!(layout.len(), 24);
        let filled: Vec<&RadialSlotLayout> = layout
            .iter()
            .filter(|entry| entry.item_id.is_some())
            .collect();
        assert_eq!(filled.len(), 12);
        assert!(
            layout
                .iter()
                .any(|entry| entry.index == 1 && entry.item_id.is_none())
        );
        // 排到第 9 格就把这一层撑到 10 格。
        let wide = RadialMenuDefinition {
            layers: vec![vec![item("x", "X", 9)], vec![], vec![]],
            ..Default::default()
        };
        assert_eq!(wide.slot_count(1), 10);
    }

    #[test]
    fn hit_test_returns_what_the_layout_painted() {
        // 画出来的每一格，往它的角平分线中点打一发，必须回到同一格。
        let config = default_config();
        let menu = config.active_menu().unwrap();
        for entry in slot_layout(&config, menu) {
            let Some(item_id) = entry.item_id.clone() else {
                continue;
            };
            let (dx, dy) = point_of(&entry);
            let hit = slot_at(&config, menu, dx, dy)
                .unwrap_or_else(|| panic!("{item_id} 自己画出来的中点打不中"));
            assert_eq!(hit.level, entry.level);
            assert_eq!(hit.index, entry.index);
            assert_eq!(hit.item_id.as_deref(), Some(item_id.as_str()));
        }
    }

    #[test]
    fn hole_empty_slot_and_outside_all_select_nothing() {
        let config = default_config();
        let menu = config.active_menu().unwrap();
        // 中心空洞：松手取消。
        assert_eq!(slot_at(&config, menu, 10.0, 0.0), None);
        // 外缘之外。
        assert_eq!(slot_at(&config, menu, 241.0, 0.0), None);
        // 第 1 环里的空格（slotIndex 1）：没有条目 ⇒ 不选中，而不是「选中隔壁」。
        let empty = slot_layout(&config, menu)
            .into_iter()
            .find(|entry| entry.level == 1 && entry.index == 1)
            .unwrap();
        let (dx, dy) = point_of(&empty);
        assert_eq!(slot_at(&config, menu, dx, dy), None);
        // 压在最外缘这一条边界上仍属最外层。
        let last = slot_layout(&config, menu).pop().unwrap();
        let (dx, _) = point_of(&last);
        let edge = (config.outer_radius(), 0.0);
        assert!(slot_at(&config, menu, edge.0, edge.1).is_some() || dx < 0.0);
    }

    #[test]
    fn start_angle_and_sweep_move_the_whole_wheel() {
        // 起始角 -90 ⇒ 第 0 格居中于 12 点；改成 0 ⇒ 居中于 3 点。
        let config = default_config();
        let menu = config.active_menu().unwrap();
        let first = &slot_layout(&config, menu)[0];
        assert!((first.mid_deg - (-90.0)).abs() < 1e-4);
        assert_eq!(first.selectable, true);

        let turned = RadialConfig {
            start_angle: 0.0,
            ..default_config()
        };
        let laid = slot_layout(&turned, turned.active_menu().unwrap());
        assert!((laid[0].mid_deg - 0.0).abs() < 1e-4);
        let (dx, dy) = point_of(&laid[0]);
        assert_eq!(
            slot_at(&turned, turned.active_menu().unwrap(), dx, dy)
                .unwrap()
                .index,
            0
        );

        // 扫过角 90° ⇒ 只有右下那一象限是轮盘，超出扫过角的不算选中。
        let fan = RadialConfig {
            start_angle: -45.0,
            sweep_angle: 90.0,
            ..default_config()
        };
        let fan_menu = fan.active_menu().unwrap();
        assert_eq!(
            slot_layout(&fan, fan_menu).len(),
            8 * 3,
            "格数不变，只是挤进 90°"
        );
        assert!(
            slot_at(&fan, fan_menu, 80.0, 0.0).is_some(),
            "0° 在 -45..45 里"
        );
        assert_eq!(
            slot_at(&fan, fan_menu, 0.0, 80.0),
            None,
            "90° 已经在扇形之外"
        );
    }

    #[test]
    fn slots_number_clockwise_from_the_start_angle() {
        let config = default_config();
        let menu = config.active_menu().unwrap();
        let at = |angle: f32| {
            let radius = 80.0;
            let radian = angle.to_radians();
            slot_at(&config, menu, radian.cos() * radius, radian.sin() * radius)
        };
        assert_eq!(at(-90.0).unwrap().index, 0, "12 点 = 第 0 格");
        assert_eq!(at(0.0).unwrap().index, 2, "3 点顺时针第 2 格");
        assert_eq!(at(90.0).unwrap().index, 4, "6 点");
        assert_eq!(at(180.0).unwrap().index, 6, "9 点");
    }

    #[test]
    fn preset_items_all_resolve_through_the_binding_table() {
        // 「轮盘里的每个操作都是绑定系统里的 action」—— 这条判据就是这个测试：
        // 预设条目必须由**同一个解析器**解析出动作，而不是走一条轮盘专用路径。
        let config = default_config();
        let menu = config.active_menu().unwrap();
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        for entry in slot_layout(&config, menu)
            .iter()
            .filter(|e| e.item_id.is_some())
        {
            let item_id = entry.item_id.clone().unwrap();
            let resolved = resolve(
                &bindings,
                &radial_input(DEFAULT_RADIAL_MENU_ID, &item_id),
                &[InputContext::Reader],
            )
            .unwrap_or_else(|| panic!("{item_id} 解析不出动作"));
            let definition = action_definition(&resolved.action).unwrap();
            assert!(definition.implemented, "{item_id} 绑了未实现的动作");
            // neoview 的槽位动作选项里**排除** `radial.*`：轮盘里再放一个「开轮盘」是循环。
            assert!(
                !definition.id.starts_with("radial."),
                "{item_id} 绑了轮盘自身的动作"
            );
        }
        assert!(preset_bindings("menu-2").is_empty(), "新轮盘是空的");
    }

    #[test]
    fn every_preset_item_has_a_binding_and_vice_versa() {
        // 文档里的条目与绑定行必须一一对上：多出来的绑定行是孤儿（画不出来），
        // 缺了绑定行的条目是死槽（点了没反应）。
        let config = default_config();
        let menu = config.active_menu().unwrap();
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        let bound: Vec<&str> = bindings
            .iter()
            .filter_map(|binding| match &binding.input {
                InputDescriptor::Radial { item_id, .. } => Some(item_id.as_str()),
                _ => None,
            })
            .collect();
        for item_id in item_ids(menu) {
            assert!(bound.contains(&item_id.as_str()), "{item_id} 没有绑定行");
        }
        assert_eq!(bound.len(), menu.layers.iter().map(Vec::len).sum::<usize>());
    }

    #[test]
    fn preset_slots_fit_their_layer_and_do_not_collide() {
        let config = default_config();
        let menu = config.active_menu().unwrap();
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        for binding in &bindings {
            let InputDescriptor::Radial { item_id, .. } = &binding.input else {
                continue;
            };
            assert!(menu.item(item_id).is_some(), "{item_id} 在默认轮盘里不存在");
        }
        assert!(conflicts(&bindings).is_empty());
    }

    #[test]
    fn deleting_an_item_or_layer_prunes_only_its_bindings() {
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        let config = default_config();
        assert_eq!(prune_bindings(&config, &bindings).len(), bindings.len());

        // 把第 3 层清空 ⇒ 那一层的 4 条走，其余留着。
        let mut shrunk = default_config();
        shrunk.menus[0].layers[2].clear();
        let kept = prune_bindings(&shrunk, &bindings);
        assert_eq!(kept.len(), 8);
        assert!(
            prune_bindings(&shrunk, &kept).len() == 8,
            "再剪一次不该更少（幂等）"
        );

        // 删掉整个轮盘 ⇒ 它的绑定全清，键盘/点击那些一条不许动。
        let emptied = RadialConfig {
            menus: vec![RadialMenuDefinition {
                id: "other".into(),
                name: "别的".into(),
                ..Default::default()
            }],
            active_menu_id: "other".into(),
            ..Default::default()
        };
        let mixed: Vec<InputBinding> = bindings
            .into_iter()
            .chain(tap_preset_bindings(TapPreset::RightHand))
            .collect();
        let kept = prune_bindings(&emptied, &mixed);
        assert_eq!(kept.len(), 3, "只剩九宫格那三条");
        assert!(
            kept.iter()
                .all(|b| !b.id.starts_with(RADIAL_PRESET_ID_PREFIX))
        );
    }

    #[test]
    fn validation_names_the_offending_field() {
        let mut config = default_config();
        config.layer_count = 5;
        let problems = validate(&config);
        assert!(problems.iter().any(|p| p.contains("层数")), "{problems:?}");

        config.layer_count = 3;
        config.inner_radius = 200.0;
        assert!(validate(&config).iter().any(|p| p.contains("内半径")));

        config.inner_radius = 40.0;
        config.radius = 400.0;
        assert!(validate(&config).iter().any(|p| p.contains("半径")));

        config.radius = 120.0;
        config.sweep_angle = 30.0;
        assert!(validate(&config).iter().any(|p| p.contains("扫过角")));

        config.sweep_angle = 360.0;
        config.active_menu_id = "nope".into();
        assert!(validate(&config).iter().any(|p| p.contains("nope")));

        config.active_menu_id = DEFAULT_RADIAL_MENU_ID.into();
        config.menus[0].layers[0].push(item("radial-next-page", "重复", 7));
        assert!(validate(&config).iter().any(|p| p.contains("重复")));

        config.menus[0].layers[0].pop();
        config.menus[0].layers[0][0].move_to_menu_id = Some("gone".into());
        assert!(validate(&config).iter().any(|p| p.contains("不存在的轮盘")));
        assert!(is_valid(&default_config()));
    }

    #[test]
    fn malformed_item_ids_are_rejected_by_validation() {
        // 形状不合法的 id 会静默失效（老版本读不懂、绑定永远匹配不上），所以它必须
        // 过不了校验 —— 而不是只在外壳的一句 assert 里挡一下（release 会被剥掉）。
        assert!(is_item_id_shape("item-1"));
        assert!(is_item_id_shape("radial-next-page"));
        assert!(is_item_id_shape("a"));
        assert!(is_item_id_shape("x_1-2.3"));
        for bad in ["", "-bad", ".bad", "a b", "a/b", &"x".repeat(81)] {
            assert!(!is_item_id_shape(bad), "{bad} 应当被挡下");
        }
        let mut config = default_config();
        config.menus[0].layers[0][0].id = "-nope".into();
        assert!(
            validate(&config).iter().any(|p| p.contains("形状不合法")),
            "{:?}",
            validate(&config)
        );
    }

    #[test]
    fn menu_count_is_capped_like_neoview() {
        let mut config = default_config();
        for index in 1..MAX_RADIAL_MENUS {
            config.menus.push(new_menu(index));
        }
        assert_eq!(config.menus.len(), MAX_RADIAL_MENUS);
        assert!(is_valid(&config), "16 个轮盘是上限不是越界");
        config.menus.push(new_menu(MAX_RADIAL_MENUS));
        assert!(validate(&config).iter().any(|p| p.contains("上限")));
    }

    #[test]
    fn new_menus_and_items_use_neoview_slug_ids() {
        assert_eq!(new_menu_id(1), "menu-2");
        assert_eq!(new_item_id(0), "item-1");
        assert_eq!(new_item_id(41), "item-42");
        // id 形状要过 neoview 的校验：`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$`。
        // 手写而不是引一个正则依赖：这是测试里的一次性检查，不值得为此加 crate。
        fn matches_neoview_id_shape(raw: &str) -> bool {
            let mut chars = raw.chars();
            let Some(first) = chars.next() else {
                return false;
            };
            if !(first.is_ascii_alphanumeric()) {
                return false;
            }
            raw.len() <= 80
                && chars.all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
        }
        assert!(matches_neoview_id_shape(&new_menu_id(1)));
        assert!(matches_neoview_id_shape(&new_item_id(3)));
        for id in item_ids(&default_menu()) {
            assert!(
                matches_neoview_id_shape(&id),
                "出厂条目 id {id} 过不了 neoview 的校验"
            );
        }
    }

    #[test]
    fn config_round_trips_and_keeps_unknown_and_missing_fields() {
        let config = default_config();
        let json = serde_json::to_string(&config).unwrap();
        let parsed: RadialConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, config);
        for field in [
            "\"activeMenuId\"",
            "\"layerCount\"",
            "\"innerRadius\"",
            "\"startAngle\"",
            "\"sweepAngle\"",
            "\"slotIndex\"",
        ] {
            assert!(json.contains(field), "缺字段 {field}：{json}");
        }
        // 老包（只有 menus）也要能读进来：启用类字段缺省为**开**。
        let legacy: RadialConfig = serde_json::from_str(
            r#"{"menus":[{"id":"default","name":"默认轮盘","layers":[[{"id":"a","label":"A","slotIndex":0}]]}]}"#,
        )
        .unwrap();
        assert!(legacy.enabled);
        assert_eq!(legacy.radius, DEFAULT_RADIAL_RADIUS);
        assert_eq!(legacy.active_menu().map(|m| m.id.as_str()), Some("default"));
        assert_eq!(legacy.active_menu().unwrap().layer(1).len(), 1);
        // 未知字段忽略而不是崩（导入 neoview 的包时会有）。
        let future: RadialConfig = serde_json::from_str(
            r#"{"enabled":true,"layerCount":2,"activeMenuId":"","menus":[],"brandNew":42}"#,
        )
        .unwrap();
        assert_eq!(future.layer_count, 2);
    }

    #[test]
    fn legacy_inline_action_and_move_to_survive_the_layout() {
        // 遗留直连动作与「跳转轮盘」都要随布局带回外壳：前者是派发不到时的回落，
        // 后者决定松手是执行还是换轮盘。
        let menu = RadialMenuDefinition {
            id: "default".into(),
            name: "默认轮盘".into(),
            layers: vec![
                vec![
                    RadialMenuItem {
                        id: "a".into(),
                        label: "A".into(),
                        slot_index: 0,
                        action: Some("reader.next-page".into()),
                        ..Default::default()
                    },
                    RadialMenuItem {
                        id: "b".into(),
                        label: "B".into(),
                        slot_index: 1,
                        move_to_menu_id: Some("two".into()),
                        ..Default::default()
                    },
                    RadialMenuItem {
                        id: "c".into(),
                        label: "C".into(),
                        slot_index: 2,
                        disabled: true,
                        ..Default::default()
                    },
                ],
                vec![],
                vec![],
            ],
        };
        let config = RadialConfig {
            menus: vec![
                menu,
                RadialMenuDefinition {
                    id: "two".into(),
                    name: "另一个".into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        assert!(is_valid(&config), "{:?}", validate(&config));
        let layout = slot_layout(&config, config.menu("default").unwrap());
        assert_eq!(layout[0].legacy_action.as_deref(), Some("reader.next-page"));
        assert_eq!(layout[1].move_to_menu_id.as_deref(), Some("two"));
        assert!(!layout[2].selectable, "disabled 的条目不可选");
        let (dx, dy) = point_of(&layout[2]);
        assert_eq!(
            slot_at(&config, config.menu("default").unwrap(), dx, dy),
            None
        );
    }

    #[test]
    fn radial_descriptor_shape_matches_model_rs() {
        // 运行时产的这条必须与 model.rs 钉过的形状逐字节一致，
        // 否则「导入的包能认、自己产的认不出」。
        let json = serde_json::to_string(&radial_input("default", "radial-next-page")).unwrap();
        assert_eq!(
            json,
            r#"{"device":"radial","menuId":"default","itemId":"radial-next-page"}"#
        );
    }

    #[test]
    fn radial_bindings_do_not_shadow_click_bindings() {
        // 轮盘与点击住在同一张表里，靠 descriptor 区分，不许互相顶掉。
        let mut bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        bindings.extend(tap_preset_bindings(TapPreset::RightHand));
        assert!(conflicts(&bindings).is_empty());
        let wheel = resolve(
            &bindings,
            &radial_input(DEFAULT_RADIAL_MENU_ID, "radial-next-page"),
            &[InputContext::Reader],
        )
        .unwrap();
        assert_eq!(wheel.action, action::NEXT_PAGE);
        let tap = resolve(
            &bindings,
            &InputDescriptor::Area {
                area: ReaderViewArea::MiddleRight,
                button: 0,
                action: PointerAction::Click,
            },
            &[InputContext::Reader],
        )
        .unwrap();
        assert_eq!(tap.action, action::PAGE_RIGHT);
    }

    #[test]
    fn layout_covers_every_shown_layer_only() {
        let three = default_config();
        assert_eq!(slot_layout(&three, three.active_menu().unwrap()).len(), 24);
        let two = RadialConfig {
            layer_count: 2,
            ..default_config()
        };
        let laid = slot_layout(&two, two.active_menu().unwrap());
        assert_eq!(laid.len(), 16);
        assert!(laid.iter().all(|entry| entry.level <= 2));
        // 层数只是**显示**几层，第 3 层的条目与绑定必须原样留着：
        // 用户把 3 层调成 2 层再调回来，不该发现自己的槽位被剪光了。
        // 真正会被剪的是「条目从文档里删掉」（另一条测试守着）。
        assert_eq!(
            prune_bindings(&two, &preset_bindings(DEFAULT_RADIAL_MENU_ID)).len(),
            12
        );
    }
}
