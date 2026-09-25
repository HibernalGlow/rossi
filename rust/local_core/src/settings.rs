//! mImageViewer `folder_tree` 的无 UI 排序设置适配。
//!
//! 文件管理器把设置保存在自己的 Rust 状态中；这里的类型只为直接编译并调用
//! mImageViewer `folder_tree.rs` 的源码函数，不承载 Flutter 状态。

use std::cmp::Ordering;

use crate::filename_sort::SortNameKey;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum SortOrder {
    #[default]
    FileName,
    Numeric,
    DateAsc,
    DateDesc,
    NameAsc,
    NameDesc,
}

impl SortOrder {
    /// 文件夹代表缩略图探索可用的既有 4 种排序。
    ///
    /// 与上游同口径：只为列表服务的降序值不得波及代表图选择与缓存键。
    pub fn folder_thumb_options() -> &'static [Self] {
        &[Self::FileName, Self::Numeric, Self::DateAsc, Self::DateDesc]
    }

    pub(crate) fn sanitized_for_folder_thumb(self) -> Self {
        if Self::folder_thumb_options().contains(&self) {
            self
        } else {
            Self::FileName
        }
    }

    pub fn name_key(self, name: &str) -> SortNameKey {
        match self {
            Self::Numeric => SortNameKey::with_natural(name),
            _ => SortNameKey::file_name(name),
        }
    }

    pub fn compare_name_keys(
        self,
        left: &SortNameKey,
        left_mtime: i64,
        right: &SortNameKey,
        right_mtime: i64,
    ) -> Ordering {
        let by_name = match self {
            Self::Numeric => left.compare_natural(right),
            _ => left.compare_file_name(right),
        };
        match self {
            Self::NameDesc => by_name.reverse(),
            Self::DateAsc => left_mtime
                .cmp(&right_mtime)
                .then_with(|| left.compare_file_name(right)),
            Self::DateDesc => right_mtime
                .cmp(&left_mtime)
                .then_with(|| left.compare_file_name(right)),
            _ => by_name,
        }
    }
}

pub fn default_grid_cols() -> usize {
    5
}

pub fn default_thumb_aspect() -> ThumbAspect {
    ThumbAspect::Square
}

pub fn default_thumb_aspect_auto() -> bool {
    true
}

fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub skip_zip_if_folder_exists: bool,
    #[serde(default)]
    pub skip_archive_if_zip_exists: bool,
    #[serde(default)]
    pub include_convertible_archives: bool,
    #[serde(default)]
    pub sort_order: SortOrder,
    #[serde(default = "default_grid_cols")]
    pub grid_cols: usize,
    #[serde(default)]
    pub grid_view_mode: GridViewMode,
    #[serde(default = "default_thumb_aspect")]
    pub thumb_aspect: ThumbAspect,
    #[serde(default = "default_thumb_aspect_auto")]
    pub thumb_aspect_auto: bool,
    #[serde(default)]
    pub grid_display_order: GridDisplayOrder,
    #[serde(default)]
    pub default_spread_mode: SpreadMode,
    #[serde(default)]
    pub default_reading_flow: ReadingFlow,
    #[serde(default = "default_true")]
    pub remember_favorite_view_state: bool,
    #[serde(skip)]
    pub(crate) favorite_view_overlay: Option<FavoriteViewOverlay>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            skip_zip_if_folder_exists: false,
            skip_archive_if_zip_exists: false,
            include_convertible_archives: false,
            sort_order: SortOrder::default(),
            grid_cols: default_grid_cols(),
            grid_view_mode: GridViewMode::default(),
            thumb_aspect: default_thumb_aspect(),
            thumb_aspect_auto: default_thumb_aspect_auto(),
            grid_display_order: GridDisplayOrder::default(),
            default_spread_mode: SpreadMode::default(),
            default_reading_flow: ReadingFlow::default(),
            remember_favorite_view_state: default_true(),
            favorite_view_overlay: None,
        }
    }
}

impl Settings {
    pub fn archive_file_handling_ignores_convertible(&self) -> bool {
        !self.include_convertible_archives
    }

    /// 把当前的显示字段暂存为公共值，并将收藏专用值载入为有效值。
    pub fn apply_favorite_view_overlay(
        &mut self,
        favorite_id: impl Into<String>,
        state: &FavoriteViewState,
    ) {
        self.clear_favorite_view_overlay();
        let common = FavoriteViewState::from_settings(self);
        state.apply_to_settings(self);
        self.favorite_view_overlay = Some(FavoriteViewOverlay {
            favorite_id: favorite_id.into(),
            common,
        });
    }

