//! 轮盘（radial menu）的**文档模型 + 几何**（neoview `ReaderRadialMenu` 那一层）。
//!
//! ## 为什么几何归核心
//!
//! 画一个槽和判断「手指/鼠标落在这个槽里」必须是同一份算术。两边各写一遍时，
//! 只要起始角差 1°、或者层带的划分差一个像素，就会出现**高亮的槽和真正执行的槽
//! 不是同一个** —— 而屏幕上看着没错，没人能靠看发现。所以这里一次算出
//! [`RadialSlotLayout`]（外壳照着它画），命中判定 [`slot_at`] 也从同一组数字读，
//! 外壳拿到的永远是「画出来的那个 = 点得到的那个」。
//!
//! ## 槽位为什么不住在这份文档里
//!
//! 轮盘文档只描述**形状**（几个轮盘、几层、每层几格、半径）。一个槽「干什么」
//! 是一条**绑定**（`InputDescriptor::Radial { menu_id, item_id }` → 注册表里的动作 id），
//! 存在绑定表里而不是这里。理由就是 ADR-0009 的判据 E1：动作 id 是唯一稳定契约，
//! 轮盘只是**另一种输入设备**。于是轮盘槽位与键盘按键完全同权 —— 同一张表、同一个
//! 解析器、同一套冲突判定，追加动作（`followUpActions`）也自动可用，
//! 不需要为轮盘再写一遍「这个输入对应什么动作」。
//!
//! 这份文档与绑定表之间的接缝由 [`prune_bindings`] 守住：删轮盘 / 减层数会让
//! `itemId` 不复存在，那些绑定行必须一起消失，否则设置页会列出画不出来的槽。

use serde::{Deserialize, Serialize};

use super::model::{InputBinding, InputDescriptor};
use super::vocabulary::{InputContext, action};

/// 一个轮盘文档最多能有多少个轮盘（neoview 的上限，见 ADR-0009）。
pub const MAX_RADIAL_MENUS: usize = 16;
/// 层数下限/上限（neoview「3 层」那一档的上限）。
pub const MIN_RADIAL_LAYERS: u8 = 1;
pub const MAX_RADIAL_LAYERS: u8 = 3;
/// 每层扇区数的上下限。8 = 出厂值，与 neoview 的默认轮盘一致。
pub const MIN_RADIAL_SECTORS: u8 = 4;
pub const MAX_RADIAL_SECTORS: u8 = 16;
/// 外半径（截图里「r120」那一项）。
pub const DEFAULT_RADIAL_RADIUS: f32 = 120.0;
/// 中心空洞半径（截图里「内40」）：落在洞里的指针**不选中任何槽**，
/// 这一档同时充当「松手在这里 = 取消」的判据。
pub const DEFAULT_RADIAL_INNER_RADIUS: f32 = 40.0;
pub const DEFAULT_RADIAL_SECTORS: u8 = 8;
/// 第一个扇区的**中心角**：`-90°` 即正上方（12 点方向），顺时针编号。
///
/// 做成常量、并且只被 [`slot_layout`] 与 [`slot_at`] 读，是因为画法和命中判定一旦
/// 分叉就是「画在 12 点、点中在 1 点」，而这种错位靠看屏幕发现不了。
pub const RADIAL_START_DEG: f32 = -90.0;

/// 轮盘出厂时的默认菜单 id（也是 [`default_config`] 里唯一那个轮盘的 id）。
pub const DEFAULT_RADIAL_MENU_ID: &str = "default";
/// 预设轮盘绑定的 id 前缀：「重置轮盘」只重写这一批，用户自加的绑定原样保留
/// （与 `preset.rs` 的 `preset-tap-` 同一手法）。
pub const RADIAL_PRESET_ID_PREFIX: &str = "preset-radial-";

/// 一个轮盘的**外观与几何**（截图里折叠起来的那一节）。
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialGeometry {
    pub radius: f32,
    pub inner_radius: f32,
    pub sectors: u8,
}

impl Default for RadialGeometry {
    fn default() -> Self {
        Self {
            radius: DEFAULT_RADIAL_RADIUS,
            inner_radius: DEFAULT_RADIAL_INNER_RADIUS,
            sectors: DEFAULT_RADIAL_SECTORS,
        }
    }
}

