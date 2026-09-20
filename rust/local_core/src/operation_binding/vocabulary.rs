//! 操作绑定的**词汇表**：输入 context / 画面九宫格 / 动作 id。
//!
//! ## 为什么字符串与数值必须逐条照抄 neoview
//!
//! 绑定表、context 名、动作 id 都是**要落进用户配置**的东西（导出/导入绑定包）。
//! schema 一旦有用户数据就难改，而两边的绑定包将来要能互换（ADR-0009 §7）——
//! 所以这里的每一个字符串都取自
//! `packages/nodes/neoview/src/domain/input/ReaderInputBindings.ts` 与
//! `ReaderInputActions.ts`，**不做任何「顺手改名」**。
//!
//! ## 动作目录为什么只收一部分
//!
//! 只收**Rossi 运行时真的要执行的那一部分**（导航 / 缩放 / 视图 / 会话）。
//! 视频、轮盘、幻灯片、手柄、轨迹手势、文件命令等条目等对应运行时落地时再**追加**。
//! 「schema 一次做全」的意思是**不许改名、不许改值**，不是不许追加 —— 追加不会让
//! 已发出去的绑定包失效，改名会。
//!
//! **一处例外**：`comic-info.*`（详情页操作栏）是在执行端之前整族登记的一族，全部
//! `implemented: false`。理由是那一屏的按钮清单要**只有这一份权威** —— 外壳自己列
//! 一份「有哪些按钮」，加动作时两处必分叉（同 ADR-0015 收注册表进核心的动机）。
//! 代价是这一族的 id 从登记那一刻起就**不能再改名**，所以命名按 `video.` 那条规矩
//! 走独立前缀，且未接执行的条目由 `implemented` 标灰、由阅读器绑定表按分类整族排除。

use std::fmt;

/// 输入 context 的**全集**（neoview `READER_INPUT_CONTEXTS`，顺序也一致）。
pub const READER_INPUT_CONTEXTS: [InputContext; 7] = [
    InputContext::Global,
    InputContext::Reader,
    InputContext::Video,
    InputContext::Panel,
    InputContext::Shell,
    InputContext::Editor,
    InputContext::Modal,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum InputContext {
    /// 全局：优先级最低，且在 [`InputContext::isolates_global`] 为真的 context 在场时**被隔离**。
    Global,
    Reader,
    Video,
    Panel,
    Shell,
    Editor,
    Modal,
}

impl InputContext {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Global => "global",
            Self::Reader => "reader",
            Self::Video => "video",
            Self::Panel => "panel",
            Self::Shell => "shell",
            Self::Editor => "editor",
            Self::Modal => "modal",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        READER_INPUT_CONTEXTS
            .into_iter()
            .find(|context| context.as_str() == raw)
    }

    /// neoview `READER_INPUT_CONTEXT_PRIORITY` 的数值，逐条一致（越大越优先）。
    ///
    /// 解析时**只有严格更大**才顶替已匹配的那条 ⇒ 同优先级时**先注册者胜**，
    /// 与 neoview 的 `if (priority > matchPriority)` 同一个语义。
    pub const fn priority(self) -> i32 {
        match self {
            Self::Global => 0,
            Self::Reader => 100,
            Self::Video => 150,
            Self::Panel => 200,
            Self::Shell => 250,
            Self::Editor => 300,
            Self::Modal => 400,
        }
    }

    /// neoview `READER_INPUT_GLOBAL_ISOLATION_CONTEXTS`：
    /// 这些 context 在场时 `global` 的**绑定不生效**（不是「优先级更低」，是「隔离」）。
    pub const fn isolates_global(self) -> bool {
        matches!(self, Self::Shell | Self::Editor | Self::Modal)
    }
}

