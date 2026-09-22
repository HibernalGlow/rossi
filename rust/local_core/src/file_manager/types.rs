// 从 file_manager.rs 整块原样搬出；除补必要的可见性前缀外未改一个字符。
use super::*;

/// NeoView 文件卡片默认的页签上限。上限属于核心状态，而不是 Dart 的布局常量，
/// 这样其它 UI 不会因为自己的按钮实现而出现不同的行为。
pub const MAX_FILE_MANAGER_TABS: usize = 8;
pub const MAX_RECENTLY_CLOSED_TABS: usize = 16;
pub const MAX_PENETRATION_DEPTH: usize = 32;
/// 一次递归搜索最多交出多少条。与 NeoView 的 `SEARCH_RESULT_LIMIT` 同值：
/// 再多的命中在这一屏里也看不清，而截断可以让遍历提前结束。
pub const MAX_SEARCH_RESULTS: usize = 512;
/// 递归搜索的目录深度上限。穿透用 `MAX_PENETRATION_DEPTH` 是有意的单链，
/// 这里按层展开，取更小的值以免一次键入扫完整棵盘树。
pub const MAX_SEARCH_DEPTH: usize = 12;
/// 默认递归深度：`库/分组/本/页` 这种常见结构够用。
pub const DEFAULT_SEARCH_DEPTH: usize = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InternalItemsMode {
    Single,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum ViewMode {
    #[default]
    Compact,
    CoverList,
    MosaicList,
    Details,
    CoverGrid,
    MosaicGrid,
}

/// 字段级排序沿用 NeoView 文件卡片的可切换排序模型。名称排序本身仍交给
/// mImageViewer 的 `filename_sort`，所以 Windows 与其它平台不会各自出现一套自然排序。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SortField {
    Name,
    Type,
    Size,
    /// 修改时间。目录的 `modified_secs` 同样参与比较，不做目录/文件特殊处理。
    Date,
    /// 稳定洗牌。顺序由 `FileManagerSettings::shuffle_seed` 决定，同一目录在
    /// 两次快照之间不会因为重新求值而跳动；重新洗牌只发生在切到该字段或刷新时。
    Random,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SortOrder {
    Ascending,
    Descending,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum EntryFilter {
    All,
    Folders,
    Archives,
    Images,
    Video,
    Audio,
}

/// 一个目录「上次怎么看的」的完整快照：目录级视图状态的持久化单元。
///
/// **为什么不复用 reader 侧的 `crate::settings::FavoriteViewState`**：那是 viewer 的表示状態
/// （网格列数、缩略图比例、翻页方向、阅读流），视图口径只有 Thumbnail / Details 两档。
/// 文件管理器有六种视图模式，经那套映射往返会把「紧凑列表 / 封面列表 / 横幅」全部塌成
/// 「详细信息」——所以这里要一套自己的、逐字往返的字段。
///
/// 字段范围＝「用户会期望按目录记住」的那些：视图模式、排序字段与方向、类型筛选、
/// 目录优先、显示隐藏项。`shuffle_seed` 跟着排序一起记，否则「随机」在重启后会换一副顺序。
/// 搜索词、穿透深度、目录列开关**不进**这里：它们描述的是这次浏览动作，不是这个目录的偏好。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct FileManagerViewState {
    pub view_mode: ViewMode,
    pub sort_field: SortField,
    pub sort_order: SortOrder,
    pub shuffle_seed: u64,
    pub entry_filter: EntryFilter,
    pub directories_first: bool,
    pub show_hidden_files: bool,
}

impl FileManagerViewState {
    pub fn from_settings(settings: &FileManagerSettings) -> Self {
        Self {
            view_mode: settings.view_mode,
            sort_field: settings.sort_field,
            sort_order: settings.sort_order,
            shuffle_seed: settings.shuffle_seed,
            entry_filter: settings.entry_filter,
            directories_first: settings.directories_first,
            show_hidden_files: settings.show_hidden_files,
        }
    }

    /// 目录视图状态的唯一写入口。
    ///
    /// 「临时排序」只应该活在当前画面里，所以置位时把上一次锁定的排序与种子盖回去，
    /// 避免它在离开目录（`transition_view_state_for_path`）或另一次 capture 时顺带落进目录偏好。
    pub fn from_settings_keeping_locked_sort(settings: &FileManagerSettings, base: &Self) -> Self {
        let mut state = Self::from_settings(settings);
        if settings.sort_temporary {
            state.sort_field = base.sort_field;
            state.sort_order = base.sort_order;
            state.shuffle_seed = base.shuffle_seed;
        }
        state
    }

    pub fn apply_to_settings(&self, settings: &mut FileManagerSettings) {
        settings.view_mode = self.view_mode;
        settings.sort_field = self.sort_field;
        settings.sort_order = self.sort_order;
        settings.shuffle_seed = self.shuffle_seed;
        settings.entry_filter = self.entry_filter;
        settings.directories_first = self.directories_first;
        settings.show_hidden_files = self.show_hidden_files;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSettings {
    pub penetration_enabled: bool,
    pub show_child_names: bool,
    pub internal_items_mode: InternalItemsMode,
    pub max_depth: usize,
    pub view_mode: ViewMode,
    pub show_hidden_files: bool,
    pub search_query: String,
    /// 查询词元在「条目名 + 相对根目录的路径」上匹配，还是只看条目名。
    /// 当前目录内的条目相对路径为空，因此单层浏览时该开关不改变结果。
    pub search_in_path: bool,
    /// 多个 include 词元的结合方式：`false` 为 AND（默认），`true` 为 OR。
    /// 否定词元（`-词`）在两种模式下都是硬性排除。
    pub search_or_mode: bool,
    /// 是否连同子目录一起搜。关掉时只在当前这一层找（`search_max_depth` 被忽略）。
    pub search_include_subfolders: bool,
    /// 递归搜索的层数上限，实际生效值再被 [`MAX_SEARCH_DEPTH`] 夹一次。
    pub search_max_depth: usize,
    pub entry_filter: EntryFilter,
    pub sort_field: SortField,
    pub sort_order: SortOrder,
    pub directories_first: bool,
    pub directory_columns_enabled: bool,
    /// 「临时排序」：置位时排序变更只影响当前画面，不写回当前目录的视图状态。
    /// 关闭时会把当前排序固化成该目录的偏好（工具栏的「锁定当前目录排序」）。
    pub sort_temporary: bool,
    /// `SortField::Random` 的洗牌种子。0 表示尚未洗过牌。
    pub shuffle_seed: u64,
}

impl Default for FileManagerSettings {
    fn default() -> Self {
        Self {
            penetration_enabled: false,
            show_child_names: true,
            internal_items_mode: InternalItemsMode::Single,
            max_depth: 3,
            view_mode: ViewMode::Compact,
            show_hidden_files: false,
            search_query: String::new(),
            search_in_path: true,
            search_or_mode: false,
            // 默认只搜当前一层：一次键入就扫整棵树的第一印象太差。要不要连子目录
            // 一起搜是搜索框上那颗开关的职责（并可被全局设置记住默认值）。
            search_include_subfolders: false,
            search_max_depth: DEFAULT_SEARCH_DEPTH,
            entry_filter: EntryFilter::All,
            sort_field: SortField::Name,
            sort_order: SortOrder::Ascending,
            directories_first: true,
            directory_columns_enabled: false,
            sort_temporary: false,
            shuffle_seed: 0,
        }
    }
}

impl FileManagerSettings {
    /// 回到「没有目录偏好」的公共值。
    ///
    /// 与 mImageViewer 的 `clear_favorite_view_overlay` 同一分工：切换位置时先干净回退，
    /// 再套用新位置的 overlay，避免上一个目录的局部修改在无匹配目录上漏出来。
    pub fn reset_view_fields_to(&mut self, common: &Self) {
        self.view_mode = common.view_mode;
        self.sort_field = common.sort_field;
        self.sort_order = common.sort_order;
        self.shuffle_seed = common.shuffle_seed;
        self.entry_filter = common.entry_filter;
        self.directories_first = common.directories_first;
        self.show_hidden_files = common.show_hidden_files;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerChild {
    pub path: PathBuf,
    pub name: String,
    pub is_dir: bool,
    pub is_archive: bool,
    pub is_image: bool,
    pub is_video: bool,
    pub is_audio: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerEntry {
    pub node: FileTreeNode,
    pub children: Vec<FileManagerChild>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerBreadcrumb {
    pub path: PathBuf,
    pub name: String,
    pub is_root: bool,
    pub is_current: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerDirectoryChoice {
    pub path: PathBuf,
    pub name: String,
    pub selected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerDirectoryColumn {
    pub path: PathBuf,
    pub name: String,
    pub entries: Vec<FileManagerDirectoryChoice>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerTab {
    pub id: u64,
    pub path: PathBuf,
    pub back: Vec<PathBuf>,
    pub forward: Vec<PathBuf>,
    pub pinned: bool,
    pub settings: FileManagerSettings,
    pub common_settings: FileManagerSettings,
    pub active_view_state_id: Option<String>,
    /// 搜索结果列表。非空时这个页签画的就是这份命中，而不是 `path` 那一层
    /// （NeoView 的 `virtual://search` 页签）。
    ///
    /// 命中存在核心里而不是 UI 里，为的是让**列表只有一个真本**：换布局、重建卡片
    /// 或别的页签切回来，看到的仍是同一份结果；陈旧判定也才能用会话的 generation。
    pub search: Option<FileManagerSearchListing>,
}

/// 一次搜索落在页签上的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchListing {
    /// 搜索根。结果里的条目都在这下面，页签的 `path` 也停在这里。
    pub root: PathBuf,
    /// 这批命中对应的查询，用于说明与「重新搜索」。
    pub query: String,
    pub entries: Vec<FileManagerEntry>,
    pub scanned: usize,
    pub matched: usize,
    pub truncated: bool,
    pub cancelled: bool,
}

/// 页签标题里最多露出多少个搜索词。再长就该去输入框里看，而不是把页签条撑开。
pub(super) const SEARCH_TITLE_QUERY_CHARS: usize = 24;

impl FileManagerTab {
    pub(super) fn new(id: u64, path: PathBuf) -> Self {
        Self {
            id,
            path,
            back: Vec::new(),
            forward: Vec::new(),
            pinned: false,
            settings: FileManagerSettings::default(),
            common_settings: FileManagerSettings::default(),
            active_view_state_id: None,
            search: None,
        }
    }

    pub fn title(&self) -> String {
        if let Some(search) = &self.search {
            // NeoView 的 `searchTabTitle`：有词就露词，没词（纯条件筛选）叫「搜索结果」。
            let query = search.query.trim();
            if query.is_empty() {
                return "搜索结果".to_string();
            }
            let short: String = query.chars().take(SEARCH_TITLE_QUERY_CHARS).collect();
            let needs_ellipsis = query.chars().count() > SEARCH_TITLE_QUERY_CHARS;
            return if needs_ellipsis {
                format!("搜索: {short}…")
            } else {
                format!("搜索: {short}")
            };
        }
        self.path
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty())
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| self.path.to_string_lossy().into_owned())
    }

    pub fn can_go_back(&self) -> bool {
        !self.back.is_empty()
    }

    pub fn can_go_forward(&self) -> bool {
        !self.forward.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PenetrationResult {
    /// 目录本身是一个纯媒体来源，或目录链最终落到唯一归档。
    Terminal(PathBuf),
    /// 存在多个候选，用户必须进入目录自行选择。
    Branch,
    Empty,
    Blocked,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenEntryResult {
    Entered(PathBuf),
    Opened(PathBuf),
}
