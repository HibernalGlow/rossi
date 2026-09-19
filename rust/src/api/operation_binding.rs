//! 操作绑定引擎（ADR-0015）的 **FRB 薄入口**。
//!
//! 引擎本体住 `rossi_local_core::operation_binding`（纯函数：词汇表 / 模型 /
//! 冲突与解析 / 出厂预设），这里只做两件事：
//!
//! 1. 把 Dart 侧的绑定表与输入事件（**JSON 字符串**）喂给引擎；
//! 2. 把解析结果（动作 id / 翻页语义 / 冲突清单）原样带回去。
//!
//! ## 为什么 JSON 进出而不是结构体过桥
//!
//! 绑定表的 schema 归引擎管（neoview 兼容，含九类 descriptor），Dart 侧**不持有**
//! 它的强类型镜像 —— 强类型镜像一旦过桥，schema 演进就得两边同步改生成物。
//! JSON 过桥把「schema 的唯一权威」留在 Rust 侧，Dart 只在**执行**时拆自己关心的
//! 字段。解析频率是「每次按键 / 每次点击」量级，序列化成本可忽略。

use anyhow::Context;
use flutter_rust_bridge::frb;
use rossi_local_core::operation_binding as engine;

/// 解析一次输入事件 → 命中的动作 id（没人认领时返回 `None`）。
///
/// `contexts` 是当前**活跃**的 context 名（`reader` / `shell` / …），
/// 由 Dart adapter 报告 —— 只有应用自己知道现在在场的是哪块内容。
#[frb(sync)]
pub fn operation_binding_resolve(
    bindings_json: String,
    input_json: String,
    contexts: Vec<String>,
) -> Option<String> {
    let bindings: Vec<engine::InputBinding> =
        serde_json::from_str(&bindings_json).expect("绑定表 JSON 必须合法");
    let input: engine::InputDescriptor =
        serde_json::from_str(&input_json).expect("输入描述符 JSON 必须合法");
    let contexts = contexts
        .iter()
        .filter_map(|raw| engine::InputContext::parse(raw))
        .collect::<Vec<_>>();

    engine::resolve(&bindings, &input, &contexts).map(|binding| binding.action.clone())
}

/// 把一条翻页动作解释成翻页语义：`"next"` / `"previous"`；不是翻页动作返回 `None`。
///
/// 这是**阅读方向唯一生效的地方**：`reader.page-right` 在右开（readMode≠2）下是
/// 下一页、在左开（readMode=2）下是上一页。`read_mode` 的取值与阅读页一致
/// （0 条漫 / 1 右开 / 2 左开；条漫按右开解释 —— 竖向没有左右）。
#[frb(sync)]
pub fn operation_binding_resolve_page_turn(action_id: String, read_mode: i32) -> Option<String> {
    let direction = engine::ReadingDirection::from_read_mode(read_mode);
    engine::resolve_page_turn(&action_id, direction).map(|turn| match turn {
        engine::PageTurn::Next => "next".to_string(),
        engine::PageTurn::Previous => "previous".to_string(),
    })
}

/// 找出绑定表里所有冲突（同 `context + 输入` 上多于一条启用绑定）。
///
/// 返回 JSON 数组：`[{"key": "...", "bindingIds": ["a", "b"]}, …]`。
/// **冲突阻止保存**：由设置页挡在保存之前，而不是安静地取第一条。
#[frb(sync)]
pub fn operation_binding_conflicts(bindings_json: String) -> String {
    let bindings: Vec<engine::InputBinding> =
        serde_json::from_str(&bindings_json).expect("绑定表 JSON 必须合法");
    serde_json::to_string(&engine::conflicts(&bindings)).expect("冲突清单必须能序列化")
}

/// 出厂预设：九宫格点击绑定表（`right-hand` / `left-hand`），JSON 数组。
///
/// 预设绑的是**空间动作**（`reader.page-right` / `reader.page-left`），
/// 阅读方向在 [`operation_binding_resolve_page_turn`] 里解释 —— 方向换挡
/// 不需要重写绑定表。
#[frb(sync)]
pub fn operation_binding_tap_preset(preset: String) -> Result<String, anyhow::Error> {
    let parsed = engine::preset::TapPreset::parse(&preset)
        .with_context(|| format!("未知的点击预设：{preset}"))?;
    serde_json::to_string(&engine::preset::tap_preset_bindings(parsed))
        .context("预设绑定表必须能序列化")
}