impl fmt::Display for InputContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 画面**九宫格**（neoview `READER_VIEW_AREAS`，含顺序）。
///
/// 顺序 = 行优先（上排三格 → 中排三格 → 下排三格），索引算法与 neoview 的
/// `READER_VIEW_AREAS[row * 3 + column]` 一致。
pub const READER_VIEW_AREAS: [ReaderViewArea; 9] = [
    ReaderViewArea::TopLeft,
    ReaderViewArea::TopCenter,
    ReaderViewArea::TopRight,
    ReaderViewArea::MiddleLeft,
    ReaderViewArea::MiddleCenter,
    ReaderViewArea::MiddleRight,
    ReaderViewArea::BottomLeft,
    ReaderViewArea::BottomCenter,
    ReaderViewArea::BottomRight,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ReaderViewArea {
    TopLeft,
    TopCenter,
    TopRight,
    MiddleLeft,
    MiddleCenter,
    MiddleRight,
    BottomLeft,
    BottomCenter,
    BottomRight,
}

impl ReaderViewArea {
    pub const ALL: [Self; 9] = READER_VIEW_AREAS;

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::TopLeft => "top-left",
            Self::TopCenter => "top-center",
            Self::TopRight => "top-right",
            Self::MiddleLeft => "middle-left",
            Self::MiddleCenter => "middle-center",
            Self::MiddleRight => "middle-right",
            Self::BottomLeft => "bottom-left",
            Self::BottomCenter => "bottom-center",
            Self::BottomRight => "bottom-right",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|area| area.as_str() == raw)
    }

    /// 列号（0 左 / 1 中 / 2 右）。
    pub const fn column(self) -> u8 {
        match self {
            Self::TopLeft | Self::MiddleLeft | Self::BottomLeft => 0,
            Self::TopCenter | Self::MiddleCenter | Self::BottomCenter => 1,
            Self::TopRight | Self::MiddleRight | Self::BottomRight => 2,
        }
    }

    /// 行号（0 上 / 1 中 / 2 下）。
    pub const fn row(self) -> u8 {
        match self {
            Self::TopLeft | Self::TopCenter | Self::TopRight => 0,
            Self::MiddleLeft | Self::MiddleCenter | Self::MiddleRight => 1,
            Self::BottomLeft | Self::BottomCenter | Self::BottomRight => 2,
        }
    }

    /// 九宫格在 3×3 里的序号（行优先）。构造时用来替代一堆手写映射。
    pub const fn index(self) -> usize {
        (self.row() as usize) * 3 + self.column() as usize
    }
}

impl fmt::Display for ReaderViewArea {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 阅读方向（neoview `ReadingDirection`）。**这是「空间动作」唯一的解释器**：
/// 同一条 `reader.page-right`，在 `LeftToRight` 下是下一页、在 `RightToLeft` 下是上一页。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ReadingDirection {
    /// 从左到右推进 —— 下一页在右边，界面文案叫「右开」。
    LeftToRight,
    /// 从右到左推进（漫画经典排版）—— 下一页在左边，界面文案叫「左开」。
    RightToLeft,
}

impl ReadingDirection {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::LeftToRight => "left-to-right",
            Self::RightToLeft => "right-to-left",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "left-to-right" => Some(Self::LeftToRight),
            "right-to-left" => Some(Self::RightToLeft),
            _ => None,
        }
    }

    pub const fn toggled(self) -> Self {
        match self {
            Self::LeftToRight => Self::RightToLeft,
            Self::RightToLeft => Self::LeftToRight,
        }
    }

    /// 从阅读模式解出方向。
    ///
    /// `readMode`：`0` 条漫 / `1` 右开 / `2` 左开（见 `read_layout.dart` 的
    /// `kReadMode*`）。条漫是**竖向**的连续滚动，没有「左右」可言 —— 取
    /// [`ReadingDirection::LeftToRight`] 当缺省，于是 `page-left/page-right`
    /// 在条漫下退化成「上一屏/下一屏」，与改造前 `key.dart` 的左右键行为一致。
    pub const fn from_read_mode(read_mode: i32) -> Self {
        if read_mode == 2 {
            Self::RightToLeft
        } else {
            Self::LeftToRight
        }
    }
}

