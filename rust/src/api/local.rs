//! 本地来源（散图文件夹 / CBZ / CBR）的会话层 —— v0.1 判据 A 进入 App 的唯一入口。
//!
//! 对应 `docs/v0.1-local-core.md` §9。`rossi_local_core` 只保存「根路径 + 类型 + 页序列」，
//! 不持有任何打开的文件/归档对象，所以**会话表放在这一层**（Reader session 由 Rossi 侧持有）。
//!
//! ```text
//! open_local_source(path) -> LocalSourceOpenResult { source | rejection }
//! local_source_pages(id)  -> Vec<LocalPageInfo>
//! local_page_bytes(id, i) -> 该页的**编码字节**（JPEG/PNG/…）
//! local_close(id)         -> bool
//! ```
//!
//! ## 为什么 open 不返回 `anyhow::Result`
//!
//! `rossi_local_core` 故意用**类型**而不是错误字符串表达拒绝原因（`UnsupportedSource`），
//! 因为 UI 要区分「这本是固实压缩的 RAR」和「这文件损坏了」——这两种情况给用户的下一步动作
//! 完全不同（换一本 / 查文件）。而 `anyhow::Error` 跨 FRB 之后只剩 Dart 侧的
//! `AnyhowException.message` 一个字符串，**类别信息在那一步就丢了**。
//!
//! 所以 `open_local_source` 返回 `LocalSourceOpenResult`，让类别以**枚举**过桥；
//! 其余接口（读字节等）的失败确实是「意料之外的 IO/损坏」，继续用 `anyhow` 不会丢信息。
//!
//! ## 边界：这里传的是**编码字节**，不是像素
//!
//! `local_page_bytes` 返回的是归档里的原始 JPEG/PNG 字节。这与 ROADMAP「明确不做」里
//! 那条「不把所有图片转成 Dart `Uint8List` 再交给 Flutter」**不冲突**：
//! 那条禁止的是把**解码后的 RGBA** 搬过桥（即 decode → CPU RGBA → Flutter 的老路）。
//! 上屏路径的目标形态是 Rust 侧解码后直接进 GPU texture（Phase 1 的 `texture-bridge`），
//! 编码字节过桥只用于 Dart 侧兜底显示与尺寸探测。

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use anyhow::Error;
use dashmap::DashMap;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use rossi_local_core::{
    AllowReason, BlockReason, FS_PAGE_LOAD_HIGH_RESERVED_PERMITS, FS_PAGE_LOAD_TOTAL_PERMITS,
    FsPageLoadContract, FsPageLoadPriority, FsPageLoadScheduler, LocalSource,
    PREFETCH_IDLE_THRESHOLD, PrefetchDecision, ShellOnlyFormat, SourceKind, UnsupportedSource,
    decide_prefetch_allowed, interleaved_prefetch_positions,
};

lazy_static! {
    /// `id → LocalSource`。**只存路径与页元数据**，所以它的体积与「打开了几本」成正比，
    /// 与「读了多少页」无关——这是判据 D 在 App 层仍然成立的原因。
    static ref SESSIONS: DashMap<u64, LocalSource> = DashMap::new();
    static ref NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
    /// 页加载请求的调用序号。只喂给调度器的 perf 埋点（`perf_seq`），
    /// 让它能把「同一页的排队 → 拿到许可 → 完成」串起来。
    static ref NEXT_LOAD_SEQ: AtomicU64 = AtomicU64::new(1);

    /// 页加载**许可调度器**（进程级单例）。
    ///
    /// 类型来自 `rossi_local_core::FsPageLoadScheduler`（逐字搬自 mImageViewer，
    /// 见 `docs/local-core-vendored-modules.md`）。它放在**会话层**而不是 core：
    /// core 不持有会话、也不该知道「谁在请求」，而调度器的 `owner_context` 正是会话 id。
    ///
    /// 它管的是**并发度**：总 6 张许可、其中 2 张留给 `High`。
    /// 不加限制时「预取 3 页 + 用户翻页」会同时解 4 张全尺寸 AVIF —— 每张 170 MB 位图，
    /// 这就是 2026-09-16 之前那个「连翻几页 RSS 一路涨」的结构性来源。
    static ref FS_PAGE_LOAD: Arc<FsPageLoadScheduler> = Arc::new(FsPageLoadScheduler::new());
}

/// 来源类型。与 `rossi_local_core::SourceKind` 一一对应（单独声明是为了不受
/// 依赖里的类型改动直接影响 Dart 侧的枚举名）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalSourceKind {
    Folder,
    Zip,
    Rar,
}