/// 出厂预设：键盘绑定表（左右方向键绑空间动作、空格绑语义前进），JSON 数组。
#[frb(sync)]
pub fn operation_binding_key_preset() -> String {
    serde_json::to_string(&engine::preset::key_preset_bindings()).expect("键盘预设必须能序列化")
}

/// 动作注册表（`id` / `label` / `category` / `categoryLabel` / `implemented`），JSON 数组。
///
/// 设置页的选项清单从这里取 —— Dart 侧不抄第二份「有哪些动作、哪个能用」（ADR-0015）。
#[frb(sync)]
pub fn operation_binding_action_catalog() -> String {
    serde_json::to_string(&engine::action_catalog_entries()).expect("注册表必须能序列化")
}

/// 这份 JSON 是不是**合法**的绑定表（数组或裸数组都算，解析不了返回 `false`）。
///
/// 存在的理由：上面几个函数对不合法的输入直接 `expect`（那是「调用方已经校验过」的前提）。
/// 绑定表要落进用户设置、还要吃用户导入的文本，所以校验这一步必须**能失败**而不是
/// 让 Rust 侧 panic —— 每次点击都跨一次桥，崩在这里等于阅读器整体打不开。
#[frb(sync)]
pub fn operation_binding_validate(bindings_json: String) -> bool {
    serde_json::from_str::<Vec<engine::InputBinding>>(&bindings_json).is_ok()
}

// ── 轮盘（radial menu）───────────────────────────────────────────────────────
//
// 轮盘的**形状**（几个轮盘 / 每层哪些条目 / 半径与角度）走下面这几个口子；
// 条目「干什么」不走 —— 它就是一条 `device: radial` 的绑定，落在上面那张绑定表里，
// 由 [`operation_binding_resolve`] 与键盘、点击同一个解析器解析。
// 所以这里没有 `radial_resolve_slot_action` 之类的函数：那会是判定处的第二份实现。

fn parse_radial_config(config_json: &str) -> Option<engine::radial::RadialConfig> {
    serde_json::from_str(config_json).ok()
}

/// 轮盘的出厂文档（默认轮盘：3 层 · r120 · 内 40 · 起始角 -90 · 扫过 360），JSON。
#[frb(sync)]
pub fn operation_binding_radial_default_config() -> String {
    serde_json::to_string(&engine::radial::default_config()).expect("出厂轮盘必须能序列化")
}

/// 这份轮盘文档**读得懂且合法**吗（吃用户设置与用户导入，所以校验要能失败而不是 panic）。
#[frb(sync)]
pub fn operation_binding_radial_validate(config_json: String) -> bool {
    match parse_radial_config(&config_json) {
        Some(config) => engine::radial::is_valid(&config),
        None => false,
    }
}

/// 轮盘文档的问题清单（人话，JSON 数组；空数组 = 可用）。
///
/// 与 [`operation_binding_radial_validate`] 分开是两个用途：validate 给保存路径当闸门，
/// problems 给设置页当说明 —— 「不许保存」得配上「为什么」。
#[frb(sync)]
pub fn operation_binding_radial_problems(config_json: String) -> String {
    let problems = match parse_radial_config(&config_json) {
        Some(config) => engine::radial::validate(&config),
        None => vec!["轮盘配置读不出来".to_string()],
    };
    serde_json::to_string(&problems).expect("问题清单必须能序列化")
}

/// 一个轮盘显示出来的全部槽位（**含空格**），JSON 数组。
///
/// 外壳**照着这份数字画**：每格的内外半径、起止角、标签、能不能选，都在里面。
/// 命中判定读的是同一组数字（见 [`operation_binding_radial_slot`]），所以
/// 「高亮的一格」与「执行的一格」不可能是两格。
#[frb(sync)]
pub fn operation_binding_radial_layout(config_json: String, menu_id: String) -> String {
    let empty = serde_json::to_string(&Vec::<engine::radial::RadialSlotLayout>::new())
        .expect("空布局必须能序列化");
    let Some(config) = parse_radial_config(&config_json) else {
        return empty;
    };
    let Some(menu) = radial_menu(&config, &menu_id) else {
        return empty;
    };
    serde_json::to_string(&engine::radial::slot_layout(&config, menu))
        .expect("槽位布局必须能序列化")
}