impl RadialGeometry {
    /// 合法几何：半径为正、空洞小于外半径、扇区数在档内。
    fn is_sane(&self) -> bool {
        self.radius > 0.0
            && self.inner_radius >= 0.0
            && self.inner_radius < self.radius
            && (MIN_RADIAL_SECTORS..=MAX_RADIAL_SECTORS).contains(&self.sectors)
    }

    /// 单层环带的宽度。层数由外部给（几何本身不知道自己是几层）。
    fn band(&self, layers: u8) -> f32 {
        let layers = layers.max(MIN_RADIAL_LAYERS) as f32;
        (self.radius - self.inner_radius) / layers
    }

    /// 第 [layer] 环（1 起）的内外半径。
    fn band_radii(&self, layers: u8, layer: u8) -> (f32, f32) {
        let band = self.band(layers);
        (
            self.inner_radius + (layer.saturating_sub(1)) as f32 * band,
            self.inner_radius + layer as f32 * band,
        )
    }
}

/// 一个轮盘（一份文档里的一个条目）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialMenu {
    pub id: String,
    pub name: String,
    pub layers: u8,
    pub geometry: RadialGeometry,
}

impl Default for RadialMenu {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            layers: MAX_RADIAL_LAYERS,
            geometry: RadialGeometry::default(),
        }
    }
}

impl RadialMenu {
    /// 这个轮盘上一共有多少个槽（层数 × 每层扇区）。
    pub fn slot_count(&self) -> usize {
        self.layers.max(MIN_RADIAL_LAYERS) as usize
            * self.geometry.sectors.max(MIN_RADIAL_SECTORS) as usize
    }

    /// 槽 [slot] 是否存在于这个轮盘的形状里。
    pub fn has_slot(&self, slot: &RadialSlot) -> bool {
        (MIN_RADIAL_LAYERS..=self.layers).contains(&slot.layer)
            && slot.sector < self.geometry.sectors
    }
}

/// 一份轮盘文档（持久化单位，与绑定表并列存在用户设置里）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RadialConfig {
    /// 轮盘总开关。
    ///
    /// 默认**开**：结构体新增「启用类」字段必须默认 true，否则导入一份旧配置
    /// 会把用户没碰过的通道关掉（`preset-and-adjustment` 里 `gamepad_enabled` 的教训）。
    pub enabled: bool,
    /// 当前生效的轮盘 id（设置页的下拉框选中的就是它）。
    pub active_menu_id: String,
    pub menus: Vec<RadialMenu>,
}

impl Default for RadialConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            active_menu_id: DEFAULT_RADIAL_MENU_ID.into(),
            menus: vec![default_menu()],
        }
    }
}

impl RadialConfig {
    /// 取某个轮盘（按 id）。找不到返回 `None`。
    pub fn menu(&self, id: &str) -> Option<&RadialMenu> {
        self.menus.iter().find(|menu| menu.id == id)
    }

    /// 当前生效的那个轮盘：`activeMenuId` 优先，指向已删除的轮盘时退回第一个
    /// —— 运行时不该因为一次「删了又没改激活项」而整个轮盘打不开。
    pub fn active_menu(&self) -> Option<&RadialMenu> {
        self.menu(&self.active_menu_id)
            .or_else(|| self.menus.first())
    }
}

/// 一个槽的位置：第 [layer] 环（1 起）、第 [sector] 格（0 起，顺时针）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RadialSlot {
    pub layer: u8,
    pub sector: u8,
}

impl RadialSlot {
    /// 槽的稳定标识 = 绑定包里的 `itemId`。
    ///
    /// 形状 `l{层}s{格}` 是**要落进用户绑定包**的东西：改了它，用户已有的轮盘绑定
    /// 全部指向不存在的槽。所以它只能追加、不能重排。
    pub fn item_id(&self) -> String {
        format!("l{}s{}", self.layer, self.sector)
    }

    pub fn parse_item_id(raw: &str) -> Option<Self> {
        let rest = raw.strip_prefix('l')?;
        let (layer, sector) = rest.split_once('s')?;
        Some(Self {
            layer: layer.parse().ok()?,
            sector: sector.parse().ok()?,
        })
    }
}