/// 动作 id —— 字符串逐条照抄 neoview（含 Rossi 追加的两条，见文件末尾说明）。
pub mod action {
    // ── navigation ─────────────────────────────────────────────────────────
    /// 下一页（**语义**：不论从哪边来，就是「前进」）。
    pub const NEXT_PAGE: &str = "reader.next-page";
    /// 上一页（语义）。
    pub const PREVIOUS_PAGE: &str = "reader.previous-page";
    pub const FIRST_PAGE: &str = "reader.first-page";
    pub const LAST_PAGE: &str = "reader.last-page";
    /// 向左翻页（**空间**：画面往左翻，是不是「前进」由阅读方向决定）。
    pub const PAGE_LEFT: &str = "reader.page-left";
    /// 向右翻页（空间）。
    pub const PAGE_RIGHT: &str = "reader.page-right";
    pub const NEXT_BOOK: &str = "reader.next-book";
    pub const PREVIOUS_BOOK: &str = "reader.previous-book";

    // ── zoom ───────────────────────────────────────────────────────────────
    pub const ZOOM_IN: &str = "reader.zoom-in";
    pub const ZOOM_OUT: &str = "reader.zoom-out";
    pub const FIT_WINDOW: &str = "reader.fit-window";
    pub const ACTUAL_SIZE: &str = "reader.actual-size";
    pub const RESET_VIEW: &str = "reader.reset-view";

    // ── view ───────────────────────────────────────────────────────────────
    pub const FULLSCREEN: &str = "reader.fullscreen";
    /// 阅读方向切换（左开 ⇄ 右开）。
    pub const TOGGLE_READING_DIRECTION: &str = "reader.toggle-reading-direction";
    /// 书籍模式（单页 ⇄ 双页）。
    pub const TOGGLE_BOOK_MODE: &str = "reader.toggle-book-mode";
    pub const ROTATE_CLOCKWISE: &str = "reader.rotate-clockwise";
    pub const ROTATE_180: &str = "reader.rotate-180";
    /// **Rossi 追加**（neoview 没有这一条）：唤出/收起阅读器上下栏。
    ///
    /// neoview 的 chrome 显隐挂在 shell 自己的手势上，没有做成可绑定动作；Rossi 的
    /// 「点正中那一格唤出上下栏」是一个**用户可关的开关**（`centerTapToggleBars`），
    /// 于是它需要一个动作 id 才能进九宫格绑定表。
    /// 命名跟随 neoview 的扩展先例（它们自己也是用 `workspace.*` / `reader.open-settings`
    /// 追加 XR 专属动作）；若将来 neoview 定义了同名语义的动作，**以它为准改名并留迁移映射**。
    pub const TOGGLE_CONTROLS: &str = "reader.toggle-controls";

    // ── session ────────────────────────────────────────────────────────────
    pub const OPEN_SETTINGS: &str = "reader.open-settings";
    // ── radial（neoview `ReaderInputActions.ts` 的 `radial` 一族）─────────────
    /// 唤出轮盘。id 与显示名都照抄 neoview 的注册表条目
    /// `action("radial.open-default", "openRadialMenu.default", "打开轮盘菜单", "radial")`，
    /// 因为它是**要落进用户绑定包**的东西；neoview 的默认绑法是右键按下 + `Enter`。
    ///
    pub const OPEN_RADIAL_MENU: &str = "radial.open-default";
    pub const CONFIRM_RADIAL_MENU: &str = "radial.confirm";
    pub const TOGGLE_LIBRARY: &str = "reader.toggle-library";