/// 落点（相对圆心的偏移）→ 选中的槽，返回 `RadialSlotHit` 的 JSON
/// （`menuId` / `itemId` / `level` / `index` / `legacyAction` / `moveToMenuId`）。
///
/// 外壳拿 `itemId` 拼出那条 `radial` 输入去问解析器；`legacyAction` 是 neoview 的
/// 回落（老包里条目自己带动作、而绑定表里没有那一行时用它），`moveToMenuId` 非空
/// 表示这一格是「跳转轮盘」，松手换轮盘而不是执行动作。
/// 落在空洞、空格、被禁用的条目或扫过角之外 ⇒ `None`。
#[frb(sync)]
pub fn operation_binding_radial_slot(
    config_json: String,
    menu_id: String,
    dx: f64,
    dy: f64,
) -> Option<String> {
    let config = parse_radial_config(&config_json)?;
    let menu = radial_menu(&config, &menu_id)?;
    let hit = engine::radial::slot_at(&config, menu, dx as f32, dy as f32)?;
    Some(serde_json::to_string(&hit).expect("轮盘命中结果必须能序列化"))
}

/// 某个轮盘的出厂槽位绑定（只有默认轮盘有；新轮盘返回空数组），JSON 数组。
#[frb(sync)]
pub fn operation_binding_radial_preset(menu_id: String) -> String {
    serde_json::to_string(&engine::radial::preset_bindings(&menu_id)).expect("轮盘预设必须能序列化")
}

/// 新建一个轮盘（设置页的「新轮盘」），JSON。
///
/// id 与名字的生成规则归核心：与 [`operation_binding_radial_default_config`] 同一处，
/// 免得外壳自己拼一套而与核心 `prune_bindings` 认的 id 分叉。
#[frb(sync)]
pub fn operation_binding_radial_new_menu(count: i32) -> String {
    serde_json::to_string(&engine::radial::new_menu(count.max(0) as usize))
        .expect("新轮盘必须能序列化")
}

/// 新建一个条目的 id（`item-N`，neoview 的 `uniqueId("item", …)`）。
#[frb(sync)]
pub fn operation_binding_radial_new_item_id(count: i32) -> String {
    engine::radial::new_item_id(count.max(0) as usize)
}

/// 轮盘形状变了之后，剪掉指向**已不存在的条目**的那些绑定，返回留下的绑定（JSON 数组）。
///
/// 剪的只有 `input.device == "radial"` 且 `(menuId, itemId)` 已经画不出来的行；
/// 键盘、鼠标、点击、滚轮一条都不许动。
#[frb(sync)]
pub fn operation_binding_radial_prune(config_json: String, bindings_json: String) -> String {
    let bindings: Vec<engine::InputBinding> =
        serde_json::from_str(&bindings_json).unwrap_or_default();
    let kept = match parse_radial_config(&config_json) {
        Some(config) => engine::radial::prune_bindings(&config, &bindings),
        // 形状读不懂就什么都别剪 —— 「剪枝」把用户的表洗空是最坏的结果。
        None => bindings,
    };
    serde_json::to_string(&kept).expect("剪枝后的绑定表必须能序列化")
}

/// 按 id 取轮盘；id 指不到时退回**生效的那个**。
///
/// 外壳传的一般就是 `activeMenuId`，这一层兜底只在「刚删了轮盘、设置还没落盘」
/// 这种瞬间窗口里起作用：宁可画出别的轮盘，也不要画出一个空的。
fn radial_menu<'a>(
    config: &'a engine::radial::RadialConfig,
    menu_id: &str,
) -> Option<&'a engine::radial::RadialMenuDefinition> {
    config.menu(menu_id).or_else(|| config.active_menu())
}