/// 一个槽的**画法与命中区**（同一个结构体服务两件事，见模块头）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RadialSlotLayout {
    pub item_id: String,
    pub layer: u8,
    pub sector: u8,
    pub inner_radius: f32,
    pub outer_radius: f32,
    /// 起始角与终止角（度，屏幕坐标系：x 向右、y 向下）。
    pub start_deg: f32,
    pub end_deg: f32,
    /// 角平分线：文字与图标摆放处。
    pub mid_deg: f32,
}

/// 算出这个轮盘的**全部**槽位布局（按层、再按格排序）。
///
/// 每格的**中心角**落在 `RADIAL_START_DEG + sector * sweep` 上（扇区 0 居中于 12 点），
/// 所以一格是「以中线为界左右各半格」—— 与手指从圆心往外推的手感一致。
pub fn slot_layout(menu: &RadialMenu) -> Vec<RadialSlotLayout> {
    let layers = menu.layers.clamp(MIN_RADIAL_LAYERS, MAX_RADIAL_LAYERS);
    let sectors = menu
        .geometry
        .sectors
        .clamp(MIN_RADIAL_SECTORS, MAX_RADIAL_SECTORS);
    let sweep = 360.0 / sectors as f32;
    let mut out = Vec::with_capacity(layers as usize * sectors as usize);
    for layer in 1..=layers {
        let (inner_radius, outer_radius) = menu.geometry.band_radii(layers, layer);
        for sector in 0..sectors {
            let mid_deg = RADIAL_START_DEG + sector as f32 * sweep;
            out.push(RadialSlotLayout {
                item_id: RadialSlot { layer, sector }.item_id(),
                layer,
                sector,
                inner_radius,
                outer_radius,
                start_deg: mid_deg - sweep / 2.0,
                end_deg: mid_deg + sweep / 2.0,
                mid_deg,
            });
        }
    }
    out
}

/// 落点 → 槽（`dx` / `dy` 是相对轮盘**圆心**的偏移，屏幕坐标系）。
///
/// 落在中心空洞里、或落在外半径之外，返回 `None` —— 前者是「松手取消」，
/// 后者是「移出去了，别硬塞一个动作给用户」。
pub fn slot_at(menu: &RadialMenu, dx: f32, dy: f32) -> Option<RadialSlot> {
    let distance = (dx * dx + dy * dy).sqrt();
    let geometry = menu.geometry;
    if distance < geometry.inner_radius || distance > geometry.radius {
        return None;
    }
    let layers = menu.layers.clamp(MIN_RADIAL_LAYERS, MAX_RADIAL_LAYERS);
    let sectors = menu
        .geometry
        .sectors
        .clamp(MIN_RADIAL_SECTORS, MAX_RADIAL_SECTORS);
    let band = geometry.band(layers);
    // 环号由半径决定。**夹**到 [1, layers] 而不是判越界返回 None：刚好压在外半径上
    // 的那一发（`distance == radius`）在浮点下会算出 `layers + 1`，而它显然属于最外环。
    let layer =
        (((distance - geometry.inner_radius) / band).floor() + 1.0).clamp(1.0, layers as f32) as u8;
    let sweep = 360.0 / sectors as f32;
    let angle = dy.atan2(dx).to_degrees();
    // 半格的偏移：中线两侧各算同一格（与 slot_layout 的 start/end 同一口径）。
    let offset = (angle - RADIAL_START_DEG + sweep / 2.0).rem_euclid(360.0);
    let sector = ((offset / sweep).floor() as u8).min(sectors - 1);
    Some(RadialSlot { layer, sector })
}

/// 这个落点对应的布局条目（外壳高亮时用它取矩形边界，省得再算一遍）。
pub fn layout_at<'a>(
    menu: &RadialMenu,
    layout: &'a [RadialSlotLayout],
    dx: f32,
    dy: f32,
) -> Option<&'a RadialSlotLayout> {
    let slot = slot_at(menu, dx, dy)?;
    layout
        .iter()
        .find(|entry| entry.layer == slot.layer && entry.sector == slot.sector)
}