    // ── video（ADR-0016 追加；mImageViewer `keymap.rs` 的 `KeyAction::Video*` 面）──
    // 命名用 `video.` 前缀而不是塞进 `reader.`：`InputContext::Video` 的优先级
    // 高于 `reader`，前缀一致才能让人一眼看出这条动作在哪个上下文里生效。
    pub const VIDEO_PLAY_PAUSE: &str = "video.play-pause";
    pub const VIDEO_SEEK_BACKWARD: &str = "video.seek-backward";
    pub const VIDEO_SEEK_FORWARD: &str = "video.seek-forward";
    pub const VIDEO_SEEK_MODE_TOGGLE: &str = "video.seek-mode-toggle";
    pub const VIDEO_FRAME_STEP: &str = "video.frame-step";
    pub const VIDEO_FRAME_STEP_BACK: &str = "video.frame-step-back";
    pub const VIDEO_SPEED_UP: &str = "video.speed-up";
    pub const VIDEO_SPEED_DOWN: &str = "video.speed-down";
    pub const VIDEO_TOGGLE_SPEED: &str = "video.toggle-speed";
    pub const VIDEO_VOLUME_UP: &str = "video.volume-up";
    pub const VIDEO_VOLUME_DOWN: &str = "video.volume-down";
    pub const VIDEO_TOGGLE_MUTE: &str = "video.toggle-mute";
    pub const VIDEO_CYCLE_LOOP: &str = "video.cycle-loop";
    pub const VIDEO_AB_LOOP_TAP: &str = "video.ab-loop-tap";
    pub const VIDEO_AB_LOOP_CLEAR: &str = "video.ab-loop-clear";
    pub const VIDEO_SCREENSHOT: &str = "video.screenshot";
    pub const VIDEO_TOGGLE_CONTROLS: &str = "video.toggle-controls";
    pub const VIDEO_TOGGLE_SUBTITLE: &str = "video.toggle-subtitle";
    pub const VIDEO_SUBTITLE_DELAY_UP: &str = "video.subtitle-delay-up";
    pub const VIDEO_SUBTITLE_DELAY_DOWN: &str = "video.subtitle-delay-down";
    pub const VIDEO_TOGGLE_AUDIO_ONLY: &str = "video.toggle-audio-only";
    pub const VIDEO_TOGGLE_FULLSCREEN: &str = "video.toggle-fullscreen";
    /// 上一章 / 下一章（mImageViewer `decoder.rs:1594` 的章节边界才真的能用：
    /// 光把章节画在进度条上，用户没有跳的入口）。
    pub const VIDEO_NEXT_CHAPTER: &str = "video.next-chapter";
    pub const VIDEO_PREVIOUS_CHAPTER: &str = "video.previous-chapter";

    // ── comic-info（Rossi 追加：详情页操作栏，见 `docs/comic-info-action-rail.md`）──
    //
    // 前缀用 `comic-info.` 而不是塞进 `reader.`：同 `video.` 那条理由，前缀要能看出
    // 这一族在哪个界面生效。这一族**只有清单，还没有执行端**（车道 C 才接），所以
    // 全部 `implemented: false`；阅读器的绑定表编辑器按 `category` 把它们整族排除，
    // 否则会出现「绑得上、按下去什么都不发生」的键。
    //
    // 文案与页面既有措辞对齐（`t.comicInfo.*`）：状态化的显示文字（开始/继续、
    // 收藏/已收藏）由外壳按当前状态挑，注册表里只放中性名。
    /// 返回上一页（住在发现页标签里时关的是那条标签）。
    pub const COMIC_INFO_BACK: &str = "comic-info.back";
    /// 回到首页 / 工作台根。
    pub const COMIC_INFO_HOME: &str = "comic-info.home";
    /// 开始或继续阅读（有历史就是「继续」，注册表不区分）。
    pub const COMIC_INFO_READ: &str = "comic-info.read";
    /// 收藏或取消收藏（本地与云端由 `cloudFavoritePreferred` 决定，同一颗）。
    pub const COMIC_INFO_COLLECT: &str = "comic-info.collect";
    /// 关注或取消关注上传者。
    pub const COMIC_INFO_FOLLOW: &str = "comic-info.follow";
    /// 点赞（远程写操作，受 `allowLike` 约束）。
    pub const COMIC_INFO_LIKE: &str = "comic-info.like";
    /// 打开评论区。
    pub const COMIC_INFO_COMMENTS: &str = "comic-info.comments";
    /// 下载整本。
    pub const COMIC_INFO_DOWNLOAD: &str = "comic-info.download";
    /// 下载：挑章节（详情页现在是长按下载那颗，见 `comic_operation.dart`）。
    pub const COMIC_INFO_DOWNLOAD_CHAPTERS: &str = "comic-info.download-chapters";
    /// 复制磁力链接（插件没给磁力时整颗不渲染）。
    pub const COMIC_INFO_COPY_MAGNET: &str = "comic-info.copy-magnet";
    /// 章节列表正序 ⇄ 倒序。
    pub const COMIC_INFO_TOGGLE_CHAPTER_ORDER: &str = "comic-info.toggle-chapter-order";
    /// 导出本条漫画的信息。
    pub const COMIC_INFO_EXPORT: &str = "comic-info.export";
    /// 详情页的「更多」弹层。
    pub const COMIC_INFO_MORE: &str = "comic-info.more";
}