impl From<SourceKind> for LocalSourceKind {
    fn from(value: SourceKind) -> Self {
        match value {
            SourceKind::Folder => Self::Folder,
            SourceKind::Zip => Self::Zip,
            SourceKind::Rar => Self::Rar,
        }
    }
}

/// 被**主动拒绝**的原因类别。UI 按类别给不同提示与下一步动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalRejectionKind {
    /// 扩展名不在 v0.1 范围内（7z / PDF / 视频……）。
    UnknownFormat,
    /// 固实 RAR：读第 N 页要解压前 N-1 页。
    RarSolid,
    /// 归档里含嵌套归档（v0.1 不展开）。
    RarNestedArchive,
    /// 加密 RAR（v0.1 不提供密码输入）。
    RarEncrypted,
    /// 路径不存在或不可读。
    NotFound,
    /// 其他 IO / 解析失败（含归档损坏）。
    Io,
}

#[derive(Debug, Clone)]
pub struct LocalRejection {
    pub kind: LocalRejectionKind,
    /// 可直接展示给用户的说明（已本地化）。
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct LocalSourceInfo {
    /// 会话 id，后续所有调用都用它。
    pub id: u64,
    pub path: String,
    pub kind: LocalSourceKind,
    pub page_count: u32,
    pub total_bytes: u64,
}

/// `open_local_source` 的返回值：要么拿到 `source`，要么拿到 `rejection`，不会两者都有。
#[derive(Debug, Clone)]
pub struct LocalSourceOpenResult {
    pub source: Option<LocalSourceInfo>,
    pub rejection: Option<LocalRejection>,
}

#[derive(Debug, Clone)]
pub struct LocalPageInfo {
    pub index: u32,
    /// 展示名（页序已由 Rust 侧自然序决定，Dart 侧不要再排一次）。
    pub name: String,
    /// 编码字节数。文件夹来源为文件长度。
    pub size: u64,
}

#[frb]
pub async fn open_local_source(path: String) -> LocalSourceOpenResult {
    // 打开归档要解析中央目录 / RAR 头部，是阻塞 IO，放到全局阻塞线程池上。
    rquickjs_playground::global_handle()
        .spawn_blocking(move || open_local_source_impl(path))
        .await
        .unwrap_or_else(|err| LocalSourceOpenResult {
            source: None,
            rejection: Some(LocalRejection {
                kind: LocalRejectionKind::Io,
                message: format!("打开本地来源的任务失败: {err}"),
            }),
        })
}

fn open_local_source_impl(path: String) -> LocalSourceOpenResult {
    let source = match LocalSource::open(&path) {
        Ok(source) => source,
        Err(error) => {
            return LocalSourceOpenResult {
                source: None,
                rejection: Some(classify_open_error(&error)),
            };
        }
    };

    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let info = LocalSourceInfo {
        id,
        path: source.root().to_string_lossy().into_owned(),
        kind: source.kind().into(),
        page_count: source.len() as u32,
        total_bytes: source.total_bytes(),
    };
    SESSIONS.insert(id, source);
    LocalSourceOpenResult {
        source: Some(info),
        rejection: None,
    }
}

/// 把 `anyhow::Error` 还原成可分类的拒绝原因。
///
/// `LocalSource::open` 用 `with_context` 包了一层，所以类型化的原因要用
/// `downcast_ref` **向下穿透**（而不是只看最外层消息）。
fn classify_open_error(error: &Error) -> LocalRejection {
    if let Some(unsupported) = error.downcast_ref::<UnsupportedSource>() {
        let kind = match unsupported {
            UnsupportedSource::UnknownFormat(_) => LocalRejectionKind::UnknownFormat,
            UnsupportedSource::RarSolid => LocalRejectionKind::RarSolid,
            UnsupportedSource::RarNestedArchive => LocalRejectionKind::RarNestedArchive,
            UnsupportedSource::RarEncrypted => LocalRejectionKind::RarEncrypted,
        };
        return LocalRejection {
            kind,
            message: unsupported.to_string(),
        };
    }

    if let Some(io_error) = error.downcast_ref::<std::io::Error>() {
        let kind = if io_error.kind() == std::io::ErrorKind::NotFound {
            LocalRejectionKind::NotFound
        } else {
            LocalRejectionKind::Io
        };
        return LocalRejection {
            kind,
            message: format!("{error:#}"),
        };
    }

    LocalRejection {
        kind: LocalRejectionKind::Io,
        message: format!("{error:#}"),
    }
}

#[frb]
pub async fn local_source_pages(id: u64) -> Result<Vec<LocalPageInfo>, Error> {
    let source = session(id)?;
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            Ok(source
                .pages()
                .iter()
                .enumerate()
                .map(|(index, page)| LocalPageInfo {
                    index: index as u32,
                    name: page.name.clone(),
                    size: page.size,
                })
                .collect())
        })
        .await?
}