/// 一条轮盘输入 → 引擎认识的 descriptor（外壳只负责报「哪个轮盘的哪个槽」）。
pub fn radial_input(menu_id: &str, item_id: &str) -> InputDescriptor {
    InputDescriptor::Radial {
        menu_id: menu_id.into(),
        item_id: item_id.into(),
    }
}

/// 出厂轮盘：3 层、r120、内 40、每层 8 格。
pub fn default_menu() -> RadialMenu {
    RadialMenu {
        id: DEFAULT_RADIAL_MENU_ID.into(),
        name: "默认轮盘".into(),
        layers: MAX_RADIAL_LAYERS,
        geometry: RadialGeometry::default(),
    }
}

/// 新建一个轮盘（设置页的「新轮盘」按钮）。
pub fn new_menu(count: usize) -> RadialMenu {
    RadialMenu {
        id: format!("menu-{}", count + 1),
        name: format!("轮盘 {}", count + 1),
        layers: MAX_RADIAL_LAYERS,
        geometry: RadialGeometry::default(),
    }
}

/// 出厂文档。
pub fn default_config() -> RadialConfig {
    RadialConfig::default()
}

/// 轮盘的出厂绑定（**只有默认轮盘**有；新建的空轮盘故意什么都不绑）。
///
/// 布局照 neoview 的手感：内环是最高频的四条（前进 / 退回 / 全屏 / 上下栏），
/// 中环是翻页族与首尾，外环是低频的视图与设置。绑的都是注册表里 `implemented`
/// 为真的动作 —— 出厂即失效的槽位比空槽更糟。
pub fn preset_bindings(menu_id: &str) -> Vec<InputBinding> {
    if menu_id != DEFAULT_RADIAL_MENU_ID {
        return Vec::new();
    }
    // (层, 格, 动作)。格 0 = 正上方，顺时针。
    const SLOTS: [(u8, u8, &str); 12] = [
        (1, 0, action::NEXT_PAGE),
        (1, 2, action::PREVIOUS_PAGE),
        (1, 4, action::TOGGLE_CONTROLS),
        (1, 6, action::FULLSCREEN),
        (2, 0, action::FIRST_PAGE),
        (2, 2, action::PAGE_RIGHT),
        (2, 4, action::LAST_PAGE),
        (2, 6, action::PAGE_LEFT),
        (3, 0, action::TOGGLE_BOOK_MODE),
        (3, 2, action::TOGGLE_READING_DIRECTION),
        (3, 4, action::RESET_VIEW),
        (3, 6, action::OPEN_SETTINGS),
    ];
    SLOTS
        .iter()
        .map(|(layer, sector, action_id)| {
            let slot = RadialSlot {
                layer: *layer,
                sector: *sector,
            };
            let item_id = slot.item_id();
            InputBinding {
                id: format!("{RADIAL_PRESET_ID_PREFIX}{DEFAULT_RADIAL_MENU_ID}-{item_id}"),
                action: (*action_id).into(),
                follow_up_actions: Vec::new(),
                context: InputContext::Reader,
                enabled: true,
                ignore_repeat: false,
                input: radial_input(DEFAULT_RADIAL_MENU_ID, &item_id),
            }
        })
        .collect()
}

/// 校验：返回**人话**的问题清单（空 = 这份文档可用）。
///
/// 为什么不返回错误码：这份清单要直接显示在设置页上，而「哪里不对」几乎总是
/// 需要一句上下文才能看懂（「层数越界」不如「轮盘『默认轮盘』的层数 5 超过 3」）。
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
    let unique = {
        let mut sorted = ids.clone();
        sorted.sort_unstable();
        sorted.dedup();
        sorted.len()
    };
    if unique != ids.len() {
        problems.push("轮盘 id 有重复（绑定会指错轮盘）".into());
    }
    ids.sort_unstable();
    if !config.active_menu_id.is_empty() && !ids.contains(&config.active_menu_id.as_str()) {
        problems.push(format!("生效轮盘 {} 不存在", config.active_menu_id));
    }
    for menu in &config.menus {
        if menu.id.is_empty() {
            problems.push("有轮盘的 id 是空的".into());
        }
        if !(MIN_RADIAL_LAYERS..=MAX_RADIAL_LAYERS).contains(&menu.layers) {
            problems.push(format!(
                "轮盘『{}』的层数 {} 不在 {MIN_RADIAL_LAYERS}..={MAX_RADIAL_LAYERS}",
                menu.name, menu.layers
            ));
        }
        if !menu.geometry.is_sane() {
            problems.push(format!(
                "轮盘『{}』的几何不合法（r{} · 内{} · {} 格）",
                menu.name, menu.geometry.radius, menu.geometry.inner_radius, menu.geometry.sectors
            ));
        }
    }
    problems
}

