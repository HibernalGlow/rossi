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

mod layout;
mod validation;

pub use layout::*;
pub use validation::*;

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::model::PointerAction;
    use crate::operation_binding::preset::{TapPreset, tap_preset_bindings};
    use crate::operation_binding::resolve::{conflicts, resolve};
    use crate::operation_binding::vocabulary::{ReaderViewArea, action_definition};

    mod cases;
}