/// 取一页的**编码字节**。每调用一次都会重新打开来源（不常驻句柄，判据 D）。
#[frb]
pub async fn local_page_bytes(id: u64, index: u32) -> Result<Vec<u8>, Error> {
    let source = session(id)?;
    rquickjs_playground::global_handle()
        .spawn_blocking(move || source.page_bytes(index as usize))
        .await?
}

/// 这次页加载的**优先级**。语义来自 mImageViewer 的 `FsPageLoadPriority`。
///
/// 为什么要有它：用户正在等的那一页（`High`）必须能插队到预取（`Normal`）前面，
/// 否则「预取把全部许可占满、用户翻页排在后面」就是必然。
/// 调度器为此留了 2 张许可只给 `High`。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalPageLoadPriority {
    /// 预取、预热之类：可以等。
    Normal,
    /// 用户此刻在等这一页。
    High,
}

/// 这次页加载的**准入契约**。语义来自 mImageViewer 的 `FsPageLoadContract`。
///
/// 区别只在「它会不会作废别的请求」：
/// - `Sequential`：顺序翻页。**永不**作废已受理的目标 —— 连翻三页就是三页都要，
///   中间那页用户真的看过。
/// - `LatestSeek`：直接跳页。用户已经改主意了，同一会话里还在排队的旧请求
///   全部作废（它们读完也没人看），从而把许可让给新的目标。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalPageLoadContract {
    Sequential,
    LatestSeek,
}

impl From<LocalPageLoadPriority> for FsPageLoadPriority {
    fn from(value: LocalPageLoadPriority) -> Self {
        match value {
            LocalPageLoadPriority::Normal => Self::Normal,
            LocalPageLoadPriority::High => Self::High,
        }
    }
}

impl From<LocalPageLoadContract> for FsPageLoadContract {
    fn from(value: LocalPageLoadContract) -> Self {
        match value {
            LocalPageLoadContract::Sequential => Self::Sequential,
            LocalPageLoadContract::LatestSeek => Self::LatestSeek,
        }
    }
}

/// 一页解码后的像素（RGBA8，未预乘，行主序）。
#[derive(Debug, Clone)]
pub struct LocalPagePixels {
    pub width: u32,
    pub height: u32,
    /// 解码器输出的原始尺寸（降采样之前）。与 `width`/`height` 分开，
    /// 是为了让「请求的宽度到底生效了没有」在 UI 上一眼可见。
    pub source_width: u32,
    pub source_height: u32,
    /// `width * height * 4` 字节。
    pub rgba: Vec<u8>,
}

/// 解码失败的**类别**。用枚举而不是字符串，理由与 `LocalRejection` 相同：
/// 「这一页的格式核心没解码器」和「字节坏了」给用户的下一步动作完全不同。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalDecodeFailureKind {
    /// 核心没有这个格式的解码器（`heic` / `heif`；`jxl` 开了后端 feature 就进
    /// 核心档了），要交外壳 —— 而外壳解得动与否取决于平台
    /// （Windows 引擎实测解不动，见 `rossi_local_core::page_order`）。
    ShellOnlyFormat,
    /// 核心有解码器但没解出来：字节损坏、内容与格式不符等。
    DecodeFailed,
    /// **没轮到就作废了**：请求还在排队时被更新的 `LatestSeek` 取代，或调用方放弃。
    ///
    /// 与上两者分开，是因为它既不是格式问题也不是数据问题 —— **这一页完全可能解得出**，
    /// 只是没人要了。UI 不该把它显示成错误，更不该据此判定「这本解不了」。
    Cancelled,
}

#[derive(Debug, Clone)]
pub struct LocalDecodeFailure {
    pub kind: LocalDecodeFailureKind,
    /// 可直接展示的说明（已本地化）。
    pub message: String,
}

/// `local_page_pixels` 的返回值：要么 `pixels`，要么 `failure`。
#[derive(Debug, Clone)]
pub struct LocalPageDecodeResult {
    pub pixels: Option<LocalPagePixels>,
    pub failure: Option<LocalDecodeFailure>,
}