/// 动作分类（neoview `READER_INPUT_ACTION_CATEGORIES`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionCategory {
    Navigation,
    Zoom,
    View,
    Session,
    /// 轮盘自身的动作（neoview `radial` 分类）。
    ///
    /// 设置页的**槽位**选项会排除这一类：轮盘里再放一个「打开轮盘」是循环。
    Radial,
    /// 详情页那一族（**Rossi 追加**，neoview 没有详情页）。
    ///
    /// 阅读器的绑定表编辑器整族排除：这一族的执行端在详情页，而 v0.1 没有
    /// `comic-info` 这个 `InputContext`，列进去等于给用户一排绑得上、按下去
    /// 什么都不发生的键（见 `OperationBindingStore.readerBindableCatalog`）。
    ComicInfo,
}

impl ActionCategory {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Navigation => "navigation",
            Self::Zoom => "zoom",
            Self::View => "view",
            Self::Session => "session",
            Self::Radial => "radial",
            Self::ComicInfo => "comic-info",
        }
    }

    /// neoview `READER_INPUT_ACTION_CATEGORY_LABELS`。
    pub const fn label(self) -> &'static str {
        match self {
            Self::Navigation => "导航",
            Self::Zoom => "缩放",
            Self::View => "视图",
            Self::Session => "会话",
            Self::Radial => "轮盘",
            Self::ComicInfo => "详情页",
        }
    }
}

/// 一条动作定义（注册表条目）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ActionDefinition {
    pub id: &'static str,
    /// 显示名 —— neoview `READER_INPUT_ACTION_LABELS` 的中文原文。
    pub label: &'static str,
    pub category: ActionCategory,
    /// 本仓运行时**是否已能执行**。
    ///
    /// `false` 的条目是「schema 里已认，运行时未接」：它们可以被解析出来，但执行体
    /// 会返回 unavailable。把这件事写在数据里，设置页就能直接标灰，而不用在 UI 里
    /// 维护第二份「哪些动作能用」的名单。
    pub implemented: bool,
}

macro_rules! action_def {
    ($id:expr, $label:expr, $category:expr, $implemented:expr) => {
        ActionDefinition {
            id: $id,
            label: $label,
            category: $category,
            implemented: $implemented,
        }
    };
}

