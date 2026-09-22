//! 把 1 张横长页拆成左右两个显示步骤来读 (§1.119)。
//!
//! ── 来源与形态（读之前先看这段）──
//!
//! 搬自 mImageViewer `src/page_split.rs` @ `1fd6f863`（MIT）。
//!
//! 版权：Copyright (c) 2026 SANO Taku (佐野 拓), online handle "Mikage Sawatari"。
//! 上游以 MIT 授权（全文见 `vendor/mimageviewer/LICENSE`），本文件保留该来源声明。
//!
//! **刻意偏离**（遵循 B3 架构约束，登记在 `script/sync_vendored_modules.py` 的 `PORTS` 表）：
//! 1. 剥离 `eframe::egui`：上游直接使用 `egui::Rect` 与 `egui::pos2`。按 B3 规范，
//!    核心库与任何具体 UI 框架完全解耦。本文件内部定义无依赖的纯 Rust 几何类型
//!    [`Pos2`] / [`Rect`]（别名 [`NormalizedRect`]），保留原有全部几何方法与行为。
//! 2. 旋转类型重定向：`crate::rotation_db::Rotation` → `crate::rotation::Rotation`。
//! 3. 逆 UV 变换重定向：`crate::displayed_image_transform::inverse_uv` → `crate::rotation::inverse_uv`。
//!
//! **原来的 item index 始终保持为正本**，只有全屏的显示位置会分到左右两侧。
//! ★ / 标签 / 书签 / 阅读位置 / 校正 / 注释 / 裁剪都记录在分割前的页面上，
//! 缩略图也使用分割前的图片。前提是不产生持久的逻辑页面
//! (一旦产生，DB、搜索、进度条、缩略图就会全部被迫改成按逻辑页面处理)。
//!
//! 本模块只持有**分割的顺序**。不持有的东西:
//!
//! - **是否属于分割对象的判定**。反映旋转后的纵横比与「是否为静止画」，列表侧的
//!   `is_landscape` / `is_spread_pairable_item` 已经持有，因此通过谓词接收。
//!   如果在这里重新读一遍纵横比，同一个判定就会增加到 2 处。
//! - 绘制、纹理、持久化。`PageSlice::uv_rect` 返回的只是范围，
//!   由谁来怎么画是调用方的责任。
//!
//! 纵向拼接也使用同一套步骤列。拼接时会变成「把源自同一 texture 的 2 个区域纵向排列」，
//! 而排列的顺序与翻页的顺序相同。

// ── B3 几何类型剥离 ────────────────────────────────────────────────────────
//
// 上游使用 eframe::egui 的 Rect 与 pos2。按 B3 规范，几何类型必须与 UI 框架完全解耦。
// 这里提供轻量无依赖的纯 Rust 几何类型，保持相同的 API 与计算语义。

/// 2D 坐标（通常在 0.0..=1.0 归一化 UV 空间）。
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Pos2 {
    pub x: f32,
    pub y: f32,
}

pub const fn pos2(x: f32, y: f32) -> Pos2 {
    Pos2 { x, y }
}

/// 2D 矩形（剥离 egui::Rect 的纯几何类型）。
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Rect {
    pub min: Pos2,
    pub max: Pos2,
}

pub type NormalizedRect = Rect;

impl Rect {
    pub const fn from_min_max(min: Pos2, max: Pos2) -> Self {
        Self { min, max }
    }

    pub fn width(self) -> f32 {
        self.max.x - self.min.x
    }

    pub fn height(self) -> f32 {
        self.max.y - self.min.y
    }

    pub fn area(self) -> f32 {
        (self.width() * self.height()).max(0.0)
    }

    pub fn intersects(self, other: Self) -> bool {
        self.min.x < other.max.x
            && self.max.x > other.min.x
            && self.min.y < other.max.y
            && self.max.y > other.min.y
    }

    pub fn intersect(self, other: Self) -> Self {
        let min_x = self.min.x.max(other.min.x);
        let min_y = self.min.y.max(other.min.y);
        let max_x = self.max.x.min(other.max.x).max(min_x);
        let max_y = self.max.y.min(other.max.y).max(min_y);
        Self {
            min: Pos2 { x: min_x, y: min_y },
            max: Pos2 { x: max_x, y: max_y },
        }
    }
}

pub mod egui_compat {
    pub use super::{Pos2, Rect, pos2};
}
use egui_compat as egui;