/// 取一页的**解码后像素**。
///
/// 和 [`local_page_bytes`] 的分工必须说清，否则很容易用错：
/// - `local_page_bytes` 给的是**编码字节**，Dart 侧自己解 —— 只对 Dart 引擎认识的格式有效。
///   Windows 引擎没有 AV1 解码器，所以 avif 走那条路只会得到
///   `Could not decompress image.`（实测见 `rossi_local_core::page_order`）。
/// - 这一条走 **Rust 侧解码器**，是 avif 目前唯一能出图的路。
///
/// # `target_width`：这个参数决定这条路径能不能用
///
/// `None` = 原尺寸。**对 44.8 MPix 的页，原尺寸是不可接受的**：
/// Rust 侧解出来只要约 267 ms（其中 dav1d 249 ms），但 170 MB 的位图
/// 过桥 + 交给 `ui.decodeImageFromPixels` 要多花约 1260 ms —— 实测 App 里
/// 同一页量到 1526 ms，**其中解码只占 17%**。
///
/// 给了 `target_width` 之后，位图按宽度降采样（不放大），后面那 1260 ms
/// 随位图大小等比下降：缩到 768 px 时位图 3.4 MB，Rust 侧总成本约 305 ms。
/// 完整档位实测见 `rossi_local_core::decode::decode_rgba_scaled`。
///
/// # 这是过渡形态，不是终点
///
/// Phase 1 的目标是「Rust 解码 → GPU texture 上屏」，那一步**不过桥**，
/// 因而也不需要靠降采样来省拷贝。判据 C 的 p95 ≤ 16.7 ms 不在当前形态下成立，
/// 别拿它的数字当结论。
#[frb]
pub async fn local_page_pixels(
    id: u64,
    index: u32,
    target_width: Option<u32>,
    priority: LocalPageLoadPriority,
    contract: LocalPageLoadContract,
) -> LocalPageDecodeResult {
    let source = match session(id) {
        Ok(source) => source,
        Err(error) => return decode_failed(format!("{error:#}")),
    };

    // 拿号。`LatestSeek` 会在这一步把同一会话里**还在排队**的旧请求作废 ——
    // 用户连点页码时，中间那些页读完也没人看，不该占着许可。
    let ticket = FS_PAGE_LOAD.request(
        id,
        index as usize,
        priority.into(),
        contract.into(),
        None,
        NEXT_LOAD_SEQ.fetch_add(1, Ordering::Relaxed),
    );
    let waiter = ticket.waiter();

    let outcome = rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            // 排队等许可。**这一步会阻塞**，所以它在 spawn_blocking 的线程里 ——
            // 不卡 UI 线程，也不卡 tokio 的调度线程。
            let Some(_permit) = waiter.acquire_cancellable() else {
                // 被 `LatestSeek` 取代（或调用方放弃）：这不是错误，见 `Cancelled` 的说明。
                return LocalPageDecodeResult {
                    pixels: None,
                    failure: Some(LocalDecodeFailure {
                        kind: LocalDecodeFailureKind::Cancelled,
                        message: "该请求已被更新的跳页取代，未解码".to_string(),
                    }),
                };
            };
            decode_page_impl(&source, index as usize, target_width)
        })
        .await;

    // `ticket` 到这里才 drop。它 armed 时会在 Drop 里 cancel —— 那时请求已完成
    // （permit 已释放、记录已移除），所以是 no-op。真正有意义的是**提前返回**的路径：
    // Dart 侧若放弃这个 future，`ticket` 随之 drop 并 cancel，排队中的请求会立刻退出。
    outcome.unwrap_or_else(|error| decode_failed(format!("解码任务失败: {error}")))
}

fn decode_failed(message: String) -> LocalPageDecodeResult {
    LocalPageDecodeResult {
        pixels: None,
        failure: Some(LocalDecodeFailure {
            kind: LocalDecodeFailureKind::DecodeFailed,
            message,
        }),
    }
}

fn decode_page_impl(
    source: &LocalSource,
    index: usize,
    target_width: Option<u32>,
) -> LocalPageDecodeResult {
    match source.page_pixels_scaled(index, target_width) {
        Ok(pixels) => LocalPageDecodeResult {
            pixels: Some(LocalPagePixels {
                width: pixels.width,
                height: pixels.height,
                source_width: pixels.source_width,
                source_height: pixels.source_height,
                rgba: pixels.rgba,
            }),
            failure: None,
        },
        Err(error) => {
            // 与 `classify_open_error` 同理：`page_pixels` 内部也用 `with_context` 包过，
            // 类型化的原因必须 `downcast_ref` **向下穿透**。否则「这本是 jxl、要交外壳」
            // 会退化成「解码失败」，而这两者的下一步动作完全不同。
            let kind = if error.downcast_ref::<ShellOnlyFormat>().is_some() {
                LocalDecodeFailureKind::ShellOnlyFormat
            } else {
                LocalDecodeFailureKind::DecodeFailed
            };
            LocalPageDecodeResult {
                pixels: None,
                failure: Some(LocalDecodeFailure {
                    kind,
                    message: format!("{error:#}"),
                }),
            }
        }
    }
}

