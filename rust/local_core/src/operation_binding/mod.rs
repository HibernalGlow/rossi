//! 操作绑定引擎（ADR-0015）。
//!
//! 分层与边界：
//!
//! - [`vocabulary`]：词汇表 —— context / 九宫格 / 动作 id，字符串逐条照抄 neoview
//!   （要落进用户绑定包的东西不许改名）；
//! - [`model`]：绑定与输入描述符的数据模型（九类 descriptor 全集，后四类可解析、
//!   不可编辑，导入 neoview 的包不许洗掉用户的手柄/轮盘绑定）；
//! - [`resolve`]：**纯函数**解析器 —— 冲突检测 + 「输入事件 → 动作」，算法逐行
//!   对齐 neoview；阅读方向（左开/右开）在这里解释空间动作（`page-left`/`page-right`）；
//! - [`factory`]：Neo 默认九宫格、滚轮、键盘、鼠标，以及旧默认表迁移；
//! - [`preset`]：旧版兼容预设（左右手三分区 + 键盘）；
//! - [`radial`]：轮盘的**形状**（几个轮盘 / 几层 / 半径）与几何 —— 画法与命中判定
//!   同一份算术。槽位「干什么」仍然是一条绑定（`InputDescriptor::Radial` →
//!   注册表里的动作 id），所以轮盘不需要同样的解析器第二遍。
//!
//! 「换外壳也能用」的接缝：外壳只做三件事 —— 把真实事件归一化成
//! [`model::InputDescriptor`]、报告活跃 context、把解析出的 action id 映射到执行体。

pub mod factory;
pub mod model;
pub mod preset;
pub mod radial;
pub mod resolve;
pub mod vocabulary;

pub use model::{InputBinding, InputBindingsConfig, InputDescriptor};
pub use radial::{
    DEFAULT_RADIAL_MENU_ID, RadialConfig, RadialMenuDefinition, RadialMenuItem, RadialSlotHit,
    RadialSlotLayout, default_config as radial_default_config,
};
pub use resolve::{InputConflict, PageTurn, conflicts, resolve, resolve_page_turn};
pub use vocabulary::{
    ActionCatalogEntry, InputContext, ReaderViewArea, ReadingDirection, action,
    action_catalog_entries, action_definition,
};