/// 这份文档能不能用。
pub fn is_valid(config: &RadialConfig) -> bool {
    validate(config).is_empty()
}

/// 删掉指向**已不存在的槽**的轮盘绑定，返回留下的那些。
///
/// 这是「形状在文档、动作在绑定表」这个分工的必要收口：用户把 3 层改成 2 层、
/// 或者删掉一个轮盘之后，`l3s0` 这类 `itemId` 就再没有对应的画法了。留着它们
/// 的表现是「设置页列出一堆画不出来的槽」，所以形状一变就顺手剪一次。
pub fn prune_bindings(config: &RadialConfig, bindings: &[InputBinding]) -> Vec<InputBinding> {
    bindings
        .iter()
        .filter(|binding| match &binding.input {
            InputDescriptor::Radial { menu_id, item_id } => config
                .menu(menu_id)
                .and_then(|menu| {
                    RadialSlot::parse_item_id(item_id).map(|slot| menu.has_slot(&slot))
                })
                .unwrap_or(false),
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

    fn point(menu: &RadialMenu, layer: u8, sector: u8) -> (f32, f32) {
        let layout = slot_layout(menu);
        let entry = layout
            .iter()
            .find(|entry| entry.layer == layer && entry.sector == sector)
            .expect("这一格应当在布局里");
        let radius = (entry.inner_radius + entry.outer_radius) / 2.0;
        let angle = entry.mid_deg.to_radians();
        (angle.cos() * radius, angle.sin() * radius)
    }

    #[test]
    fn default_wheel_is_three_layers_of_eight_sectors() {
        let menu = default_menu();
        assert_eq!(menu.layers, 3);
        assert_eq!(menu.geometry.sectors, 8);
        assert_eq!(menu.slot_count(), 24);
        assert_eq!(slot_layout(&menu).len(), 24);
        assert!(is_valid(&default_config()));
    }

    #[test]
    fn first_sector_is_centered_straight_up_and_numbering_is_clockwise() {
        let menu = default_menu();
        let layout = slot_layout(&menu);
        let first = &layout[0];
        // 正上方 = 屏幕坐标的 -90°（y 向下）。第一格的中线在 12 点，左右各半格。
        assert_eq!(first.item_id, "l1s0");
        assert!((first.mid_deg - RADIAL_START_DEG).abs() < 1e-4);
        assert!((first.start_deg - (-112.5)).abs() < 1e-4);
        assert!((first.end_deg - (-67.5)).abs() < 1e-4);
        assert!(
            slot_at(&menu, 0.0, -80.0).unwrap().sector == 0,
            "12 点方向必须是第 0 格"
        );
        // 顺时针：3 点方向（角度 0）是第 2 格。
        assert!(slot_at(&menu, 80.0, 0.0).unwrap().sector == 2);
        assert!(slot_at(&menu, 0.0, 80.0).unwrap().sector == 4, "6 点方向");
        assert!(slot_at(&menu, -80.0, 0.0).unwrap().sector == 6, "9 点方向");
    }

    #[test]
    fn hit_test_returns_what_the_layout_painted() {
        // 画出来的每一格，往它的角平分线中点打一发，必须回到同一格。
        // 这条判据的存在理由就是模块头那句「高亮的槽与执行的槽必须同一个」。
        let menu = default_menu();
        for entry in slot_layout(&menu) {
            let (dx, dy) = point(&menu, entry.layer, entry.sector);
            let hit = slot_at(&menu, dx, dy)
                .unwrap_or_else(|| panic!("{} 自己画出来的中点打不中自己", entry.item_id));
            assert_eq!(hit.item_id(), entry.item_id);
        }
    }

    #[test]
    fn band_boundaries_and_hole_and_outside() {
        let menu = default_menu();
        // 内 40 是空洞：落在洞里什么都不选（松手 = 取消）。
        assert_eq!(slot_at(&menu, 10.0, 0.0), None);
        assert_eq!(slot_at(&menu, 0.0, -39.0), None);
        // 外半径之外同样不选。
        assert_eq!(slot_at(&menu, 121.0, 0.0), None);
        // 三层的环带边界：r120 内 40 ⇒ 每层宽 (120-40)/3。
        let band = (120.0 - 40.0) / 3.0;
        assert_eq!(slot_at(&menu, 40.0 + band - 1.0, 0.0).unwrap().layer, 1);
        assert_eq!(slot_at(&menu, 40.0 + band + 1.0, 0.0).unwrap().layer, 2);
        assert_eq!(slot_at(&menu, 119.0, 0.0).unwrap().layer, 3);
        // 压着外半径这一条边界不许越界。
        assert_eq!(slot_at(&menu, 120.0, 0.0).unwrap().layer, 3);
    }

    #[test]
    fn fewer_layers_reduces_the_rings_not_the_sectors() {
        let mut menu = default_menu();
        menu.layers = 1;
        assert_eq!(menu.slot_count(), 8);
        assert_eq!(slot_layout(&menu).len(), 8);
        // 单层时整圈宽度就是 120-40，所以 115 仍属第 1 层。
        assert_eq!(slot_at(&menu, 0.0, -115.0).unwrap().layer, 1);
        assert_eq!(slot_at(&menu, 0.0, -115.0).unwrap().sector, 0);
        // 3 层时那个半径是第 3 层 —— 层数变了，同一落点的归属跟着变，
        // 而绑定表里的 itemId 不许跟着漂（所以形状改动要配 prune_bindings）。
        menu.layers = 3;
        assert_eq!(slot_at(&menu, 0.0, -115.0).unwrap().layer, 3);
    }

    #[test]
    fn item_id_round_trips_and_is_stable() {
        let slot = RadialSlot {
            layer: 2,
            sector: 5,
        };
        assert_eq!(slot.item_id(), "l2s5");
        assert_eq!(RadialSlot::parse_item_id("l2s5"), Some(slot));
        for raw in ["", "s5", "l2", "lXs2", "2s5", "l2x5"] {
            assert_eq!(
                RadialSlot::parse_item_id(raw),
                None,
                "{raw} 不是合法 itemId"
            );
        }
    }

    #[test]
    fn every_preset_slot_resolves_through_the_binding_table() {
        // 「轮盘里的每个操作都是绑定系统里的 action」—— 这条判据就是这个测试：
        // 预设槽位必须能被**同一个解析器**解析出来，而不是另一条专用路径。
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        assert!(!bindings.is_empty());
        for binding in &bindings {
            let InputDescriptor::Radial { menu_id, item_id } = &binding.input else {
                panic!("轮盘预设的 input 必须是 radial：{}", binding.id)
            };
            let resolved = resolve(
                &bindings,
                &radial_input(menu_id, item_id),
                &[InputContext::Reader],
            )
            .unwrap_or_else(|| panic!("{} 解析不出动作", binding.id));
            assert_eq!(resolved.action, binding.action);
        }
        // 新轮盘是空的：用户从零开始绑，不该被塞一份别人的默认值。
        assert!(preset_bindings("menu-2").is_empty());
    }

    #[test]
    fn preset_actions_all_exist_and_are_implemented() {
        for binding in preset_bindings(DEFAULT_RADIAL_MENU_ID) {
            let entry = action_definition(&binding.action)
                .unwrap_or_else(|| panic!("注册表里没有 {}", binding.action));
            assert!(
                entry.implemented,
                "{} 绑了尚未实现的动作 {}（出厂即失效）",
                binding.id, binding.action
            );
        }
    }

    #[test]
    fn preset_slots_fit_the_default_wheel_and_do_not_collide() {
        let menu = default_menu();
        for binding in preset_bindings(DEFAULT_RADIAL_MENU_ID) {
            let InputDescriptor::Radial { item_id, .. } = &binding.input else {
                continue;
            };
            let slot = RadialSlot::parse_item_id(item_id).unwrap();
            assert!(menu.has_slot(&slot), "{item_id} 在默认轮盘上画不出来");
        }
        assert!(conflicts(&preset_bindings(DEFAULT_RADIAL_MENU_ID)).is_empty());
    }

    #[test]
    fn radial_slots_are_laid_out_only_where_the_wheel_has_room() {
        // 每格都得有画法：预设里出现 `l4s*` 这种不存在的槽，设置页就会列出点不到的行。
        let menu = default_menu();
        let painted: Vec<String> = slot_layout(&menu).into_iter().map(|e| e.item_id).collect();
        for binding in preset_bindings(DEFAULT_RADIAL_MENU_ID) {
            let InputDescriptor::Radial { item_id, .. } = &binding.input else {
                continue;
            };
            assert!(painted.contains(item_id), "{item_id} 没被画出来");
        }
    }

    #[test]
    fn shrinking_the_wheel_prunes_the_orphan_bindings() {
        let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        let config = default_config();
        assert_eq!(prune_bindings(&config, &bindings).len(), bindings.len());

        let mut shrunk = default_config();
        shrunk.menus[0].layers = 1;
        let kept = prune_bindings(&shrunk, &bindings);
        // 第 2、3 层那 8 条应当被剪掉，内环 4 条留下。
        assert_eq!(kept.len(), 4);
        for binding in &kept {
            let InputDescriptor::Radial { item_id, .. } = &binding.input else {
                continue;
            };
            assert!(item_id.starts_with("l1s"), "留下了 {item_id}");
        }

        // 删掉整个轮盘 ⇒ 它的轮盘绑定全清，但键盘/点击那些一条不许动。
        let emptied = RadialConfig {
            menus: vec![RadialMenu {
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
    fn validation_names_the_offending_wheel() {
        let mut config = default_config();
        config.menus[0].layers = 5;
        let problems = validate(&config);
        assert_eq!(problems.len(), 1, "{problems:?}");
        assert!(
            problems[0].contains("默认轮盘"),
            "要说清是哪个轮盘：{}",
            problems[0]
        );

        config.menus[0].layers = 3;
        config.menus[0].geometry.inner_radius = 200.0;
        assert!(!is_valid(&config), "空洞比外半径还大不合法");

        config.menus[0].geometry = RadialGeometry::default();
        config.active_menu_id = "nope".into();
        assert!(validate(&config).iter().any(|p| p.contains("nope")));

        config.active_menu_id = DEFAULT_RADIAL_MENU_ID.into();
        config.menus.push(RadialMenu {
            id: DEFAULT_RADIAL_MENU_ID.into(),
            ..default_menu()
        });
        assert!(validate(&config).iter().any(|p| p.contains("重复")));
        assert!(is_valid(&default_config()));
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
    fn new_menus_get_distinct_ids_and_names() {
        let first = new_menu(1);
        let second = new_menu(2);
        assert_eq!(first.id, "menu-2");
        assert_eq!(second.id, "menu-3");
        assert_ne!(first.id, second.id);
        assert!(is_valid(&RadialConfig {
            menus: vec![default_menu(), first, second],
            ..Default::default()
        }));
    }

    #[test]
    fn config_round_trips_through_json_and_keeps_defaults() {
        let config = default_config();
        let json = serde_json::to_string(&config).unwrap();
        let parsed: RadialConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, config);
        // 字段名是落进用户设置的，形状要稳。
        for field in [
            "\"activeMenuId\"",
            "\"menus\"",
            "\"innerRadius\"",
            "\"layers\"",
        ] {
            assert!(json.contains(field), "缺字段 {field}：{json}");
        }
        // 老配置（只有 menus）也要能读进来，且 enabled 缺省为**开**。
        let legacy: RadialConfig =
            serde_json::from_str(r#"{"menus":[{"id":"default","name":"默认轮盘","layers":3}]}"#)
                .unwrap();
        assert!(legacy.enabled, "新增的启用类字段必须默认开");
        assert_eq!(legacy.menus[0].geometry.sectors, DEFAULT_RADIAL_SECTORS);
        assert_eq!(legacy.active_menu(), legacy.menus.first());
        assert!(legacy.menu("nope").is_none());
    }

    #[test]
    fn active_menu_falls_back_when_the_selection_was_deleted() {
        let config = RadialConfig {
            active_menu_id: "gone".into(),
            ..Default::default()
        };
        assert_eq!(
            config.active_menu().map(|m| m.id.as_str()),
            Some(DEFAULT_RADIAL_MENU_ID)
        );
    }

    #[test]
    fn radial_input_matches_the_shape_the_engine_already_parses() {
        // descriptor 的 JSON 形状是 model.rs 钉过的（menuId / itemId）。
        // 运行时产的这条必须与它逐字节一致，否则「导入的包能认、自己产的认不出」。
        let json = serde_json::to_string(&radial_input("default", "l1s0")).unwrap();
        assert_eq!(
            json,
            r#"{"device":"radial","menuId":"default","itemId":"l1s0"}"#
        );
        let parsed: InputDescriptor = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, radial_input("default", "l1s0"));
    }

    #[test]
    fn layout_angles_cover_the_full_circle_without_gaps() {
        let menu = default_menu();
        let layout = slot_layout(&menu);
        let band = (menu.geometry.radius - menu.geometry.inner_radius) / menu.layers as f32;
        for layer in 1..=menu.layers {
            let ring: Vec<&RadialSlotLayout> = layout.iter().filter(|e| e.layer == layer).collect();
            assert_eq!(ring.len(), menu.geometry.sectors as usize);
            for pair in ring.windows(2) {
                assert!(
                    (pair[0].end_deg - pair[1].start_deg).abs() < 1e-4,
                    "第 {layer} 层相邻两格之间有缝"
                );
            }
            let span: f32 = ring.iter().map(|e| e.end_deg - e.start_deg).sum();
            assert!(
                (span - 360.0).abs() < 1e-3,
                "第 {layer} 层没铺满一圈：{span}"
            );
            // 每层占一条等宽的环带，从空洞边缘一路铺到外半径。
            let expected_inner = menu.geometry.inner_radius + (layer - 1) as f32 * band;
            let expected_outer = menu.geometry.inner_radius + layer as f32 * band;
            assert!(
                (ring[0].inner_radius - expected_inner).abs() < 1e-3,
                "第 {layer} 层的内缘不对"
            );
            assert!(
                (ring[ring.len() - 1].outer_radius - expected_outer).abs() < 1e-3,
                "第 {layer} 层的外缘不对"
            );
        }
        assert!(
            (slot_layout(&menu).last().unwrap().outer_radius - menu.geometry.radius).abs() < 1e-3,
            "最外一层必须铺到 r120"
        );
        // 角度换算的自洽：layout 给的 mid_deg 与 atan2 回来的是同一个角。
        let entry = &layout[3];
        let (dx, dy) = point(&menu, entry.layer, entry.sector);
        assert!((dy.atan2(dx).to_degrees() - entry.mid_deg).abs() < 1e-3);
        assert!(entry.mid_deg > RADIAL_START_DEG && entry.mid_deg < RADIAL_START_DEG + 360.0);
    }

    #[test]
    fn layout_at_agrees_with_slot_at() {
        let menu = default_menu();
        let layout = slot_layout(&menu);
        let (dx, dy) = point(&menu, 2, 3);
        let entry = layout_at(&menu, &layout, dx, dy).expect("这一格要有画法");
        assert_eq!(entry.item_id, "l2s3");
        assert_eq!(entry.item_id, slot_at(&menu, dx, dy).unwrap().item_id());
        assert!(layout_at(&menu, &layout, 0.0, 0.0).is_none());
    }

    #[test]
    fn pointer_clicks_still_win_over_radial_bindings() {
        // 轮盘绑定与点击绑定住在同一张表里，靠 descriptor 区分；
        // 混在一张表里不许互相顶掉（那等于「装了轮盘就不能点着翻页」）。
        let mut bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
        bindings.extend(tap_preset_bindings(TapPreset::RightHand));
        let wheel = resolve(
            &bindings,
            &radial_input(DEFAULT_RADIAL_MENU_ID, "l1s0"),
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
        assert!(conflicts(&bindings).is_empty());
    }
}