    /// 移除收藏专用值，回到 overlay 中保留的公共值。
    pub fn clear_favorite_view_overlay(&mut self) {
        let Some(overlay) = self.favorite_view_overlay.take() else {
            return;
        };
        overlay.common.apply_to_settings(self);
    }

    /// 生成传给偏好设置对话框的 snapshot。
    ///
    /// 即使有效值上载入了收藏专用的显示状态，偏好设置显示与编辑的
    /// 也始终是标准值。涉及项目仅由 [`FavoriteViewState`] 的转换导出。
    pub fn preferences_snapshot(&self) -> Self {
        let mut snapshot = self.clone();
        snapshot.clear_favorite_view_overlay();
        snapshot
    }

    /// 把在偏好设置中编辑的显示状态 route 到标准值。
    ///
    /// 收藏专用值生效期间，把该有效值继续保留在 `Settings` 的字段里，
    /// 只把对话框的值反映到标准值。非收藏状态下，直接把对话框的值
    /// 作为有效值 (= 标准值)。
    pub fn route_preferences_view_state(
        &mut self,
        standard: FavoriteViewState,
        active: FavoriteViewState,
    ) {
        let Some(overlay) = self.favorite_view_overlay.as_mut() else {
            standard.apply_to_settings(self);
            return;
        };
        overlay.common = standard;
        active.apply_to_settings(self);
    }

    pub fn active_favorite_view_id(&self) -> Option<&str> {
        self.favorite_view_overlay
            .as_ref()
            .map(|overlay| overlay.favorite_id.as_str())
    }
}

// -----------------------------------------------------------------------
// 缩略图宽高比
// -----------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum ThumbAspect {
    Landscape16x9,
    Landscape3x2,
    Landscape4x3,
    #[default]
    Square,
    Portrait3x4,
    Portrait2x3,
    Portrait9x16,
}

impl ThumbAspect {
    /// 单元格高度相对宽度的比率 (h / w)
    pub fn height_ratio(self) -> f32 {
        match self {
            Self::Landscape16x9 => 9.0 / 16.0,
            Self::Landscape3x2 => 2.0 / 3.0,
            Self::Landscape4x3 => 3.0 / 4.0,
            Self::Square => 1.0,
            Self::Portrait3x4 => 4.0 / 3.0,
            Self::Portrait2x3 => 3.0 / 2.0,
            Self::Portrait9x16 => 16.0 / 9.0,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Landscape16x9 => "16:9",
            Self::Landscape3x2 => "3:2",
            Self::Landscape4x3 => "4:3",
            Self::Square => "1:1",
            Self::Portrait3x4 => "3:4",
            Self::Portrait2x3 => "2:3",
            Self::Portrait9x16 => "9:16",
        }
    }

    pub fn all() -> &'static [Self] {
        &[
            Self::Landscape16x9,
            Self::Landscape3x2,
            Self::Landscape4x3,
            Self::Square,
            Self::Portrait3x4,
            Self::Portrait2x3,
            Self::Portrait9x16,
        ]
    }
}

// -----------------------------------------------------------------------
// 见开 / 跨页 / 横长页左右分割模式
// -----------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum ReadingDirection {
    #[default]
    Ltr,
    Rtl,
}

impl ReadingDirection {
    pub fn from_int(v: i32) -> Self {
        match v {
            1 => Self::Rtl,
            _ => Self::Ltr,
        }
    }

    pub fn to_int(self) -> i32 {
        match self {
            Self::Ltr => 0,
            Self::Rtl => 1,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Ltr => "左→右",
            Self::Rtl => "右→左",
        }
    }

    pub fn next(self) -> Self {
        match self {
            Self::Ltr => Self::Rtl,
            Self::Rtl => Self::Ltr,
        }
    }
}

/// 见开 / 跨页与横长页分割模式 (§1.119)。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum SpreadMode {
    #[default]
    Single,
    Ltr,
    LtrCover,
    Rtl,
    RtlCover,
    Vertical,
    SplitLtr,
    SplitRtl,
}

impl SpreadMode {
    /// 见开构成（双页并排）
    pub fn is_spread(self) -> bool {
        matches!(
            self,
            Self::Ltr | Self::LtrCover | Self::Rtl | Self::RtlCover
        )
    }