// ── 上游核心逻辑 ──

/// 分割后的页面正在看哪一侧。
///
/// `Full` 是「没有分割」，而不是「左右中间」。竖长页、视频、
/// 分割 OFF 都会变成 `Full`。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum PageSlice {
    #[default]
    Full,
    Left,
    Right,
}

impl PageSlice {
    /// 纹理上要绘制哪个范围 (以左上角为原点的归一化坐标)。
    ///
    /// 分割位置固定为 50%。手动调整不包含在 MVP 里。
    pub fn uv_rect(self) -> egui::Rect {
        match self {
            Self::Full => egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
            Self::Left => egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(0.5, 1.0)),
            Self::Right => egui::Rect::from_min_max(egui::pos2(0.5, 0.0), egui::pos2(1.0, 1.0)),
        }
    }

    /// 是否只看了一半。这也是禁用自动显示裁剪的条件。
    pub fn is_half(self) -> bool {
        matches!(self, Self::Left | Self::Right)
    }

    /// **原图空间**的部分矩形。传给 `content_bbox` 的是这个。
    ///
    /// [`Self::uv_rect`] 是「从画面看左半边 / 右半边」，因此是**显示空间**。
    /// 存在保存旋转时两者不一致 (旋转 90 度的页面，画面左半部分在原图中
    /// 是上半部分)。映射使用与 screen ↔ source 相同的 `inverse_uv`。
    pub fn source_bbox(self, rotation: crate::rotation::Rotation) -> egui::Rect {
        let display = self.uv_rect();
        let (ax, ay) = crate::rotation::inverse_uv(rotation, display.min.x, display.min.y);
        let (bx, by) = crate::rotation::inverse_uv(rotation, display.max.x, display.max.y);
        egui::Rect::from_min_max(
            egui::pos2(ax.min(bx), ay.min(by)),
            egui::pos2(ax.max(bx), ay.max(by)),
        )
    }
}

/// 分割后的页面从哪一侧开始读。
///
/// 作为显示模式排他地选择。不要做成与「单页显示 / 普通跨页」组合的独立
/// bool (组合状态会变多，每条路径在哪里有效要各处重新判定)。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SplitDirection {
    /// 从左半边开始读。
    LeftFirst,
    /// 从右半边开始读。
    RightFirst,
}

impl SplitDirection {
    /// 从显示模式取分割方向。不是分割模式时返回 `None`。
    ///
    /// 与 `SpreadMode::is_split` 的不一致，由
    /// `every_split_mode_names_a_direction` 固定住。
    pub fn from_spread_mode(mode: crate::settings::SpreadMode) -> Option<Self> {
        match mode {
            crate::settings::SpreadMode::SplitLtr => Some(Self::LeftFirst),
            crate::settings::SpreadMode::SplitRtl => Some(Self::RightFirst),
            _ => None,
        }
    }

    /// 在此页面最先看到的一侧。也是从书签等打开时的落点。
    pub fn first(self) -> PageSlice {
        match self {
            Self::LeftFirst => PageSlice::Left,
            Self::RightFirst => PageSlice::Right,
        }
    }

    /// 第二个看到的一侧。
    pub fn second(self) -> PageSlice {
        match self {
            Self::LeftFirst => PageSlice::Right,
            Self::RightFirst => PageSlice::Left,
        }
    }
}

/// 全屏时的显示位置。
///
/// `source_idx` 是正本，`slice` 只是显示用的临时状态。**看过哪一侧
/// 不持久化**，因此这个类型不会传给保存路径。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PresentationStep {
    pub source_idx: usize,
    pub slice: PageSlice,
}

impl PresentationStep {
    /// 不分割页面的显示位置。
    pub fn whole(source_idx: usize) -> Self {
        Self {
            source_idx,
            slice: PageSlice::Full,
        }
    }
}

/// 显示前进 1 步的结果。
///
/// 原始页面是否变了，会改变纹理的重读、显示确定、历史记录的处理方式。
/// 如果调用方在各处自行拼 `before.source_idx != after.source_idx`，
/// 判定就会分散，所以在这里做成类型返回。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StepMove {
    /// 同一个原始页面内左右发生了变化。
    WithinPage { to: PresentationStep },
    /// 移到了另一个原始页面。
    ToAnotherPage { to: PresentationStep },
    /// 处在端点，不移动。
    AtEnd,
}