// ── 预取策略的桥接 ───────────────────────────────────────────────────────────
//
// 判决与目标选择**都在 Rust 侧**（`rossi_local_core::prefetch_policy`，
// 逐字搬自 mImageViewer，见 `docs/local-core-vendored-modules.md`）。
// 这里只做两件事：把 Dart 的状态翻译成上游函数的入参，把上游的返回值翻译成
// 能显示给人看的形状。**不在这一层写第二套策略** —— 那会让上面那些测试失去意义。

/// 预取准入判决的结果。
///
/// 带**理由**而不是一个 bool —— 上游的理由枚举（`AllowReason` / `BlockReason`）
/// 就是为了让人看到「现在为什么不预取」。只返回 bool 的话，调试页只能显示
/// 「没预取」，而「因为当前页还在加载」和「因为你刚翻页 43 ms」是完全不同的两件事，
/// 对应的下一步动作也不同。
#[derive(Debug, Clone)]
pub struct LocalPrefetchDecision {
    pub allowed: bool,
    /// 机器可读的理由标签。
    pub reason: String,
    /// 可直接展示的说明（中文）。
    pub message: String,
}

/// 现在该不该发预取。
///
/// 上游语义在这里一一对应（分页阅读 vs 连续阅读，判据同构）：
///
/// | 上游（连续阅读） | 这里（分页阅读） |
/// |---|---|
/// | `last_prefetch_scroll_at` | 上一次翻页/跳页的时刻，用「距现在多少毫秒」传 |
/// | `visible_state_pending` | 当前页是否还没出图（0 = 已出图） |
///
/// `Instant` 不能跨桥，所以传毫秒差；还原成 `Instant` 是这一层唯一的翻译动作。
///
/// 三种放行：还没翻过页 / 翻完 100 ms 且当前页已出图 / 距上次翻页满 3 秒
/// （兜底：防止「当前页永远加载不出来」把预取永久冻住）。
#[frb]
pub fn local_prefetch_decision(
    ms_since_last_turn: Option<u64>,
    visible_pending: u32,
) -> LocalPrefetchDecision {
    let now = Instant::now();
    // 时钟异常时 `checked_sub` 给 None：退化成「刚翻过页」，宁可少预取。
    let last =
        ms_since_last_turn.map(|ms| now.checked_sub(Duration::from_millis(ms)).unwrap_or(now));

    match decide_prefetch_allowed(now, last, visible_pending as usize) {
        PrefetchDecision::Allow { reason } => {
            let (tag, message) = match reason {
                AllowReason::NoScrollYet => ("no_scroll_yet", "还没翻过页，可以预取"),
                AllowReason::ScrollIdleAndVisibleReady => (
                    "scroll_idle_and_visible_ready",
                    "翻页已静默且当前页已出图，可以预取",
                ),
                AllowReason::Backstop3s => ("backstop_3s", "距上次翻页已满 3 秒，兜底放行"),
            };
            LocalPrefetchDecision {
                allowed: true,
                reason: tag.to_string(),
                message: message.to_string(),
            }
        }
        PrefetchDecision::Block { reason } => match reason {
            BlockReason::ScrollNotIdle { elapsed_ms } => LocalPrefetchDecision {
                allowed: false,
                reason: "scroll_not_idle".to_string(),
                message: format!(
                    "刚翻过页（{elapsed_ms} ms 前），等满 {} ms 再预取",
                    PREFETCH_IDLE_THRESHOLD.as_millis()
                ),
            },
            BlockReason::VisibleStillLoading { pending } => LocalPrefetchDecision {
                allowed: false,
                reason: "visible_still_loading".to_string(),
                message: format!("当前页还没出图（{pending} 项待完成），先别抢许可"),
            },
        },
    }
}

/// 预取目标（页序号）。顺序是 `+1, -1, +2, -2, …`，同距离 **forward 先**。
///
/// 为什么 forward 先：下一个要看的页大概率是下一页；而 backward 那页用户刚看过，
/// 它的解码结果很可能还在（或还在用），先解它等于把许可花在更没用的地方。
///
/// 边界由上游函数处理：`pos` 在头/尾时只有一侧有值，越界的位置直接跳过。
#[frb]
pub fn local_prefetch_targets(pos: u32, n: u32, forward: u32, back: u32) -> Vec<u32> {
    interleaved_prefetch_positions(pos as usize, n as usize, forward as usize, back as usize)
        .into_iter()
        .map(|position| position as u32)
        .collect()
}

/// 调度器此刻的快照 —— 「在跑几个解码」。
///
/// 这是 `FS_PAGE_LOAD` 的**可观测面**。没有它，判据 D（连读内存不增长）与
/// 「预取有没有在抢当前页的许可」只能靠感觉判断。
#[derive(Debug, Clone, Copy)]
pub struct LocalPageLoadStats {
    pub waiting: u32,
    pub running: u32,
    pub cancelling: u32,
    pub running_normal: u32,
    pub total_limit: u32,
    pub high_reserved: u32,
}