    /// 兼容用纵读模式
    pub fn is_vertical(self) -> bool {
        matches!(self, Self::Vertical)
    }

    /// 右→左（RTL）模式。
    ///
    /// 见开配对排序判定，不含分割模式（分割左右由 `SplitDirection` 决定）。
    pub fn is_rtl(self) -> bool {
        matches!(self, Self::Rtl | Self::RtlCover)
    }

    /// 若此模式自身决定阅读方向，则返回该方向；否则返回 None。
    pub fn canonical_reading_direction(self) -> Option<ReadingDirection> {
        match self {
            Self::Ltr | Self::LtrCover | Self::SplitLtr => Some(ReadingDirection::Ltr),
            Self::Rtl | Self::RtlCover | Self::SplitRtl => Some(ReadingDirection::Rtl),
            Self::Single | Self::Vertical => None,
        }
    }

    /// 横长页左右分割模式
    pub fn is_split(self) -> bool {
        matches!(self, Self::SplitLtr | Self::SplitRtl)
    }

    /// 是否有单页封面（第 1 页单独展示）
    pub fn has_cover(self) -> bool {
        matches!(self, Self::LtrCover | Self::RtlCover)
    }

    /// 从整数恢复 (与上游 DB 序列化保持一致)
    pub fn from_int(v: i32) -> Self {
        match v {
            1 => Self::Ltr,
            2 => Self::LtrCover,
            3 => Self::Rtl,
            4 => Self::RtlCover,
            5 => Self::Vertical,
            6 => Self::SplitLtr,
            7 => Self::SplitRtl,
            _ => Self::Single,
        }
    }

    /// 返回整数值
    pub fn to_int(self) -> i32 {
        match self {
            Self::Single => 0,
            Self::Ltr => 1,
            Self::LtrCover => 2,
            Self::Rtl => 3,
            Self::RtlCover => 4,
            Self::Vertical => 5,
            Self::SplitLtr => 6,
            Self::SplitRtl => 7,
        }
    }

    /// 循环切换下一个见开模式
    pub fn next_in_spread_cycle(self) -> Self {
        const CYCLE: [SpreadMode; 5] = [
            SpreadMode::Single,
            SpreadMode::Ltr,
            SpreadMode::LtrCover,
            SpreadMode::Rtl,
            SpreadMode::RtlCover,
        ];
        match CYCLE.iter().position(|&m| m == self) {
            Some(i) => CYCLE[(i + 1) % CYCLE.len()],
            None => CYCLE[0],
        }
    }

    pub fn all() -> &'static [Self] {
        &[
            Self::Single,
            Self::Ltr,
            Self::LtrCover,
            Self::Rtl,
            Self::RtlCover,
            Self::Vertical,
            Self::SplitLtr,
            Self::SplitRtl,
        ]
    }
}

// -----------------------------------------------------------------------
// 网格显示模式 (GridViewMode)
// -----------------------------------------------------------------------

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum GridViewMode {
    #[default]
    Thumbnail,
    Details,
}

impl GridViewMode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Thumbnail => "缩略图",
            Self::Details => "详细",
        }
    }

    pub fn all() -> &'static [Self] {
        &[Self::Thumbnail, Self::Details]
    }
}

// -----------------------------------------------------------------------
// ReadingFlow (阅读流向)
// -----------------------------------------------------------------------

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ReadingFlow {
    #[default]
    Paged,
    Vertical,
    Horizontal,
}

impl ReadingFlow {
    pub fn is_paged(self) -> bool {
        matches!(self, Self::Paged)
    }

    pub fn is_vertical(self) -> bool {
        matches!(self, Self::Vertical)
    }

    pub fn is_horizontal(self) -> bool {
        matches!(self, Self::Horizontal)
    }

    pub fn from_int(v: i32) -> Self {
        match v {
            1 => Self::Vertical,
            2 => Self::Horizontal,
            _ => Self::Paged,
        }
    }

    pub fn to_int(self) -> i32 {
        match self {
            Self::Paged => 0,
            Self::Vertical => 1,
            Self::Horizontal => 2,
        }
    }
}

// -----------------------------------------------------------------------
// GridDisplayOrder (条目类型在网格中的行分布与显示顺序)
// -----------------------------------------------------------------------

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum GridItemDisplayKind {
    Folder,
    Archive,
    Image,
    VideoAudio,
}