/// Rossi 动作注册表（子集，见模块头注释）。
pub const ACTION_CATALOG: [ActionDefinition; 60] = [
    action_def!(
        action::CONFIRM_RADIAL_MENU,
        "确认轮盘选项",
        ActionCategory::Radial,
        true
    ),
    action_def!(
        action::TOGGLE_LIBRARY,
        "切换书库",
        ActionCategory::View,
        false
    ),
    action_def!(
        action::VIDEO_NEXT_CHAPTER,
        "视频：上一章",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_PREVIOUS_CHAPTER,
        "视频：下一章",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_PLAY_PAUSE,
        "视频：播放/暂停",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SEEK_BACKWARD,
        "视频：后退 10 秒",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SEEK_FORWARD,
        "视频：前进 10 秒",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SEEK_MODE_TOGGLE,
        "视频：快进档",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_FRAME_STEP,
        "视频：下一帧",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_FRAME_STEP_BACK,
        "视频：上一帧",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SPEED_UP,
        "视频：加速",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SPEED_DOWN,
        "视频：减速",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_SPEED,
        "视频：切换倍速",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_VOLUME_UP,
        "视频：音量+",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_VOLUME_DOWN,
        "视频：音量-",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_MUTE,
        "视频：静音",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_CYCLE_LOOP,
        "视频：循环档",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_AB_LOOP_TAP,
        "视频：A-B 打点",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_AB_LOOP_CLEAR,
        "视频：清除 A-B",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SCREENSHOT,
        "视频：截图",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_CONTROLS,
        "视频：显隐控制条",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_SUBTITLE,
        "视频：切字幕轨",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SUBTITLE_DELAY_UP,
        "视频：字幕延迟+",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_SUBTITLE_DELAY_DOWN,
        "视频：字幕延迟-",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_AUDIO_ONLY,
        "视频：只听声音",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::VIDEO_TOGGLE_FULLSCREEN,
        "视频：全屏",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::NEXT_PAGE,
        "下一页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::PREVIOUS_PAGE,
        "上一页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::FIRST_PAGE,
        "第一页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::LAST_PAGE,
        "最后一页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::PAGE_LEFT,
        "向左翻页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::PAGE_RIGHT,
        "向右翻页",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::NEXT_BOOK,
        "下一个书籍",
        ActionCategory::Navigation,
        true
    ),
    action_def!(
        action::PREVIOUS_BOOK,
        "上一个书籍",
        ActionCategory::Navigation,
        true
    ),
    action_def!(action::ZOOM_IN, "放大", ActionCategory::Zoom, true),
    action_def!(action::ZOOM_OUT, "缩小", ActionCategory::Zoom, true),
    action_def!(action::FIT_WINDOW, "适应窗口", ActionCategory::Zoom, true),
    action_def!(action::ACTUAL_SIZE, "实际大小", ActionCategory::Zoom, true),
    action_def!(action::FULLSCREEN, "全屏", ActionCategory::View, true),
    action_def!(
        action::TOGGLE_READING_DIRECTION,
        "阅读方向切换",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::TOGGLE_BOOK_MODE,
        "书籍模式",
        ActionCategory::View,
        true
    ),
    action_def!(action::ROTATE_CLOCKWISE, "旋转", ActionCategory::View, true),
    action_def!(action::ROTATE_180, "旋转180度", ActionCategory::View, true),
    action_def!(action::RESET_VIEW, "重置视图", ActionCategory::View, true),
    action_def!(
        action::TOGGLE_CONTROLS,
        "唤出/收起上下栏",
        ActionCategory::View,
        true
    ),
    action_def!(
        action::OPEN_SETTINGS,
        "打开设置",
        ActionCategory::Session,
        true
    ),
    action_def!(
        action::OPEN_RADIAL_MENU,
        "打开轮盘菜单",
        ActionCategory::Radial,
        true
    ),
    // ── comic-info（详情页操作栏）─────────────────────────────────────────────
    //
    // 全部 `implemented: false` 是刻意的：这一族先把**清单**定下来，外壳（rail 与
    // 移动端底部条）才有唯一的动作来源，不用在 Dart 里抄一份「有哪些按钮」。
    // 执行端逐条接上时把对应条目翻成 `true`，未接的自动置灰。
    action_def!(
        action::COMIC_INFO_BACK,
        "返回",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_HOME,
        "回到首页",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_READ,
        "开始或继续阅读",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_COLLECT,
        "收藏",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_FOLLOW,
        "关注",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_LIKE,
        "点赞",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_COMMENTS,
        "查看评论",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_DOWNLOAD,
        "下载",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_DOWNLOAD_CHAPTERS,
        "下载：选择章节",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_COPY_MAGNET,
        "复制磁力链接",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_TOGGLE_CHAPTER_ORDER,
        "章节正序/倒序",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_EXPORT,
        "导出",
        ActionCategory::ComicInfo,
        false
    ),
    action_def!(
        action::COMIC_INFO_MORE,
        "更多操作",
        ActionCategory::ComicInfo,
        false
    ),
];