#[frb]
pub fn local_page_load_stats() -> LocalPageLoadStats {
    let stats = FS_PAGE_LOAD.stats();
    LocalPageLoadStats {
        waiting: stats.waiting as u32,
        running: stats.running as u32,
        cancelling: stats.cancelling as u32,
        running_normal: stats.running_normal as u32,
        total_limit: FS_PAGE_LOAD_TOTAL_PERMITS as u32,
        high_reserved: FS_PAGE_LOAD_HIGH_RESERVED_PERMITS as u32,
    }
}

/// 关闭会话并释放。返回 `false` 表示 id 不存在（重复关闭、或已被回收）。
#[frb(sync)]
pub fn local_close(id: u64) -> bool {
    SESSIONS.remove(&id).is_some()
}

/// 当前打开的会话数。
///
/// 这是判据 D 的**探针**：连读三本之后，这个数必须回落到基线附近，
/// 不允许单调上升。GPU/handle 侧泄漏不体现在 RSS 里，只能靠这种计数观测。
#[frb(sync)]
pub fn local_open_session_count() -> u32 {
    SESSIONS.len() as u32
}

/// 关闭全部会话。用于「换书」「退出阅读器」这类整批释放的场景。
#[frb(sync)]
pub fn local_close_all() -> u32 {
    let count = SESSIONS.len() as u32;
    SESSIONS.clear();
    count
}

fn session(id: u64) -> Result<LocalSource, Error> {
    SESSIONS
        .get(&id)
        .map(|entry| entry.value().clone())
        .ok_or_else(|| anyhow::anyhow!("本地来源会话不存在或已关闭: id={id}"))
}

// ───────────────────────── 文件树浏览 ─────────────────────────

/// 根位置条目（跨平台驱动器、挂载卷、常用主目录）。
#[frb]
#[derive(Debug, Clone)]
pub struct LocalRootLocation {
    pub label: String,
    pub path: String,
}

/// 文件树节点。
#[frb]
#[derive(Debug, Clone)]
pub struct LocalFileTreeNode {
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    pub is_archive: bool,
    pub is_image: bool,
    pub is_video: bool,
    pub is_audio: bool,
    pub size: u64,
    pub has_children: bool,
}

/// 获取跨平台的可用根路径与驱动器列表。
#[frb(sync)]
pub fn local_get_available_roots() -> Vec<LocalRootLocation> {
    rossi_local_core::get_available_roots()
        .into_iter()
        .map(|r| LocalRootLocation {
            label: r.label,
            path: r.path,
        })
        .collect()
}