impl GridItemDisplayKind {
    pub const ALL: [Self; 4] = [Self::Folder, Self::Archive, Self::Image, Self::VideoAudio];

    pub fn default_row(self) -> usize {
        match self {
            Self::Folder | Self::Archive => 0,
            Self::Image | Self::VideoAudio => 1,
        }
    }
}

#[derive(serde::Serialize, Clone, Debug, PartialEq, Eq)]
#[serde(transparent)]
pub struct GridDisplayOrder([Vec<GridItemDisplayKind>; 4]);

impl GridDisplayOrder {
    pub fn from_rows(rows: [Vec<GridItemDisplayKind>; 4]) -> Self {
        let mut order = Self(rows);
        order.normalize();
        order
    }

    pub fn rows(&self) -> &[Vec<GridItemDisplayKind>; 4] {
        &self.0
    }

    pub fn row_for(&self, kind: GridItemDisplayKind) -> usize {
        self.0
            .iter()
            .position(|row| row.contains(&kind))
            .unwrap_or_else(|| kind.default_row())
    }

    pub fn assign(&mut self, kind: GridItemDisplayKind, row: usize) {
        let row = row.min(self.0.len() - 1);
        for current in &mut self.0 {
            current.retain(|candidate| *candidate != kind);
        }
        self.0[row].push(kind);
    }

    pub fn normalize(&mut self) {
        let mut normalized: [Vec<GridItemDisplayKind>; 4] = std::array::from_fn(|_| Vec::new());
        let mut seen = std::collections::HashSet::new();
        for (row_idx, row) in self.0.iter().enumerate() {
            for &kind in row {
                if seen.insert(kind) {
                    normalized[row_idx].push(kind);
                }
            }
        }
        for kind in GridItemDisplayKind::ALL {
            if seen.insert(kind) {
                normalized[kind.default_row()].push(kind);
            }
        }
        self.0 = normalized;
    }

    pub fn normalized(&self) -> Self {
        let mut value = self.clone();
        value.normalize();
        value
    }
}

impl Default for GridDisplayOrder {
    fn default() -> Self {
        Self([
            vec![GridItemDisplayKind::Folder, GridItemDisplayKind::Archive],
            vec![GridItemDisplayKind::Image, GridItemDisplayKind::VideoAudio],
            Vec::new(),
            Vec::new(),
        ])
    }
}

impl<'de> serde::Deserialize<'de> for GridDisplayOrder {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = <serde_json::Value as serde::Deserialize>::deserialize(deserializer)?;
        let Some(rows) = value.as_array() else {
            return Ok(Self::default());
        };
        if rows.len() != 4 || rows.iter().any(|row| !row.is_array()) {
            return Ok(Self::default());
        }

        let mut parsed: [Vec<GridItemDisplayKind>; 4] = std::array::from_fn(|_| Vec::new());
        for (row_idx, row) in rows.iter().enumerate() {
            for raw in row.as_array().expect("row shape checked above") {
                if let Ok(kind) = serde_json::from_value::<GridItemDisplayKind>(raw.clone()) {
                    parsed[row_idx].push(kind);
                }
            }
        }
        let mut order = Self(parsed);
        order.normalize();
        Ok(order)
    }
}

// -----------------------------------------------------------------------
// FavoriteViewState (每个位置/收藏独立记忆的视图状态)
// -----------------------------------------------------------------------

/// 按收藏/位置为单位记忆的显示状态。
///
/// 出处：`vendor/mimageviewer/src/settings.rs` 的 `FavoriteViewState`（约 3595–3640 行）。
/// 整组记忆屏幕上的列数、缩略图缩放比例、显示模式、排序顺序、见开设置等。
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct FavoriteViewState {
    pub grid_view_mode: GridViewMode,
    /// 屏幕上的列数。用户所看到的「缩略图大小」由它决定。
    pub grid_cols: usize,
    pub thumb_aspect: ThumbAspect,
    pub thumb_aspect_auto: bool,
    pub grid_display_order: GridDisplayOrder,
    pub sort_order: SortOrder,
    pub default_spread_mode: SpreadMode,
    pub default_reading_flow: ReadingFlow,
}

impl FavoriteViewState {
    pub fn from_settings(settings: &Settings) -> Self {
        Self {
            grid_view_mode: settings.grid_view_mode,
            grid_cols: settings.grid_cols,
            thumb_aspect: settings.thumb_aspect,
            thumb_aspect_auto: settings.thumb_aspect_auto,
            grid_display_order: settings.grid_display_order.clone(),
            sort_order: settings.sort_order,
            default_spread_mode: settings.default_spread_mode,
            default_reading_flow: settings.default_reading_flow,
        }
    }