impl StepMove {
    /// 移动目标。在端点时为 `None`。
    pub fn destination(self) -> Option<PresentationStep> {
        match self {
            Self::WithinPage { to } | Self::ToAnotherPage { to } => Some(to),
            Self::AtEnd => None,
        }
    }
}

/// 把 nav 顺序的 item 展开为织入分割后的显示步骤列。
///
/// 只有 `is_split_idx` 为真的 item 变成 2 步。尺寸还不清楚的 item 返回
/// 假并只占 1 步 — 尺寸到达后步骤列会重新组装。
/// 这与既有跨页单元生成对 `is_landscape` 持有的性质相同，
/// 不会仅为了分割而等待加载。
///
/// 谓词接收与既有跨页单元生成相同的 `(nav 内的位置, item index)`。
/// 因为保存旋转按与 nav 相同的顺序返回，所以需要位置。
pub fn presentation_steps(
    nav: &[usize],
    direction: SplitDirection,
    mut is_split_idx: impl FnMut(usize, usize) -> bool,
) -> Vec<PresentationStep> {
    let mut steps = Vec::with_capacity(nav.len());
    for (nav_pos, &idx) in nav.iter().enumerate() {
        if is_split_idx(nav_pos, idx) {
            steps.push(PresentationStep {
                source_idx: idx,
                slice: direction.first(),
            });
            steps.push(PresentationStep {
                source_idx: idx,
                slice: direction.second(),
            });
        } else {
            steps.push(PresentationStep::whole(idx));
        }
    }
    steps
}

/// 打开这个 item 时落脚的步骤位置。
///
/// **落到分割方向的第一半**。从书签、历史、搜索、进度条重新打开时
/// 不记得「上次看的是哪一侧」，这是规格；一旦记住，保存对象就会增加，
/// 以原始页面为单位的前提也会崩塌。
pub fn landing_step(steps: &[PresentationStep], source_idx: usize) -> Option<usize> {
    steps.iter().position(|s| s.source_idx == source_idx)
}

/// 显示前进 1 步。
pub fn step_forward(steps: &[PresentationStep], at: usize) -> StepMove {
    step_to(steps, at, at.checked_add(1))
}

/// 显示后退 1 步。
pub fn step_backward(steps: &[PresentationStep], at: usize) -> StepMove {
    step_to(steps, at, at.checked_sub(1))
}