/// 列出指定目录下的节点（子目录、漫画包、图片，已按自然排序整理）。
pub fn local_list_directory(dir_path: String) -> anyhow::Result<Vec<LocalFileTreeNode>> {
    let path = std::path::Path::new(&dir_path);
    let nodes = rossi_local_core::list_directory(path)?;
    Ok(nodes
        .into_iter()
        .map(|n| LocalFileTreeNode {
            path: n.path,
            name: n.name,
            is_dir: n.is_dir,
            is_archive: n.is_archive,
            is_image: n.is_image,
            is_video: n.is_video,
            is_audio: n.is_audio,
            size: n.size,
            has_children: n.has_children,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 碰全局 `SESSIONS` 的测试必须串行 —— `cargo test` 默认是多线程的。
    ///
    /// `SESSIONS` 是进程级单例：`open_read_close_round_trip` 插入会话的那一瞬间，
    /// 如果 `session_count_does_not_drift_when_books_are_cycled` 正在读计数，
    /// 断言就会看到 1 而不是 0。这不是逻辑错，是**拿共享全局状态当夹具**的固有代价。
    /// 2026-09-16 观察到这个抖动：新增一条测试改变了调度顺序，它才露出来。
    static SESSIONS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock_sessions() -> std::sync::MutexGuard<'static, ()> {
        // 有测试 panic 过会把锁标记为 poisoned；这里关心的是互斥，不是那次失败。
        SESSIONS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn make_cbz(dir: &std::path::Path, name: &str) -> std::path::PathBuf {
        use std::io::Write;
        let path = dir.join(name);
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        for page in ["p1.png", "p2.png"] {
            zip.start_file(page, options).unwrap();
            let buffer = image::RgbaImage::new(4, 3);
            let mut bytes = std::io::Cursor::new(Vec::new());
            image::DynamicImage::ImageRgba8(buffer)
                .write_to(&mut bytes, image::ImageFormat::Png)
                .unwrap();
            zip.write_all(&bytes.into_inner()).unwrap();
        }
        zip.finish().unwrap();
        path
    }

    #[test]
    fn open_read_close_round_trip() {
        let _guard = lock_sessions();
        let dir = tempfile::tempdir().unwrap();
        let path = make_cbz(dir.path(), "book.cbz");

        let opened = open_local_source_impl(path.to_string_lossy().into_owned());
        assert!(opened.rejection.is_none(), "{:?}", opened.rejection);
        let info = opened.source.unwrap();
        assert_eq!(info.kind, LocalSourceKind::Zip);
        assert_eq!(info.page_count, 2);

        let source = session(info.id).unwrap();
        assert_eq!(source.pages()[0].name, "p1.png");
        assert!(!source.page_bytes(0).unwrap().is_empty());

        assert!(local_close(info.id));
        assert!(!local_close(info.id), "重复关闭应当返回 false");
        assert!(session(info.id).is_err());
    }

    #[test]
    fn rejection_keeps_the_category_across_the_boundary() {
        // 未知扩展名：必须是 UnknownFormat，而不是笼统的 Io。
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.7z");
        std::fs::write(&path, b"7z\xBC\xAF\x27\x1C").unwrap();

        let opened = open_local_source_impl(path.to_string_lossy().into_owned());
        let rejection = opened.rejection.expect("应当被拒绝");
        assert_eq!(rejection.kind, LocalRejectionKind::UnknownFormat);
        assert!(opened.source.is_none());

        // 路径不存在：必须是 NotFound（UI 提示「文件不见了」而不是「格式不支持」）。
        let opened =
            open_local_source_impl(dir.path().join("nope.cbz").to_string_lossy().into_owned());
        let rejection = opened.rejection.expect("应当被拒绝");
        assert_eq!(rejection.kind, LocalRejectionKind::NotFound);
    }

    #[test]
    fn session_count_does_not_drift_when_books_are_cycled() {
        let _guard = lock_sessions();
        // 判据 D 的探针在 App 层仍然要成立：反复开关不会留下会话。
        let dir = tempfile::tempdir().unwrap();
        let baseline = local_open_session_count();
        for round in 0..5 {
            let path = make_cbz(dir.path(), &format!("book-{round}.cbz"));
            let opened = open_local_source_impl(path.to_string_lossy().into_owned());
            let info = opened.source.unwrap();
            assert_eq!(local_close(info.id), true);
            assert_eq!(local_open_session_count(), baseline);
        }
    }

    /// 解码归属**不能**在过桥时退化成「解码失败」。
    ///
    /// 三种输入各走一条岔路：能解的、核心没解码器的（交外壳）、核心解不出来的（坏了）。
    /// 前两个若被合成一个，UI 就没法给出正确的下一步动作 —— 这是 `LocalRejection`
    /// 那条教训在解码侧的同一个形状。
    #[test]
    fn page_pixels_separate_shell_only_from_broken_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("mixed");
        std::fs::create_dir(&root).unwrap();

        let buffer = image::RgbaImage::new(4, 3);
        let mut encoded = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(buffer)
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        std::fs::write(root.join("1.png"), encoded.into_inner()).unwrap();
        // 垃圾字节冒充 heic：闸门在解码**之前**，所以内容是什么无关紧要。
        // 样例不用 jxl：jxl 开了后端 feature（App 默认 jxl-rs-mt）就进核心档了。
        std::fs::write(root.join("2.heic"), b"not really a heic").unwrap();
        // 垃圾字节冒充 png：这一页会真的走到解码器，报出的必须是 DecodeFailed。
        std::fs::write(root.join("3.png"), b"not really a png").unwrap();

        let source = LocalSource::open(&root).unwrap();
        assert_eq!(source.len(), 3);

        let ok = decode_page_impl(&source, 0, None);
        assert!(ok.failure.is_none(), "{:?}", ok.failure);
        assert_eq!(ok.pixels.unwrap().width, 4);

        let shell = decode_page_impl(&source, 1, None);
        assert_eq!(
            shell.failure.expect("应当失败").kind,
            LocalDecodeFailureKind::ShellOnlyFormat
        );

        let broken = decode_page_impl(&source, 2, None);
        assert_eq!(
            broken.failure.expect("应当失败").kind,
            LocalDecodeFailureKind::DecodeFailed
        );
    }

    /// 过桥之后「原始尺寸」必须还在 —— 否则 UI 无法判断降采样到底生效没有。
    ///
    /// 这一条同时把「不放大」钉在 API 层：上层传一个比原图大的宽度时，
    /// 返回的仍是原尺寸，而不是被悄悄放大成 179 MB。
    #[test]
    fn target_width_reaches_the_pixels_and_keeps_the_source_size() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("wide");
        std::fs::create_dir(&root).unwrap();

        let buffer = image::RgbaImage::new(64, 32);
        let mut encoded = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(buffer)
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        std::fs::write(root.join("1.png"), encoded.into_inner()).unwrap();

        let source = LocalSource::open(&root).unwrap();

        let scaled = decode_page_impl(&source, 0, Some(16)).pixels.unwrap();
        assert_eq!((scaled.width, scaled.height), (16, 8));
        assert_eq!((scaled.source_width, scaled.source_height), (64, 32));
        assert_eq!(scaled.rgba.len(), 16 * 8 * 4);

        let big = decode_page_impl(&source, 0, Some(4096)).pixels.unwrap();
        assert_eq!((big.width, big.height), (64, 32), "不放大");
    }

    /// 许可模型接上来之后，**并发请求不许被丢掉**。
    ///
    /// 调度器只有 6 张许可（其中 2 张不给 `Normal`）。8 个请求同时来必然排队 ——
    /// 排队是设计，丢请求是 bug。这条盯的是「接线对不对」：每一份都要出图，
    /// 且跑完之后许可必须**全部归还**（`running` / `waiting` 归零）——
    /// 漏归还一个请求，判据 D 那类「连读不增长」的观测就被永久污染了。
    ///
    /// 值得单测的理由：`waiter.acquire_cancellable()` 是 `Mutex` + `Condvar`，
    /// 接线写错（在 async 上下文里持锁、忘了 drop permit）的表现是**偶发卡死**
    /// 而不是报错 —— 那种 bug 只有并发测试抓得到。
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_page_loads_queue_instead_of_dropping() {
        let _guard = lock_sessions();
        let dir = tempfile::tempdir().unwrap();
        let path = make_cbz(dir.path(), "scheduled.cbz");
        let opened = open_local_source_impl(path.to_string_lossy().into_owned());
        assert!(opened.rejection.is_none(), "{:?}", opened.rejection);
        let info = opened.source.unwrap();

        let mut handles = Vec::new();
        for i in 0..8_u32 {
            handles.push(tokio::spawn(local_page_pixels(
                info.id,
                i % 2,
                None,
                LocalPageLoadPriority::Normal,
                LocalPageLoadContract::Sequential,
            )));
        }
        for handle in handles {
            let result = handle.await.expect("任务不应 panic");
            assert!(result.failure.is_none(), "{:?}", result.failure);
            assert!(result.pixels.is_some());
        }

        let stats = local_page_load_stats();
        assert_eq!(stats.running, 0, "许可必须全部归还");
        assert_eq!(stats.waiting, 0, "等待队列必须清空");
        assert_eq!(stats.total_limit as usize, FS_PAGE_LOAD_TOTAL_PERMITS);

        local_close(info.id);
    }

    /// 判决与目标选择确实是**上游那两个函数**在回答，而不是桥接层自己又判了一遍。
    ///
    /// 每条断言都对着 `rossi_local_core::prefetch_policy` 里那条同名测试的期望值，
    /// 所以这一层改坏了、而上游函数没动，这里就会红。
    #[test]
    fn prefetch_decision_and_targets_bridge_the_core_policy() {
        // 还没翻过页 → 放行（上游 `AllowReason::NoScrollYet`）。
        let fresh = local_prefetch_decision(None, 0);
        assert!(fresh.allowed);
        assert_eq!(fresh.reason, "no_scroll_yet");

        // 刚翻过页（0 ms 前）→ 拦截，这是 100 ms 静默阈值的边界。
        let just_turned = local_prefetch_decision(Some(0), 0);
        assert!(!just_turned.allowed);
        assert_eq!(just_turned.reason, "scroll_not_idle");

        // 翻完 200 ms 但当前页还在加载 → 换一个拦截理由。
        let still_loading = local_prefetch_decision(Some(200), 1);
        assert!(!still_loading.allowed);
        assert_eq!(still_loading.reason, "visible_still_loading");

        // 翻完 200 ms 且当前页已出图 → 放行。
        let ready = local_prefetch_decision(Some(200), 0);
        assert!(ready.allowed);
        assert_eq!(ready.reason, "scroll_idle_and_visible_ready");

        // 目标顺序取自上游 `interleaved_prefetch_positions`：forward 先，越界自动跳过。
        assert_eq!(local_prefetch_targets(3, 7, 1, 1), vec![4, 2]);
        assert_eq!(
            local_prefetch_targets(0, 7, 1, 1),
            vec![1],
            "头部没有上一页"
        );
        assert_eq!(
            local_prefetch_targets(6, 7, 1, 1),
            vec![5],
            "尾部没有下一页"
        );
    }
}