    pub fn apply_to_settings(&self, settings: &mut Settings) {
        settings.grid_view_mode = self.grid_view_mode;
        settings.grid_cols = self.grid_cols;
        settings.thumb_aspect = self.thumb_aspect;
        settings.thumb_aspect_auto = self.thumb_aspect_auto;
        settings.grid_display_order = self.grid_display_order.clone();
        settings.sort_order = self.sort_order;
        settings.default_spread_mode = self.default_spread_mode;
        settings.default_reading_flow = self.default_reading_flow;
    }
}

/// 当前正应用到 `Settings` 显示字段上的位置 overlay。
///
/// `common` 是应当持久化的公共值的正本，`Settings::preferences_snapshot` 与
/// DB 保存时一律以它为准。切换 viewer context 时先回到公共值，
/// 再应用下一个 overlay。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FavoriteViewOverlay {
    pub favorite_id: String,
    pub common: FavoriteViewState,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_favorite_view_state_roundtrip() {
        let mut settings = Settings::default();
        settings.grid_cols = 4;
        settings.grid_view_mode = GridViewMode::Details;
        settings.thumb_aspect = ThumbAspect::Portrait2x3;
        settings.thumb_aspect_auto = false;
        settings.sort_order = SortOrder::Numeric;
        settings.default_spread_mode = SpreadMode::RtlCover;
        settings.default_reading_flow = ReadingFlow::Vertical;

        let state = FavoriteViewState::from_settings(&settings);
        let json = serde_json::to_string(&state).unwrap();
        let loaded: FavoriteViewState = serde_json::from_str(&json).unwrap();

        assert_eq!(state, loaded);

        let mut restored_settings = Settings::default();
        loaded.apply_to_settings(&mut restored_settings);
        assert_eq!(restored_settings.grid_cols, 4);
        assert_eq!(restored_settings.grid_view_mode, GridViewMode::Details);
        assert_eq!(restored_settings.thumb_aspect, ThumbAspect::Portrait2x3);
        assert!(!restored_settings.thumb_aspect_auto);
        assert_eq!(restored_settings.sort_order, SortOrder::Numeric);
        assert_eq!(restored_settings.default_spread_mode, SpreadMode::RtlCover);
        assert_eq!(
            restored_settings.default_reading_flow,
            ReadingFlow::Vertical
        );
    }

    #[test]
    fn test_favorite_view_overlay_preserves_common_and_reverts() {
        let mut settings = Settings::default();
        settings.grid_cols = 5;
        settings.grid_view_mode = GridViewMode::Thumbnail;
        let common = FavoriteViewState::from_settings(&settings);

        let mut custom_state = common.clone();
        custom_state.grid_cols = 8;
        custom_state.grid_view_mode = GridViewMode::Details;

        // 应用 overlay
        settings.apply_favorite_view_overlay("folder_a", &custom_state);
        assert_eq!(settings.active_favorite_view_id(), Some("folder_a"));
        assert_eq!(settings.grid_cols, 8);
        assert_eq!(settings.grid_view_mode, GridViewMode::Details);

        // preferences_snapshot 导出的必须是 common 正本，不能包含 overlay 的值
        let snapshot = settings.preferences_snapshot();
        assert_eq!(snapshot.grid_cols, 5);
        assert_eq!(snapshot.grid_view_mode, GridViewMode::Thumbnail);
        assert!(snapshot.favorite_view_overlay.is_none());

        // 清除 overlay 恢复 common
        settings.clear_favorite_view_overlay();
        assert_eq!(settings.active_favorite_view_id(), None);
        assert_eq!(settings.grid_cols, 5);
        assert_eq!(settings.grid_view_mode, GridViewMode::Thumbnail);
    }

    #[test]
    fn test_grid_display_order_normalize() {
        let mut order = GridDisplayOrder::default();
        order.assign(GridItemDisplayKind::Image, 3);
        assert_eq!(order.row_for(GridItemDisplayKind::Image), 3);

        let json = serde_json::to_string(&order).unwrap();
        let loaded: GridDisplayOrder = serde_json::from_str(&json).unwrap();
        assert_eq!(loaded.row_for(GridItemDisplayKind::Image), 3);
    }
}