fn step_to(steps: &[PresentationStep], at: usize, target: Option<usize>) -> StepMove {
    let (Some(current), Some(to)) = (steps.get(at), target.and_then(|t| steps.get(t))) else {
        return StepMove::AtEnd;
    };
    if current.source_idx == to.source_idx {
        StepMove::WithinPage { to: *to }
    } else {
        StepMove::ToAnotherPage { to: *to }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 没有分割对象时，步骤列与 nav 直接保持 1 对 1。
    #[test]
    fn pages_that_do_not_split_stay_one_step_each() {
        let steps = presentation_steps(&[4, 7, 9], SplitDirection::LeftFirst, |_, _| false);
        assert_eq!(
            steps,
            vec![
                PresentationStep::whole(4),
                PresentationStep::whole(7),
                PresentationStep::whole(9),
            ]
        );
    }

    #[test]
    fn a_split_page_is_read_from_the_side_the_direction_names() {
        let ltr = presentation_steps(&[0], SplitDirection::LeftFirst, |_, _| true);
        assert_eq!(
            ltr.iter().map(|s| s.slice).collect::<Vec<_>>(),
            vec![PageSlice::Left, PageSlice::Right]
        );

        let rtl = presentation_steps(&[0], SplitDirection::RightFirst, |_, _| true);
        assert_eq!(
            rtl.iter().map(|s| s.slice).collect::<Vec<_>>(),
            vec![PageSlice::Right, PageSlice::Left]
        );

        // 无论哪个方向，原始页面都仍是 1 个。
        assert!(ltr.iter().all(|s| s.source_idx == 0));
        assert!(rtl.iter().all(|s| s.source_idx == 0));
    }

    /// 横长与竖长混杂时，只有被分割的页面才变成 2 步。
    #[test]
    fn only_the_landscape_pages_are_split() {
        let steps = presentation_steps(&[0, 1, 2], SplitDirection::RightFirst, |_, idx| idx == 1);
        assert_eq!(
            steps,
            vec![
                PresentationStep::whole(0),
                PresentationStep {
                    source_idx: 1,
                    slice: PageSlice::Right
                },
                PresentationStep {
                    source_idx: 1,
                    slice: PageSlice::Left
                },
                PresentationStep::whole(2),
            ]
        );
    }

    #[test]
    fn an_empty_navigation_has_no_steps() {
        assert!(presentation_steps(&[], SplitDirection::LeftFirst, |_, _| true).is_empty());
    }

    /// 重新打开时落到分割方向的第一半。不会落到后半。
    #[test]
    fn reopening_a_split_page_lands_on_its_first_half() {
        let steps = presentation_steps(&[5, 6], SplitDirection::RightFirst, |_, _| true);
        let at = landing_step(&steps, 6).expect("6 不在步骤列中");
        assert_eq!(
            steps[at],
            PresentationStep {
                source_idx: 6,
                slice: PageSlice::Right
            }
        );
        assert_eq!(landing_step(&steps, 99), None);
    }

    /// 区分同一原始页面内的左右移动与移到下一个原始页面。
    #[test]
    fn moving_within_a_page_is_distinguished_from_moving_to_the_next_one() {
        let steps = presentation_steps(&[0, 1], SplitDirection::LeftFirst, |_, idx| idx == 0);
        // [0:Left, 0:Right, 1:Full]
        assert_eq!(
            step_forward(&steps, 0),
            StepMove::WithinPage {
                to: PresentationStep {
                    source_idx: 0,
                    slice: PageSlice::Right
                }
            }
        );
        assert_eq!(
            step_forward(&steps, 1),
            StepMove::ToAnotherPage {
                to: PresentationStep::whole(1)
            }
        );
        assert_eq!(
            step_backward(&steps, 2),
            StepMove::ToAnotherPage {
                to: PresentationStep {
                    source_idx: 0,
                    slice: PageSlice::Right
                }
            }
        );
        assert_eq!(
            step_backward(&steps, 1),
            StepMove::WithinPage {
                to: PresentationStep {
                    source_idx: 0,
                    slice: PageSlice::Left
                }
            }
        );
    }

    /// 在端点不动。不要出现分割中途撞到端点的形态。
    #[test]
    fn both_ends_stop_instead_of_wrapping() {
        let steps = presentation_steps(&[0], SplitDirection::LeftFirst, |_, _| true);
        assert_eq!(step_backward(&steps, 0), StepMove::AtEnd);
        assert_eq!(step_forward(&steps, 1), StepMove::AtEnd);
        assert_eq!(step_forward(&steps, 99), StepMove::AtEnd);
        assert_eq!(StepMove::AtEnd.destination(), None);
    }

    /// 左右合起来恰好覆盖原图，且不重叠。
    #[test]
    fn the_two_halves_tile_the_whole_image() {
        let left = PageSlice::Left.uv_rect();
        let right = PageSlice::Right.uv_rect();
        assert_eq!(left.max.x, right.min.x);
        assert_eq!(left.min.x, 0.0);
        assert_eq!(right.max.x, 1.0);
        assert_eq!(left.width(), right.width());
        // 纵向不切。
        for rect in [left, right, PageSlice::Full.uv_rect()] {
            assert_eq!(rect.min.y, 0.0);
            assert_eq!(rect.max.y, 1.0);
        }
    }

    #[test]
    fn only_the_halves_count_as_split_for_display_rules() {
        assert!(!PageSlice::Full.is_half());
        assert!(PageSlice::Left.is_half());
        assert!(PageSlice::Right.is_half());
    }

    /// 自称分割模式的模式，必须都能答出方向。
    ///
    /// `SpreadMode::is_split` 与 `SplitDirection::from_spread_mode` 是分开写的，
    /// 增加模式时如果只改一边，就会出现**分割 ON 却什么都不发生**的
    /// 状态。这里把它固定住。
    #[test]
    fn every_split_mode_names_a_direction() {
        use crate::settings::SpreadMode;
        // `all()` 是下拉框里展示的排列，不要拿它作为网罗的依据。
        let every_mode = [
            SpreadMode::Single,
            SpreadMode::Ltr,
            SpreadMode::LtrCover,
            SpreadMode::Rtl,
            SpreadMode::RtlCover,
            SpreadMode::Vertical,
            SpreadMode::SplitLtr,
            SpreadMode::SplitRtl,
        ];
        for mode in every_mode {
            assert_eq!(
                mode.is_split(),
                SplitDirection::from_spread_mode(mode).is_some(),
                "{mode:?} 的 is_split 与 from_spread_mode 不一致"
            );
        }
        assert_eq!(
            SplitDirection::from_spread_mode(SpreadMode::SplitLtr),
            Some(SplitDirection::LeftFirst)
        );
        assert_eq!(
            SplitDirection::from_spread_mode(SpreadMode::SplitRtl),
            Some(SplitDirection::RightFirst)
        );
    }

    /// 画面看到的左右，随旋转对应到原图的哪个位置。
    ///
    /// 这里若按显示空间原样传递，旋转 90 度的页面上切掉的将是**上下而非左右**。
    #[test]
    fn the_halves_map_back_through_the_rotation() {
        use crate::rotation::Rotation;
        let left = PageSlice::Left;
        // 无旋转: 画面左 = 原图的左。
        assert_eq!(left.source_bbox(Rotation::None), left.uv_rect());
        // 顺时针旋转 90 度显示 = 原图的下半部分出现在画面左侧。
        let mapped = left.source_bbox(Rotation::Cw90);
        assert!((mapped.min.x - 0.0).abs() < 1e-5, "{mapped:?}");
        assert!((mapped.max.x - 1.0).abs() < 1e-5, "{mapped:?}");
        assert!((mapped.min.y - 0.5).abs() < 1e-5, "{mapped:?}");
        assert!((mapped.max.y - 1.0).abs() < 1e-5, "{mapped:?}");
        // 180 度时左右互换。
        assert_eq!(
            left.source_bbox(Rotation::Cw180),
            PageSlice::Right.uv_rect()
        );
    }

    /// 无论哪种旋转，左右合起来都恰好覆盖原图。
    #[test]
    fn the_two_halves_still_tile_the_source_under_every_rotation() {
        use crate::rotation::Rotation;
        for rotation in [
            Rotation::None,
            Rotation::Cw90,
            Rotation::Cw180,
            Rotation::Cw270,
        ] {
            let a = PageSlice::Left.source_bbox(rotation);
            let b = PageSlice::Right.source_bbox(rotation);
            assert!((a.area() - 0.5).abs() < 1e-5, "{rotation:?} {a:?}");
            assert!((b.area() - 0.5).abs() < 1e-5, "{rotation:?} {b:?}");
            assert!(
                !a.intersects(b) || a.intersect(b).area() < 1e-5,
                "{rotation:?}"
            );
        }
    }

    /// 不分割时是原图整体。旋转后也保持整体。
    #[test]
    fn a_whole_page_stays_whole_under_rotation() {
        use crate::rotation::Rotation;
        for rotation in [Rotation::None, Rotation::Cw90, Rotation::Cw270] {
            let full = PageSlice::Full.source_bbox(rotation);
            assert!(
                (full.min.x).abs() < 1e-5 && (full.min.y).abs() < 1e-5,
                "{full:?}"
            );
            assert!((full.max.x - 1.0).abs() < 1e-5 && (full.max.y - 1.0).abs() < 1e-5);
        }
    }

    /// 分割不是跨页。不要混进跨页专用的分支里。
    #[test]
    fn splitting_is_not_a_spread() {
        use crate::settings::SpreadMode;
        for mode in [SpreadMode::SplitLtr, SpreadMode::SplitRtl] {
            assert!(!mode.is_spread(), "{mode:?}");
            assert!(!mode.is_rtl(), "{mode:?}");
            assert!(!mode.has_cover(), "{mode:?}");
        }
    }

    /// 与整数往返后方向不丢失 (存入 DB 时使用整数)。
    #[test]
    fn the_split_modes_survive_the_integer_round_trip() {
        use crate::settings::SpreadMode;
        for mode in [SpreadMode::SplitLtr, SpreadMode::SplitRtl] {
            assert_eq!(SpreadMode::from_int(mode.to_int()), mode);
        }
        // 不与旧版本写入的值冲突。
        assert_eq!(SpreadMode::from_int(5), SpreadMode::Vertical);
        // 不认识的值倒向默认 (新版写入的值被旧版读到时的路径)。
        assert_eq!(SpreadMode::from_int(99), SpreadMode::Single);
    }
}