/// 动作 id 是否在注册表里（**判据 E1**：id 稳定且唯一）。
pub fn action_definition(id: &str) -> Option<&'static ActionDefinition> {
    ACTION_CATALOG.iter().find(|entry| entry.id == id)
}

/// 注册表的一条**导出记录**（字段名是 camelCase，因为设置页拿到的是 JSON）。
///
/// 为什么要导出而不是让 Dart 侧抄一份清单：ADR-0015 §「设置页的操作绑定卡片从核心取
/// 注册表」。Dart 一旦自己维护「有哪些动作 / 哪个能用」，就有了第二份权威，
/// 换外壳时两处会分叉。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionCatalogEntry {
    pub id: &'static str,
    pub label: &'static str,
    /// 分类的 platform-neutral 名（`navigation` / `zoom` / `view` / `session`）。
    pub category: &'static str,
    /// 分类的显示名 —— 显示名归核心是因为它和 id 一样要**成对**演进。
    pub category_label: &'static str,
    pub implemented: bool,
}

/// 注册表全量（顺序即 [`ACTION_CATALOG`] 的顺序：设置页按它分组）。
pub fn action_catalog_entries() -> Vec<ActionCatalogEntry> {
    ACTION_CATALOG
        .iter()
        .map(|entry| ActionCatalogEntry {
            id: entry.id,
            label: entry.label,
            category: entry.category.as_str(),
            category_label: entry.category.label(),
            implemented: entry.implemented,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn context_priority_and_isolation_match_neoview() {
        // 数值逐条对齐 neoview `READER_INPUT_CONTEXT_PRIORITY`。
        assert_eq!(InputContext::Global.priority(), 0);
        assert_eq!(InputContext::Reader.priority(), 100);
        assert_eq!(InputContext::Video.priority(), 150);
        assert_eq!(InputContext::Panel.priority(), 200);
        assert_eq!(InputContext::Shell.priority(), 250);
        assert_eq!(InputContext::Editor.priority(), 300);
        assert_eq!(InputContext::Modal.priority(), 400);

        // 顺序与名字也一致（它们是落进绑定包的字符串）。
        let names: Vec<&str> = READER_INPUT_CONTEXTS
            .iter()
            .map(|context| context.as_str())
            .collect();
        assert_eq!(
            names,
            vec![
                "global", "reader", "video", "panel", "shell", "editor", "modal"
            ]
        );

        for context in READER_INPUT_CONTEXTS {
            assert_eq!(
                context.isolates_global(),
                matches!(
                    context,
                    InputContext::Shell | InputContext::Editor | InputContext::Modal
                )
            );
            assert_eq!(InputContext::parse(context.as_str()), Some(context));
        }
    }

    #[test]
    fn nine_grid_is_row_major_and_round_trips() {
        let names: Vec<&str> = READER_VIEW_AREAS.iter().map(|a| a.as_str()).collect();
        assert_eq!(
            names,
            vec![
                "top-left",
                "top-center",
                "top-right",
                "middle-left",
                "middle-center",
                "middle-right",
                "bottom-left",
                "bottom-center",
                "bottom-right",
            ]
        );

        for (index, area) in READER_VIEW_AREAS.into_iter().enumerate() {
            assert_eq!(area.index(), index, "{area} 的序号必须与 neoview 一致");
            assert_eq!(area.row() as usize, index / 3);
            assert_eq!(area.column() as usize, index % 3);
            assert_eq!(ReaderViewArea::parse(area.as_str()), Some(area));
        }
    }

    #[test]
    fn reading_direction_round_trips_and_toggles() {
        assert_eq!(
            ReadingDirection::LeftToRight.as_str(),
            "left-to-right",
            "界面文案的「右开」就是 left-to-right"
        );
        assert_eq!(ReadingDirection::RightToLeft.as_str(), "right-to-left");
        assert_eq!(
            ReadingDirection::LeftToRight.toggled(),
            ReadingDirection::RightToLeft
        );
        assert_eq!(
            ReadingDirection::RightToLeft.toggled(),
            ReadingDirection::LeftToRight
        );

        // 阅读模式 → 方向：只有 2（左开）是 RTL；条漫(0)/右开(1) 都是 LTR。
        assert_eq!(
            ReadingDirection::from_read_mode(0),
            ReadingDirection::LeftToRight
        );
        assert_eq!(
            ReadingDirection::from_read_mode(1),
            ReadingDirection::LeftToRight
        );
        assert_eq!(
            ReadingDirection::from_read_mode(2),
            ReadingDirection::RightToLeft
        );
    }

    #[test]
    fn action_ids_are_unique_and_catalog_is_consistent() {
        let ids: Vec<&str> = ACTION_CATALOG.iter().map(|entry| entry.id).collect();
        let unique: HashSet<&str> = ids.iter().copied().collect();
        assert_eq!(ids.len(), unique.len(), "动作 id 不许重复：{ids:?}");

        for entry in ACTION_CATALOG {
            assert_eq!(action_definition(entry.id).map(|e| e.id), Some(entry.id));
            assert!(!entry.label.is_empty());
            assert!(
                entry.id.contains('.'),
                "动作 id 的形状是 `<域>.<动作>`：{}",
                entry.id
            );
        }
        assert_eq!(action_definition("reader.nope"), None);
    }

    #[test]
    fn catalog_export_keeps_labels_and_implemented_flag() {
        // 设置页靠这份导出渲染选项（ADR-0015：注册表归核心，Dart 不抄第二份）。
        let entries = action_catalog_entries();
        assert_eq!(entries.len(), ACTION_CATALOG.len());
        assert!(
            entries.iter().any(|entry| entry.implemented),
            "至少要有一条能执行的动作，否则设置页全是灰的"
        );
        assert!(
            entries.iter().any(|entry| !entry.implemented),
            "schema 里已认、运行时未接的动作必须标出来，设置页才好置灰"
        );
        for entry in &entries {
            assert_eq!(
                entry.category,
                action_definition(entry.id).unwrap().category.as_str()
            );
            assert!(!entry.category_label.is_empty());
        }

        // 字段名是落进 JSON 给外壳看的，形状要稳。
        let json = serde_json::to_string(&entries[0]).unwrap();
        for field in [
            "\"id\"",
            "\"label\"",
            "\"category\"",
            "\"categoryLabel\"",
            "\"implemented\"",
        ] {
            assert!(json.contains(field), "导出字段缺失 {field}：{json}");
        }
    }

    #[test]
    fn comic_info_family_is_registered_with_stable_names() {
        // 详情页那一族是「清单先于执行端」的例外（见模块头），所以它的 id 与分类名
        // 从登记那一刻起就是**对外契约**：外壳按 `comic-info` 这个分类名把整族挡在
        // 阅读器绑定表外面，改这个字符串等于把 13 条没接执行的条目放进绑定表。
        assert_eq!(ActionCategory::ComicInfo.as_str(), "comic-info");
        assert_eq!(ActionCategory::ComicInfo.label(), "详情页");

        let family: Vec<&ActionDefinition> = ACTION_CATALOG
            .iter()
            .filter(|entry| entry.category == ActionCategory::ComicInfo)
            .collect();
        assert_eq!(family.len(), 13, "comic-info 一族的条目数变了");
        for entry in &family {
            assert!(
                entry.id.starts_with("comic-info."),
                "这一族必须用独立前缀，不许塞进 reader.：{}",
                entry.id
            );
            assert!(!entry.label.is_empty());
            assert_eq!(action_definition(entry.id).map(|e| e.id), Some(entry.id));
        }

        // 阅读器仍然至少有一条可执行动作（这一族整族被排除后，绑定表不能变空）。
        assert!(
            ACTION_CATALOG
                .iter()
                .any(|e| e.category != ActionCategory::ComicInfo && e.implemented),
        );
    }
}
